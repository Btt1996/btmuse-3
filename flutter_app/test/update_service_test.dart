import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/services/update_service.dart';

// Dio stubbed to answer the GitHub releases endpoint — same adapter
// pattern as jamendo_provider_test.dart. Captures every request so
// tests can prove the exact URL and headers are used.
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

ResponseBody _jsonBody(Object body, [int statusCode = 200]) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );
}

Map<String, dynamic> _releaseJson({
  String tag = 'v3.0.6',
  String? name = 'Btmus 3.0.6',
  String? body = 'Fixes and improvements.',
  String? htmlUrl = 'https://github.com/Btt1996/btmuse-3/releases/tag/v3.0.6',
}) {
  return {
    'tag_name': tag,
    'name': name,
    'body': body,
    'html_url': htmlUrl,
  };
}

Dio _dioAnswering(ResponseBody Function(RequestOptions options) handler) {
  final dio = Dio();
  dio.httpClientAdapter = _StubAdapter(handler);
  return dio;
}

void main() {
  group('UpdateService.compareVersions', () {
    test('2.00 equals 2.0.0 (missing segments count as 0)', () {
      expect(UpdateService.compareVersions('2.00', '2.0.0'), 0);
      expect(UpdateService.compareVersions('v2.0.0', '2.00'), 0);
    });

    test('newer tag compares greater, older compares smaller', () {
      expect(UpdateService.compareVersions('v2.0.1', '2.00'), 1);
      expect(UpdateService.compareVersions('1.9.9', '2.00'), -1);
      expect(UpdateService.compareVersions('2.1', '2.00'), 1);
      expect(UpdateService.compareVersions('2.00', '2.00'), 0);
    });

    test('leading v is stripped on either side', () {
      expect(UpdateService.compareVersions('v2.0.1', 'v2.0.0'), 1);
    });

    test('pre-release suffix is ignored, numeric part still compares', () {
      expect(UpdateService.compareVersions('2.0.1-beta', '2.00'), 1);
    });
  });

  group('UpdateCheckResult.fromReleaseJson', () {
    test('newer tag parses as update available with notes and URL', () {
      final result = UpdateCheckResult.fromReleaseJson(_releaseJson());
      expect(result.status, UpdateCheckStatus.updateAvailable);
      expect(result.isUpdateAvailable, isTrue);
      expect(result.latestTag, 'v3.0.6');
      expect(result.releaseName, 'Btmus 3.0.6');
      expect(result.releaseNotes, 'Fixes and improvements.');
      expect(
        result.releaseUrl,
        'https://github.com/Btt1996/btmuse-3/releases/tag/v3.0.6',
      );
      expect(result.currentVersion, UpdateService.currentVersion);
    });

    test('same version parses as up to date', () {
      final result =
          UpdateCheckResult.fromReleaseJson(_releaseJson(tag: 'v3.0.5'));
      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.isUpdateAvailable, isFalse);
      expect(result.latestTag, 'v3.0.5');
    });

    test('empty notes and name become null, not empty strings', () {
      final result = UpdateCheckResult.fromReleaseJson(
        _releaseJson(name: '', body: '   ', htmlUrl: ''),
      );
      expect(result.releaseName, isNull);
      expect(result.releaseNotes, isNull);
      expect(result.releaseUrl, isNull);
    });

    test('missing tag_name throws instead of inventing a version', () {
      expect(
        () => UpdateCheckResult.fromReleaseJson({'name': 'No tag here'}),
        throwsFormatException,
      );
    });
  });

  group('UpdateService.checkForUpdates (mocked HTTP)', () {
    test('hits the releases/latest URL with the GitHub Accept header', () async {
      final seen = <RequestOptions>[];
      final dio = _dioAnswering((options) {
        seen.add(options);
        return _jsonBody(_releaseJson(tag: 'v3.0.5'));
      });
      final result = await UpdateService(dio: dio).checkForUpdates();
      expect(result.status, UpdateCheckStatus.upToDate);
      expect(seen, hasLength(1));
      expect(seen.single.uri.toString(), UpdateService.releasesApiUrl);
      expect(seen.single.headers['Accept'], 'application/vnd.github+json');
    });

    test('newer release is update available', () async {
      final dio = _dioAnswering((_) => _jsonBody(_releaseJson(tag: 'v3.0.6')));
      final result = await UpdateService(dio: dio).checkForUpdates();
      expect(result.status, UpdateCheckStatus.updateAvailable);
      expect(result.latestTag, 'v3.0.6');
    });

    test('GitHub 404 means no releases yet — never "up to date"', () async {
      final dio = _dioAnswering(
        (_) => _jsonBody({'message': 'Not Found'}, 404),
      );
      final result = await UpdateService(dio: dio).checkForUpdates();
      expect(result.status, UpdateCheckStatus.noReleases);
      expect(result.isUpdateAvailable, isFalse);
      expect(result.latestTag, isNull);
    });

    test('connection failure means offline, not error', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException('No route to host'),
        );
      });
      final result = await UpdateService(dio: dio).checkForUpdates();
      expect(result.status, UpdateCheckStatus.offline);
      expect(result.errorMessage, contains('offline'));
    });

    test('GitHub 403 surfaces as an error naming the rate limit', () async {
      final dio = _dioAnswering(
        (_) => _jsonBody({'message': 'API rate limit exceeded'}, 403),
      );
      final result = await UpdateService(dio: dio).checkForUpdates();
      expect(result.status, UpdateCheckStatus.error);
      expect(result.errorMessage, contains('403'));
    });

    test('release body without a tag is an error, not up to date', () async {
      final dio = _dioAnswering(
        (_) => _jsonBody({'name': 'Tagless release'}),
      );
      final result = await UpdateService(dio: dio).checkForUpdates();
      expect(result.status, UpdateCheckStatus.error);
    });
  });
}
