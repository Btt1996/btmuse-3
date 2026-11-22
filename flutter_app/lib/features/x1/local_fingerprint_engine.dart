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

    // Simple onset envelope autocorrelation for rough BPM estimation (60–180 BPM)
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

    String? bestTrackId;
    var bestAlignedCount = 0;

    for (final entry in indexedTracks.entries) {
      final offsetHistogram = <int, int>{};
      for (final refLandmark in entry.value) {
        final sampleTimes = sampleByHash[refLandmark.hash];
        if (sampleTimes == null) continue;
        for (final tSample in sampleTimes) {
          final delta = refLandmark.timeFrame - tSample;
          final count = (offsetHistogram[delta] ?? 0) + 1;
          offsetHistogram[delta] = count;
          if (count > bestAlignedCount) {
            bestAlignedCount = count;
            bestTrackId = entry.key;
          }
        }
      }
    }

    if (bestTrackId == null || bestAlignedCount < minAlignedHits) {
      return null;
    }

    final confidence = (bestAlignedCount / math.max(12, sampleHashes.length * 0.18)).clamp(0.45, 0.99);
    return FingerprintMatchResult(
      trackId: bestTrackId,
      alignedHits: bestAlignedCount,
      confidence: confidence,
    );
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

  static double _estimateTempoBpm(List<double> samples, int sampleRate) {
    if (samples.length < sampleRate * 2) return 0;
    final windowSize = math.max(1, sampleRate ~/ 40); // 25ms energy frames -> 40 fps
    final envLen = samples.length ~/ windowSize;
    if (envLen < 40) return 0;

    final env = Float64List(envLen);
    for (var i = 0; i < envLen; i++) {
      var e = 0.0;
      final base = i * windowSize;
      for (var k = 0; k < windowSize; k++) {
        e += samples[base + k].abs();
      }
      env[i] = e / windowSize;
    }

    // Autocorrelate over lags corresponding to 65–175 BPM at 40 Hz (~14 to 37 frames)
    var bestLag = 20;
    var bestCorr = -1.0;
    for (var lag = 14; lag <= 37 && lag < envLen ~/ 2; lag++) {
      var corr = 0.0;
      for (var i = 0; i < envLen - lag; i++) {
        corr += env[i] * env[i + lag];
      }
      if (corr > bestCorr) {
        bestCorr = corr;
        bestLag = lag;
      }
    }
    return (40.0 * 60.0) / bestLag;
  }
}
