import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:btmu/core/storage/local_database.dart';

/// Persisted playback queue (Phase 3, Q-1).
///
/// Storage layout (schema v4, created by [LocalDatabase]):
///
/// * `playback_queue (position INTEGER PRIMARY KEY, track_id TEXT NOT NULL,
///   FOREIGN KEY(track_id) REFERENCES tracks(id) ON DELETE CASCADE)` —
///   one row per track, `position` is the 0-based play order.
/// * `playback_state` — exactly one row (`id = 1`): current index,
///   resume position, shuffle flag, repeat mode, optional source label.
///
/// The shuffled traversal order is deliberately NOT stored: it is rebuilt
/// on restore with the current track first (see `TraversalOrder.shuffled`),
/// so a queue edit can never leave a stale shuffled order behind.
///
/// One write path: every queue mutation persists the full ordered queue
/// plus state in a single transaction ([saveQueue]). The 5-second
/// checkpoint timer uses the cheap [savePosition] instead, which only
/// touches the state row.
///
/// This repository mirrors [LibraryRepository]: it takes the
/// [LocalDatabase] and opens the database through it. It never touches
/// the `tracks`, `lyrics_cache`, or backup tables.
class QueueRepository {
  final LocalDatabase _db;

  QueueRepository(this._db);

  /// Repeat-mode values stored in `playback_state.repeat_mode`. They match
  /// `AudioServiceRepeatMode.name` (`'none'` | `'one'` | `'all'`); anything
  /// else read back is treated as `'none'`.
  static const List<String> validRepeatModes = ['none', 'one', 'all'];

  static String normalizeRepeatMode(String? raw) =>
      validRepeatModes.contains(raw) ? raw! : 'none';

  /// The rows [saveQueue] inserts into `playback_queue` for [trackIds]:
  /// one `{position, track_id}` map per track, positions 0-based in order.
  /// Pure helper, unit-tested in `test/queue_repository_test.dart`.
  static List<Map<String, Object?>> queueRowsFor(List<String> trackIds) {
    return List<Map<String, Object?>>.generate(
      trackIds.length,
      (i) => {'position': i, 'track_id': trackIds[i]},
    );
  }

  /// Persists the whole queue + state atomically. An empty [queue] clears
  /// the stored queue (the state row is kept with `current_index = -1`
  /// so a later [loadQueue] still returns a well-formed empty state).
  Future<void> saveQueue(SavedQueue queue) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('playback_queue');
      for (final row in queueRowsFor(queue.trackIds)) {
        await txn.insert('playback_queue', row);
      }
      await txn.insert(
        'playback_state',
        queue.copyWith(updatedAtMs: now).toStateMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Loads the saved queue, or `null` when nothing was ever saved.
  /// The current index is clamped to the loaded ids; an empty queue
  /// loads as an empty [SavedQueue] with `currentIndex == -1`.
  Future<SavedQueue?> loadQueue() async {
    final db = await _db.database;
    final stateRows = await db.query(
      'playback_state',
      where: 'id = ?',
      whereArgs: const [1],
      limit: 1,
    );
    if (stateRows.isEmpty) return null;
    final queueRows = await db.query(
      'playback_queue',
      columns: const ['track_id'],
      orderBy: 'position ASC',
    );
    final ids = queueRows
        .map((r) => r['track_id'] as String?)
        .whereType<String>()
        .toList();
    return SavedQueue.fromStateRow(stateRows.first, ids);
  }

  /// Drops the saved queue and its state row.
  Future<void> clearQueue() async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('playback_queue');
      await txn.delete('playback_state');
    });
  }

  /// Cheap position-only update for the checkpoint timer: touches only
  /// the state row. No-op when no queue state has been saved yet.
  Future<void> savePosition(int positionMs) async {
    final db = await _db.database;
    await db.update(
      'playback_state',
      {
        'position_ms': math.max(0, positionMs),
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: const [1],
    );
  }
}

/// The queue + playback state as stored in SQLite (schema v4).
///
/// Pure value object: [toStateMap]/[fromStateRow] are the only
/// serialization, and are unit-tested without opening a database
/// (the repo has no `sqflite_common_ffi` test double — see
/// `test/queue_repository_test.dart`).
class SavedQueue {
  /// Ordered track ids, as listed in `playback_queue`.
  final List<String> trackIds;

  /// Index of the current track in [trackIds], or -1 when the queue is
  /// empty / nothing is playing.
  final int currentIndex;

  /// Resume position of the current track, milliseconds.
  final int positionMs;

  final bool shuffle;

  /// `'none'` | `'one'` | `'all'` (see [QueueRepository.validRepeatModes]).
  final String repeatMode;

  /// Where the queue came from (e.g. a playlist name), for the UI.
  final String? sourceLabel;

  final int updatedAtMs;

  const SavedQueue({
    required this.trackIds,
    required this.currentIndex,
    this.positionMs = 0,
    this.shuffle = false,
    this.repeatMode = 'none',
    this.sourceLabel,
    this.updatedAtMs = 0,
  });

  SavedQueue copyWith({
    List<String>? trackIds,
    int? currentIndex,
    int? positionMs,
    bool? shuffle,
    String? repeatMode,
    String? sourceLabel,
    int? updatedAtMs,
  }) {
    return SavedQueue(
      trackIds: trackIds ?? this.trackIds,
      currentIndex: currentIndex ?? this.currentIndex,
      positionMs: positionMs ?? this.positionMs,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  /// The `playback_state` row (single row, `id = 1`).
  Map<String, Object?> toStateMap() => {
        'id': 1,
        'current_index': currentIndex,
        'position_ms': math.max(0, positionMs),
        'shuffle': shuffle ? 1 : 0,
        'repeat_mode': QueueRepository.normalizeRepeatMode(repeatMode),
        'source_label': sourceLabel,
        'updated_at_ms': updatedAtMs,
      };

  /// Rebuilds a [SavedQueue] from a `playback_state` row plus the ordered
  /// ids read from `playback_queue`. Defensive by design: a corrupt or
  /// out-of-range stored index is clamped, a negative position becomes 0,
  /// and an unknown repeat mode becomes `'none'` — a bad stored row must
  /// never crash the restore path.
  factory SavedQueue.fromStateRow(
    Map<String, Object?> row,
    List<String> trackIds,
  ) {
    final storedIndex = (row['current_index'] as int?) ?? -1;
    return SavedQueue(
      trackIds: List<String>.unmodifiable(trackIds),
      currentIndex: trackIds.isEmpty
          ? -1
          : storedIndex.clamp(0, trackIds.length - 1),
      positionMs: math.max(0, (row['position_ms'] as int?) ?? 0),
      shuffle: ((row['shuffle'] as int?) ?? 0) == 1,
      repeatMode:
          QueueRepository.normalizeRepeatMode(row['repeat_mode'] as String?),
      sourceLabel: row['source_label'] as String?,
      updatedAtMs: (row['updated_at_ms'] as int?) ?? 0,
    );
  }
}
