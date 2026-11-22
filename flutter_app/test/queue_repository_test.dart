import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/core/storage/queue_repository.dart';

// Repository-level tests for the Phase 3 (Q-1) persisted queue.
//
// NOTE on scope: the repo has no `sqflite_common_ffi` test double — the
// existing test suite deliberately avoids opening a sqflite database
// (see e.g. `test/backup_service_test.dart`). So these tests cover the
// pure parts of the repository contract: state serialization, repeat-mode
// normalisation, the row builder `saveQueue` inserts, and the schema
// version. A full save → reload round-trip against a real database needs
// a device or a sqflite test double and is a CI/device follow-up, not
// something these tests pretend to prove.

void main() {
  group('schema version (Q-1)', () {
    test('schema is v4 (queue tables exist from v4 on)', () {
      expect(LocalDatabase.schemaVersion, 4);
    });
  });

  group('SavedQueue serialization', () {
    test('toStateMap / fromStateRow round-trips all fields', () {
      const saved = SavedQueue(
        trackIds: ['t1', 't2', 't3'],
        currentIndex: 1,
        positionMs: 12345,
        shuffle: true,
        repeatMode: 'all',
        sourceLabel: 'Road Trip',
        updatedAtMs: 999,
      );
      final restored = SavedQueue.fromStateRow(
        saved.toStateMap(),
        saved.trackIds,
      );
      expect(restored.trackIds, ['t1', 't2', 't3']);
      expect(restored.currentIndex, 1);
      expect(restored.positionMs, 12345);
      expect(restored.shuffle, isTrue);
      expect(restored.repeatMode, 'all');
      expect(restored.sourceLabel, 'Road Trip');
      expect(restored.updatedAtMs, 999);
    });

    test('state row always uses id 1 (single-row table)', () {
      const saved = SavedQueue(trackIds: ['t1'], currentIndex: 0);
      expect(saved.toStateMap()['id'], 1);
    });

    test('empty queue restores with currentIndex -1', () {
      const saved = SavedQueue(trackIds: [], currentIndex: -1);
      final restored = SavedQueue.fromStateRow(saved.toStateMap(), []);
      expect(restored.trackIds, isEmpty);
      expect(restored.currentIndex, -1);
    });

    test('out-of-range stored index is clamped, never crashes restore', () {
      final tooBig = SavedQueue.fromStateRow(
        {'current_index': 99, 'position_ms': 0, 'shuffle': 0, 'repeat_mode': 'none'},
        ['t1', 't2'],
      );
      expect(tooBig.currentIndex, 1);

      final negative = SavedQueue.fromStateRow(
        {'current_index': -5, 'position_ms': 0, 'shuffle': 0, 'repeat_mode': 'none'},
        ['t1', 't2'],
      );
      expect(negative.currentIndex, 0);
    });

    test('negative stored position becomes 0', () {
      final restored = SavedQueue.fromStateRow(
        {'current_index': 0, 'position_ms': -100, 'shuffle': 0, 'repeat_mode': 'none'},
        ['t1'],
      );
      expect(restored.positionMs, 0);
    });

    test('unknown repeat mode becomes none', () {
      final restored = SavedQueue.fromStateRow(
        {'current_index': 0, 'position_ms': 0, 'shuffle': 1, 'repeat_mode': 'banana'},
        ['t1'],
      );
      expect(restored.repeatMode, 'none');
      expect(restored.shuffle, isTrue);
    });

    test('missing columns fall back to defaults', () {
      final restored = SavedQueue.fromStateRow({}, ['t1']);
      expect(restored.currentIndex, 0);
      expect(restored.positionMs, 0);
      expect(restored.shuffle, isFalse);
      expect(restored.repeatMode, 'none');
      expect(restored.sourceLabel, isNull);
    });
  });

  group('repeat-mode normalisation', () {
    test('valid modes pass through, anything else becomes none', () {
      expect(QueueRepository.normalizeRepeatMode('none'), 'none');
      expect(QueueRepository.normalizeRepeatMode('one'), 'one');
      expect(QueueRepository.normalizeRepeatMode('all'), 'all');
      expect(QueueRepository.normalizeRepeatMode('off'), 'none');
      expect(QueueRepository.normalizeRepeatMode(''), 'none');
      expect(QueueRepository.normalizeRepeatMode(null), 'none');
    });
  });

  group('queueRowsFor (what saveQueue inserts)', () {
    test('rows are 0-based positions in queue order', () {
      final rows = QueueRepository.queueRowsFor(['a', 'b', 'c']);
      expect(rows, [
        {'position': 0, 'track_id': 'a'},
        {'position': 1, 'track_id': 'b'},
        {'position': 2, 'track_id': 'c'},
      ]);
    });

    test('empty queue produces no rows', () {
      expect(QueueRepository.queueRowsFor([]), isEmpty);
    });
  });
}
