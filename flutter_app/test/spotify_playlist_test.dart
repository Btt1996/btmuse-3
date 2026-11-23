import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/features/x2/providers/library_matcher.dart';
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

Track _track({
  required String id,
  String title = 'Song',
  String artist = 'Artist',
  String sha256 = 'aabbcc',
}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    album: 'Single',
    durationSeconds: 180,
    localFilePath: '/tmp/btmu_audio/$id.mp3',
    format: 'MP3',
    fileSizeBytes: 1000,
    sha256: sha256,
    sourceProvider: 'local_file',
    addedAtMs: 1000,
  );
}

/// Fake repository that answers `getAllTracks` from memory and never
/// touches sqflite: the real repository needs a device database,
/// which unit tests do not have.
class _FakeLibraryRepository extends LibraryRepository {
  _FakeLibraryRepository(this.tracks) : super(LocalDatabase.instance);

  final List<Track> tracks;

  @override
  Future<List<Track>> getAllTracks({String? query, bool favoritesOnly = false}) async =>
      tracks;
}

const _playlistUri = 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M';

Map<String, dynamic> _embedPlaylistJson() {
  return {
    'source': 'spotify',
    'playlistTitle': 'Test Playlist',
    'playlistDescription': 'A test list',
    'playlistCoverUrl': 'https://cover.example.com/x.jpg',
    'externalUrl': _playlistUri,
    'totalTracks': 3,
    'tracks': [
      {
        'title': 'Midnight City',
        'artists': ['M83'],
        'album': "Hurry Up, We're Dreaming",
        'durationMs': 243000,
        'isrc': 'USQX91200347',
        'artworkUrl': null,
        'position': 0,
      },
      {
        'title': 'Dreams',
        'artists': ['Fleetwood Mac'],
        'album': 'Rumours',
        'durationMs': 257000,
        'isrc': 'USWB77000156',
        'artworkUrl': 'https://art.example.com/rumours.jpg',
        'position': 1,
      },
      {
        'title': 'Unknown Song',
        'artists': <String>[],
        'album': 'Test Playlist',
        'durationMs': 0,
        'isrc': null,
        'artworkUrl': null,
        'position': 2,
      },
    ],
  };
}

/// Dio stubbed to answer the backend playlist endpoint. Captures the
/// request so tests can prove no Spotify credentials ever leave the app.
({Dio dio, List<Map<String, dynamic>?> seenBodies}) _backendDio({
  required Map<String, dynamic> Function() responseJson,
  int statusCode = 200,
}) {
  final seenBodies = <Map<String, dynamic>?>[];
  final dio = Dio();
  dio.httpClientAdapter = _StubAdapter((options) {
    seenBodies.add(options.data is Map ? Map<String, dynamic>.from(options.data as Map) : null);
    return ResponseBody.fromString(
      jsonEncode(responseJson()),
      statusCode,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  });
  return (dio: dio, seenBodies: seenBodies);
}

void main() {
  group('SpotifyMetadataProvider.fetchPlaylist', () {
    test('maps the backend embed response to metadata-only results', () async {
      final stub = _backendDio(responseJson: _embedPlaylistJson);
      final api = ApiClient(
        backendBaseUrl: 'https://backend.example.com',
        customDio: stub.dio,
      );
      final provider = SpotifyMetadataProvider(api);

      final playlist = await provider.fetchPlaylist(Uri.parse(_playlistUri));

      expect(playlist.title, 'Test Playlist');
      expect(playlist.description, 'A test list');
      expect(playlist.coverUrl, 'https://cover.example.com/x.jpg');
      expect(playlist.totalTracks, 3);
      expect(playlist.tracks.length, 3);
      expect(playlist.inLibraryCount, 0);

      final first = playlist.tracks[0].result;
      expect(first.title, 'Midnight City');
      expect(first.artist, 'M83');
      expect(first.album, "Hurry Up, We're Dreaming");
      expect(first.durationSeconds, 243);
      expect(first.artworkUrl, 'https://cover.example.com/x.jpg');
      expect(first.providerId, 'spotify');
      expect(first.audioAvailable, isFalse);
      expect(first.downloadAuthorized, isFalse);
      expect(first.authorizationNote, contains('cannot be downloaded'));

      final second = playlist.tracks[1].result;
      expect(second.title, 'Dreams');
      expect(second.artist, 'Fleetwood Mac');
      expect(second.artworkUrl, 'https://art.example.com/rumours.jpg');

      final third = playlist.tracks[2].result;
      expect(third.artist, 'Unknown Artist');
      expect(third.durationSeconds, 0);

      // The request carries only the URL + id: no Spotify credentials
      // ever leave the app (the official-API fallback uses the
      // server's own environment credentials).
      expect(stub.seenBodies.length, 1);
      expect(stub.seenBodies.first?['url'], _playlistUri);
      expect(stub.seenBodies.first?.containsKey('clientId'), isFalse);
      expect(stub.seenBodies.first?.containsKey('clientSecret'), isFalse);
    });

    test('marks tracks already in the library (normalized title + artist)', () async {
      final stub = _backendDio(responseJson: _embedPlaylistJson);
      final api = ApiClient(
        backendBaseUrl: 'https://backend.example.com',
        customDio: stub.dio,
      );
      final repo = _FakeLibraryRepository([
        // Punctuation/case differ from the playlist entry on purpose:
        // the normalized deduplication key must still match.
        _track(id: 't-m83', title: 'midnight city!', artist: 'm83'),
        _track(id: 't-other', title: 'Other Song', artist: 'Someone Else'),
      ]);
      final provider = SpotifyMetadataProvider(api);

      final playlist = await provider.fetchPlaylist(
        Uri.parse(_playlistUri),
        libraryRepository: repo,
      );

      expect(playlist.inLibraryCount, 1);
      expect(playlist.tracks[0].isInLibrary, isTrue);
      expect(playlist.tracks[0].existingTrack?.id, 't-m83');
      expect(playlist.tracks[1].isInLibrary, isFalse);
      expect(playlist.tracks[1].existingTrack, isNull);
      expect(playlist.tracks[2].isInLibrary, isFalse);
    });

    test('without a backend it fails honestly instead of inventing one', () async {
      final provider = SpotifyMetadataProvider(ApiClient());
      expect(
        () => provider.fetchPlaylist(Uri.parse(_playlistUri)),
        throwsA(
          isA<NetworkFailure>()
              .having((e) => e.code, 'code', 'spotify_playlist_needs_backend')
              .having((e) => e.message, 'message', contains('X2_BACKEND_URL')),
        ),
      );
    });

    test('a single track link is rejected with a pointer to metadata resolve', () async {
      final stub = _backendDio(responseJson: _embedPlaylistJson);
      final api = ApiClient(
        backendBaseUrl: 'https://backend.example.com',
        customDio: stub.dio,
      );
      final provider = SpotifyMetadataProvider(api);
      expect(
        () => provider.fetchPlaylist(
          Uri.parse('https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC'),
        ),
        throwsA(
          isA<ValidationFailure>()
              .having((e) => e.code, 'code', 'spotify_not_playlist')
              .having((e) => e.message, 'message', contains('playlist or album')),
        ),
      );
      expect(stub.seenBodies, isEmpty);
    });

    test('surfaces the server error details on a failed lookup', () async {
      final stub = _backendDio(
        responseJson: () => {
          'error': 'Playlist Resolution Failed',
          'details': 'This Spotify playlist is private, deleted, or unavailable.',
        },
        statusCode: 422,
      );
      final api = ApiClient(
        backendBaseUrl: 'https://backend.example.com',
        customDio: stub.dio,
      );
      final provider = SpotifyMetadataProvider(api);
      expect(
        () => provider.fetchPlaylist(Uri.parse(_playlistUri)),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.message,
            'message',
            contains('private, deleted, or unavailable'),
          ),
        ),
      );
    });
  });

  group('LibraryMatcher', () {
    test('hash match wins even when title and artist differ', () {
      final library = [
        _track(id: 't-hash', title: 'Retagged Title', artist: 'Someone Else', sha256: 'ff00ff'),
      ];
      final found = LibraryMatcher.findInLibrary(
        library,
        title: 'Original Title',
        artist: 'Original Artist',
        sha256: 'ff00ff',
      );
      expect(found?.id, 't-hash');
    });

    test('an empty hash never matches by hash', () {
      final library = [_track(id: 't-empty', title: 'Other', artist: 'Other', sha256: '')];
      expect(
        LibraryMatcher.findInLibrary(library, title: 'Song', artist: 'Artist', sha256: ''),
        isNull,
      );
      expect(
        LibraryMatcher.findInLibrary(library, title: 'Song', artist: 'Artist'),
        isNull,
      );
    });

    test('title + artist match is case- and punctuation-insensitive', () {
      final library = [_track(id: 't-m', title: 'Midnight City!', artist: 'M83')];
      expect(
        LibraryMatcher.findInLibrary(library, title: 'midnight city', artist: 'm83')?.id,
        't-m',
      );
      expect(
        LibraryMatcher.findInLibrary(library, title: 'Midnight City', artist: 'M83')?.id,
        't-m',
      );
    });

    test('returns null when nothing matches', () {
      final library = [_track(id: 't-a', title: 'Alpha', artist: 'Beta')];
      expect(
        LibraryMatcher.findInLibrary(library, title: 'Gamma', artist: 'Delta'),
        isNull,
      );
      expect(LibraryMatcher.findInLibrary([], title: 'Gamma', artist: 'Delta'), isNull);
    });
  });
}
