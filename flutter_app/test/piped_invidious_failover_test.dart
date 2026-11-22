import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/config/x2_config.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/x2/clients/piped_client.dart';
import 'package:btmu/features/x2/providers/youtube_provider.dart';

typedef _MockResponder = ({int statusCode, Object body}) Function(RequestOptions options);

class _FakeHttpAdapter implements HttpClientAdapter {
  final _MockResponder responder;

  _FakeHttpAdapter(this.responder);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final result = responder(options);
    final encoded = utf8.encode(jsonEncode(result.body));
    return ResponseBody.fromBytes(
      encoded,
      result.statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}

void main() {
  test('ApiClient never invents a backend URL when X2_BACKEND_URL is empty', () {
    final client = ApiClient();
    expect(client.isBackendConfigured, isFalse);
    expect(
      () => client.buildBackendUri('/api/x2/health'),
      throwsA(
        isA<NetworkFailure>().having(
          (e) => e.message,
          'message',
          contains('X2_BACKEND_URL is not configured'),
        ),
      ),
    );
  });

  test('X2Config.parseUrlList filters SSRF/private URLs and deduplicates valid endpoints', () {
    final parsed = X2Config.parseUrlList(
      'https://piped-1.example.org/, http://localhost:3000, https://127.0.0.1:8080, https://192.168.1.5, https://piped-1.example.org, https://piped-2.example.org',
    );
    expect(parsed, ['https://piped-1.example.org', 'https://piped-2.example.org']);
  });

  test('PipedClient probes availability first and fails over to secondary Piped instance', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeHttpAdapter((options) {
      final url = options.uri.toString();
      if (url.startsWith('https://piped-dead.example.org')) {
        return (statusCode: 503, body: {'error': 'Service Unavailable'});
      }
      if (url.startsWith('https://piped-live.example.org/trending')) {
        return (
          statusCode: 200,
          body: [
            {'url': '/watch?v=abc123', 'title': 'Sample'},
          ],
        );
      }
      if (url.startsWith('https://piped-live.example.org/search')) {
        return (
          statusCode: 200,
          body: {
            'items': [
              {
                'url': '/watch?v=xyz789',
                'title': 'Midnight Skyline',
                'uploaderName': 'Kairo',
                'duration': 215,
                'thumbnail': 'https://img.example.org/thumb.jpg',
              },
            ],
          },
        );
      }
      return (statusCode: 404, body: {'error': 'Not found'});
    });

    final client = ApiClient(
      customDio: dio,
      pipedInstances: const [
        'https://piped-dead.example.org',
        'https://piped-live.example.org',
      ],
    );
    final piped = PipedClient(client);
    final res = await piped.search('Midnight Skyline', client.pipedInstances);

    expect(res.ok, isTrue);
    expect(res.providerUsed, 'piped');
    expect(res.instanceUsed, 'https://piped-live.example.org');
    expect(res.items.length, 1);
    expect(res.items.first.title, 'Midnight Skyline');
    expect(res.attempts.first.ok, isFalse);
    expect(res.attempts.first.stage, 'probe');
  });

  test('YoutubeProvider fails over from unavailable Piped instances to healthy Invidious', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeHttpAdapter((options) {
      final url = options.uri.toString();
      if (url.startsWith('https://piped-bad.example.org')) {
        return (statusCode: 502, body: {'error': 'Bad Gateway'});
      }
      if (url.startsWith('https://invidious-ok.example.org/api/v1/stats')) {
        return (statusCode: 200, body: {'version': '2.0', 'openRegistrations': false});
      }
      if (url.startsWith('https://invidious-ok.example.org/api/v1/search')) {
        return (
          statusCode: 200,
          body: [
            {
              'videoId': 'inv999',
              'title': 'Aurora Waves',
              'author': 'Lumina',
              'lengthSeconds': 184,
              'videoThumbnails': [
                {'url': 'https://img.example.org/aurora.jpg'},
              ],
            },
          ],
        );
      }
      return (statusCode: 500, body: {'error': 'Unexpected URL'});
    });

    final client = ApiClient(
      customDio: dio,
      pipedInstances: const ['https://piped-bad.example.org'],
      invidiousInstances: const ['https://invidious-ok.example.org'],
    );
    final youtube = YoutubeProvider(client);
    final trace = await youtube.searchWithAttemptTrace('Aurora Waves');

    expect(trace.ok, isTrue);
    expect(trace.providerUsed, 'invidious');
    expect(trace.instanceUsed, 'https://invidious-ok.example.org');
    expect(trace.items.first.title, 'Aurora Waves');
    expect(trace.attempts.any((a) => a.provider == 'piped' && !a.ok), isTrue);
    expect(trace.attempts.any((a) => a.provider == 'invidious' && a.ok), isTrue);
  });

  test('YoutubeProvider reports explicit unconfigured error when all config vars are empty', () async {
    final client = ApiClient();
    final youtube = YoutubeProvider(client);

    expect(
      () => youtube.searchTracks('test song'),
      throwsA(
        isA<NetworkFailure>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('PIPED_API_URL'),
            contains('INVIDIOUS_API_URL'),
            contains('X2_BACKEND_URL'),
          ),
        ),
      ),
    );
  });
}
