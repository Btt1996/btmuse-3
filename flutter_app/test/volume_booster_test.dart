import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/utilities/volume_dsp_math.dart';

/// Phase 3, E-2 / P3: port of the SwiftUI `BoosterTests` gain mapping.
///
/// The SwiftUI tests asserted the booster gain law — gain = multiplier,
/// `dB = 20 * log10(multiplier)` — at the boost presets. This file ports
/// that mapping against the Flutter path's Dart mirror
/// ([VolumeDspMath.evaluateGain]) and the numbers the native plugin reports
/// (`AudioEnginePlugin.applyAudioSettings` returns `rawBoostDb`,
/// `normalizationDb`, `boostDb` and `overallGainDb`; the DynamicsProcessor
/// `OverallGain` parameter receives the effective gain clamped to
/// [-40, +12] dB).
///
/// What this test does NOT prove (recorded explicitly, per the Phase 3
/// brief): that the native `OverallGain` parameter itself is applied — no
/// iOS unit-test target exists in this repo, so the Swift value is asserted
/// only by the code in `AudioEnginePlugin.swift` plus device gates G-6/G-7
/// (booster on + background playback; each EQ/booster setting audible).
/// This test proves the Dart model the UI shows is the same law.
///
/// Reference numbers (all `20 * log10(multiplier)`):
///   100% ->   0.00 dB      200% ->  +6.02 dB
///   125% ->  +1.94 dB      250% ->  +7.96 dB
///   150% ->  +3.52 dB      300% ->  +9.54 dB (raw, normalization off)
/// Since v3.0.5 the normalization pad no longer subtracts from an explicit
/// boost: 300% delivers its full +9.54 dB (see
/// `VolumeDspMath.effectiveNormalizationOffsetDb`). The pure function
/// below still honors any offset it is handed — the -1.5 dB case is kept
/// as a math check, not as the app's behaviour while boosting.
/// 300% is +9.5 dB of digital gain, not 3x perceived loudness.
void main() {
  group('BoosterTests port — gain = multiplier, dB = 20 * log10(multiplier)', () {
    test('gain mapping at every boost preset (normalization off)', () {
      final expectedDb = <double, double>{
        1.0: 0.0,
        1.25: 1.94,
        1.5: 3.52,
        2.0: 6.02,
        2.5: 7.96,
        3.0: 9.54,
      };
      for (final entry in expectedDb.entries) {
        final res = VolumeDspMath.evaluateGain(
          multiplier: entry.key,
          limiterEnabled: false,
          normalizationOffsetDb: 0.0,
        );
        expect(res.gainDb, closeTo(entry.value, 0.01),
            reason: '${entry.key}x should be ${entry.value} dB');
      }
    });

    test('100% is unity gain (0 dB)', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 1.0,
        limiterEnabled: false,
        normalizationOffsetDb: 0.0,
      );
      expect(res.gainDb, closeTo(0.0, 0.001));
      expect(res.linearOutput, closeTo(1.0, 0.001));
      expect(res.clippingRisk, isFalse);
    });

    test('200% is +6.02 dB', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 2.0,
        limiterEnabled: false,
        normalizationOffsetDb: 0.0,
      );
      expect(res.gainDb, closeTo(6.02, 0.01));
    });

    test('300% raw gain is +9.54 dB with normalization off', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 3.0,
        limiterEnabled: false,
        normalizationOffsetDb: 0.0,
      );
      expect(res.gainDb, closeTo(9.54, 0.01));
      expect(res.linearOutput, closeTo(3.0, 0.001));
    });

    test('pure math: a -1.5 dB offset handed in still yields +8.04 dB at 300%', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 3.0,
        limiterEnabled: false,
        normalizationOffsetDb: -1.5,
      );
      expect(res.gainDb, closeTo(8.04, 0.01));
      // The pure function honors the offset it is handed. The app no
      // longer hands it -1.5 while boosting — see the helper group below.
      expect(res.gainDb, isNot(closeTo(9.54, 0.01)));
    });

    test('100% with default normalization is -1.5 dB, not 0 dB', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 1.0,
        limiterEnabled: false,
        normalizationOffsetDb: -1.5,
      );
      expect(res.gainDb, closeTo(-1.5, 0.001));
    });
  });

  group('limiter ceiling — soft-knee at -1.0 dBFS (~0.89125 linear)', () {
    test('300% with limiter engaged stays below the ceiling', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 3.0,
        limiterEnabled: true,
        normalizationOffsetDb: 0.0,
        nominalSignalRms: 0.45,
      );
      expect(res.limiterEngaged, isTrue);
      expect(res.clippingRisk, isFalse);
      expect(res.linearOutput * 0.45, lessThan(0.89125));
    });

    test('300% with limiter engaged stays below the ceiling even for a loud signal', () {
      for (final rms in [0.9, 1.0]) {
        final res = VolumeDspMath.evaluateGain(
          multiplier: 3.0,
          limiterEnabled: true,
          normalizationOffsetDb: 0.0,
          nominalSignalRms: rms,
        );
        expect(res.limiterEngaged, isTrue);
        expect(res.clippingRisk, isFalse);
        expect(res.linearOutput * rms, lessThan(0.89125),
            reason: 'nominal RMS $rms');
      }
    });

    test('300% without limiter flags clipping risk (limiter off is the risky state)', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 3.0,
        limiterEnabled: false,
        normalizationOffsetDb: 0.0,
        nominalSignalRms: 0.45,
      );
      expect(res.limiterEngaged, isFalse);
      expect(res.clippingRisk, isTrue);
      expect(res.linearOutput, closeTo(3.0, 0.001));
    });

    test('100% does not engage the limiter for a nominal signal', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 1.0,
        limiterEnabled: true,
        normalizationOffsetDb: 0.0,
        nominalSignalRms: 0.45,
      );
      expect(res.limiterEngaged, isFalse);
      expect(res.clippingRisk, isFalse);
    });
  });

  group('multiplier clamping', () {
    test('multiplier above 3.0 clamps to 300% (+9.54 dB)', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 4.0,
        limiterEnabled: false,
        normalizationOffsetDb: 0.0,
      );
      expect(res.gainDb, closeTo(9.54, 0.01));
    });

    test('multiplier 0.0 mutes (-96 dB, zero output)', () {
      final res = VolumeDspMath.evaluateGain(
        multiplier: 0.0,
        limiterEnabled: false,
        normalizationOffsetDb: 0.0,
      );
      expect(res.gainDb, -96.0);
      expect(res.linearOutput, 0.0);
    });
  });

  group('crossfade law agrees with the Swift equal-power curve', () {
    // AudioEnginePlugin.startCrossfade ramps outgoing = cos(t*pi/2),
    // incoming = sin(t*pi/2); the Dart helper must implement the same law
    // (brief change S-3 contract, asserted here at endpoints + midpoint).
    test('endpoints and midpoint match cos/sin', () {
      final (out0, in0) = VolumeDspMath.equalPowerCrossfade(0.0);
      expect(out0, closeTo(1.0, 0.0001));
      expect(in0, closeTo(0.0, 0.0001));

      final (outHalf, inHalf) = VolumeDspMath.equalPowerCrossfade(0.5);
      expect(outHalf, closeTo(math.cos(math.pi / 4), 0.0001));
      expect(inHalf, closeTo(math.sin(math.pi / 4), 0.0001));

      final (out1, in1) = VolumeDspMath.equalPowerCrossfade(1.0);
      expect(out1, closeTo(0.0, 0.0001));
      expect(in1, closeTo(1.0, 0.0001));
    });
  });

  group('v3.0.5 — normalization never subtracts from an explicit boost', () {
    test('offset is -1.5 dB at normal volume with normalization on', () {
      expect(
        VolumeDspMath.effectiveNormalizationOffsetDb(
          multiplier: 1.0,
          normalizeVolume: true,
        ),
        -1.5,
      );
      expect(
        VolumeDspMath.effectiveNormalizationOffsetDb(
          multiplier: 0.5,
          normalizeVolume: true,
        ),
        -1.5,
      );
    });

    test('offset is 0 dB while boosting, even with normalization on', () {
      for (final m in [1.25, 1.5, 2.0, 2.5, 3.0]) {
        expect(
          VolumeDspMath.effectiveNormalizationOffsetDb(
            multiplier: m,
            normalizeVolume: true,
          ),
          0.0,
          reason: '${m}x must not be taxed by the normalization pad',
        );
      }
    });

    test('offset is 0 dB when normalization is off at any multiplier', () {
      expect(
        VolumeDspMath.effectiveNormalizationOffsetDb(
          multiplier: 1.0,
          normalizeVolume: false,
        ),
        0.0,
      );
      expect(
        VolumeDspMath.effectiveNormalizationOffsetDb(
          multiplier: 3.0,
          normalizeVolume: false,
        ),
        0.0,
      );
    });

    test('300% net gain is the full +9.54 dB with normalization on', () {
      final offset = VolumeDspMath.effectiveNormalizationOffsetDb(
        multiplier: 3.0,
        normalizeVolume: true,
      );
      final res = VolumeDspMath.evaluateGain(
        multiplier: 3.0,
        limiterEnabled: false,
        normalizationOffsetDb: offset,
      );
      expect(res.gainDb, closeTo(9.54, 0.01));
    });

    test('limiter still engages at 300% — the boost is real, not unclipped', () {
      final offset = VolumeDspMath.effectiveNormalizationOffsetDb(
        multiplier: 3.0,
        normalizeVolume: true,
      );
      final res = VolumeDspMath.evaluateGain(
        multiplier: 3.0,
        limiterEnabled: true,
        normalizationOffsetDb: offset,
        nominalSignalRms: 0.45,
      );
      expect(res.limiterEngaged, isTrue);
      expect(res.clippingRisk, isFalse);
      expect(res.linearOutput * 0.45, lessThan(0.89125));
    });
  });
}
