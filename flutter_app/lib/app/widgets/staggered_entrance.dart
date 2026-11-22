// Btt Music 2.00 — staggered list entrance.
//
// Wraps one list item so it fades + slides up once, on first appearance
// only. Used on the Home and Library track lists.
//
// Guarantees:
// - Animates once: the "played" state lives in the [State] object, keyed by
//   the track id at the call site (`ValueKey(track.id)`), so a provider
//   refresh, a rebuild, or a scroll never replays the entrance. State
//   survives rebuilds; only a genuinely new track id animates.
// - Capped: only the first [BttMotion.maxStaggeredItems] items animate.
//   Items below the fold render immediately with no wrapper at all.
// - Subtle: fade + a ~4 px rise over 350 ms, `Curves.easeOutCubic`, with a
//   40 ms delay per index — the list feels alive, never slow.
// - Built-in widgets only: [AnimatedOpacity] + [SlideTransition], driven by
//   one [AnimationController] started from [initState]. No `AnimatedList`,
//   no new packages.

import 'package:flutter/material.dart';
import 'package:btmu/app/btt_motion.dart';

class StaggeredEntrance extends StatefulWidget {
  /// Zero-based position of this item in its list. Drives the delay
  /// (`index * BttMotion.staggerStep`) and the stagger cap.
  final int index;

  final Widget child;

  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  /// Set once, in [initState], and never reset — this is what makes the
  /// entrance first-build-only.
  bool _visible = false;

  bool get _animates => widget.index < BttMotion.maxStaggeredItems;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: BttMotion.entranceDuration,
    );
    _slide = Tween<Offset>(
      begin: Offset(0.0, BttMotion.entranceSlideDistance),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: BttMotion.entranceCurve),
    );

    if (_animates) {
      // Stagger by index; the fade and the slide start in the same frame
      // so they read as one motion.
      Future.delayed(BttMotion.staggerStep * widget.index).then((_) {
        if (!mounted) return;
        setState(() => _visible = true);
        _controller.forward();
      });
    } else {
      _visible = true;
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Below the stagger cap: no wrapper, no animation, no cost.
    if (!_animates) return widget.child;

    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: BttMotion.entranceDuration,
      curve: BttMotion.entranceCurve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
