import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/x2/providers/jamendo_provider.dart';

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

Map<String, dynamic> _trackJson({
  required int id,
  required String name,
  String? downloadUrl,
  String? streamUrl,
}) {
  return {
    'id': id,
    'name': name,
    'duration': 187,
    'artist_name': 'Indie Artist',
    'artist_id': '42',
    'album_name': 'Summer EP',
    'album_image': 'https://images.example.org/album.jpg',
    'image': 'https://images.example.org/track.jpg',
    'audio': streamUrl ?? 'https://audio.example.org/stream/$id.mp3',
    'audiodownload': downloadUrl,
    'license_ccurl': 'https://creativecommons.org/licenses/by/3.0/',
    'shareurl': 'https://www.jamendo.com/track/$id/summer-breeze',
  };
}

/// Dio stubbed to answer the Jamendo tracks endpoint. Captures every
/// request so tests can prove the client ID is sent (and that no client
/// secret is ever sent) and that the no-ID path makes zero requests.
({Dio dio, List<RequestOptions> seenRequests}) _jamendoDio() {
  final seenRequests = <RequestOptions>[];
  final dio = Dio();
  dio.httpClientAdapter = _StubAdapter((options) {
    seenRequests.add(options);
    final query = options.uri.queryParameters;
    if (query['id'] == '123') {
      return _jsonBody({
        'headers': {'status': 'success', 'code': 0},
        'results': [
          _trackJson(
            id: 123,
            name: 'Summer Breeze',
            downloadUrl: 'https://audio.example.org/download/123.mp3',
          ),
        ],
      });
    }
    return _jsonBody({
      'headers': {'status': 'success', 'code': 0},
      'results': [
        _trackJson(
          id: 123,
          name: 'Summer Breeze',
          downloadUrl: 'https://audio.example.org/download/123.mp3',
        ),
        _trackJson(id: 456, name: 'Stream Only', downloadUrl: null),
      ],
    });
  });
  return (dio: dio, seenRequests: seenRequests);
}

void main() {
  group('JamendoProvider without a client ID', () {
    test('search is not offered and throws the named Settings error', () async {
      final stub = _jamendoDio();
      final provider = JamendoProvider(ApiClient(customDio: stub.dio));

      expect(provider.supportsKeywordSearch, isFalse);
      expect(provider.supportsUrlResolution, isTrue);

      expect(
        () => provider.searchTracks('summer'),
        throwsA(
          isA<AuthorizationFailure>()
              .having((e) => e.code, 'code', 'jamendo_client_id_missing')
              .having(
                (e) => e.message,
                'message',
                contains('Jamendo client ID in Settings'),
              ),
        ),
      );
      // The honest failure happens before any HTTP request is made.
      expect(stub.seenRequests, isEmpty);
    });

    test('URL resolution also refuses without a client ID', () async {
      final stub = _jamendoDio();
      final provider = JamendoProvider(ApiClient(customDio: stub.dio));
      expect(
        () => provider.resolveUrl(
          Uri.parse('https://www.jamendo.com/track/123/summer-breeze'),
        ),
        throwsA(isA<AuthorizationFailure>().having(
          (e) => e.message,
          'message',
          contains('Jamendo client ID in Settings'),
        )),
      );
      expect(stub.seenRequests, isEmpty);
    });
  });

  group('JamendoProvider with a client ID', () {
    test('search parses tracks and sends only the client ID', () async {
      final stub = _jamendoDio();
      final provider = JamendoProvider(
        ApiClient(customDio: stub.dio),
        jamendoClientId: 'test-client-id',
      );

      expect(provider.supportsKeywordSearch, isTrue);

      final results = await provider.searchTracks('summer');

      expect(results.length, 2);

      final first = results[0];
      expect(first.providerId, 'jamendo');
      expect(first.title, 'Summer Breeze');
      expect(first.artist, 'Indie Artist');
      expect(first.album, 'Summer EP');
      expect(first.durationSeconds, 187);
      expect(first.artworkUrl, 'https://images.example.org/album.jpg');
      expect(first.audioUrl, 'https://audio.example.org/download/123.mp3');
      expect(first.audioAvailable, isTrue);
      expect(first.downloadAuthorized, isTrue);
      expect(first.licenseName, 'Creative Commons');
      expect(first.authorizationNote, contains('Jamendo'));

      // A track with no audiodownload link is stream-only, honestly.
      final second = results[1];
      expect(second.title, 'Stream Only');
      expect(second.audioUrl, 'https://audio.example.org/stream/456.mp3');
      expect(second.downloadAuthorized, isFalse);

      // Exactly one request, carrying client_id + search, no secret.
      expect(stub.seenRequests.length, 1);
      final query = stub.seenRequests.first.uri.queryParameters;
      expect(query['client_id'], 'test-client-id');
      expect(query['format'], 'json');
      expect(query['search'], 'summer');
      expect(query.containsKey('clientSecret'), isFalse);
      expect(query.containsKey('client_secret'), isFalse);
    });

    test('resolveUrl resolves a Jamendo track page by ID', () async {
      final stub = _jamendoDio();
      final provider = JamendoProvider(
        ApiClient(customDio: stub.dio),
        jamendoClientId: 'test-client-id',
      );

      final resolved = await provider.resolveUrl(
        Uri.parse('https://www.jamendo.com/track/123/summer-breeze'),
      );

      expect(resolved, isNotNull);
      expect(resolved!.id, 'jam_123');
      expect(resolved.title, 'Summer Breeze');
      expect(stub.seenRequests.first.uri.queryParameters['id'], '123');

      // Non-track Jamendo pages resolve to null, not a fake result.
      expect(
        await provider.resolveUrl(Uri.parse('https://www.jamendo.com/artist/42/x')),
        isNull,
      );
    });

    test('provider flags and URL routing', () {
      final provider = JamendoProvider(ApiClient(), jamendoClientId: 'x');
      expect(provider.id, 'jamendo');
      expect(provider.isMetadataOnly, isFalse);
      expect(provider.canHandleUrl(Uri.parse('https://www.jamendo.com/track/1/x')), isTrue);
      expect(provider.canHandleUrl(Uri.parse('https://example.org/track/1/x')), isFalse);
    });
  });
}
