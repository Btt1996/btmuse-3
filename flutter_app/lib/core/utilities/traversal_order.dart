import 'dart:math';

/// Pure playback traversal order (Phase 3, S-1 / S-2).
///
/// The handler keeps one of these instead of picking a random track on
/// every skip. `order` is the queue indices in play order and `position`
/// is where the current track sits in that order:
///
/// * sequential: `order` is `[0, 1, 2, ...]`, so next/previous step
///   through the queue as listed.
/// * shuffled: `order` is a Fisher–Yates shuffle with the current track
///   moved to the front, so a shuffled session visits every track exactly
///   once before any repeat, and Previous walks the shuffled order
///   backwards instead of jumping to the previous index in the original
///   list. Turning shuffle off discards the shuffled order and the
///   sequential order takes over from the current track.
///
/// Repeat is honoured at the boundaries only: `next`/`previous` return
/// `null` at the end/start unless `wrap` is true (repeat-all). Repeat-one
/// never reaches these helpers — the handler restarts the current track
/// on completion instead. A `null` result is what makes repeat-none
/// actually end the queue instead of wrapping with `% length`.
///
/// This class is pure Dart (no audio, no platform) so the traversal
/// contract is unit-testable; see `test/shuffle_repeat_test.dart`.
class TraversalOrder {
  /// Queue indices in play order. Never mutated in place by this class.
  final List<int> order;

  /// Position of the current track inside [order], or -1 if there is no
  /// current track.
  int position;

  TraversalOrder._(this.order, this.position);

  /// Sequential order over a queue of [length] tracks, positioned at
  /// [currentIndex] (-1 when nothing is playing).
  factory TraversalOrder.sequential(int length, int currentIndex) {
    final order = List<int>.generate(length, (i) => i);
    return TraversalOrder._(
      order,
      currentIndex >= 0 && currentIndex < length ? currentIndex : -1,
    );
  }

  /// Shuffled order over a queue of [length] tracks. The current track
  /// ([currentIndex]) is moved to the front so enabling shuffle mid-queue
  /// keeps playing what is playing and shuffles the rest; every other
  /// track appears exactly once after it. Pass a seeded [random] in tests
  /// for a deterministic order.
  factory TraversalOrder.shuffled(
    int length,
    int currentIndex, {
    Random? random,
  }) {
    final order = List<int>.generate(length, (i) => i)..shuffle(random);
    var position = 0;
    if (currentIndex >= 0 && currentIndex < length) {
      order.remove(currentIndex);
      order.insert(0, currentIndex);
      position = 0;
    }
    return TraversalOrder._(order, position);
  }

  /// Queue index of the current track, or -1 when there is none.
  int get currentIndex =>
      position >= 0 && position < order.length ? order[position] : -1;

  /// The next queue index in traversal order, or `null` at the end when
  /// [wrap] is false (repeat-none: the queue ends here). With [wrap]
  /// (repeat-all) the first track in traversal order is returned.
  int? next({required bool wrap}) {
    if (order.isEmpty || position < 0) return null;
    if (position + 1 < order.length) return order[position + 1];
    return wrap ? order.first : null;
  }

  /// The previous queue index in traversal order, or `null` at the start
  /// when [wrap] is false (repeat-none: no wrap to the last track). With
  /// [wrap] (repeat-all) the last track in traversal order is returned.
  int? previous({required bool wrap}) {
    if (order.isEmpty || position < 0) return null;
    if (position - 1 >= 0) return order[position - 1];
    return wrap ? order.last : null;
  }

  /// Moves the traversal position to [queueIndex] (e.g. after a direct
  /// jump or a queue edit). No-op when the index is not in the order.
  void moveTo(int queueIndex) {
    final pos = order.indexOf(queueIndex);
    if (pos != -1) position = pos;
  }

  /// Returns a new sequential order positioned at [currentIndex]; used
  /// when shuffle is turned off so the original order is restored from
  /// the current track.
  TraversalOrder toSequential(int currentIndex) =>
      TraversalOrder.sequential(order.length, currentIndex);
}
