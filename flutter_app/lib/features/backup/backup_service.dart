import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:btmu/data/models/playlist.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/data/repositories/playlist_repository.dart';

/// Full-library backup & restore, ported from the native SwiftUI reference
/// (`BttMusic/BackupService.swift` + `LibraryStore.swift`).
///
/// Design (preserved from Swift):
/// * Export is ONE JSON document: track metadata + playlist structure.
///   Audio files are never included in the backup.
/// * Playlists reference tracks by `"title|artist"` keys (lower-cased), so a
///   restore can match them to tracks already on this device.
/// * Restore NEVER overwrites existing data: a track that already exists is
///   left exactly as it is; a playlist whose name already exists is skipped.
/// * Entries whose audio file is not on this device are restored as
///   metadata-only records and flagged as such, never silently dropped.
///
/// Flutter differences from the Swift schema (hence `version: 2`):
/// * Matching prefers the content hash (`sha256`) when the backup entry and
///   the existing track both carry one, and falls back to the Swift
///   `title|artist` key otherwise.
/// * The Flutter [Track] model has no `sourceID` and no remix flag, so those
///   Swift fields are not round-tripped; `genre`, `isFavorite`, `playCount`,
///   `lastPlayedAtMs`, `artworkUrl` and `energyScore` are preserved instead.
/// * Version 1 documents (Swift exports: `schema: 1`, `duration` /
///   `fileSize` / `source` field names) are still accepted on import.
///
/// One gap, by design: [LibraryRepository] has no method to insert a bare
/// [Track] row — [LibraryRepository.importFileIntoLibrary] requires a real
/// audio file and [LibraryRepository.updateTrackMetadata] only updates by id.
/// New tracks are therefore inserted through the injectable [insertTrack]
/// callback. Until the app wires a real `LibraryRepository.insertTrack`
/// method, the default callback throws a [BackupError] naming it, so a
/// restore of already-existing tracks and playlists still works but no
/// metadata-only row is ever silently faked. Tests inject an in-memory
/// inserter.
class BackupService {
  static const int currentVersion = 2;

  /// File name used when the user saves an export.
  static String exportFileName([DateTime? at]) {
    final now = (at ?? DateTime.now()).toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'btmu-backup-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }

  final LibraryRepository library;
  final PlaylistRepository playlists;

  /// Directory audio files live in (`LocalDatabase.audioDirectory`).
  /// Used only to check whether a backed-up audio file is still on this
  /// device. When null, every restored track is reported as metadata-only.
  final Directory? audioDirectory;

  final Future<void> Function(Track track) _insertTrack;

  static const _uuid = Uuid();

  BackupService({
    required this.library,
    required this.playlists,
    this.audioDirectory,
    Future<void> Function(Track track)? insertTrack,
  }) : _insertTrack = insertTrack ?? _defaultInsertTrack;

  static Future<void> _defaultInsertTrack(Track track) {
    throw const BackupError(
      'Cannot insert restored track: LibraryRepository has no insertTrack '
      'method yet. Add LibraryRepository.insertTrack(Track) (a plain row '
      'insert, no file copy) and pass it to BackupService.',
    );
  }

  // MARK: - Export

  /// Exports the whole library as a single JSON document.
  ///
  /// Uses only the repositories — never a raw SQL dump. The document shape is
  /// `{app: 'btmu', version: 2, exportedAt, tracks: [...], playlists: [...]}`.
  Future<String> exportLibrary() async {
    final tracks = await library.getAllTracks();
    final allPlaylists = await playlists.getAllPlaylists();
    final byId = {for (final t in tracks) t.id: t};

    final doc = <String, Object?>{
      'app': 'btmu',
      'version': currentVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'tracks': tracks.map(_trackToJson).toList(),
      'playlists': allPlaylists.map((pl) {
        return <String, Object?>{
          'name': pl.name,
          'description': pl.description,
          'trackKeys': pl.trackIds
              .map((id) => byId[id])
              .whereType<Track>()
              .map(trackKey)
              .toList(),
        };
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  Map<String, Object?> _trackToJson(Track t) => <String, Object?>{
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'genre': t.genre,
        'durationSeconds': t.durationSeconds,
        'fileName': p.basename(t.localFilePath),
        'fileSizeBytes': t.fileSizeBytes,
        'format': t.format,
        'sha256': t.sha256,
        'sourceProvider': t.sourceProvider,
        'artworkUrl': t.artworkUrl,
        'isFavorite': t.isFavorite,
        'playCount': t.playCount,
        'lastPlayedAtMs': t.lastPlayedAtMs,
        'addedAtMs': t.addedAtMs,
        'bpm': t.bpm,
        'energyScore': t.energyScore,
      };

  /// Swift-compatible match key: `"title|artist"`, lower-cased and trimmed.
  static String trackKey(Track t) => trackKeyFor(t.title, t.artist);

  static String trackKeyFor(String title, String artist) =>
      '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';

  // MARK: - Preview (read-only)

  /// Parses and validates [json], then reports what a restore would do —
  /// counts, playlist names and missing-audio flags — WITHOUT writing
  /// anything to the library.
  Future<BackupPreview> importPreview(String json) async {
    final doc = BackupDocument.parse(json);
    final existingTracks = await library.getAllTracks();
    final existingPlaylists = await playlists.getAllPlaylists();
    return _preview(doc, existingTracks, existingPlaylists);
  }

  Future<BackupPreview> _preview(
    BackupDocument doc,
    List<Track> existingTracks,
    List<Playlist> existingPlaylists,
  ) async {
    final bySha = <String, Track>{};
    final byKey = <String, Track>{};
    for (final t in existingTracks) {
      if (t.sha256.isNotEmpty) bySha[t.sha256] = t;
      byKey[trackKey(t)] = t;
    }
    final playlistNames = {
      for (final pl in existingPlaylists) pl.name.trim().toLowerCase(),
    };

    var newCount = 0;
    var alreadyCount = 0;
    var skipped = 0;
    final missingLabels = <String>[];
    for (final entry in doc.tracks) {
      if (entry.title.trim().isEmpty || entry.artist.trim().isEmpty) {
        skipped++;
        continue;
      }
      if (_findExisting(entry, bySha, byKey) != null) {
        alreadyCount++;
        continue;
      }
      newCount++;
      if (!await _audioFileExists(entry.fileName)) {
        missingLabels.add('${entry.title} — ${entry.artist}');
      }
    }

    final playlistPreviews = <BackupPlaylistPreview>[];
    for (final pl in doc.playlists) {
      if (pl.name.trim().isEmpty) {
        skipped++;
        continue;
      }
      playlistPreviews.add(
        BackupPlaylistPreview(
          name: pl.name,
          trackCount: pl.trackKeys.length,
          alreadyExists: playlistNames.contains(pl.name.trim().toLowerCase()),
        ),
      );
    }

    return BackupPreview(
      version: doc.version,
      exportedAt: doc.exportedAt,
      trackCount: doc.tracks.length,
      newTrackCount: newCount,
      alreadyInLibraryCount: alreadyCount,
      missingAudioFileCount: missingLabels.length,
      missingAudioTrackLabels: missingLabels,
      skippedEntryCount: skipped,
      playlists: playlistPreviews,
    );
  }

  // MARK: - Restore (writes only after explicit confirmation)

  /// Restores [json] into the library. Nothing is written unless
  /// [confirm] is true — the UI must show an [importPreview] first and get
  /// an explicit confirm tap. Existing tracks and playlists are never
  /// overwritten; only missing tracks/playlists are added.
  Future<RestoreReport> restore(String json, {bool confirm = false}) async {
    if (!confirm) {
      throw const BackupError(
        'Restore requires explicit confirmation. Show an import preview '
        'first and call restore with confirm: true.',
      );
    }
    final doc = BackupDocument.parse(json);
    final existingTracks = await library.getAllTracks();
    final existingPlaylists = await playlists.getAllPlaylists();

    final bySha = <String, Track>{};
    final byKey = <String, Track>{};
    for (final t in existingTracks) {
      if (t.sha256.isNotEmpty) bySha[t.sha256] = t;
      byKey[trackKey(t)] = t;
    }

    final report = RestoreReport();
    final resolvedByKey = <String, Track>{};

    for (final entry in doc.tracks) {
      if (entry.title.trim().isEmpty || entry.artist.trim().isEmpty) {
        report.skippedEntries++;
        continue;
      }
      final match = _findExisting(entry, bySha, byKey);
      if (match != null) {
        report.matchedExisting++;
        resolvedByKey[trackKeyFor(entry.title, entry.artist)] = match;
        continue;
      }
      final fileExists = await _audioFileExists(entry.fileName);
      final track = Track(
        id: _uuid.v4(),
        title: entry.title,
        artist: entry.artist,
        album: entry.album,
        genre: entry.genre,
        durationSeconds: entry.durationSeconds,
        localFilePath: _expectedAudioPath(entry.fileName),
        artworkUrl: entry.artworkUrl,
        format: entry.format,
        fileSizeBytes: entry.fileSizeBytes,
        sha256: entry.sha256,
        sourceProvider: entry.sourceProvider,
        isFavorite: entry.isFavorite,
        playCount: entry.playCount,
        lastPlayedAtMs: entry.lastPlayedAtMs,
        addedAtMs: entry.addedAtMs,
        bpm: entry.bpm,
        energyScore: entry.energyScore,
      );
      await _insertTrack(track);
      if (entry.sha256.isNotEmpty) bySha[entry.sha256] = track;
      byKey[trackKey(track)] = track;
      resolvedByKey[trackKey(track)] = track;
      if (fileExists) {
        report.restoredWithFile++;
      } else {
        report.restoredMetadata++;
      }
    }

    final existingNames = {
      for (final pl in existingPlaylists) pl.name.trim().toLowerCase(),
    };
    for (final pl in doc.playlists) {
      if (pl.name.trim().isEmpty) {
        report.skippedEntries++;
        continue;
      }
      if (existingNames.contains(pl.name.trim().toLowerCase())) {
        report.playlistsSkipped++;
        continue;
      }
      final created = await playlists.createPlaylist(
        name: pl.name,
        description: pl.description,
      );
      existingNames.add(pl.name.trim().toLowerCase());
      for (final key in pl.trackKeys) {
        final member = resolvedByKey[key.trim().toLowerCase()];
        if (member != null) {
          await playlists.addTrackToPlaylist(created.id, member.id);
        }
      }
      report.playlistsCreated++;
    }

    return report;
  }

  Track? _findExisting(
    BackupTrackEntry entry,
    Map<String, Track> bySha,
    Map<String, Track> byKey,
  ) {
    // Content hash first (exact audio), title+artist key as fallback,
    // exactly as the Swift design matches on title+artist.
    if (entry.sha256.isNotEmpty) {
      final byHash = bySha[entry.sha256];
      if (byHash != null) return byHash;
    }
    return byKey[trackKeyFor(entry.title, entry.artist)];
  }

  /// Expected on-device path for a backed-up audio file: the audio
  /// directory + the exported base file name (absolute source-device paths
  /// are never trusted — only the base name travels in the backup).
  String _expectedAudioPath(String fileName) {
    if (audioDirectory == null || fileName.isEmpty) return fileName;
    return p.join(audioDirectory!.path, p.basename(fileName));
  }

  Future<bool> _audioFileExists(String fileName) async {
    if (audioDirectory == null || fileName.isEmpty) return false;
    return File(p.join(audioDirectory!.path, p.basename(fileName))).exists();
  }
}

// MARK: - Parsed document + strict validation

/// Thrown when a backup document is structurally malformed. Entry-level
/// problems (empty title/artist) do not throw — they are skipped and counted
/// in [RestoreReport.skippedEntries], as in the Swift reference.
class BackupError implements Exception {
  final String message;
  const BackupError(this.message);

  @override
  String toString() => 'BackupError: $message';
}

class BackupFormatException extends BackupError {
  const BackupFormatException(super.message);
}

/// A validated backup document. Parse with [BackupDocument.parse], which
/// rejects malformed input instead of guessing.
class BackupDocument {
  final int version;
  final DateTime? exportedAt;
  final List<BackupTrackEntry> tracks;
  final List<BackupPlaylistEntry> playlists;

  const BackupDocument({
    required this.version,
    required this.exportedAt,
    required this.tracks,
    required this.playlists,
  });

  static BackupDocument parse(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw BackupFormatException('Not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatException(
        'Backup must be a JSON object with version, tracks and playlists.',
      );
    }
    final app = decoded['app'];
    if (app != 'btmu') {
      throw const BackupFormatException(
        'Not a btmu backup (top-level "app" must be "btmu").',
      );
    }
    final version = decoded['version'];
    if (version is! int) {
      throw const BackupFormatException(
        'Backup "version" must be an integer (1 or 2).',
      );
    }
    if (version != 1 && version != 2) {
      throw BackupFormatException(
        'Unsupported backup version $version (supported: 1, 2).',
      );
    }
    // Swift used `schema`; accept it as an alias for very old exports.
    final schema = decoded['schema'];
    if (schema != null && schema is! int) {
      throw const BackupFormatException('Backup "schema" must be an integer.');
    }

    DateTime? exportedAt;
    final exportedRaw = decoded['exportedAt'];
    if (exportedRaw != null) {
      if (exportedRaw is! String) {
        throw const BackupFormatException(
          'Backup "exportedAt" must be an ISO 8601 string.',
        );
      }
      exportedAt = DateTime.tryParse(exportedRaw);
      if (exportedAt == null) {
        throw const BackupFormatException(
          'Backup "exportedAt" is not a valid ISO 8601 date.',
        );
      }
    }

    final tracksRaw = decoded['tracks'];
    if (tracksRaw is! List) {
      throw const BackupFormatException('Backup "tracks" must be a list.');
    }
    final playlistsRaw = decoded['playlists'];
    if (playlistsRaw is! List) {
      throw const BackupFormatException('Backup "playlists" must be a list.');
    }

    final tracks = <BackupTrackEntry>[];
    for (var i = 0; i < tracksRaw.length; i++) {
      final raw = tracksRaw[i];
      if (raw is! Map<String, dynamic>) {
        throw BackupFormatException('Track entry #$i must be a JSON object.');
      }
      tracks.add(BackupTrackEntry.fromJson(raw, index: i));
    }
    final playlistEntries = <BackupPlaylistEntry>[];
    for (var i = 0; i < playlistsRaw.length; i++) {
      final raw = playlistsRaw[i];
      if (raw is! Map<String, dynamic>) {
        throw BackupFormatException(
          'Playlist entry #$i must be a JSON object.',
        );
      }
      playlistEntries.add(BackupPlaylistEntry.fromJson(raw, index: i));
    }

    return BackupDocument(
      version: version,
      exportedAt: exportedAt,
      tracks: tracks,
      playlists: playlistEntries,
    );
  }
}

class BackupTrackEntry {
  final String title;
  final String artist;
  final String album;
  final String? genre;
  final int durationSeconds;
  final String fileName;
  final int fileSizeBytes;
  final String format;
  final String sha256;
  final String sourceProvider;
  final String? artworkUrl;
  final bool isFavorite;
  final int playCount;
  final int? lastPlayedAtMs;
  final int addedAtMs;
  final double? bpm;
  final double? energyScore;

  const BackupTrackEntry({
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.durationSeconds,
    required this.fileName,
    required this.fileSizeBytes,
    required this.format,
    required this.sha256,
    required this.sourceProvider,
    required this.artworkUrl,
    required this.isFavorite,
    required this.playCount,
    required this.lastPlayedAtMs,
    required this.addedAtMs,
    required this.bpm,
    required this.energyScore,
  });

  /// Reads both v2 field names and v1 (Swift) aliases:
  /// `duration` → `durationSeconds`, `fileSize` → `fileSizeBytes`,
  /// `source` → `sourceProvider`. Wrong-typed fields throw
  /// [BackupFormatException]; a missing/empty title or artist is kept and
  /// counted as skipped at restore time, as in Swift.
  factory BackupTrackEntry.fromJson(Map<String, dynamic> json, {required int index}) {
    String reqString(String key, {String fallback = '', String? alias}) {
      final v = json[key] ?? (alias != null ? json[alias] : null);
      if (v == null) return fallback;
      if (v is! String) {
        throw BackupFormatException('Track #$index: "$key" must be a string.');
      }
      return v;
    }

    String? optString(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is! String) {
        throw BackupFormatException('Track #$index: "$key" must be a string.');
      }
      return v;
    }

    int reqInt(String key, {int fallback = 0, String? alias}) {
      final v = json[key] ?? (alias != null ? json[alias] : null);
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      throw BackupFormatException('Track #$index: "$key" must be a number.');
    }

    int? optInt(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      throw BackupFormatException('Track #$index: "$key" must be a number.');
    }

    double? optDouble(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is num) return v.toDouble();
      throw BackupFormatException('Track #$index: "$key" must be a number.');
    }

    bool reqBool(String key) {
      final v = json[key];
      if (v == null) return false;
      if (v is! bool) {
        throw BackupFormatException('Track #$index: "$key" must be a boolean.');
      }
      return v;
    }

    return BackupTrackEntry(
      title: reqString('title'),
      artist: reqString('artist'),
      album: reqString('album', fallback: 'Single'),
      genre: optString('genre'),
      durationSeconds: reqInt('durationSeconds', alias: 'duration'),
      fileName: reqString('fileName'),
      fileSizeBytes: reqInt('fileSizeBytes', alias: 'fileSize'),
      format: reqString('format', fallback: 'mp3'),
      sha256: reqString('sha256'),
      sourceProvider: reqString('sourceProvider', alias: 'source', fallback: 'local'),
      artworkUrl: optString('artworkUrl'),
      isFavorite: reqBool('isFavorite'),
      playCount: reqInt('playCount'),
      lastPlayedAtMs: optInt('lastPlayedAtMs'),
      addedAtMs: reqInt('addedAtMs'),
      bpm: optDouble('bpm'),
      energyScore: optDouble('energyScore'),
    );
  }
}

class BackupPlaylistEntry {
  final String name;
  final String description;
  final List<String> trackKeys;

  const BackupPlaylistEntry({
    required this.name,
    required this.description,
    required this.trackKeys,
  });

  factory BackupPlaylistEntry.fromJson(Map<String, dynamic> json, {required int index}) {
    final name = json['name'];
    if (name != null && name is! String) {
      throw BackupFormatException('Playlist #$index: "name" must be a string.');
    }
    final description = json['description'];
    if (description != null && description is! String) {
      throw BackupFormatException(
        'Playlist #$index: "description" must be a string.',
      );
    }
    final keys = json['trackKeys'];
    if (keys != null && keys is! List) {
      throw BackupFormatException(
        'Playlist #$index: "trackKeys" must be a list of strings.',
      );
    }
    final trackKeys = <String>[];
    if (keys != null) {
      for (final k in keys) {
        if (k is! String) {
          throw BackupFormatException(
            'Playlist #$index: every "trackKeys" entry must be a string.',
          );
        }
        trackKeys.add(k);
      }
    }
    return BackupPlaylistEntry(
      name: (name as String?) ?? '',
      description: (description as String?) ?? '',
      trackKeys: trackKeys,
    );
  }
}

// MARK: - Preview + report models

class BackupPlaylistPreview {
  final String name;
  final int trackCount;
  final bool alreadyExists;

  const BackupPlaylistPreview({
    required this.name,
    required this.trackCount,
    required this.alreadyExists,
  });
}

/// What [BackupService.importPreview] reports. Read-only: producing a
/// preview never writes to the library.
class BackupPreview {
  final int version;
  final DateTime? exportedAt;
  final int trackCount;
  final int newTrackCount;
  final int alreadyInLibraryCount;
  final int missingAudioFileCount;
  final List<String> missingAudioTrackLabels;
  final int skippedEntryCount;
  final List<BackupPlaylistPreview> playlists;

  const BackupPreview({
    required this.version,
    required this.exportedAt,
    required this.trackCount,
    required this.newTrackCount,
    required this.alreadyInLibraryCount,
    required this.missingAudioFileCount,
    required this.missingAudioTrackLabels,
    required this.skippedEntryCount,
    required this.playlists,
  });

  int get newPlaylistCount => playlists.where((p) => !p.alreadyExists).length;
  int get existingPlaylistCount => playlists.where((p) => p.alreadyExists).length;
}

class RestoreReport {
  int matchedExisting = 0;
  int restoredMetadata = 0;
  int restoredWithFile = 0;
  int playlistsCreated = 0;
  int playlistsSkipped = 0;
  int skippedEntries = 0;

  RestoreReport();

  int get addedTracks => restoredMetadata + restoredWithFile;

  String get summary {
    final lines = <String>[
      '$matchedExisting track${matchedExisting == 1 ? '' : 's'} already in your library (untouched)',
    ];
    if (restoredWithFile > 0) {
      lines.add('$restoredWithFile restored with audio file');
    }
    if (restoredMetadata > 0) {
      lines.add(
        '$restoredMetadata restored as metadata-only (audio file not on this device)',
      );
    }
    lines.add(
      '$playlistsCreated playlist${playlistsCreated == 1 ? '' : 's'} created, '
      '$playlistsSkipped skipped (name exists)',
    );
    if (skippedEntries > 0) {
      lines.add('$skippedEntries malformed entries skipped');
    }
    return lines.join('\n');
  }
}
