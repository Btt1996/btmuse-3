import 'package:uuid/uuid.dart';
import '../../core/storage/local_database.dart';
import '../models/playlist.dart';

class PlaylistRepository {
  final LocalDatabase _db;
  static const _uuid = Uuid();

  PlaylistRepository(this._db);

  Future<List<Playlist>> getAllPlaylists() async {
    final db = await _db.database;
    final rows = await db.query('playlists', orderBy: 'updated_at_ms DESC');
    final playlists = <Playlist>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final trackRows = await db.query(
        'playlist_tracks',
        columns: ['track_id'],
        where: 'playlist_id = ?',
        whereArgs: [id],
        orderBy: 'position ASC',
      );
      playlists.add(
        Playlist.fromMap(
          row,
          trackIds: trackRows.map((r) => r['track_id'] as String).toList(),
        ),
      );
    }
    return playlists;
  }

  Future<Playlist> createPlaylist({required String name, String description = ''}) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final playlist = Playlist(
      id: _uuid.v4(),
      name: name.trim(),
      description: description.trim(),
      createdAtMs: now,
      updatedAtMs: now,
    );
    await db.insert('playlists', playlist.toMap());
    return playlist;
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    final db = await _db.database;
    final countRow = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next_pos FROM playlist_tracks WHERE playlist_id = ?',
      [playlistId],
    );
    final nextPos = (countRow.first['next_pos'] as int?) ?? 0;
    await db.rawInsert(
      'INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)',
      [playlistId, trackId, nextPos],
    );
    await db.update(
      'playlists',
      {'updated_at_ms': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final db = await _db.database;
    await db.delete(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, trackId],
    );
  }

  Future<void> deletePlaylist(String playlistId) async {
    final db = await _db.database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }
}
