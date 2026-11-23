import 'package:sqflite/sqflite.dart';
import '../../core/storage/local_database.dart';
import '../models/download_task.dart';

class HistoryRepository {
  final LocalDatabase _db;

  HistoryRepository(this._db);

  Future<List<DownloadTask>> getDownloadHistory() async {
    final db = await _db.database;
    final rows = await db.query(
      'download_tasks',
      orderBy: 'updated_at_ms DESC',
    );
    return rows.map(DownloadTask.fromMap).toList();
  }

  Future<void> upsertTask(DownloadTask task) async {
    final db = await _db.database;
    await db.insert(
      'download_tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearFinishedHistory() async {
    final db = await _db.database;
    await db.delete(
      'download_tasks',
      where: 'stage IN (?, ?, ?)',
      whereArgs: [
        DownloadStage.completed.name,
        DownloadStage.failed.name,
        DownloadStage.cancelled.name,
      ],
    );
  }
}
