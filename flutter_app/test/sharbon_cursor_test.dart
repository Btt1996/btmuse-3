import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/features/player/sharbon_cursor.dart';

// v3.0.5, item 14 — Sharbon player cursor. Pure-Dart painter tests only:
// no widgets, no assets. Painting to a PictureRecorder canvas must not
// throw, and the thumb shape must report a sane preferred size (20x20,
// matching the seek section's 10 px thumb-radius geometry).

void main() {
  test('paintSharbonSilhouette paints without error to a canvas', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paintSharbonSilhouette(
      canvas,
      const Rect.fromLTWH(0, 0, 20, 20),
      outlineColor: Colors.white.withValues(alpha: 0.35),
      eyeColor: Colors.white,
    );
    final picture = recorder.endRecording();
    expect(picture, isNotNull);
    picture.dispose();
  });

  test('paintSharbonSilhouette works at mini-player size and with defaults', () {
    for (final size in [14.0, 20.0, 40.0]) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      paintSharbonSilhouette(canvas, Rect.fromLTWH(0, 0, size, size));
      recorder.endRecording().dispose();
    }
  });

  test('SharbonCatPainter paints without error and reports repaint correctly', () {
    const painter = SharbonCatPainter();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(20, 20));
    recorder.endRecording().dispose();

    expect(painter.shouldRepaint(const SharbonCatPainter()), isFalse);
    expect(
      painter.shouldRepaint(
        const SharbonCatPainter(color: Color(0xFF123456)),
      ),
      isTrue,
    );
  });

  test('SharbonThumbShape reports a sane 20x20 preferred size', () {
    const shape = SharbonThumbShape();
    final size = shape.getPreferredSize(true, false);
    expect(size.width, 20);
    expect(size.height, 20);
    expect(size.width, greaterThan(0));
    expect(size.width, lessThanOrEqualTo(32));
  });
}
