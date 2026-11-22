// Btt Music 2.00 — the one page transition for the whole app.
//
// Replaces every `MaterialPageRoute` push in the app (mechanical swap, same
// builders). One continuous motion, open and close:
//
// - Incoming page: slides in from the right + fades in, both driven by the
//   SAME eased animation, so slide and fade reach their end values at
//   exactly the same instant — there is no frame where the page is in place
//   but still fading (or vice versa), i.e. no pop at the end.
// - Outgoing page: drifts 8% to the left underneath, iOS-style depth. This
//   runs off `secondaryAnimation`, so it only applies while this route is
//   covered by a newer one, and it reverses symmetrically on pop.
// - 300 ms, `Curves.easeOutCubic`, both directions — see [BttMotion].
//
// Built on [PageRouteBuilder] only; no new packages. `fullscreenDialog`,
// `settings` and the generic type parameter behave exactly like
// `MaterialPageRoute`'s, so call sites change by one identifier only.

import 'package:flutter/material.dart';
import 'package:btmu/app/btt_motion.dart';

class BttPageRoute<T> extends PageRouteBuilder<T> {
  BttPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(
          transitionDuration: BttMotion.routeDuration,
          reverseTransitionDuration: BttMotion.routeReverseDuration,
          opaque: true,
          maintainState: true,
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // One eased animation drives both slide and fade, so the motion
            // lands as a single gesture instead of two layered ones.
            final curved = CurvedAnimation(
              parent: animation,
              curve: BttMotion.routeCurve,
            );
            final slide = Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(curved);
            final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);

            // The page underneath shifts slightly left while covered, and
            // glides back on pop. Driven by secondaryAnimation, so it is
            // zero while this route is on top and costs nothing then.
            final outgoing = Tween<Offset>(
              begin: Offset.zero,
              end: Offset(-BttMotion.outgoingPageShift, 0.0),
            ).animate(
              CurvedAnimation(
                parent: secondaryAnimation,
                curve: BttMotion.routeCurve,
              ),
            );

            return SlideTransition(
              position: outgoing,
              child: FadeTransition(
                opacity: fade,
                child: SlideTransition(position: slide, child: child),
              ),
            );
          },
        );
}
