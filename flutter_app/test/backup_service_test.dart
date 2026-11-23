import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/data/models/playlist.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/data/repositories/playlist_repository.dart';
import 'package:btmu/features/backup/backup_service.dart';

// Fakes extend the real repositories and override only the methods
// BackupService calls, so no sqflite database is ever opened. Constructing
// them with LocalDatabase.instance performs no I/O.
class _FakeLibraryRepository extends LibraryRepository {
  final List<Track> tracks;
  _FakeLibraryRepository(this.tracks) : super(LocalDatabase.instance);

  @override
  Future<List<Track>> getAllTracks({
    String? query,
    bool favoritesOnly = false,
  }) async =>
      List<Track>.of(tracks);
}

class _FakePlaylistRepository extends PlaylistRepository {
  // Owns a mutable copy of the injected playlists: callers may pass a
  // const (unmodifiable) list — the `service()` helper defaults to one —
  // and createPlaylist / addTrackToPlaylist mutate this list.
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
  String fileName = 'track.mp3',
  int playCount = 0,
  bool isFavorite = false,
}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    album: 'Single',
    durationSeconds: 180,
    localFilePath: '/audio/$fileName',
    format: 'MP3',
    fileSizeBytes: 12345,
    sha256: sha256,
    sourceProvider: 'local_file',
    playCount: playCount,
    isFavorite: isFavorite,
    addedAtMs: 1700000000000,
  );
}

Map<String, Object?> _trackJson({
  required String title,
  required String artist,
  String sha256 = '',
  String fileName = 'track.mp3',
  int playCount = 0,
}) {
  return {
    'title': title,
    'artist': artist,
    'album': 'Single',
    'durationSeconds': 180,
    'fileName': fileName,
    'fileSizeBytes': 12345,
    'format': 'MP3',
    'sha256': sha256,
    'sourceProvider': 'local_file',
    'isFavorite': false,
    'playCount': playCount,
    'addedAtMs': 1700000000000,
  };
}

String _backupJson({
  required List<Map<String, Object?>> tracks,
  List<Map<String, Object?>> playlists = const [],
  int version = 2,
}) {
  return jsonEncode({
    'app': 'btmu',
    'version': version,
    'exportedAt': '2026-11-22T10:00:00.000Z',
    'tracks': tracks,
    'playlists': playlists,
  });
}

void main() {
  late Directory audioDir;

  setUp(() {
    audioDir = Directory.systemTemp.createTempSync('btmu_backup_test_');
  });

  tearDown(() {
    if (audioDir.existsSync()) audioDir.deleteSync(recursive: true);
  });

  BackupService service({
    List<Track> tracks = const [],
    List<Playlist> playlists = const [],
    List<Track>? inserted,
  }) {
    return BackupService(
      library: _FakeLibraryRepository(tracks),
      playlists: _FakePlaylistRepository(playlists),
      audioDirectory: audioDir,
      insertTrack: (t) async => inserted?.add(t),
    );
  }

  group('exportLibrary', () {
    test('exports version 2 document with tracks and title|artist playlist keys', () async {
      final tracks = [
        _track(id: 't1', title: 'Skyline', artist: 'Nova', sha256: 'aaa'),
        _track(id: 't2', title: 'Midnight', artist: 'Nova', sha256: 'bbb'),
      ];
      final playlists = [
        const Playlist(
          id: 'p1',
          name: 'Chill',
          createdAtMs: 1,
          updatedAtMs: 1,
          trackIds: ['t1', 't2'],
        ),
      ];
      final svc = service(tracks: tracks, playlists: playlists);
      final decoded = jsonDecode(await svc.exportLibrary()) as Map<String, dynamic>;

      expect(decoded['app'], 'btmu');
      expect(decoded['version'], 2);
      expect(decoded['exportedAt'], isA<String>());
      expect((decoded['tracks'] as List).length, 2);
      final first = (decoded['tracks'] as List).first as Map<String, dynamic>;
      expect(first['title'], 'Skyline');
      expect(first['sha256'], 'aaa');
      expect(first['fileName'], 'track.mp3');
      final playlist = (decoded['playlists'] as List).first as Map<String, dynamic>;
      expect(playlist['name'], 'Chill');
      expect(playlist['trackKeys'], ['skyline|nova', 'midnight|nova']);
    });
  });

  group('importPreview', () {
    test('reports counts, playlist names and missing-file flags without writing', () async {
      File('${audioDir.path}/present.mp3').writeAsStringSync('fake audio');
      final existing = _track(id: 't1', title: 'Skyline', artist: 'Nova', sha256: 'aaa');
      final inserted = <Track>[];
      final svc = service(
        tracks: [existing],
        playlists: [
          const Playlist(id: 'p1', name: 'Chill', createdAtMs: 1, updatedAtMs: 1),
        ],
        inserted: inserted,
      );
      final json = _backupJson(
        tracks: [
          _trackJson(title: 'Skyline', artist: 'Nova', sha256: 'aaa'),
          _trackJson(title: 'Present', artist: 'Nova', fileName: 'present.mp3'),
          _trackJson(title: 'Gone', artist: 'Nova', fileName: 'gone.mp3'),
        ],
        playlists: [
          {'name': 'Chill', 'description': '', 'trackKeys': ['skyline|nova']},
          {'name': 'Road', 'description': '', 'trackKeys': ['gone|nova']},
        ],
      );

      final preview = await svc.importPreview(json);

      expect(preview.trackCount, 3);
      expect(preview.alreadyInLibraryCount, 1);
      expect(preview.newTrackCount, 2);
      expect(preview.missingAudioFileCount, 1);
      expect(preview.missingAudioTrackLabels, ['Gone — Nova']);
      expect(preview.playlists.map((p) => p.name), ['Chill', 'Road']);
      expect(preview.existingPlaylistCount, 1);
      expect(preview.newPlaylistCount, 1);
      expect(inserted, isEmpty, reason: 'preview must not write anything');
    });
  });

  group('malformed input', () {
    test('rejects non-JSON, non-object, wrong version and wrong-typed lists', () async {
      final svc = service();
      for (final bad in [
        'not json at all',
        '[1, 2, 3]',
        '{"version": 2, "tracks": [], "playlists": []}',
        '{"app": "other", "version": 2, "tracks": [], "playlists": []}',
        '{"app": "btmu", "version": 99, "tracks": [], "playlists": []}',
        '{"app": "btmu", "version": "2", "tracks": [], "playlists": []}',
        '{"app": "btmu", "version": 2, "tracks": {}, "playlists": []}',
        '{"app": "btmu", "version": 2, "tracks": [], "playlists": "none"}',
        '{"app": "btmu", "version": 2, "exportedAt": "yesterday", "tracks": [], "playlists": []}',
        '{"app": "btmu", "version": 2, "tracks": [{"title": 42, "artist": "X"}], "playlists": []}',
      ]) {
        expect(
          () => svc.importPreview(bad),
          throwsA(isA<BackupFormatException>()),
          reason: 'should reject: $bad',
        );
      }
    });

    test('counts entries with empty title/artist as skipped instead of crashing', () async {
      final inserted = <Track>[];
      final svc = service(inserted: inserted);
      final json = _backupJson(tracks: [
        {'title': '', 'artist': 'Nova'},
        _trackJson(title: 'Fine', artist: 'Nova'),
      ]);
      final report = await svc.restore(json, confirm: true);
      expect(report.skippedEntries, 1);
      expect(report.addedTracks, 1);
      expect(inserted.length, 1);
    });
  });

  group('restore', () {
    test('requires explicit confirmation', () async {
      final svc = service();
      final json = _backupJson(tracks: [_trackJson(title: 'A', artist: 'B')]);
      expect(() => svc.restore(json), throwsA(isA<BackupError>()));
    });

    test('matches by sha256 first, then title+artist, and never overwrites', () async {
      final existing = _track(
        id: 't1',
        title: 'Skyline',
        artist: 'Nova',
        sha256: 'aaa',
        playCount: 7,
      );
      final library = [existing];
      final inserted = <Track>[];
      final svc = service(
        tracks: library,
        playlists: [
          const Playlist(id: 'p1', name: 'Chill', createdAtMs: 1, updatedAtMs: 1),
        ],
        inserted: inserted,
      );
      final json = _backupJson(
        tracks: [
          // Same audio, different title casing: sha256 match wins.
          _trackJson(title: 'SKYLINE', artist: 'nova', sha256: 'aaa', playCount: 999),
          // No hash: title+artist match.
          _trackJson(title: 'Skyline', artist: 'Nova', playCount: 999),
          _trackJson(title: 'New Song', artist: 'Nova', fileName: 'new.mp3'),
        ],
        playlists: [
          {'name': 'Chill', 'description': '', 'trackKeys': ['skyline|nova']},
          {'name': 'Road', 'description': '', 'trackKeys': ['new song|nova']},
        ],
      );

      final first = await svc.restore(json, confirm: true);
      expect(first.matchedExisting, 2);
      expect(first.addedTracks, 1);
      expect(first.restoredMetadata, 1, reason: 'new.mp3 is not in the audio dir');
      expect(first.playlistsCreated, 1);
      expect(first.playlistsSkipped, 1);
      // The existing track is untouched: its playCount was not overwritten.
      expect(library.single.playCount, 7);

      // Restore twice: the second run adds nothing.
      library.addAll(inserted);
      final second = await svc.restore(json, confirm: true);
      expect(second.addedTracks, 0);
      expect(second.matchedExisting, 3);
      expect(second.playlistsCreated, 0);
      expect(second.playlistsSkipped, 2);
    });

    test('flags missing audio files as metadata-only, present files as restored', () async {
      File('${audioDir.path}/here.mp3').writeAsStringSync('fake audio');
      final inserted = <Track>[];
      final svc = service(inserted: inserted);
      final json = _backupJson(tracks: [
        _trackJson(title: 'Here', artist: 'Nova', fileName: 'here.mp3'),
        _trackJson(title: 'Gone', artist: 'Nova', fileName: 'gone.mp3'),
      ]);

      final report = await svc.restore(json, confirm: true);
      expect(report.restoredWithFile, 1);
      expect(report.restoredMetadata, 1);
      expect(report.summary, contains('1 restored with audio file'));
      expect(report.summary, contains('1 restored as metadata-only'));
    });

    test('accepts a Swift version-1 backup document', () async {
      final inserted = <Track>[];
      final svc = service(inserted: inserted);
      const swiftJson = '''
{
  "app": "btmu",
  "schema": 1,
  "version": 1,
  "exportedAt": "2026-11-01T12:00:00Z",
  "tracks": [
    {"title": "Old Song", "artist": "Old Artist", "album": "Old Album",
     "duration": 200, "fileName": "old.m4a", "fileSize": 5000,
     "source": "files", "sourceID": "", "bpm": 120, "playCount": 3}
  ],
  "playlists": [
    {"name": "Old Mix", "isRemix": false, "trackKeys": ["old song|old artist"]}
  ]
}''';
      final preview = await svc.importPreview(swiftJson);
      expect(preview.trackCount, 1);
      expect(preview.newTrackCount, 1);

      final report = await svc.restore(swiftJson, confirm: true);
      expect(report.addedTracks, 1);
      expect(report.playlistsCreated, 1);
      expect(inserted.single.durationSeconds, 200);
      expect(inserted.single.playCount, 3);
    });
  });
}
