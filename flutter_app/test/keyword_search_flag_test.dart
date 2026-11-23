import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/x2/providers/provider_manager.dart';
import 'package:btmu/features/x2/providers/soundcloud_provider.dart';
import 'package:btmu/features/x2/providers/vk_provider.dart';
import 'package:btmu/features/x2/x2_search_engine.dart';

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

void main() {
  group('VK & SoundCloud keyword-search capability flags', () {
    test('both providers report supportsKeywordSearch false', () {
      final api = ApiClient();
      expect(VkProvider(api).supportsKeywordSearch, isFalse);
      expect(SoundCloudProvider(api).supportsKeywordSearch, isFalse);
    });

    test('both searchTracks still throw their honest AuthorizationFailure', () async {
      final api = ApiClient();
      expect(
        () => VkProvider(api).searchTracks('daft punk'),
        throwsA(
          isA<AuthorizationFailure>()
              .having((e) => e.code, 'code', 'vk_auth_required')
              .having((e) => e.message, 'message', contains('audio.search')),
        ),
      );
      expect(
        () => SoundCloudProvider(api).searchTracks('lofi beats'),
        throwsA(
          isA<AuthorizationFailure>()
              .having((e) => e.code, 'code', 'soundcloud_search_restricted')
              .having((e) => e.message, 'message', contains('closed')),
        ),
      );
    });

    test('ProviderManager excludes both from keyword search but keeps URL resolution', () {
      final api = ApiClient();
      final manager = ProviderManager([VkProvider(api), SoundCloudProvider(api)]);
      expect(manager.searchProviders, isEmpty);
      expect(manager.urlProviders.length, 2);
      expect(
        manager.findProviderForUrl(Uri.parse('https://vk.com/audio123'))?.id,
        'vk',
      );
      expect(
        manager
            .findProviderForUrl(Uri.parse('https://soundcloud.com/artist/track'))
            ?.id,
        'soundcloud',
      );
    });

    test('X2 keyword search no longer collects their guaranteed failures', () async {
      final api = ApiClient();
      final engine = X2SearchEngine(
        ProviderManager([VkProvider(api), SoundCloudProvider(api)]),
      );
      final response = await engine.search('daft punk');
      expect(response.results, isEmpty);
      expect(response.providerErrors, isEmpty);
      expect(response.isUrlLookup, isFalse);
    });

    test('VK token search still works: the flag flip hides no working path', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter((options) {
        expect(options.uri.host, 'api.vk.com');
        return ResponseBody.fromString(
          jsonEncode({
            'response': {
              'items': [
                {
                  'owner_id': 1,
                  'id': 2,
                  'title': 'Song',
                  'artist': 'Artist',
                  'duration': 180,
                  'url': 'https://cdn.example.com/track.mp3',
                },
              ],
            },
          }),
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      });

      final vk = VkProvider(ApiClient(customDio: dio));
      final results = await vk.searchWithUserToken('song', vkAccessToken: 'user-token');
      expect(results.length, 1);
      expect(results.first.title, 'Song');
      expect(results.first.downloadAuthorized, isTrue);
      expect(results.first.format, 'MP3');
    });
  });
}
