import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/data/models/playlist.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/playlist_repository.dart';

// Fake repo owning an in-memory playlist list — same pattern as
// backup_service_test.dart: no sqflite database is ever opened.
// Constructing with LocalDatabase.instance performs no I/O.
class _FakePlaylistRepository extends PlaylistRepository {
  final List<Playlist> stored;
  _FakePlaylistRepository(List<Playlist> initial)
      : stored = List<Playlist>.of(initial),
        super(LocalDatabase.instance);

  @override
  Future<List<Playlist>> getAllPlaylists() async => List<Playlist>.of(stored);

  @override
  Future<Playlist> createPlaylist({
    required String name,
    String description = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final playlist = Playlist(
      id: 'pl-${stored.length + 1}',
      name: name,
      description: description,
      createdAtMs: now,
      updatedAtMs: now,
    );
    stored.add(playlist);
    return playlist;
  }

  @override
  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    final index = stored.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    final playlist = stored[index];
    if (playlist.trackIds.contains(trackId)) return;
    stored[index] = playlist.copyWith(
      trackIds: [...playlist.trackIds, trackId],
    );
  }
}

Track _track({
  required String id,
  required String title,
  required String artist,
  String sha256 = '',
  String album = 'Single',
}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    album: album,
    durationSeconds: 180,
    localFilePath: '/docs/$id.mp3',
    format: 'mp3',
    fileSizeBytes: 1000,
    sha256: sha256,
    sourceProvider: 'local_file',
    addedAtMs: 1000,
  );
}

Playlist _playlist({required String id, required String name}) {
  return Playlist(
    id: id,
    name: name,
    createdAtMs: 1000,
    updatedAtMs: 1000,
  );
}

void main() {
  group('Playlist JSON export / parse', () {
    test('export round-trips through parse with sha256 preserved', () {
      final playlist = _playlist(id: 'pl-1', name: 'Road Trip');
      final tracks = [
        _track(id: 't1', title: 'Song One', artist: 'Singer A', sha256: 'aaa'),
        _track(id: 't2', title: 'Song Two', artist: 'Singer B', sha256: 'bbb'),
      ];
      final json = PlaylistRepository.exportPlaylistJson(
        playlist: playlist,
        tracks: tracks,
      );
      final doc = PlaylistExportDocument.parseJson(json);
      expect(doc.name, 'Road Trip');
      expect(doc.tracks, hasLength(2));
      expect(doc.tracks[0].title, 'Song One');
      expect(doc.tracks[0].sha256, 'aaa');
      expect(doc.tracks[1].artist, 'Singer B');
      expect(doc.exportedAt, isNotNull);
    });

    test('export document is versioned and names its own format', () {
      final json = PlaylistRepository.exportPlaylistJson(
        playlist: _playlist(id: 'pl-1', name: 'Mix'),
        tracks: const [],
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['app'], 'btmu');
      expect(decoded['format'], 'btmu-playlist');
      expect(decoded['version'], 1);
    });

    test('parse rejects non-JSON, wrong app, wrong format, wrong version', () {
      expect(
        () => PlaylistExportDocument.parseJson('not json'),
        throwsA(isA<PlaylistFormatException>()),
      );
      expect(
        () => PlaylistExportDocument.parseJson(jsonEncode({
              'app': 'other',
              'format': 'btmu-playlist',
              'version': 1,
              'playlist': {'name': 'X'},
              'tracks': [],
            })),
        throwsA(isA<PlaylistFormatException>()),
      );
      // A full-library backup document must NOT parse as a playlist
      // export: the formats are distinct on purpose.
      expect(
        () => PlaylistExportDocument.parseJson(jsonEncode({
              'app': 'btmu',
              'version': 2,
              'tracks': [],
              'playlists': [],
            })),
        throwsA(isA<PlaylistFormatException>()),
      );
      expect(
        () => PlaylistExportDocument.parseJson(jsonEncode({
              'app': 'btmu',
              'format': 'btmu-playlist',
              'version': 99,
              'playlist': {'name': 'X'},
              'tracks': [],
            })),
        throwsA(isA<PlaylistFormatException>()),
      );
    });

    test('export file name is slugged and dated', () {
      final name = PlaylistRepository.exportFileNameJson(
        _playlist(id: 'pl-1', name: 'Road Trip!'),
        DateTime.utc(2026, 11, 22),
      );
      expect(name, 'btmu-playlist-road-trip-20261122.json');
      expect(
        PlaylistRepository.exportFileNameM3u(
          _playlist(id: 'pl-1', name: 'Road Trip!'),
          DateTime.utc(2026, 11, 22),
        ),
        'btmu-playlist-road-trip-20261122.m3u',
      );
    });
  });

  group('Playlist JSON import', () {
    test('matches by SHA-256 even when the title differs', () async {
      final repo = _FakePlaylistRepository(const []);
      final library = [
        _track(id: 't1', title: 'Original Title', artist: 'Singer A', sha256: 'aaa'),
      ];
      final json = jsonEncode({
        'app': 'btmu',
        'format': 'btmu-playlist',
        'version': 1,
        'playlist': {'name': 'Imported Mix', 'description': ''},
        'tracks': [
          {
            'title': 'Renamed Title',
            'artist': 'Someone Else',
            'album': 'Single',
            'durationSeconds': 180,
            'sha256': 'aaa',
          },
        ],
      });
      final result = await repo.importPlaylistJson(
        json,
        libraryTracks: library,
      );
      expect(result.added, 1);
      expect(result.missingLabels, isEmpty);
      expect(repo.stored.single.trackIds, ['t1']);
    });

    test('falls back to title+artist matching, case-insensitive', () async {
      final repo = _FakePlaylistRepository(const []);
      final library = [
        _track(id: 't1', title: 'Song One', artist: 'Singer A'),
      ];
      final json = jsonEncode({
        'app': 'btmu',
        'format': 'btmu-playlist',
        'version': 1,
        'playlist': {'name': 'Mix', 'description': ''},
        'tracks': [
          {'title': '  SONG one ', 'artist': 'singer a', 'sha256': ''},
        ],
      });
      final result = await repo.importPlaylistJson(
        json,
        libraryTracks: library,
      );
      expect(result.added, 1);
      expect(repo.stored.single.trackIds, ['t1']);
    });

    test('missing entries are reported, never silently dropped', () async {
      final repo = _FakePlaylistRepository(const []);
      final library = [
        _track(id: 't1', title: 'Song One', artist: 'Singer A', sha256: 'aaa'),
      ];
      final json = jsonEncode({
        'app': 'btmu',
        'format': 'btmu-playlist',
        'version': 1,
        'playlist': {'name': 'Mix', 'description': ''},
        'tracks': [
          {'title': 'Song One', 'artist': 'Singer A', 'sha256': 'aaa'},
          {'title': 'Not Owned', 'artist': 'Nobody', 'sha256': ''},
          {'title': '', 'artist': 'Nobody', 'sha256': ''},
        ],
      });
      final result = await repo.importPlaylistJson(
        json,
        libraryTracks: library,
      );
      expect(result.added, 1);
      expect(result.missingLabels, ['Not Owned — Nobody']);
      expect(result.skipped, 1);
      // Every entry accounted for exactly once.
      expect(result.totalEntries, 3);
      expect(repo.stored.single.trackIds, ['t1']);
    });

    test('same track listed twice is added once and counted', () async {
      final repo = _FakePlaylistRepository(const []);
      final library = [
        _track(id: 't1', title: 'Song One', artist: 'Singer A', sha256: 'aaa'),
      ];
      final json = jsonEncode({
        'app': 'btmu',
        'format': 'btmu-playlist',
        'version': 1,
        'playlist': {'name': 'Mix', 'description': ''},
        'tracks': [
          {'title': 'Song One', 'artist': 'Singer A', 'sha256': 'aaa'},
          {'title': 'Song One', 'artist': 'Singer A', 'sha256': 'aaa'},
        ],
      });
      final result = await repo.importPlaylistJson(
        json,
        libraryTracks: library,
      );
      expect(result.added, 1);
      expect(result.duplicates, 1);
      expect(repo.stored.single.trackIds, ['t1']);
    });

    test('colliding name gets an (imported) suffix; existing untouched', () async {
      final existing = _playlist(id: 'pl-1', name: 'Mix');
      final repo = _FakePlaylistRepository([existing]);
      final library = [
        _track(id: 't1', title: 'Song One', artist: 'Singer A'),
      ];
      final json = jsonEncode({
        'app': 'btmu',
        'format': 'btmu-playlist',
        'version': 1,
        'playlist': {'name': 'Mix', 'description': ''},
        'tracks': [
          {'title': 'Song One', 'artist': 'Singer A', 'sha256': ''},
        ],
      });
      final result = await repo.importPlaylistJson(
        json,
        libraryTracks: library,
      );
      expect(result.playlistName, 'Mix (imported)');
      expect(repo.stored, hasLength(2));
      expect(repo.stored.first.trackIds, isEmpty);
      expect(repo.stored.last.trackIds, ['t1']);
    });
  });

  group('Playlist M3U export / import', () {
    test('M3U round-trips through parse and import', () async {
      final repo = _FakePlaylistRepository(const []);
      final library = [
        _track(id: 't1', title: 'Song One', artist: 'Singer A'),
        _track(id: 't2', title: 'Song Two', artist: 'Singer B'),
      ];
      final m3u = PlaylistRepository.exportPlaylistM3u(
        playlist: _playlist(id: 'pl-1', name: 'Road Trip'),
        tracks: library,
      );
      expect(m3u, contains('#PLAYLIST:Road Trip'));
      expect(m3u, contains('#EXTINF:180,Singer A - Song One'));
      final result = await repo.importPlaylistM3u(
        m3u,
        libraryTracks: library,
      );
      expect(result.added, 2);
      expect(result.playlistName, 'Road Trip');
      expect(repo.stored.single.trackIds, ['t1', 't2']);
    });

    test('hand-written M3U: bare path line is reported missing, not dropped', () async {
      final repo = _FakePlaylistRepository(const []);
      final library = [
        _track(id: 't1', title: 'Song One', artist: 'Singer A'),
      ];
      const m3u = '#EXTM3U\n'
          '#PLAYLIST:Hand Made\n'
          '#EXTINF:180,Singer A - Song One\n'
          'song-one.mp3\n'
          '/music/some-file-nobody-has.mp3\n';
      final result = await repo.importPlaylistM3u(
        m3u,
        libraryTracks: library,
      );
      expect(result.added, 1);
      expect(result.missingLabels, ['/music/some-file-nobody-has.mp3']);
      expect(result.totalEntries, 2);
    });

    test('M3U without #PLAYLIST uses the fallback name', () async {
      final repo = _FakePlaylistRepository(const []);
      final result = await repo.importPlaylistM3u(
        '#EXTM3U\n#EXTINF:180,Singer A - Song One\nsong-one.mp3\n',
        libraryTracks: const [],
        fallbackName: 'my-file',
      );
      expect(result.playlistName, 'my-file');
      expect(result.missingLabels, ['Song One — Singer A']);
    });
  });
}
