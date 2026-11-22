import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:btmu/core/utilities/sha256_helper.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._();
  LocalDatabase._();

  /// Current schema version.
  ///
  /// v1: initial tracks / playlists / playlist_tracks / download_tasks.
  /// v2: added `track_fingerprints` (X1 acoustic landmarks).
  /// v3: content-hash column on `tracks` is guaranteed present, even for
  /// databases created at v1. The v2 `onCreate` already created `tracks`
  /// with a `sha256` column, but the v1 -> v2 `onUpgrade` never added it
  /// to pre-existing databases, so v1 installs could reach v2 with no
  /// `sha256` column at all. v3 closes that gap and backfills hashes
  /// from the audio files still on disk.
  /// v4: added `playback_queue` + `playback_state` (Phase 3, Q-1).
  /// The queue is persisted as ordered track ids plus a single-row state
  /// (current index, position, shuffle/repeat, source label). Migration
  /// is purely additive: existing tables and rows are untouched, so a v3
  /// library (tracks, lyrics cache, fingerprints, playlists, downloads)
  /// upgrades without losing anything. An absent/empty queue means
  /// "no saved queue", never a crash.
  static const int schemaVersion = 4;

  Database? _db;
  Directory? _audioDir;
  Directory? _artworkDir;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'btmu_library.db');
    _audioDir = Directory(p.join(docsDir.path, 'btmu_audio'));
    _artworkDir = Directory(p.join(docsDir.path, 'btmu_artwork'));

    if (!await _audioDir!.exists()) await _audioDir!.create(recursive: true);
    if (!await _artworkDir!.exists()) await _artworkDir!.create(recursive: true);

    _db = await openDatabase(
      dbPath,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tracks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL,
            genre TEXT,
            duration_seconds INTEGER NOT NULL DEFAULT 0,
            local_file_path TEXT NOT NULL,
            artwork_path TEXT,
            artwork_url TEXT,
            format TEXT NOT NULL,
            file_size_bytes INTEGER NOT NULL DEFAULT 0,
            sha256 TEXT NOT NULL,
            source_provider TEXT NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            play_count INTEGER NOT NULL DEFAULT 0,
            last_played_at_ms INTEGER,
            added_at_ms INTEGER NOT NULL,
            bpm REAL,
            energy_score REAL,
            is_analysis_estimated INTEGER NOT NULL DEFAULT 1
          );
        ''');

        await db.execute('CREATE INDEX idx_tracks_sha256 ON tracks(sha256);');
        await db.execute('CREATE INDEX idx_tracks_added ON tracks(added_at_ms DESC);');

        await db.execute('''
          CREATE TABLE playlists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE playlist_tracks (
            playlist_id TEXT NOT NULL,
            track_id TEXT NOT NULL,
            position INTEGER NOT NULL,
            PRIMARY KEY (playlist_id, track_id),
            FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
            FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
          );
        ''');

        await db.execute('''
          CREATE TABLE download_tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            source_url TEXT NOT NULL,
            artwork_url TEXT,
            stage TEXT NOT NULL,
            progress REAL NOT NULL DEFAULT 0.0,
            received_bytes INTEGER NOT NULL DEFAULT 0,
            total_bytes INTEGER NOT NULL DEFAULT 0,
            error_message TEXT,
            imported_track_id TEXT,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL
          );
        ''');

        await _createFingerprintTable(db);
        await _createQueueTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createFingerprintTable(db);
        }
        if (oldVersion < 3) {
          await _ensureSha256Column(db);
        }
        if (oldVersion < 4) {
          await _createQueueTables(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _createFingerprintTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS track_fingerprints (
        track_id TEXT NOT NULL,
        hash INTEGER NOT NULL,
        time_frame INTEGER NOT NULL,
        PRIMARY KEY (track_id, hash, time_frame),
        FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_fp_hash ON track_fingerprints(hash);',
    );
  }

  /// Guarantees the `tracks.sha256` column and its index exist, then
  /// backfills hashes for rows that lack one, where the audio file is
  /// still on disk. Other tables are untouched.
  ///
  /// Backfill is best-effort by design: a row whose file is missing or
  /// unreadable keeps an empty hash (it is surfaced as a missing file by
  /// [LibraryRepository.getStorageStats] instead of failing the whole
  /// migration and leaving the app unable to open its library).
  static Future<void> _ensureSha256Column(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(tracks)');
    final hasSha256 = columns.any((c) => c['name'] == 'sha256');
    if (!hasSha256) {
      await db.execute(
        "ALTER TABLE tracks ADD COLUMN sha256 TEXT NOT NULL DEFAULT ''",
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tracks_sha256 ON tracks(sha256);',
    );
    await _backfillSha256(db);
  }

  static Future<void> _backfillSha256(Database db) async {
    final rows = await db.query(
      'tracks',
      columns: const ['id', 'local_file_path'],
      where: "sha256 IS NULL OR sha256 = ''",
    );
    for (final row in rows) {
      final id = row['id'] as String?;
      final path = row['local_file_path'] as String?;
      if (id == null || path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        final hash = await Sha256Helper.hashFile(file);
        await db.update(
          'tracks',
          {'sha256': hash},
          where: 'id = ?',
          whereArgs: [id],
        );
      } catch (_) {
        // One unreadable file must not abort the migration for the rest
        // of the library; the row keeps an empty hash.
      }
    }
  }

  /// Phase 3, Q-1 — persisted playback queue (schema v4).
  ///
  /// `playback_queue` holds the ordered queue: one row per track, `position`
  /// is the 0-based play order (PRIMARY KEY, so re-saving the queue is a
  /// delete + re-insert in one transaction). `track_id` references
  /// `tracks(id) ON DELETE CASCADE`, so deleting a library track drops it
  /// from the saved queue automatically.
  ///
  /// `playback_state` holds exactly one row (`id = 1`): the index of the
  /// current track in the queue, the resume position in milliseconds, the
  /// shuffle flag, the repeat mode (`'none'` | `'one'` | `'all'`, matching
  /// `AudioServiceRepeatMode.name`), and an optional `source_label`
  /// (e.g. the playlist name) so the UI can say what the queue came from.
  /// The shuffled traversal order itself is NOT stored: it is rebuilt
  /// deterministically on restore with the current track first (see
  /// `TraversalOrder.shuffled`), which keeps the stored state small and
  /// avoids persisting an order that would go stale on any queue edit.
  ///
  /// Both statements are `IF NOT EXISTS`, so the v3 -> v4 `onUpgrade`
  /// and a fresh v4 `onCreate` converge on the same schema, and a
  /// half-finished upgrade can safely re-run.
  static Future<void> _createQueueTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playback_queue (
        position INTEGER PRIMARY KEY,
        track_id TEXT NOT NULL,
        FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playback_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        current_index INTEGER NOT NULL DEFAULT -1,
        position_ms INTEGER NOT NULL DEFAULT 0,
        shuffle INTEGER NOT NULL DEFAULT 0,
        repeat_mode TEXT NOT NULL DEFAULT 'none',
        source_label TEXT,
        updated_at_ms INTEGER NOT NULL
      );
    ''');
  }

  /// Low-level lookup of track rows by content hash. Returns every row
  /// with this exact hash (normally 0 or 1; more than 1 means duplicates
  /// imported before dedup was enforced). The repository layer
  /// ([LibraryRepository.findBySha256] / `findAllBySha256`) is the
  /// typed API callers should use; this exists so the hash lookup lives
  /// next to the schema that guarantees the column.
  Future<List<Map<String, Object?>>> findTracksBySha256(String sha256) async {
    final db = await database;
    return db.query(
      'tracks',
      where: 'sha256 = ?',
      whereArgs: [sha256],
      orderBy: 'added_at_ms ASC',
    );
  }

  Future<Directory> get audioDirectory async {
    await database;
    return _audioDir!;
  }

  Future<Directory> get artworkDirectory async {
    await database;
    return _artworkDir!;
  }
}
