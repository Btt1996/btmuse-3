import 'dart:math' as math;
import 'dart:typed_data';

class LandmarkHash {
  final int hash;
  final int timeFrame;

  const LandmarkHash({required this.hash, required this.timeFrame});
}

class AcousticTelemetry {
  final double durationSeconds;
  final double rmsEnergy;
  final double dominantFrequencyHz;
  final double estimatedBpm;

  const AcousticTelemetry({
    required this.durationSeconds,
    required this.rmsEnergy,
    required this.dominantFrequencyHz,
    required this.estimatedBpm,
  });
}

class FingerprintMatchResult {
  final String trackId;
  final int alignedHits;
  final double confidence;

  const FingerprintMatchResult({
    required this.trackId,
    required this.alignedHits,
    required this.confidence,
  });
}

/// Self-contained MIT-clean Spectral Constellation Landmark Fingerprinting Engine.
/// Computes Radix-2 FFT frames over 11,025 Hz mono PCM, extracts logarithmic frequency-band
/// local spectral maxima, and forms deterministic anchor-target peak pair hashes for
/// time-offset histogram matching—zero external C libraries or paid API keys required.
class LocalFingerprintEngine {
  static const int targetSampleRate = 11025;
  static const int fftSize = 1024;
  static const int hopSize = 512;

  /// Minimum fraction of the sample's hashes that must align at one time
  /// offset for a match (on top of [matchSampleAgainstIndex]'s absolute
  /// `minAlignedHits`). A handful of aligned hashes occurs by chance —
  /// pure white noise reaches 6–11 aligned hits on a ~1500-hash sample —
  /// while true matches align 23%+ of their hashes (304/1311 for a
  /// time-shifted clip, 67–77% for noisy catalog clips). The absolute
  /// floor still governs short samples, where the fraction is smaller
  /// than `minAlignedHits`.
  static const double minAlignedFraction = 0.02;

  /// Runner-up margin (Phase 6): the best-matching track must beat the
  /// second-best candidate track's best offset count by BOTH an absolute
  /// gap of at least the relative floor (see [matchSampleAgainstIndex])
  /// AND this ratio. A near-coincident sustained partial can clear the
  /// 2% floor on its own while a second track aligns nearly as well —
  /// the documented Phase 5 case, chord [180, 310, 590, 990], aligned 30
  /// hashes on track_6 against a 25-hash floor while track_2 aligned 15.
  /// A real match out-aligns every other candidate by a wide margin, so
  /// a close second-best means "ambiguous — no match" rather than a
  /// possibly-wrong match. Measured with a faithful Python port of this
  /// engine (see docs/x1-recall.md): worst true 4 s clip (SNR 0 dB)
  /// scores best 71 vs runner-up 6 (gap 65, ratio 11.8), so 1.5 leaves
  /// wide headroom on every gated recall case; the near-coincident chord
  /// scores gap 15 < floor 25 and ratio 2.0 and is now rejected. With a
  /// single candidate track there is no runner-up and the margin is
  /// vacuous. Tradeoff: short, very noisy clips sit close to the margin
  /// (2 s clips at SNR 0 dB measured worst gap 23 vs floor 21, not
  /// gated) and may flip to no-match — a conservative failure, never a
  /// wrong match. Synthetic recall is not real-song recall.
  static const double minRunnerUpMarginRatio = 1.5;

  static const List<(int lowBin, int highBin)> _bands = [
    (12, 32), // ~130–345 Hz
    (32, 64), // ~345–690 Hz
    (64, 128), // ~690–1380 Hz
    (128, 256), // ~1380–2760 Hz
    (256, 420), // ~2760–4520 Hz
  ];

  static AcousticTelemetry analyzeTelemetry(
    List<double> samples, {
    int sampleRate = targetSampleRate,
  }) {
    if (samples.isEmpty || sampleRate <= 0) {
      return const AcousticTelemetry(
        durationSeconds: 0,
        rmsEnergy: 0,
        dominantFrequencyHz: 0,
        estimatedBpm: 0,
      );
    }

    var sumSq = 0.0;
    for (final s in samples) {
      sumSq += s * s;
    }
    final rms = math.sqrt(sumSq / samples.length);
    final duration = samples.length / sampleRate;

    // Average FFT magnitude across up to 8 evenly spaced frames to estimate dominant pitch
    var peakBinSum = 0.0;
    var frameCount = 0;
    if (samples.length >= fftSize) {
      final step = math.max(hopSize, (samples.length - fftSize) ~/ 8);
      for (var start = 0; start + fftSize <= samples.length && frameCount < 8; start += step) {
        final mags = _computeFrameMagnitudes(samples, start);
        var bestBin = 1;
        var bestMag = -1.0;
        for (var b = 4; b < mags.length ~/ 2; b++) {
          if (mags[b] > bestMag) {
            bestMag = mags[b];
            bestBin = b;
          }
        }
        peakBinSum += bestBin;
        frameCount++;
      }
    }

    final avgBin = frameCount > 0 ? peakBinSum / frameCount : 0.0;
    final dominantHz = avgBin * (sampleRate / fftSize);

    // Onset-envelope autocorrelation for rough BPM estimation (65–171 BPM:
    // lags 14–37 at 40 fps). Returns 0 when no periodic onset structure is
    // detected — see [_estimateTempoBpm]. Callers must treat 0 as "no
    // tempo measured" and leave bpm unset, never as a real tempo.
    final bpm = _estimateTempoBpm(samples, sampleRate);

    return AcousticTelemetry(
      durationSeconds: duration,
      rmsEnergy: rms.clamp(0.0, 1.0),
      dominantFrequencyHz: dominantHz,
      estimatedBpm: bpm,
    );
  }

  static List<LandmarkHash> extractLandmarks(List<double> samples) {
    if (samples.length < fftSize) return const [];

    // Per-frame top band peaks: list of (frameIndex, binIndex)
    final peaksByFrame = <List<int>>[];

    for (var start = 0; start + fftSize <= samples.length; start += hopSize) {
      final mags = _computeFrameMagnitudes(samples, start);
      final framePeaks = <int>[];

      for (final (low, high) in _bands) {
        var bestBin = -1;
        var bestMag = 0.002; // Noise floor threshold
        final clampedHigh = math.min(high, mags.length - 1);
        for (var b = low; b <= clampedHigh; b++) {
          if (mags[b] > bestMag) {
            bestMag = mags[b];
            bestBin = b;
          }
        }
        if (bestBin != -1) {
          framePeaks.add(bestBin);
        }
      }
      peaksByFrame.add(framePeaks);
    }

    final hashes = <LandmarkHash>[];
    const int minDeltaFrames = 1;
    const int maxDeltaFrames = 10;

    for (var t1 = 0; t1 < peaksByFrame.length; t1++) {
      final anchors = peaksByFrame[t1];
      for (final f1 in anchors) {
        var paired = 0;
        for (var dt = minDeltaFrames;
            dt <= maxDeltaFrames && t1 + dt < peaksByFrame.length && paired < 5;
            dt++) {
          for (final f2 in peaksByFrame[t1 + dt]) {
            // Pack (f1: 9 bits, f2: 9 bits, dt: 6 bits) into deterministic integer hash
            final hash = ((f1 & 0x1FF) << 15) | ((f2 & 0x1FF) << 6) | (dt & 0x3F);
            hashes.add(LandmarkHash(hash: hash, timeFrame: t1));
            paired++;
            if (paired >= 5) break;
          }
        }
      }
    }

    return hashes;
  }

  static FingerprintMatchResult? matchSampleAgainstIndex({
    required List<LandmarkHash> sampleHashes,
    required Map<String, List<LandmarkHash>> indexedTracks,
    int minAlignedHits = 6,
  }) {
    if (sampleHashes.isEmpty || indexedTracks.isEmpty) return null;

    // Build lookup map hash -> list of sample time frames
    final sampleByHash = <int, List<int>>{};
    for (final l in sampleHashes) {
      sampleByHash.putIfAbsent(l.hash, () => []).add(l.timeFrame);
    }

    // Per-track best aligned-offset count. The runner-up margin needs the
    // second-best track, not just the global best.
    final bestPerTrack = <String, int>{};
    for (final entry in indexedTracks.entries) {
      final offsetHistogram = <int, int>{};
      var trackBest = 0;
      for (final refLandmark in entry.value) {
        final sampleTimes = sampleByHash[refLandmark.hash];
        if (sampleTimes == null) continue;
        for (final tSample in sampleTimes) {
          final delta = refLandmark.timeFrame - tSample;
          final count = (offsetHistogram[delta] ?? 0) + 1;
          offsetHistogram[delta] = count;
          if (count > trackBest) {
            trackBest = count;
          }
        }
      }
      bestPerTrack[entry.key] = trackBest;
    }
    final ranked = bestPerTrack.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final bestTrackId = ranked.first.key;
    final bestAlignedCount = ranked.first.value;
    final runnerUpAlignedCount = ranked.length > 1 ? ranked[1].value : 0;

    // A handful of aligned hashes can occur by chance (pure white noise
    // reaches 6–11 aligned hits on a ~1500-hash sample), so the absolute
    // `minAlignedHits` floor alone admits false positives. Require the
    // alignment to also clear the relative floor in [minAlignedFraction].
    final relativeFloor = (sampleHashes.length * minAlignedFraction).ceil();
    final requiredHits = math.max(minAlignedHits, relativeFloor);
    if (bestAlignedCount < requiredHits) {
      return null;
    }

    // Runner-up margin: a near-coincident partial can clear the floors
    // above while a second track aligns nearly as well (Phase 5 case:
    // best 30 vs runner-up 15). Demand BOTH an absolute gap of at least
    // the relative floor AND a ratio of at least [minRunnerUpMarginRatio];
    // a close second-best is ambiguous, so return no match rather than a
    // possibly-wrong one. A single candidate track has no runner-up and
    // skips this check.
    if (runnerUpAlignedCount > 0) {
      final gap = bestAlignedCount - runnerUpAlignedCount;
      if (gap < relativeFloor ||
          bestAlignedCount < minRunnerUpMarginRatio * runnerUpAlignedCount) {
        return null;
      }
    }

    final confidence = (bestAlignedCount / math.max(12, sampleHashes.length * 0.18)).clamp(0.45, 0.99);
    return FingerprintMatchResult(
      trackId: bestTrackId,
      alignedHits: bestAlignedCount,
      confidence: confidence,
    );
  }

  /// Sample rate (Hz) declared in a WAV (RIFF) header, or null when the
  /// bytes are not a parseable WAV header. [decodeWavBytesToMonoFloat]
  /// assumes the samples are at [targetSampleRate]; callers must check
  /// this first — a 44,100 Hz WAV decoded as 11,025 Hz would get a 4x-wrong
  /// tempo, wrong landmark time scale, and fingerprints that can never
  /// match mic audio. Byte 24, little-endian uint32, per the WAV spec.
  static int? wavSampleRateHz(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return null;
    return ByteData.sublistView(bytes).getUint32(24, Endian.little);
  }

  /// Parses uncompressed PCM WAV bytes directly in pure Dart (useful for clips & tests).
  static List<double> decodeWavBytesToMonoFloat(Uint8List bytes) {
    if (bytes.length < 44) return const [];
    final header = String.fromCharCodes(bytes.sublist(0, 4));
    if (header != 'RIFF') return const [];

    final bd = ByteData.sublistView(bytes);
    final channels = bd.getUint16(22, Endian.little).clamp(1, 8);
    final bitsPerSample = bd.getUint16(34, Endian.little);
    if (bitsPerSample != 16) return const [];

    var offset = 12;
    while (offset + 8 < bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (chunkId == 'data') {
        final frameBytes = channels * 2;
        final totalFrames = math.min(chunkSize, bytes.length - offset) ~/ frameBytes;
        final out = Float64List(totalFrames);
        for (var i = 0; i < totalFrames; i++) {
          var mono = 0.0;
          for (var c = 0; c < channels; c++) {
            mono += bd.getInt16(offset + i * frameBytes + c * 2, Endian.little) / 32768.0;
          }
          out[i] = mono / channels;
        }
        return out;
      }
      offset += chunkSize;
    }
    return const [];
  }

  static List<double> _computeFrameMagnitudes(List<double> samples, int offset) {
    final real = Float64List(fftSize);
    final imag = Float64List(fftSize);

    // Apply Hann window
    for (var i = 0; i < fftSize; i++) {
      final win = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (fftSize - 1)));
      real[i] = samples[offset + i] * win;
    }

    _radix2Fft(real, imag);

    final half = fftSize ~/ 2;
    final mags = Float64List(half);
    for (var i = 0; i < half; i++) {
      mags[i] = math.sqrt(real[i] * real[i] + imag[i] * imag[i]) / fftSize;
    }
    return mags;
  }

  static void _radix2Fft(Float64List real, Float64List imag) {
    final n = real.length;
    var j = 0;
    for (var i = 0; i < n; i++) {
      if (i < j) {
        final tr = real[i];
        final ti = imag[i];
        real[i] = real[j];
        imag[i] = imag[j];
        real[j] = tr;
        imag[j] = ti;
      }
      var m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
      j += m;
    }

    for (var size = 2; size <= n; size <<= 1) {
      final halfSize = size >> 1;
      final tableStep = -2.0 * math.pi / size;
      for (var i = 0; i < n; i += size) {
        for (var k = 0; k < halfSize; k++) {
          final angle = k * tableStep;
          final wr = math.cos(angle);
          final wi = math.sin(angle);
          final even = i + k;
          final odd = even + halfSize;
          final tr = wr * real[odd] - wi * imag[odd];
          final ti = wr * imag[odd] + wi * real[odd];
          real[odd] = real[even] - tr;
          imag[odd] = imag[even] - ti;
          real[even] += tr;
          imag[even] += ti;
        }
      }
    }
  }

  /// Minimum envelope modulation depth (std / mean of the 40 fps
  /// mean-absolute envelope) for a tempo estimate to be trusted. A steady
  /// tone or drone has an almost flat envelope, so there is no onset
  /// structure to measure; a real onset train modulates strongly.
  /// Measured with a faithful Python port of this estimator
  /// (see docs/x1-recall.md): steady 440 Hz sine CV 0.001, FM chord with
  /// no beats CV 0.036, white noise CV 0.034 — all rejected — while
  /// periodic burst trains measure CV 0.68+ even with added noise, and
  /// 1.34+ clean. The 0.25 gate sits between those clusters.
  static const double _minTempoEnvelopeCv = 0.25;

  /// Minimum normalised autocorrelation peak (best lag's correlation
  /// divided by the lag-0 energy of the mean-removed envelope) for a
  /// tempo estimate to be trusted. Below-range tempi peak weakly at the
  /// range edge (a 60 BPM burst train peaks at r = 0.254 on lag 37) while
  /// in-range bursts peak at r >= 0.38 (worst measured: an accented
  /// 120 BPM train with alternating strong/weak beats). The 0.30 gate
  /// rejects the edge case and keeps every in-range burst measured.
  static const double _minTempoAutocorrPeak = 0.30;

  /// Onset-envelope autocorrelation tempo estimation, 65–171 BPM
  /// (lags 14–37 at 40 fps). Returns 0 when no periodic onset structure
  /// is detected — callers must treat 0 as "no tempo measured" and leave
  /// bpm unset, never as a real tempo.
  ///
  /// Two guards keep steady signals from producing a bogus "measured"
  /// tempo. The pre-Phase-6 version ran a raw (non-mean-removed,
  /// un-normalised) autocorrelation and returned the argmax lag
  /// unconditionally, so a steady 440 Hz sine, white noise, and even
  /// silence all "measured" 171.4 BPM (lag 14, the first argmax on a flat
  /// correlation) and that value was stored with is_analysis_estimated=0.
  /// This version mean-removes the envelope (removing the DC bias) and
  /// normalises each lag by the overlap count (removing the small-lag
  /// term-count bias), then requires real modulation depth
  /// ([_minTempoEnvelopeCv]) and a real correlation peak
  /// ([_minTempoAutocorrPeak]).
  ///
  /// Known limits, measured on synthetic bursts (see docs/x1-recall.md):
  /// 40 fps quantisation gives +/-~2 BPM error (90 -> 88.9, 128 ->
  /// 126.3); tempi below 65 BPM have no in-range lag and read as no
  /// tempo; tempi above 171 BPM fold to half-time (180 -> 88.9) because
  /// there is no octave disambiguation — the React estimator in
  /// src/services/audioAnalysis.ts does onset-flux + octave folding and
  /// is the model for a future fix. Real-song accuracy is unmeasured:
  /// the device gate (Ahmed's iPhone XS Max) is still open.
  static double _estimateTempoBpm(List<double> samples, int sampleRate) {
    if (samples.length < sampleRate * 2) return 0;
    final windowSize = math.max(1, sampleRate ~/ 40); // 25ms energy frames -> 40 fps
    final envLen = samples.length ~/ windowSize;
    if (envLen < 40) return 0;

    final env = Float64List(envLen);
    var envSum = 0.0;
    for (var i = 0; i < envLen; i++) {
      var e = 0.0;
      final base = i * windowSize;
      for (var k = 0; k < windowSize; k++) {
        e += samples[base + k].abs();
      }
      env[i] = e / windowSize;
      envSum += env[i];
    }
    final envMean = envSum / envLen;

    var envVarSum = 0.0;
    for (var i = 0; i < envLen; i++) {
      final d = env[i] - envMean;
      envVarSum += d * d;
    }
    final envStd = math.sqrt(envVarSum / envLen);
    // No modulation depth, no onsets: steady tone / drone / silence.
    if (envMean <= 0 || envStd / envMean < _minTempoEnvelopeCv) return 0;
    // Degenerate flat envelope guard (variance zero despite the CV check).
    if (envVarSum <= 0) return 0;

    // Mean-removed autocorrelation, normalised by the lag-0 energy so
    // lags are comparable: r[lag] = sum(env[i]*env[i+lag]) / sum(env^2).
    var bestLag = 20;
    var bestR = -1.0;
    for (var lag = 14; lag <= 37 && lag < envLen ~/ 2; lag++) {
      var corr = 0.0;
      for (var i = 0; i < envLen - lag; i++) {
        corr += (env[i] - envMean) * (env[i + lag] - envMean);
      }
      final r = corr / envVarSum;
      if (r > bestR) {
        bestR = r;
        bestLag = lag;
      }
    }
    // Weak peak: no periodic onset structure (below-range tempo peaking
    // at the range edge, noise, or an FM chord's slow beating).
    if (bestR < _minTempoAutocorrPeak) return 0;
    return (40.0 * 60.0) / bestLag;
  }
}
