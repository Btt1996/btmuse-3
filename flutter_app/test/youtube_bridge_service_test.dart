import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/x2/youtube_bridge_service.dart';

// Phase 4, item 21: the self-hosted YouTube bridge client.
// No network, no device APIs — Dio is stubbed with HttpClientAdapter
// (same pattern as import_workflow_test.dart).

typedef _StubHandler = ResponseBody Function(RequestOptions options);

class _StubAdapter implements HttpClientAdapter {
  final _StubHandler handler;
  _StubAdapter(this.handler);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }
}

ResponseBody _jsonBody(Map<String, dynamic> json, [int status = 200]) {
  return ResponseBody.fromBytes(
    Uint8List.fromList(utf8.encode(jsonEncode(json))),
    status,
    headers: {Headers.contentTypeHeader: ['application/json']},
  );
}

YoutubeBridgeService _service(_StubHandler handler) {
  final dio = Dio();
  dio.httpClientAdapter = _StubAdapter(handler);
  return YoutubeBridgeService(ApiClient(customDio: dio));
}

void main() {
  group('YoutubeBridgeService.testConnection', () {
    test('healthy bridge answers {"ok": true} from /health', () async {
      final service = _service((options) {
        expect(options.path, endsWith('/health'));
        return _jsonBody({'ok': true, 'service': 'btmu-ytdlp-bridge'});
      });

      final health = await service.testConnection('http://192.168.1.10:8000');
      expect(health.ok, isTrue);
      expect(health.detail, contains('btmu-ytdlp-bridge'));
    });

    test('a server without the bridge contract reports ok: false, not an exception',
        () async {
      final service = _service((options) {
        return _jsonBody({'ok': false});
      });

      final health = await service.testConnection('https://bridge.example.org');
      expect(health.ok, isFalse);
      expect(health.detail, contains('did not confirm the bridge contract'));
    });

    test('an HTTP error from /health reports ok: false', () async {
      final service = _service((options) {
        return ResponseBody.fromBytes(
          Uint8List.fromList(utf8.encode('Not Found')),
          404,
          headers: {Headers.contentTypeHeader: ['text/plain']},
        );
      });

      final health = await service.testConnection('https://bridge.example.org');
      expect(health.ok, isFalse);
      expect(health.detail, contains('HTTP 404'));
    });

    test('an unreachable bridge throws NetworkFailure', () async {
      final service = _service((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'Connection refused',
        );
      });

      expect(
        () => service.testConnection('http://192.168.1.10:8000'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('no configured bridge throws youtube_bridge_not_configured', () async {
      final service = _service((options) => _jsonBody({'ok': true}));

      expect(
        () => service.testConnection(''),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.code,
            'code',
            'youtube_bridge_not_configured',
          ),
        ),
      );
    });
  });

  group('YoutubeBridgeService.extract', () {
    test('returns title + public download_url on success', () async {
      final service = _service((options) {
        expect(options.path, endsWith('/extract'));
        return _jsonBody({
          'title': 'Test Song',
          'download_url': 'https://files.example.org/song.m4a',
        });
      });

      final extraction = await service.extract(
        bridgeBaseUrl: 'https://bridge.example.org',
        youtubeUrl: Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      );
      expect(extraction.title, 'Test Song');
      expect(extraction.downloadUrl, 'https://files.example.org/song.m4a');
    });

    test('accepts a download_url on the bridge host itself (LAN bridge)', () async {
      final service = _service((options) {
        return _jsonBody({
          'title': 'LAN Song',
          'download_url': 'http://192.168.1.10:8000/files/song.m4a',
        });
      });

      final extraction = await service.extract(
        bridgeBaseUrl: 'http://192.168.1.10:8000',
        youtubeUrl: Uri.parse('https://youtu.be/dQw4w9WgXcQ'),
      );
      expect(extraction.downloadUrl, 'http://192.168.1.10:8000/files/song.m4a');
    });

    test('rejects a private download_url from a different host', () async {
      final service = _service((options) {
        return _jsonBody({
          'title': 'Sneaky Song',
          'download_url': 'http://192.168.1.99:8000/files/song.m4a',
        });
      });

      expect(
        () => service.extract(
          bridgeBaseUrl: 'https://bridge.example.org',
          youtubeUrl: Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (e) => e.code,
            'code',
            'youtube_bridge_unsafe_download_url',
          ),
        ),
      );
    });

    test('a bridge error surfaces the server detail', () async {
      final service = _service((options) {
        return _jsonBody({'detail': 'extraction failed: boom'}, 502);
      });

      expect(
        () => service.extract(
          bridgeBaseUrl: 'https://bridge.example.org',
          youtubeUrl: Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        ),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.message,
            'message',
            contains('extraction failed: boom'),
          ),
        ),
      );
    });

    test('a response without a download_url is a bad response, not a success',
        () async {
      final service = _service((options) {
        return _jsonBody({'title': 'No URL Here'});
      });

      expect(
        () => service.extract(
          bridgeBaseUrl: 'https://bridge.example.org',
          youtubeUrl: Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        ),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.code,
            'code',
            'youtube_bridge_bad_response',
          ),
        ),
      );
    });

    test('a non-YouTube URL is rejected before any request', () async {
      var requested = false;
      final service = _service((options) {
        requested = true;
        return _jsonBody({'title': 'x', 'download_url': 'https://x.example.org/a.m4a'});
      });

      expect(
        () => service.extract(
          bridgeBaseUrl: 'https://bridge.example.org',
          youtubeUrl: Uri.parse('https://example.org/not-youtube'),
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(requested, isFalse);
    });
  });

  group('YoutubeBridgeService.isAllowedBridgeDownloadUrl', () {
    test('same host, different port: allowed (bridge serving its own file)', () {
      expect(
        YoutubeBridgeService.isAllowedBridgeDownloadUrl(
          'http://192.168.1.10:9000/files/song.m4a',
          'http://192.168.1.10:8000',
        ),
        isTrue,
      );
    });

    test('safe public URL: allowed', () {
      expect(
        YoutubeBridgeService.isAllowedBridgeDownloadUrl(
          'https://files.example.org/song.m4a',
          'https://bridge.example.org',
        ),
        isTrue,
      );
    });

    test('private host that is not the bridge: rejected', () {
      expect(
        YoutubeBridgeService.isAllowedBridgeDownloadUrl(
          'http://10.0.0.5/files/song.m4a',
          'https://bridge.example.org',
        ),
        isFalse,
      );
    });

    test('non-http scheme: rejected', () {
      expect(
        YoutubeBridgeService.isAllowedBridgeDownloadUrl(
          'ftp://files.example.org/song.m4a',
          'https://bridge.example.org',
        ),
        isFalse,
      );
    });
  });
}
