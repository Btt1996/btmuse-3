import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/x2/providers/spotify_metadata_provider.dart';

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

Map<String, dynamic> _userPlaylistsJson() {
  return {
    'displayName': 'DJ Test',
    'avatarUrl': 'https://avatar.example.com/u.jpg',
    'playlists': [
      {
        'id': 'pl1',
        'name': 'Chill Hits',
        'description': 'Relax',
        'trackCount': 42,
        'coverUrl': 'https://cover.example.com/1.jpg',
        'ownerName': 'Spotify',
        'externalUrl': 'https://open.spotify.com/playlist/pl1',
      },
      {
        'id': 'pl2',
        'name': 'No Cover List',
        'description': '',
        'trackCount': 0,
        'ownerName': 'Someone',
        'externalUrl': 'https://open.spotify.com/playlist/pl2',
      },
    ],
  };
}

/// Dio stubbed to answer the backend user-playlists endpoint.
/// Captures every request so tests can prove no Spotify credentials
/// ever leave the app (the server holds them).
({Dio dio, List<RequestOptions> seenRequests}) _backendDio({
  required Map<String, dynamic> Function() responseJson,
  int statusCode = 200,
}) {
  final seenRequests = <RequestOptions>[];
  final dio = Dio();
  dio.httpClientAdapter = _StubAdapter((options) {
    seenRequests.add(options);
    return ResponseBody.fromString(
      jsonEncode(responseJson()),
      statusCode,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  });
  return (dio: dio, seenRequests: seenRequests);
}

void main() {
  group('SpotifyMetadataProvider.fetchUserPlaylists', () {
    test('parses a sample /api/spotify/user payload into summaries', () async {
      final stub = _backendDio(responseJson: _userPlaylistsJson);
      final api = ApiClient(
        backendBaseUrl: 'https://backend.example.com',
        customDio: stub.dio,
      );
      final provider = SpotifyMetadataProvider(api);

      final result = await provider.fetchUserPlaylists('spotify');

      expect(result.userId, 'spotify');
      expect(result.displayName, 'DJ Test');
      expect(result.avatarUrl, 'https://avatar.example.com/u.jpg');
      expect(result.playlists.length, 2);

      final first = result.playlists[0];
      expect(first.id, 'pl1');
      expect(first.name, 'Chill Hits');
      expect(first.description, 'Relax');
      expect(first.trackCount, 42);
      expect(first.coverUrl, 'https://cover.example.com/1.jpg');
      expect(first.ownerName, 'Spotify');
      expect(first.externalUrl, 'https://open.spotify.com/playlist/pl1');

      final second = result.playlists[1];
      expect(second.name, 'No Cover List');
      expect(second.trackCount, 0);
      expect(second.coverUrl, isNull);
      expect(second.ownerName, 'Someone');
    });

    test('accepts a profile URL and sends only the bare user ID', () async {
      final stub = _backendDio(responseJson: _userPlaylistsJson);
      final api = ApiClient(
        backendBaseUrl: 'https://backend.example.com',
        customDio: stub.dio,
      );
      final provider = SpotifyMetadataProvider(api);

      final result = await provider.fetchUserPlaylists(
        'https://open.spotify.com/user/spotify?si=abc123',
      );

      expect(result.userId, 'spotify');
      expect(stub.seenRequests.length, 1);
      final uri = stub.seenRequests.first.uri;
      expect(uri.path, '/api/spotify/user');
      expect(uri.queryParameters['userId'], 'spotify');
    });

    test('422 / no server credentials surfaces the backend details text', () async {
      final stub = _backendDio(
        responseJson: () => {
          'error': 'Spotify credentials not configured',
          'details':
              'The server has no Spotify API credentials configured (missing: SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET). Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET on the server to enable Spotify user discovery.',
        },
        statusCode: 422,
      );
      final api = ApiClient(
        backendBaseUrl: 'https://backend.example.com',
        customDio: stub.dio,
      );
      final provider = SpotifyMetadataProvider(api);
      expect(
        () => provider.fetchUserPlaylists('spotify'),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.message,
            'message',
            contains('SPOTIFY_CLIENT_ID'),
          ),
        ),
      );
    });

    test('without a backend it fails honestly and names X2_BACKEND_URL', () async {
      final provider = SpotifyMetadataProvider(ApiClient());
      expect(
        () => provider.fetchUserPlaylists('spotify'),
        throwsA(
          isA<NetworkFailure>()
              .having((e) => e.code, 'code', 'spotify_user_needs_backend')
              .having((e) => e.message, 'message', contains('X2_BACKEND_URL')),
        ),
      );
    });

    test('fetchUserPlaylists never sends credentials', () async {
      final stub = _backendDio(responseJson: _userPlaylistsJson);
      final api = ApiClient(
        backendBaseUrl: 'https://backend.example.com',
        customDio: stub.dio,
      );
      final provider = SpotifyMetadataProvider(api);

      await provider.fetchUserPlaylists('spotify');

      expect(stub.seenRequests.length, 1);
      final request = stub.seenRequests.first;
      // The app holds no Spotify credentials: the only Authorization
      // in this flow is the server's own Bearer token to Spotify,
      // which the app never sees and never sends.
      expect(
        request.headers.keys.any((k) => k.toLowerCase() == 'authorization'),
        isFalse,
      );
      expect(request.uri.queryParameters.containsKey('clientId'), isFalse);
      expect(request.uri.queryParameters.containsKey('clientSecret'), isFalse);
      expect(request.data, isNull);
    });

    test('an invalid user input is rejected without a network call', () async {
      final stub = _backendDio(responseJson: _userPlaylistsJson);
      final api = ApiClient(
        backendBaseUrl: 'https://backend.example.com',
        customDio: stub.dio,
      );
      final provider = SpotifyMetadataProvider(api);
      expect(
        () => provider.fetchUserPlaylists('not a user!!!'),
        throwsA(
          isA<ValidationFailure>()
              .having((e) => e.code, 'code', 'spotify_user_invalid'),
        ),
      );
      expect(stub.seenRequests, isEmpty);
    });
  });

  group('SpotifyMetadataProvider.parseUserId', () {
    test('plain username passes through', () {
      expect(SpotifyMetadataProvider.parseUserId('spotify'), 'spotify');
    });

    test('profile URL yields the bare ID, query string ignored', () {
      expect(
        SpotifyMetadataProvider.parseUserId(
          'https://open.spotify.com/user/spotify?si=abc',
        ),
        'spotify',
      );
    });

    test('spotify:user: URI yields the bare ID', () {
      expect(
        SpotifyMetadataProvider.parseUserId('spotify:user:spotify'),
        'spotify',
      );
    });

    test('@handle yields the bare ID', () {
      expect(SpotifyMetadataProvider.parseUserId('@spotify'), 'spotify');
    });

    test('empty and garbage inputs return null', () {
      expect(SpotifyMetadataProvider.parseUserId(''), isNull);
      expect(SpotifyMetadataProvider.parseUserId('   '), isNull);
      expect(SpotifyMetadataProvider.parseUserId('not a user!!!'), isNull);
      expect(
        SpotifyMetadataProvider.parseUserId('https://example.com/user/x'),
        isNull,
      );
    });
  });
}
