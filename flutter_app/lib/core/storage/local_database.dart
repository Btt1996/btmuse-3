import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._();
  LocalDatabase._();

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
      version: 2,
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createFingerprintTable(db);
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

  Future<Directory> get audioDirectory async {
    await database;
    return _audioDir!;
  }

  Future<Directory> get artworkDirectory async {
    await database;
    return _artworkDir!;
  }
}
