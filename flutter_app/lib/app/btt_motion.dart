// Btt Music 2.00 — shared motion language.
//
// ONE spec for every animation in the app. Every new animation (routes,
// list entrances, press feedback, and any future stream's work — player
// dismiss, sheet entrances, Hero flights) must take its durations, easings
// and distances from here, never from a hard-coded literal, so the whole
// app moves like one product.
//
// Design choices:
// - One easing family (easeOutCubic) for all travelling motion: fast to
//   start, gentle to land. Nothing in the app eases in, bounces, or
//   overshoots — the landing is always soft, never springy.
// - Route 300 ms: matches the iOS push rhythm; long enough to read as a
//   motion, short enough never to feel like waiting. Reverse is the same
//   300 ms so open and close are one symmetric motion with no pop.
// - Entrance 350 ms with a 40 ms stagger step: the first item is already
//   moving on arrival and the 8th settles ~630 ms in — alive, not slow.
// - Micro 150 ms: press feedback must register instantly and be gone by
//   the time the finger lifts; anything longer feels laggy.
// - Stagger is capped at the first 8 items (roughly one screenful). Items
//   below the fold appear instantly — animating them would only delay
//   content the user scrolls to later.
// - Entrance slide is 6% of the row height (~4 px on a track row):
//   perceptible, never floaty.

import 'package:flutter/widgets.dart';

/// Single source of truth for Btt Music motion.
class BttMotion {
  BttMotion._();

  /// Page-route push / pop duration.
  static const Duration routeDuration = Duration(milliseconds: 300);

  /// Page-route reverse duration. Kept equal to [routeDuration] on purpose:
  /// open and close must feel like the same motion played backwards.
  static const Duration routeReverseDuration = Duration(milliseconds: 300);

  /// Staggered list-entrance duration (fade + slide, per item).
  static const Duration entranceDuration = Duration(milliseconds: 350);

  /// Press-scale micro-interaction duration.
  static const Duration microDuration = Duration(milliseconds: 150);

  /// Delay added per staggered item index.
  static const Duration staggerStep = Duration(milliseconds: 40);

  /// Only the first this-many items in a list animate in; the rest render
  /// immediately with no entrance animation.
  static const int maxStaggeredItems = 8;

  /// Entrance slide distance, as a fraction of the child's own height.
  /// 0.06 is ~4 px on a track row — subtle by design.
  static const double entranceSlideDistance = 0.06;

  /// Pressed scale for tappable rows (1.0 at rest).
  static const double pressScale = 0.97;

  /// Slide distance of the page underneath when a new page pushes over it,
  /// as a fraction of screen width. iOS-style depth, kept small.
  static const double outgoingPageShift = 0.08;

  /// Easing for route transitions (push / pop).
  static const Curve routeCurve = Curves.easeOutCubic;

  /// Easing for staggered list entrances.
  static const Curve entranceCurve = Curves.easeOutCubic;

  /// Easing for press-scale micro-interactions (snappy return).
  static const Curve microCurve = Curves.easeOut;
}
