import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/services/ios_audio_bridge.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/core/utilities/audio_validator.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/core/utilities/sha256_helper.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/features/x1/local_fingerprint_engine.dart';

class LibraryStorageStats {
  final int trackCount;
  final int totalBytes;
  final int duplicateGroupsCount;

  const LibraryStorageStats({
    required this.trackCount,
    required this.totalBytes,
    required this.duplicateGroupsCount,
  });
}

class LibraryRepository {
  final LocalDatabase _db;
  static const _uuid = Uuid();

  LibraryRepository(this._db);

  Future<List<Track>> getAllTracks({String? query, bool favoritesOnly = false}) async {
    final db = await _db.database;
    final whereClauses = <String>[];
    final args = <Object?>[];

    if (favoritesOnly) {
      whereClauses.add('is_favorite = 1');
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim().toLowerCase()}%';
      whereClauses.add('(LOWER(title) LIKE ? OR LOWER(artist) LIKE ? OR LOWER(album) LIKE ?)');
      args.addAll([q, q, q]);
    }

    final rows = await db.query(
      'tracks',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'added_at_ms DESC',
    );
    return rows.map(Track.fromMap).toList();
  }

  Future<Track?> findById(String trackId) async {
    final db = await _db.database;
    final rows = await db.query(
      'tracks',
      where: 'id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Track.fromMap(rows.first);
  }

  Future<Track?> findBySha256(String sha256) async {
    final db = await _db.database;
    final rows = await db.query(
      'tracks',
      where: 'sha256 = ?',
      whereArgs: [sha256],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Track.fromMap(rows.first);
  }

  Future<Track> importFileIntoLibrary({
    required File sourceFile,
    required String rawTitle,
    String? rawArtist,
    String? rawAlbum,
    String? artworkUrl,
    int durationSeconds = 0,
    required String sourceProvider,
    bool deleteSourceAfterCopy = false,
  }) async {
    final validation = await AudioValidator.inspectFile(sourceFile);
    if (!validation.isValid) {
      throw ValidationFailure(validation.reason ?? 'Invalid audio file.');
    }

    final hash = await Sha256Helper.hashFile(sourceFile);
    final existing = await findBySha256(hash);
    if (existing != null && await File(existing.localFilePath).exists()) {
      if (deleteSourceAfterCopy && await sourceFile.exists()) {
        await sourceFile.delete();
      }
      return existing;
    }

    final trackId = _uuid.v4();
    final audioDir = await _db.audioDirectory;
    final artworkDir = await _db.artworkDirectory;
    final destFile = File(p.join(audioDir.path, '$trackId.${validation.extension}'));

    await sourceFile.copy(destFile.path);
    if (deleteSourceAfterCopy && await sourceFile.exists()) {
      await sourceFile.delete();
    }

    // Extract native iOS ID3 / iTunes / Vorbis metadata, duration, and embedded cover art
    final artworkDestPath = p.join(artworkDir.path, '$trackId.jpg');
    final nativeMeta = await IosAudioBridge.extractAudioMetadata(
      filePath: destFile.path,
      artworkDestPath: artworkDestPath,
    );

    final effectiveTitle =
        (nativeMeta?.title != null && nativeMeta!.title!.isNotEmpty && sourceProvider == 'local_file')
            ? nativeMeta.title!
            : rawTitle;
    final effectiveArtist =
        (rawArtist == null || rawArtist.trim().isEmpty || rawArtist == 'Unknown Artist')
            ? (nativeMeta?.artist ?? rawArtist)
            : rawArtist;
    final effectiveAlbum =
        (rawAlbum == null || rawAlbum.trim().isEmpty || rawAlbum == 'Single')
            ? (nativeMeta?.album ?? rawAlbum)
            : rawAlbum;
    final effectiveDuration =
        durationSeconds > 0 ? durationSeconds : (nativeMeta?.durationSeconds ?? 0);

    final normalized = MetadataNormalizer.normalize(
      rawTitle: effectiveTitle,
      rawArtist: effectiveArtist,
      rawAlbum: effectiveAlbum,
    );

    final sizeBytes = await destFile.length();
    final now = DateTime.now().millisecondsSinceEpoch;

    final track = Track(
      id: trackId,
      title: normalized.title,
      artist: normalized.artist,
      album: normalized.album,
      durationSeconds: effectiveDuration,
      localFilePath: destFile.path,
      artworkPath: nativeMeta?.artworkPath,
      artworkUrl: artworkUrl,
      format: validation.extension.toUpperCase(),
      fileSizeBytes: sizeBytes,
      sha256: hash,
      sourceProvider: sourceProvider,
      addedAtMs: now,
      isAnalysisEstimated: true,
    );

    final db = await _db.database;
    await db.insert('tracks', track.toMap());

    // Index acoustic constellation fingerprints asynchronously for local offline X1 matching
    unawaited(indexTrackAudio(track));
    return track;
  }

  Future<void> indexTrackAudio(Track track) async {
    try {
      final file = File(track.localFilePath);
      if (!await file.exists()) return;

      var pcm = await IosAudioBridge.extractMonoPcm(filePath: file.path, maxSeconds: 180);
      if (pcm.isEmpty && track.format.toUpperCase() == 'WAV') {
        pcm = LocalFingerprintEngine.decodeWavBytesToMonoFloat(await file.readAsBytes());
      }
      if (pcm.isEmpty) return;

      final telemetry = LocalFingerprintEngine.analyzeTelemetry(pcm);
      final landmarks = LocalFingerprintEngine.extractLandmarks(pcm);
      if (landmarks.isEmpty) return;

      // Sample evenly across the track if landmarks exceed 2500 so later song sections remain matchable
      final selectedLandmarks = landmarks.length <= 2500
          ? landmarks
          : [
              for (var i = 0; i < landmarks.length; i += (landmarks.length / 2500).ceil())
                landmarks[i],
            ];

      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.delete('track_fingerprints', where: 'track_id = ?', whereArgs: [track.id]);
        for (final lm in selectedLandmarks) {
          await txn.insert(
            'track_fingerprints',
            {
              'track_id': track.id,
              'hash': lm.hash,
              'time_frame': lm.timeFrame,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await txn.update(
          'tracks',
          {
            if (telemetry.estimatedBpm > 0) 'bpm': telemetry.estimatedBpm,
            'energy_score': (telemetry.rmsEnergy * 2.2).clamp(0.1, 1.0),
            'is_analysis_estimated': 0,
          },
          where: 'id = ?',
          whereArgs: [track.id],
        );
      });
    } catch (_) {
      // Never block library import if background DSP indexing is skipped
    }
  }

  Future<Map<String, List<LandmarkHash>>> loadFingerprintIndexForHashes(Set<int> hashes) async {
    if (hashes.isEmpty) return const {};
    final db = await _db.database;
    final sampleList = hashes.take(400).toList();
    final placeholders = List.filled(sampleList.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT track_id, hash, time_frame FROM track_fingerprints WHERE hash IN ($placeholders)',
      sampleList,
    );

    final byTrack = <String, List<LandmarkHash>>{};
    for (final r in rows) {
      final trackId = r['track_id'] as String;
      byTrack.putIfAbsent(trackId, () => []).add(
            LandmarkHash(
              hash: r['hash'] as int,
              timeFrame: r['time_frame'] as int,
            ),
          );
    }
    return byTrack;
  }

  Future<int> getIndexedFingerprintTrackCount() async {
    final db = await _db.database;
    final res = await db.rawQuery('SELECT COUNT(DISTINCT track_id) AS cnt FROM track_fingerprints');
    return (res.first['cnt'] as int?) ?? 0;
  }

  Future<void> updateTrackMetadata(Track track) async {
    final db = await _db.database;
    await db.update(
      'tracks',
      track.toMap(),
      where: 'id = ?',
      whereArgs: [track.id],
    );
  }

  Future<void> toggleFavorite(String trackId, bool isFavorite) async {
    final db = await _db.database;
    await db.update(
      'tracks',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> recordPlayback(String trackId) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate(
      'UPDATE tracks SET play_count = play_count + 1, last_played_at_ms = ? WHERE id = ?',
      [now, trackId],
    );
  }

  Future<void> deleteTrack(Track track) async {
    final db = await _db.database;
    await db.delete('tracks', where: 'id = ?', whereArgs: [track.id]);
    final file = File(track.localFilePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<LibraryStorageStats> getStorageStats() async {
    final tracks = await getAllTracks();
    var bytes = 0;
    final byHash = <String, int>{};
    final byTitleArtist = <String, int>{};
    for (final t in tracks) {
      bytes += t.fileSizeBytes;
      byHash[t.sha256] = (byHash[t.sha256] ?? 0) + 1;
      final key = MetadataNormalizer.deduplicationKey(t.title, t.artist);
      byTitleArtist[key] = (byTitleArtist[key] ?? 0) + 1;
    }
    final duplicateCount = byHash.values.where((c) => c > 1).length +
        byTitleArtist.values.where((c) => c > 1).length;
    return LibraryStorageStats(
      trackCount: tracks.length,
      totalBytes: bytes,
      duplicateGroupsCount: duplicateCount,
    );
  }
}
