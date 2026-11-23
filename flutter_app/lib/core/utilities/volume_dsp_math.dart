import 'dart:math' as math;

class VolumeDspResult {
  final double linearOutput;
  final double gainDb;
  final bool limiterEngaged;
  final bool clippingRisk;

  const VolumeDspResult({
    required this.linearOutput,
    required this.gainDb,
    required this.limiterEngaged,
    required this.clippingRisk,
  });
}

/// Pure DSP math shared between Dart audio controls, telemetry UI, and tests.
/// On iOS, native AudioEnginePlugin applies the matching DynamicsProcessor /
/// soft-knee AudioUnit chain while respecting hardware limits.
class VolumeDspMath {
  static const double minMultiplier = 0.0;
  static const double maxMultiplier = 3.0; // 300%

  /// Computes soft-knee peak limited linear output for a given input level and multiplier.
  static VolumeDspResult evaluateGain({
    required double multiplier,
    required bool limiterEnabled,
    double normalizationOffsetDb = 0.0,
    double nominalSignalRms = 0.45,
  }) {
    final clampedMult = multiplier.clamp(minMultiplier, maxMultiplier);
    final normLinear = math.pow(10.0, normalizationOffsetDb / 20.0).toDouble();
    final rawGain = clampedMult * normLinear;
    final rawPeak = nominalSignalRms * rawGain;

    final gainDb = rawGain <= 0.0001
        ? -96.0
        : 20.0 * (math.log(rawGain) / math.ln10);

    if (!limiterEnabled) {
      return VolumeDspResult(
        linearOutput: rawGain,
        gainDb: gainDb,
        limiterEngaged: false,
        clippingRisk: rawPeak > 0.98,
      );
    }

    // Soft-knee limiter ceiling at -1.0 dBFS (~0.891 linear)
    const double ceiling = 0.89125;
    const double kneeStart = 0.72;
    if (rawPeak <= kneeStart) {
      return VolumeDspResult(
        linearOutput: rawGain,
        gainDb: gainDb,
        limiterEngaged: false,
        clippingRisk: false,
      );
    }

    // Smooth hyperbolic saturation above kneeStart preventing hard digital clipping
    final excess = rawPeak - kneeStart;
    final headroom = ceiling - kneeStart;
    final compressedPeak = kneeStart + (headroom * excess) / (excess + headroom);
    final effectiveGain = compressedPeak / math.max(nominalSignalRms, 0.01);

    return VolumeDspResult(
      linearOutput: effectiveGain,
      gainDb: gainDb,
      limiterEngaged: true,
      clippingRisk: false,
    );
  }

  /// Equal-power crossfade curve helper: t in [0.0, 1.0].
  static (double outgoingGain, double incomingGain) equalPowerCrossfade(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final outgoing = math.cos(clamped * math.pi * 0.5);
    final incoming = math.sin(clamped * math.pi * 0.5);
    return (outgoing, incoming);
  }
}
