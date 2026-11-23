import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/x2/custom_provider.dart';
import 'package:btmu/features/x2/providers/provider_manager.dart';

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
  group('CustomX2ProviderConfig', () {
    test('valid http(s) URL with a host and a name is valid', () {
      const c = CustomX2ProviderConfig(
        id: '1',
        name: 'My Blog',
        baseUrl: 'https://music.example.com/feed.xml',
      );
      expect(c.isValid, isTrue);
      expect(c.host, 'music.example.com');
    });

    test('empty name, bad scheme, or missing host is invalid', () {
      expect(
        const CustomX2ProviderConfig(id: '1', name: ' ', baseUrl: 'https://x.com/')
            .isValid,
        isFalse,
      );
      expect(
        const CustomX2ProviderConfig(id: '1', name: 'X', baseUrl: 'ftp://x.com/')
            .isValid,
        isFalse,
      );
      expect(
        const CustomX2ProviderConfig(id: '1', name: 'X', baseUrl: 'https://')
            .isValid,
        isFalse,
      );
      expect(
        const CustomX2ProviderConfig(id: '', name: 'X', baseUrl: 'https://x.com/')
            .isValid,
        isFalse,
      );
    });

    test('JSON round-trip preserves id, name and URL', () {
      const c = CustomX2ProviderConfig(
        id: 'abc',
        name: 'My Source',
        baseUrl: 'https://example.com/feed',
      );
      final back = CustomX2ProviderConfig.fromJson(c.toJson());
      expect(back.id, 'abc');
      expect(back.name, 'My Source');
      expect(back.baseUrl, 'https://example.com/feed');
    });
  });

  group('CustomX2Provider', () {
    final api = ApiClient();

    test('handles its own host and subdomains, nothing else', () {
      const config = CustomX2ProviderConfig(
        id: '1',
        name: 'My Blog',
        baseUrl: 'https://music.example.com/feed.xml',
      );
      final provider = CustomX2Provider(config, api);
      expect(provider.id, 'custom_1');
      expect(provider.displayName, 'My Blog');
      expect(provider.supportsKeywordSearch, isFalse);
      expect(provider.supportsUrlResolution, isTrue);
      expect(
        provider.canHandleUrl(Uri.parse('https://music.example.com/a.mp3')),
        isTrue,
      );
      expect(
        provider.canHandleUrl(Uri.parse('https://cdn.music.example.com/a.mp3')),
        isTrue,
      );
      expect(
        provider.canHandleUrl(Uri.parse('https://other.example.com/a.mp3')),
        isFalse,
      );
      expect(
        provider.canHandleUrl(Uri.parse('https://music.example.com.evil.com/a.mp3')),
        isFalse,
      );
    });

    test('keyword search returns nothing by design', () async {
      const config = CustomX2ProviderConfig(
        id: '1',
        name: 'My Blog',
        baseUrl: 'https://music.example.com/',
      );
      final provider = CustomX2Provider(config, api);
      expect(await provider.searchTracks('anything'), isEmpty);
    });

    test('resolves a direct audio URL through the shared validation', () async {
      final dio = Dio()..httpClientAdapter = _StubAdapter((options) {
          return ResponseBody.fromString(
            '{}',
            200,
            headers: {
              'content-type': ['audio/mpeg'],
              'content-length': ['12345'],
            },
          );
        });
      final stubApi = ApiClient(customDio: dio);
      const config = CustomX2ProviderConfig(
        id: '1',
        name: 'My Blog',
        baseUrl: 'https://music.example.com/',
      );
      final provider = CustomX2Provider(config, stubApi);
      final result = await provider.resolveUrl(
        Uri.parse('https://music.example.com/songs/my-song.mp3'),
      );
      expect(result, isNotNull);
      expect(result!.title, 'my-song');
      expect(result.downloadAuthorized, isTrue);
      expect(result.providerId, 'custom_1');
    });

    test('custom providers win over the generic direct-URL provider', () {
      final custom = CustomX2Provider(
        const CustomX2ProviderConfig(
          id: '1',
          name: 'My Blog',
          baseUrl: 'https://music.example.com/',
        ),
        api,
      );
      final manager = ProviderManager([custom]);
      expect(
        manager.findProviderForUrl(
          Uri.parse('https://music.example.com/a.mp3'),
        ),
        same(custom),
      );
    });
  });

  group('CustomProviderStore', () {
    test('round-trips configs and drops invalid ones', () async {
      SharedPreferences.setMockInitialValues({});
      final store = CustomProviderStore();
      await store.save([
        const CustomX2ProviderConfig(
          id: '1',
          name: 'Good',
          baseUrl: 'https://example.com/feed',
        ),
        const CustomX2ProviderConfig(id: '2', name: '', baseUrl: 'https://x.com/'),
      ]);
      final loaded = await CustomProviderStore().load();
      expect(loaded.length, 1);
      expect(loaded.first.name, 'Good');
    });

    test('empty store loads empty', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await CustomProviderStore().load(), isEmpty);
    });
  });

  group('CustomProvidersNotifier', () {
    test('add rejects bad input, accepts good input, remove works', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = CustomProvidersNotifier(CustomProviderStore(), ApiClient());
      // Let the constructor's async load finish (empty store).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.state, isEmpty);

      expect(
        await notifier.addProvider(name: '', baseUrl: 'https://x.com/'),
        isFalse,
      );
      expect(
        await notifier.addProvider(name: 'X', baseUrl: 'not a url'),
        isFalse,
      );
      expect(notifier.state, isEmpty);

      expect(
        await notifier.addProvider(
          name: 'My Blog',
          baseUrl: 'https://music.example.com/feed.xml',
        ),
        isTrue,
      );
      expect(notifier.state.length, 1);
      expect(notifier.state.first.displayName, 'My Blog');

      final id = (notifier.state.first as CustomX2Provider).config.id;
      await notifier.removeProvider(id);
      expect(notifier.state, isEmpty);
    });
  });
}
