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

/// Human-readable byte count (B / KB / MB / GB), one decimal for MB+.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Thrown by the legacy [LibraryRepository.importFileIntoLibrary] wrapper
/// when the file being imported is already in the library. Carries the
/// existing track so callers can report "already in library: <title> by
/// <artist>" instead of silently treating the import as a success.
/// Prefer [LibraryRepository.importFile], which returns an [ImportResult]
/// instead of throwing.
class DuplicateTrackFailure extends ValidationFailure {
  final Track existingTrack;
  final String sha256;

  DuplicateTrackFailure(this.existingTrack, this.sha256)
      : super(
          'Already in library: "${existingTrack.title}" by '
          '${existingTrack.artist}.',
          code: 'duplicate_track',
        );
}

/// Explicit result of an import attempt. Callers must handle both cases:
/// a duplicate is a reportable outcome, never a silent skip.
sealed class ImportResult {
  const ImportResult();
}

/// The file was new and is now stored in the library.
class Imported extends ImportResult {
  final Track track;
  const Imported(this.track);
}

/// The file's SHA-256 already exists in the library. Nothing was copied,
/// nothing was inserted, and [existingTrack] is the track already stored.
class Duplicate extends ImportResult {
  final Track existingTrack;
  final String sha256;
  const Duplicate(this.existingTrack, this.sha256);
}

/// One set of tracks sharing the same SHA-256 content hash — i.e. byte
/// identical audio files stored more than once. Grouping is by hash only,
/// never by title/artist, so a remaster or re-encode (different bytes)
/// is not flagged as a duplicate of the original.
class DuplicateGroup {
  final String sha256;
  final List<Track> tracks;

  const DuplicateGroup({required this.sha256, required this.tracks});

  int get count => tracks.length;

  int get totalBytes => tracks.fold(0, (sum, t) => sum + t.fileSizeBytes);

  /// Bytes freed by keeping exactly one copy: everything except the
  /// largest file in the group. (Identical bytes imply identical size,
  /// but taking total-minus-largest stays correct if sizes ever differ.)
  int get reclaimableBytes {
    if (tracks.length < 2) return 0;
    final largest = tracks.map((t) => t.fileSizeBytes).reduce((a, b) => a > b ? a : b);
    return totalBytes - largest;
  }

  /// Suggested keeper when the user asks for a default, mirroring the
  /// Swift LibraryStore's `removeDuplicates` default: most-played wins,
  /// newest breaks ties. This is only a suggestion — cleanup always
  /// requires the user to confirm and to pick (or accept) the keeper;
  /// the repository never deletes on its own initiative.
  Track get suggestedKeeper {
    final sorted = List<Track>.of(tracks)
      ..sort((a, b) {
        final plays = b.playCount.compareTo(a.playCount);
        if (plays != 0) return plays;
        return b.addedAtMs.compareTo(a.addedAtMs);
      });
    return sorted.first;
  }
}

/// Pure, DB-free grouping used by [LibraryRepository.findDuplicates] and
/// directly unit-testable. Rows with an empty hash (legacy rows whose file
/// was gone at migration time, so no hash could be computed) are never
/// grouped: an empty hash is "unknown", not "identical".
List<DuplicateGroup> groupTracksBySha256(List<Track> tracks) {
  final byHash = <String, List<Track>>{};
  for (final t in tracks) {
    if (t.sha256.isEmpty) continue;
    byHash.putIfAbsent(t.sha256, () => []).add(t);
  }
  final groups = byHash.entries
      .where((e) => e.value.length > 1)
      .map((e) => DuplicateGroup(sha256: e.key, tracks: List.unmodifiable(e.value)))
      .toList();
  groups.sort((a, b) => b.reclaimableBytes.compareTo(a.reclaimableBytes));
  return groups;
}

class LibraryStorageStats {
  final int trackCount;
  final int totalBytes;
  final int duplicateGroupsCount;

  /// Bytes per `source_provider` value as stored (e.g. `local_file`,
  /// `telegram`, X2 provider ids such as `audius`). The dashboard
  /// aggregates every provider other than `local_file` / `telegram`
  /// under "X2 downloads".
  final Map<String, int> bytesBySource;

  /// Track counts per `source_provider` value, same keys as [bytesBySource].
  final Map<String, int> trackCountBySource;

  /// Library rows whose audio file no longer exists on disk.
  final int missingFilesCount;

  /// Bytes recoverable by deleting all but one copy of each duplicate
  /// group (sum of [DuplicateGroup.reclaimableBytes]).
  final int duplicateBytesReclaimable;

  /// Device free space in bytes, or null when it cannot be determined.
  /// No disk-space plugin is currently a dependency, so this is always
  /// null until one is added; the dashboard says so instead of guessing.
  final int? freeBytes;

  const LibraryStorageStats({
    required this.trackCount,
    required this.totalBytes,
    required this.duplicateGroupsCount,
    this.bytesBySource = const {},
    this.trackCountBySource = const {},
    this.missingFilesCount = 0,
    this.duplicateBytesReclaimable = 0,
    this.freeBytes,
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
    if (sha256.isEmpty) return null;
    final rows = await _db.findTracksBySha256(sha256);
    if (rows.isEmpty) return null;
    return Track.fromMap(rows.first);
  }

  /// Every track with this exact content hash, oldest first. Empty when
  /// there is no match; an empty hash never matches (see
  /// [groupTracksBySha256]).
  Future<List<Track>> findAllBySha256(String sha256) async {
    if (sha256.isEmpty) return const [];
    final rows = await _db.findTracksBySha256(sha256);
    return rows.map(Track.fromMap).toList();
  }

  /// Canonical import entry point for ALL sources — local files, Telegram
  /// downloads and X2 acquisition all funnel through here, so hashing
  /// once here covers every path. SHA-256 is computed on the source file
  /// BEFORE anything is copied or inserted:
  ///
  /// * hash already in the library with its file still on disk ->
  ///   [Duplicate]; nothing is copied or inserted. A temporary download
  ///   source (`deleteSourceAfterCopy: true`, Telegram/X2) is still
  ///   cleaned up; a user-picked local file is never deleted.
  /// * hash in the library but its file is gone (stale row) -> the stale
  ///   row is removed and the import proceeds; it replaces the broken
  ///   entry instead of creating a duplicate group.
  /// * new hash -> copy, extract metadata, insert, return [Imported].
  ///
  /// The insert re-checks the hash inside a transaction, so two
  /// concurrent imports of the same bytes cannot both insert.
  Future<ImportResult> importFile({
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

    // Pre-insert dedup check. Stale rows (hash matches, file gone) are
    // purged so they neither block a good re-import nor inflate groups.
    final db = await _db.database;
    for (final candidate in await findAllBySha256(hash)) {
      if (await File(candidate.localFilePath).exists()) {
        if (deleteSourceAfterCopy && await sourceFile.exists()) {
          await sourceFile.delete();
        }
        return Duplicate(candidate, hash);
      }
      await db.delete('tracks', where: 'id = ?', whereArgs: [candidate.id]);
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

    // Transactional re-check: a concurrent import of the same bytes that
    // slipped past the pre-check above loses here instead of inserting
    // a second row. The just-copied file is removed in that case.
    final result = await db.transaction<ImportResult>((txn) async {
      final raced = await txn.query(
        'tracks',
        where: 'sha256 = ?',
        whereArgs: [hash],
        limit: 1,
      );
      if (raced.isNotEmpty) {
        return Duplicate(Track.fromMap(raced.first), hash);
      }
      await txn.insert('tracks', track.toMap());
      return Imported(track);
    });

    if (result is Duplicate) {
      if (await destFile.exists()) await destFile.delete();
      return result;
    }

    // Index acoustic constellation fingerprints asynchronously for local offline X1 matching
    unawaited(indexTrackAudio(track));
    return result;
  }

  /// Legacy wrapper kept so existing callers (Import Center, Library
  /// screen, TelegramService, X2AcquisitionEngine) keep compiling
  /// unchanged. Behaviour change vs. before: a duplicate no longer
  /// returns the existing track as if the import had succeeded — it
  /// throws [DuplicateTrackFailure] carrying that track, so every caller
  /// can report "already in library". New code should call [importFile]
  /// and handle [ImportResult] directly instead.
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
    final result = await importFile(
      sourceFile: sourceFile,
      rawTitle: rawTitle,
      rawArtist: rawArtist,
      rawAlbum: rawAlbum,
      artworkUrl: artworkUrl,
      durationSeconds: durationSeconds,
      sourceProvider: sourceProvider,
      deleteSourceAfterCopy: deleteSourceAfterCopy,
    );
    return switch (result) {
      Imported(:final track) => track,
      Duplicate(:final existingTrack, :final sha256) =>
        throw DuplicateTrackFailure(existingTrack, sha256),
    };
  }

  /// Inserts a bare [Track] row without copying any file and without
  /// hashing or dedup checks.
  ///
  /// Used by backup restore for metadata-only entries (and by tests).
  /// Callers must already have decided the track's audio-file state and
  /// de-duplication; this is a plain row insert of `track.toMap()`, the
  /// same write [importFile] performs after its checks.
  Future<void> insertTrack(Track track) async {
    final db = await _db.database;
    await db.insert('tracks', track.toMap());
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

  /// Deletes exactly the tracks whose ids are given — file + DB row
  /// together, via [deleteTrack] — and nothing else. The dashboard calls
  /// this only after the user confirms, with ids the user (or the
  /// suggested keeper) explicitly chose. Returns the number deleted.
  Future<int> deleteTracksByIds(List<String> trackIds) async {
    var deleted = 0;
    for (final id in trackIds) {
      final track = await findById(id);
      if (track == null) continue;
      await deleteTrack(track);
      deleted++;
    }
    return deleted;
  }

  /// Confirmed-only duplicate cleanup for one [DuplicateGroup]: deletes
  /// every member except [keepTrackId] (which must belong to the group)
  /// and returns the number of tracks removed. The keeper is chosen by
  /// the caller (dashboard: the user, defaulting to
  /// [DuplicateGroup.suggestedKeeper]); this method never picks a loser
  /// on its own and never deletes a whole group.
  Future<int> deleteDuplicateCopies(
    DuplicateGroup group, {
    required String keepTrackId,
  }) async {
    if (!group.tracks.any((t) => t.id == keepTrackId)) {
      throw ValidationFailure('Keeper track is not a member of this duplicate group.');
    }
    final losers = group.tracks.where((t) => t.id != keepTrackId).map((t) => t.id).toList();
    return deleteTracksByIds(losers);
  }

  /// All duplicate groups in the library, grouped by SHA-256, largest
  /// reclaimable space first. Groups are computed from the rows
  /// ([groupTracksBySha256]) rather than SQL `GROUP BY` so the grouping
  /// rule — hash-only, empty hash excluded — lives in exactly one place
  /// and is unit-testable without a database.
  Future<List<DuplicateGroup>> findDuplicates() async {
    return groupTracksBySha256(await getAllTracks());
  }

  Future<LibraryStorageStats> getStorageStats() async {
    final tracks = await getAllTracks();
    var bytes = 0;
    var missingFiles = 0;
    final bytesBySource = <String, int>{};
    final countBySource = <String, int>{};
    for (final t in tracks) {
      bytes += t.fileSizeBytes;
      bytesBySource[t.sourceProvider] =
          (bytesBySource[t.sourceProvider] ?? 0) + t.fileSizeBytes;
      countBySource[t.sourceProvider] = (countBySource[t.sourceProvider] ?? 0) + 1;
      if (!await File(t.localFilePath).exists()) missingFiles++;
    }
    final groups = groupTracksBySha256(tracks);
    final reclaimable = groups.fold(0, (sum, g) => sum + g.reclaimableBytes);
    return LibraryStorageStats(
      trackCount: tracks.length,
      totalBytes: bytes,
      // Previously this summed hash-groups AND title/artist-groups, so
      // one duplicated song could count twice. Hash groups only now.
      duplicateGroupsCount: groups.length,
      bytesBySource: bytesBySource,
      trackCountBySource: countBySource,
      missingFilesCount: missingFiles,
      duplicateBytesReclaimable: reclaimable,
      // No disk-space plugin is a dependency; free space is unknown.
      freeBytes: null,
    );
  }
}
