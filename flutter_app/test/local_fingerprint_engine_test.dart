import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/features/x1/local_fingerprint_engine.dart';

Float64List _synthChord(
  List<double> freqsHz,
  double seconds, {
  int sr = 11025,
  double noiseLevel = 0.0,
  int seed = 42,
}) {
  final n = (seconds * sr).round();
  final out = Float64List(n);
  final rng = math.Random(seed);
  for (var i = 0; i < n; i++) {
    var val = 0.0;
    final t = i / sr;
    for (final f in freqsHz) {
      // FM modulation + harmonic overtone creates multi-band spectral landmarks over time
      val += math.sin(2.0 * math.pi * (f + 40 * math.sin(2 * math.pi * 1.5 * t)) * t);
      val += 0.3 * math.sin(2.0 * math.pi * (f * 1.5) * t);
    }
    final norm = freqsHz.isEmpty ? 0.0 : val / freqsHz.length;
    final noise = noiseLevel > 0 ? (rng.nextDouble() * 2 - 1) * noiseLevel : 0.0;
    out[i] = (norm * 0.65 + noise).clamp(-1.0, 1.0);
  }
  return out;
}

void main() {
  test('LocalFingerprintEngine matches time-shifted audio sub-clip accurately', () {
    final trackA = _synthChord([440, 880, 1760, 3100], 6.0);
    final trackB = _synthChord([260, 520, 1040, 2080], 6.0);

    final refA = LocalFingerprintEngine.extractLandmarks(trackA);
    final refB = LocalFingerprintEngine.extractLandmarks(trackB);

    expect(refA.length, greaterThan(10));
    expect(refB.length, greaterThan(10));

    // Take a 3-second snippet shifted 1.5 seconds into Track A
    final startIdx = (1.5 * 11025).round();
    final endIdx = (4.5 * 11025).round();
    final sampleFromA = trackA.sublist(startIdx, endIdx);
    final sampleLandmarks = LocalFingerprintEngine.extractLandmarks(sampleFromA);

    final match = LocalFingerprintEngine.matchSampleAgainstIndex(
      sampleHashes: sampleLandmarks,
      indexedTracks: {
        'track_a': refA,
        'track_b': refB,
      },
      minAlignedHits: 4,
    );

    expect(match, isNotNull);
    expect(match!.trackId, 'track_a');
    expect(match.confidence, greaterThanOrEqualTo(0.45));
  });

  test('LocalFingerprintEngine multi-track noisy-clip identification benchmark', () {
    final catalog = <String, Float64List>{
      'track_1': _synthChord([220, 440, 1320, 2640], 8.0, seed: 1),
      'track_2': _synthChord([293.6, 587.3, 1468, 2936], 8.0, seed: 2),
      'track_3': _synthChord([349.2, 698.5, 1746, 3322], 8.0, seed: 3),
      'track_4': _synthChord([392.0, 784.0, 1960, 3490], 8.0, seed: 4),
    };

    final indexed = {
      for (final e in catalog.entries) e.key: LocalFingerprintEngine.extractLandmarks(e.value),
    };

    var hits = 0;
    for (final e in catalog.entries) {
      final noisyClip = _synthChord(
        e.key == 'track_1'
            ? [220, 440, 1320, 2640]
            : e.key == 'track_2'
                ? [293.6, 587.3, 1468, 2936]
                : e.key == 'track_3'
                    ? [349.2, 698.5, 1746, 3322]
                    : [392.0, 784.0, 1960, 3490],
        3.5,
        noiseLevel: 0.04,
        seed: 99,
      );
      final match = LocalFingerprintEngine.matchSampleAgainstIndex(
        sampleHashes: LocalFingerprintEngine.extractLandmarks(noisyClip),
        indexedTracks: indexed,
        minAlignedHits: 6,
      );
      if (match?.trackId == e.key) {
        hits++;
      }
    }

    expect(hits, equals(catalog.length));

    // Unrelated white noise signal should be rejected
    final unknownNoise = _synthChord(const [], 3.0, noiseLevel: 0.25, seed: 77);
    final unknownMatch = LocalFingerprintEngine.matchSampleAgainstIndex(
      sampleHashes: LocalFingerprintEngine.extractLandmarks(unknownNoise),
      indexedTracks: indexed,
      minAlignedHits: 6,
    );
    expect(unknownMatch, isNull);
  });

  test('LocalFingerprintEngine rejects unrelated frequency signal', () {
    final trackA = _synthChord([440, 880, 1760, 3100], 4.0);
    final noiseSignal = _synthChord([180, 310, 590, 990], 3.0);

    final match = LocalFingerprintEngine.matchSampleAgainstIndex(
      sampleHashes: LocalFingerprintEngine.extractLandmarks(noiseSignal),
      indexedTracks: {
        'track_a': LocalFingerprintEngine.extractLandmarks(trackA),
      },
      minAlignedHits: 6,
    );

    expect(match, isNull);
  });

  test('AcousticTelemetry detects pure 440Hz tone frequency and positive RMS', () {
    const sr = 11025;
    final sine440 = Float64List(sr * 2);
    for (var i = 0; i < sine440.length; i++) {
      sine440[i] = 0.5 * math.sin(2.0 * math.pi * 440.0 * (i / sr));
    }
    final telemetry = LocalFingerprintEngine.analyzeTelemetry(sine440, sampleRate: sr);
    expect(telemetry.rmsEnergy, closeTo(0.353, 0.05));
    expect(telemetry.dominantFrequencyHz, closeTo(440.0, 25.0));
  });
}
