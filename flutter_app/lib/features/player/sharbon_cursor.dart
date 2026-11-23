import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sharbon — the user's black kitten — as a small vector silhouette.
///
/// No photo, no image asset: the cat is drawn with paths (sitting cat:
/// body, head, two ears, tail curve), so it stays crisp at ~20 px and
/// costs nothing to ship. The near-black fill reads on the dark player
/// because the thumb / cursor variants add a faint light outline and two
/// tiny eye dots; the fill itself stays black, as Sharbon is.
///
/// v3.0.5, item 14.
void paintSharbonSilhouette(
  Canvas canvas,
  Rect bounds, {
  Color color = const Color(0xFF0B0B0F),
  Color? outlineColor,
  Color? eyeColor,
}) {
  // Work in a 20x20 box, scaled/translated into [bounds].
  final scale = bounds.width / 20.0;
  canvas.save();
  canvas.translate(bounds.left, bounds.top);
  canvas.scale(scale, scale);

  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  final outline = outlineColor == null
      ? null
      : (Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..strokeJoin = StrokeJoin.round);

  // Tail: a curve sweeping up the right side of the body, drawn first
  // so the body overlaps its base.
  final tail = Path()
    ..moveTo(14.5, 18.5)
    ..quadraticBezierTo(19.5, 17.0, 19.0, 11.5)
    ..quadraticBezierTo(18.7, 8.5, 16.5, 7.0);
  canvas.drawPath(
    tail,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round,
  );

  // Body: sitting haunch, wider at the base.
  final body = Path()
    ..moveTo(4.0, 19.0)
    ..quadraticBezierTo(2.5, 12.5, 6.0, 9.5)
    ..quadraticBezierTo(9.0, 7.5, 12.5, 9.5)
    ..quadraticBezierTo(15.5, 12.0, 15.0, 19.0)
    ..close();
  canvas.drawPath(body, fill);
  if (outline != null) canvas.drawPath(body, outline);

  // Head.
  final head = Path()
    ..addOval(Rect.fromCircle(center: const Offset(9.5, 6.0), radius: 4.4));
  canvas.drawPath(head, fill);
  if (outline != null) canvas.drawPath(head, outline);

  // Ears: two small triangles on top of the head.
  final ears = Path()
    ..moveTo(5.6, 4.6)
    ..lineTo(7.6, 4.4)
    ..lineTo(6.1, 0.6)
    ..close()
    ..moveTo(11.4, 4.4)
    ..lineTo(13.4, 4.6)
    ..lineTo(12.9, 0.6)
    ..close();
  canvas.drawPath(ears, fill);
  if (outline != null) canvas.drawPath(ears, outline);

  // Eyes: two tiny dots so the mark reads as a cat at ~20 px.
  if (eyeColor != null) {
    final eyes = Paint()..color = eyeColor;
    canvas.drawCircle(const Offset(7.8, 6.0), 0.75, eyes);
    canvas.drawCircle(const Offset(11.2, 6.0), 0.75, eyes);
  }

  canvas.restore();
}

/// Paints [paintSharbonSilhouette] into the given [size].
class SharbonCatPainter extends CustomPainter {
  final Color color;
  final Color? outlineColor;
  final Color? eyeColor;

  const SharbonCatPainter({
    this.color = const Color(0xFF0B0B0F),
    this.outlineColor,
    this.eyeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintSharbonSilhouette(
      canvas,
      Offset.zero & size,
      color: color,
      outlineColor: outlineColor,
      eyeColor: eyeColor,
    );
  }

  @override
  bool shouldRepaint(covariant SharbonCatPainter oldDelegate) =>
      color != oldDelegate.color ||
      outlineColor != oldDelegate.outlineColor ||
      eyeColor != oldDelegate.eyeColor;
}

/// A tiny Sharbon, ready to drop into a row or stack (e.g. the mini
/// player's progress bar). No assets involved.
class SharbonCursor extends StatelessWidget {
  final double size;
  final Color? outlineColor;
  final Color? eyeColor;

  const SharbonCursor({
    super.key,
    this.size = 20,
    this.outlineColor,
    this.eyeColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: SharbonCatPainter(
          outlineColor: outlineColor,
          eyeColor: eyeColor,
        ),
      ),
    );
  }
}

/// Slider thumb shaped like Sharbon. Preferred size is 20x20 so it drops
/// into the existing seek section without moving the gradient track
/// geometry (which insets the fill by the 10 px thumb radius).
class SharbonThumbShape extends SliderComponentShape {
  const SharbonThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(20, 20);

  @override
  void paint(
    PaintingContext context,
    Offset thumbCenter, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    // Faint halo so the near-black cat stays visible on the dark track.
    canvas.drawCircle(
      thumbCenter,
      11,
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );
    paintSharbonSilhouette(
      canvas,
      Rect.fromCenter(center: thumbCenter, width: 20, height: 20),
      outlineColor: Colors.white.withValues(alpha: 0.35),
      eyeColor: Colors.white,
    );
  }
}

/// Idle animation: when nothing is playing, Sharbon paces slowly along
/// the track with a subtle bob. Ping-pong (0 → 1 → 0) so the cat never
/// teleports back to the start.
class SharbonIdleAnimation extends StatefulWidget {
  final double height;

  const SharbonIdleAnimation({super.key, this.height = 22});

  @override
  State<SharbonIdleAnimation> createState() => _SharbonIdleAnimationState();
}

class _SharbonIdleAnimationState extends State<SharbonIdleAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              // Smooth ping-pong along the track.
              final along = (1 - math.cos(t * 2 * math.pi)) / 2;
              // Subtle bob: three little steps per crossing.
              final bob = -1.5 * (math.sin(t * 2 * math.pi * 3).abs());
              final travel = (width - 20).clamp(0.0, double.infinity);
              return Stack(
                children: [
                  Positioned(
                    left: along * travel,
                    top: 2 + bob,
                    child: child!,
                  ),
                ],
              );
            },
            child: SharbonCursor(
              size: 20,
              outlineColor: Colors.white.withValues(alpha: 0.30),
              eyeColor: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
