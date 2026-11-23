import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/utilities/crossfade_trigger.dart';
import 'package:btmu/core/utilities/traversal_order.dart';
import 'package:btmu/data/models/audio_settings.dart';

// Pure-logic tests for Phase 3 shuffle (S-1), repeat boundaries (S-2)
// and the crossfade trigger (S-3).
//
// These test `TraversalOrder` / `shouldTriggerCrossfade` directly: the
// handler delegates its next/previous/crossfade decisions to them, and
// the handler itself cannot be instantiated in a unit test without an
// audio session, a database and the platform channels. Handler-level
// behaviour (queue mutations, restore, missing-file skips) is therefore
// verified by device gate G-8 / G-9, not here.

void main() {
  group('TraversalOrder.sequential', () {
    test('walks the queue in order and stops at the ends (repeat-none)', () {
      final order = TraversalOrder.sequential(4, 0);
      expect(order.order, [0, 1, 2, 3]);
      expect(order.currentIndex, 0);

      expect(order.next(wrap: false), 1);
      order.moveTo(1);
      expect(order.next(wrap: false), 2);
      order.moveTo(3);
      expect(order.next(wrap: false), isNull);
      expect(order.previous(wrap: false), 2);

      order.moveTo(0);
      expect(order.previous(wrap: false), isNull);
    });

    test('repeat-all wraps at both ends', () {
      final order = TraversalOrder.sequential(3, 2);
      expect(order.next(wrap: true), 0);
      order.moveTo(0);
      expect(order.previous(wrap: true), 2);
    });

    test('empty queue has no next, previous or current track', () {
      final order = TraversalOrder.sequential(0, -1);
      expect(order.currentIndex, -1);
      expect(order.next(wrap: false), isNull);
      expect(order.next(wrap: true), isNull);
      expect(order.previous(wrap: false), isNull);
    });

    test('moveTo ignores an index that is not in the order', () {
      final order = TraversalOrder.sequential(3, 1);
      order.moveTo(99);
      expect(order.currentIndex, 1);
    });
  });

  group('TraversalOrder.shuffled (S-1)', () {
    test('current track first, every other track exactly once', () {
      final order = TraversalOrder.shuffled(5, 2, random: Random(42));
      expect(order.order, hasLength(5));
      expect(order.order.toSet(), {0, 1, 2, 3, 4});
      expect(order.order.first, 2);
      expect(order.currentIndex, 2);
    });

    test('full traversal visits every track exactly once, no repeats', () {
      final order = TraversalOrder.shuffled(10, 0, random: Random(7));
      final visited = <int>[order.currentIndex];
      var next = order.next(wrap: false);
      while (next != null) {
        visited.add(next);
        order.moveTo(next);
        next = order.next(wrap: false);
      }
      expect(visited, hasLength(10));
      expect(visited.toSet(), hasLength(10));
      expect(visited.toSet(), {0, 1, 2, 3, 4, 5, 6, 7, 8, 9});
      // And the queue ends there with repeat-none: no wrap.
      expect(order.next(wrap: false), isNull);
    });

    test('previous walks the shuffled order backwards', () {
      final order = TraversalOrder.shuffled(5, 1, random: Random(11));
      // Walk to the end, then step back and confirm we retrace.
      final forward = <int>[order.currentIndex];
      var next = order.next(wrap: false);
      while (next != null) {
        forward.add(next);
        order.moveTo(next);
        next = order.next(wrap: false);
      }
      final backward = <int>[order.currentIndex];
      var prev = order.previous(wrap: false);
      while (prev != null) {
        backward.add(prev);
        order.moveTo(prev);
        prev = order.previous(wrap: false);
      }
      expect(backward, forward.reversed.toList());
    });

    test('repeat-all wraps from the last shuffled track to the first', () {
      final order = TraversalOrder.shuffled(4, 0, random: Random(3));
      // Walk to the true end of the shuffled order, then wrap.
      var next = order.next(wrap: false);
      while (next != null) {
        order.moveTo(next);
        next = order.next(wrap: false);
      }
      expect(order.next(wrap: true), order.order.first);
    });

    test('toSequential restores the original order from the current track', () {
      final shuffled = TraversalOrder.shuffled(5, 3, random: Random(5));
      final sequential = shuffled.toSequential(3);
      expect(sequential.order, [0, 1, 2, 3, 4]);
      expect(sequential.currentIndex, 3);
      expect(sequential.next(wrap: false), 4);
    });
  });

  group('repeat boundaries (S-2)', () {
    test('next at the last track is null with repeat-none, first with repeat-all', () {
      final order = TraversalOrder.sequential(3, 2);
      expect(order.next(wrap: false), isNull);
      expect(order.next(wrap: true), 0);
    });

    test('previous at the first track is null with repeat-none, last with repeat-all', () {
      final order = TraversalOrder.sequential(3, 0);
      expect(order.previous(wrap: false), isNull);
      expect(order.previous(wrap: true), 2);
    });
  });

  group('shouldTriggerCrossfade (S-3)', () {
    const base = (
      crossfadeEnabled: true,
      isPlaying: true,
      isCrossfading: false,
      remaining: Duration(seconds: 5),
      duration: Duration(seconds: 200),
      crossfadeSeconds: 6.0,
      queueLength: 3,
    );

    bool trigger({
      bool? crossfadeEnabled,
      bool? isPlaying,
      bool? isCrossfading,
      Duration? remaining,
      Duration? duration,
      double? crossfadeSeconds,
      int? queueLength,
    }) {
      return shouldTriggerCrossfade(
        crossfadeEnabled: crossfadeEnabled ?? base.crossfadeEnabled,
        isPlaying: isPlaying ?? base.isPlaying,
        isCrossfading: isCrossfading ?? base.isCrossfading,
        remaining: remaining ?? base.remaining,
        duration: duration ?? base.duration,
        crossfadeSeconds: crossfadeSeconds ?? base.crossfadeSeconds,
        queueLength: queueLength ?? base.queueLength,
      );
    }

    test('fires inside the overlap window', () {
      expect(trigger(), isTrue);
      expect(trigger(remaining: const Duration(seconds: 6)), isTrue);
      expect(trigger(remaining: const Duration(milliseconds: 500)), isTrue);
    });

    test('does not fire outside the window', () {
      expect(trigger(remaining: const Duration(seconds: 7)), isFalse);
      expect(trigger(remaining: Duration.zero), isFalse);
    });

    test('does not fire when crossfade is disabled', () {
      expect(trigger(crossfadeEnabled: false), isFalse);
    });

    test('does not fire when paused, already crossfading, or alone in the queue', () {
      expect(trigger(isPlaying: false), isFalse);
      expect(trigger(isCrossfading: true), isFalse);
      expect(trigger(queueLength: 1), isFalse);
    });

    test('does not fire for a track too short to contain an overlap', () {
      expect(
        trigger(duration: const Duration(seconds: 7), crossfadeSeconds: 6.0),
        isFalse,
      );
      expect(
        trigger(duration: const Duration(seconds: 9), crossfadeSeconds: 6.0),
        isTrue,
      );
    });
  });

  group('AudioSettings crossfade fields (S-3 / C-3)', () {
    test('crossfade defaults to off with a 6 s overlap', () {
      const settings = AudioSettings();
      expect(settings.crossfadeEnabled, isFalse);
      expect(settings.crossfadeSeconds, 6.0);
      expect(settings.playbackSpeed, 1.0);
    });

    test('copyWith carries the crossfade fields', () {
      const settings = AudioSettings();
      final next = settings.copyWith(
        crossfadeEnabled: true,
        crossfadeSeconds: 2.0,
        playbackSpeed: 1.5,
      );
      expect(next.crossfadeEnabled, isTrue);
      expect(next.crossfadeSeconds, 2.0);
      expect(next.playbackSpeed, 1.5);
      // Unchanged fields survive the copy.
      expect(next.volumeMultiplier, settings.volumeMultiplier);
      expect(next.eqPreset, settings.eqPreset);
    });
  });
}
