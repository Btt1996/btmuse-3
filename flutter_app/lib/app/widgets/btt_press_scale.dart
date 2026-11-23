// Btt Music 2.00 — press-scale micro-interaction.
//
// Wraps a tappable row so it shrinks gently to 0.97 while the finger is
// down and springs back on release. Used on the Home / Library track rows
// (around [TrackTile] and the Home "Recently Played" cards).
//
// Deliberately built on [Listener], not [GestureDetector]: raw pointer
// down/up/cancel events never enter the gesture arena, so this can never
// steal, delay, or swallow the child's own tap (InkWell ripple, onTap,
// favorite button, etc.). It only observes the press and animates the
// scale. [AnimatedScale] is built-in; no new packages.

import 'package:flutter/material.dart';
import 'package:btmu/app/btt_motion.dart';

class BttPressScale extends StatefulWidget {
  final Widget child;

  /// Scale while pressed. Defaults to [BttMotion.pressScale] (0.97).
  final double pressedScale;

  const BttPressScale({
    super.key,
    required this.child,
    this.pressedScale = BttMotion.pressScale,
  });

  @override
  State<BttPressScale> createState() => _BttPressScaleState();
}

class _BttPressScaleState extends State<BttPressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: BttMotion.microDuration,
        curve: BttMotion.microCurve,
        child: widget.child,
      ),
    );
  }
}
