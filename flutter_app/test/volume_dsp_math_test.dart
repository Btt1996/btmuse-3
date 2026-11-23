import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/utilities/volume_dsp_math.dart';

void main() {
  test('300% boost with limiter engaged caps output safely below hard clipping', () {
    final res = VolumeDspMath.evaluateGain(
      multiplier: 3.0,
      limiterEnabled: true,
      nominalSignalRms: 0.45,
    );

    expect(res.limiterEngaged, isTrue);
    expect(res.clippingRisk, isFalse);
    expect(res.linearOutput * 0.45, lessThan(0.90));
  });

  test('300% boost without limiter flags clipping risk accurately', () {
    final res = VolumeDspMath.evaluateGain(
      multiplier: 3.0,
      limiterEnabled: false,
      nominalSignalRms: 0.45,
    );

    expect(res.limiterEngaged, isFalse);
    expect(res.clippingRisk, isTrue);
  });

  test('Equal-power crossfade conserves signal power across transition', () {
    for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final (outGain, inGain) = VolumeDspMath.equalPowerCrossfade(t);
      final power = math.pow(outGain, 2) + math.pow(inGain, 2);
      expect(power, closeTo(1.0, 0.0001));
    }
  });
}
