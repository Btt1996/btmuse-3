import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/data/models/playlist.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/data/repositories/playlist_repository.dart';
import 'package:btmu/features/backup/backup_service.dart';

// v3.0.5, item 16 — single `.btmu` library file for iCloud Drive.
// The file is JSON content (track metadata + playlists, never audio)
// under the new `btmu-library-<timestamp>.btmu` name. Fakes mirror
// backup_service_test.dart (extend the real repositories, override only
// the methods BackupService calls) so no sqflite database is opened.

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

Track _track({required String id, required String title, required String artist}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    album: 'Single',
    durationSeconds: 180,
    localFilePath: '/audio/$id.mp3',
    format: 'MP3',
    fileSizeBytes: 12345,
    sha256: 'sha-$id',
    sourceProvider: 'telegram',
    addedAtMs: 1700000000000,
  );
}

/// Every key a track entry is allowed to carry. Anything else — in
/// particular an audio blob — fails the no-audio test below.
const _allowedTrackKeys = {
  'title',
  'artist',
  'album',
  'genre',
  'durationSeconds',
  'fileName',
  'fileSizeBytes',
  'format',
  'sha256',
  'sourceProvider',
  'artworkUrl',
  'isFavorite',
  'playCount',
  'lastPlayedAtMs',
  'addedAtMs',
  'bpm',
  'energyScore',
};

void _assertNoAudioBytes(Object? value, String path) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      expect(key, isNot(contains('audiodata')),
          reason: 'audio blob key at $path');
      expect(key, isNot(contains('base64')),
          reason: 'base64 blob key at $path');
      expect(key, isNot(equals('audio')), reason: 'audio key at $path');
      _assertNoAudioBytes(entry.value, '$path.${entry.key}');
    }
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      _assertNoAudioBytes(value[i], '$path[$i]');
    }
  } else if (value is String) {
    expect(value, isNot(contains('data:audio')),
        reason: 'embedded audio data URI at $path');
  }
}

void main() {
  group('library file name', () {
    test('exportFileName is btmu-library-<timestamp>.btmu', () {
      final name = BackupService.exportFileName(
        DateTime.utc(2026, 11, 23, 4, 5, 6),
      );
      expect(name, 'btmu-library-20261123-040506.btmu');
      expect(
        BackupService.exportFileName(),
        matches(RegExp(r'^btmu-library-\d{8}-\d{6}\.btmu$')),
      );
    });
  });

  group('library file export', () {
    test('exported JSON contains tracks + playlists and no audio bytes', () async {
      final svc = BackupService(
        library: _FakeLibraryRepository([
          _track(id: 't1', title: 'Skyline', artist: 'Nova'),
          _track(id: 't2', title: 'Midnight', artist: 'Nova'),
        ]),
        playlists: _FakePlaylistRepository([
          const Playlist(
            id: 'p1',
            name: 'Chill',
            createdAtMs: 1,
            updatedAtMs: 1,
            trackIds: ['t1', 't2'],
          ),
        ]),
      );

      final json = await svc.exportLibrary();
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['app'], 'btmu');
      expect((decoded['tracks'] as List).length, 2);
      expect((decoded['playlists'] as List).length, 1);
      expect(
        (decoded['playlists'] as List).first['trackKeys'],
        ['skyline|nova', 'midnight|nova'],
      );

      // No audio bytes: no audioData/base64/audio key anywhere, no
      // embedded data URI, and every track entry carries metadata keys
      // only (fileName is a bare file name, not audio content).
      _assertNoAudioBytes(decoded, r'$');
      for (final raw in decoded['tracks'] as List) {
        final track = raw as Map<String, dynamic>;
        expect(track.keys.toSet().difference(_allowedTrackKeys), isEmpty);
        expect(track['fileName'], endsWith('.mp3'));
      }
      expect(json, isNot(contains('data:audio')));
    });

    test('export -> import round-trip restores tracks + playlists', () async {
      final source = BackupService(
        library: _FakeLibraryRepository([
          _track(id: 't1', title: 'Skyline', artist: 'Nova'),
          _track(id: 't2', title: 'Midnight', artist: 'Nova'),
        ]),
        playlists: _FakePlaylistRepository([
          const Playlist(
            id: 'p1',
            name: 'Chill',
            description: 'Evening mix',
            createdAtMs: 1,
            updatedAtMs: 1,
            trackIds: ['t1', 't2'],
          ),
        ]),
      );
      final exported = await source.exportLibrary();

      // Fresh device: empty library, no audio files on disk.
      final inserted = <Track>[];
      final targetPlaylists = _FakePlaylistRepository([]);
      final target = BackupService(
        library: _FakeLibraryRepository([]),
        playlists: targetPlaylists,
        audioDirectory: Directory.systemTemp,
        insertTrack: (t) async => inserted.add(t),
      );

      final preview = await target.importPreview(exported);
      expect(preview.trackCount, 2);
      expect(preview.newTrackCount, 2);
      expect(preview.playlists.map((p) => p.name), ['Chill']);

      final report = await target.restore(exported, confirm: true);
      expect(report.addedTracks, 2);
      expect(report.restoredMetadata, 2,
          reason: 'no audio files on the new device — metadata-only');
      expect(report.restoredWithFile, 0);
      expect(report.playlistsCreated, 1);
      expect(inserted.map((t) => t.title), ['Skyline', 'Midnight']);
      expect(targetPlaylists.stored.single.name, 'Chill');
      expect(targetPlaylists.stored.single.trackIds.length, 2);
    });
  });
}
