import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/features/x1/local_fingerprint_engine.dart';

// X1 recall benchmark — deterministic synthetic harness (Phase 5, plan item 23).
//
// WHAT THIS MEASURES
// The local fingerprint engine's recall on synthetic "tracks" built
// in-memory as PCM (summed sine partials, 8s at 11,025 Hz mono). Each track
// is fingerprinted once into an 8-track index; clips cut from the tracks
// are then identified with the PRODUCTION matching defaults
// (`matchSampleAgainstIndex` with its default `minAlignedHits: 6` and
// `minAlignedFraction: 0.02` — no test-only loosening), and the number of
// correctly identified clips is the recall.
//
// WHAT IT DOES NOT PROVE
// Synthetic recall is NOT real-song recall. These signals are stationary
// FM chords with clean, stable partials: no vocals, no drums, no room
// reverb, no speaker colouration, no mic noise floor, no codec artefacts,
// and no other songs playing nearby. A 100% synthetic score says the
// matcher works end-to-end on clean tonal audio; it says nothing about a
// real song played in a room. The device gate — real songs on Ahmed's
// iPhone XS Max, mic permission, background noise, speaker playback — is
// still open and can only be measured on-device (see docs/x1-recall.md).
//
// HOW THE THRESHOLDS WERE SET (measured, not invented)
// The numbers below were measured BEFORE the thresholds were written, with
// a faithful Python port of this exact engine (same 1024-point FFT, Hann
// window, 5 log bands, 0.002 magnitude floor, anchor-target hashing with
// dt 1..10 / max 5 pairs, same offset-histogram match with minAlignedHits
// 6 and minAlignedFraction 0.02) and the same synth and clip offsets used
// here, over the same 8 tracks. Measured: clean 4s clips 8/8, time-shifted
// 4s clips 16/16 (offsets 2.0s and 1.37s), 4s clips + white noise at
// SNR 10 dB 8/8, at SNR 0 dB 8/8, and both rejection cases null. The port
// also reproduced the existing engine test's rejection case (unrelated
// chord vs a single-track index -> null), which cross-checks the port
// against the Dart engine. Every gate below is set BELOW the measured
// value so ordinary floating-point differences between the port's FFT and
// Dart's radix-2 FFT cannot flip the gate; the margins are wide (worst
// true match aligned 167+ hashes against a ~31-42 required floor).
// The Dart test itself was NOT run in the authoring environment (no
// Dart/Flutter toolchain there) — run `flutter test
// test/x1_recall_benchmark_test.dart` on CI or a dev machine; if it fails
// there, the regression is real and the thresholds must be re-measured,
// not lowered silently.
// Noise is added with a fixed seed (Box-Muller Gaussian, dart:math only)
// so the harness is deterministic run to run.

// Eight synthetic "tracks": distinct spectral signatures built from summed
// sine partials at distinct fundamentals (plus a 1.5x harmonic, as in the
// existing engine test's synth). Frequencies are spaced so no two tracks
// share an FFT bin for a sustained partial.
const Map<String, List<double>> _kTrackPartials = {
  'track_1': [220.0, 440.0, 1320.0, 2640.0],
  'track_2': [293.66, 587.33, 1468.0, 2936.0],
  'track_3': [349.23, 698.46, 1746.0, 3322.0],
  'track_4': [392.0, 784.0, 1960.0, 3490.0],
  'track_5': [261.63, 523.25, 1308.0, 2616.0],
  'track_6': [311.13, 622.25, 1556.0, 3111.0],
  'track_7': [369.99, 739.99, 1850.0, 3700.0],
  'track_8': [415.30, 830.61, 2076.0, 4153.0],
};

const int _kSampleRate = 11025;

// Same synth as flutter_app/test/local_fingerprint_engine_test.dart:
// FM modulation (+-40 Hz at 1.5 Hz) + 0.3x harmonic overtone creates
// multi-band spectral landmarks that vary over time.
Float64List _synthChord(
  List<double> freqsHz,
  double seconds, {
  int sr = _kSampleRate,
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
      val += math.sin(2.0 * math.pi * (f + 40 * math.sin(2 * math.pi * 1.5 * t)) * t);
      val += 0.3 * math.sin(2.0 * math.pi * (f * 1.5) * t);
    }
    final norm = freqsHz.isEmpty ? 0.0 : val / freqsHz.length;
    final noise = noiseLevel > 0 ? (rng.nextDouble() * 2 - 1) * noiseLevel : 0.0;
    out[i] = (norm * 0.65 + noise).clamp(-1.0, 1.0);
  }
  return out;
}

/// Adds deterministic white noise to [clip] at the stated signal-to-noise
/// ratio (dB), where SNR = 20*log10(rms(signal) / rms(noise)). Gaussian
/// samples come from a Box-Muller transform over a fixed-seed [math.Random]
/// so the harness is deterministic.
Float64List _addWhiteNoiseAtSnr(List<double> clip, double snrDb, {int seed = 7}) {
  var sumSq = 0.0;
  for (final s in clip) {
    sumSq += s * s;
  }
  final sigRms = math.sqrt(sumSq / clip.length);
  final noiseRms = sigRms / math.pow(10, snrDb / 20);
  final rng = math.Random(seed);
  final out = Float64List(clip.length);
  for (var i = 0; i < out.length; i++) {
    // Box-Muller: u1 in (0, 1], u2 in [0, 1).
    final u1 = 1.0 - rng.nextDouble();
    final u2 = rng.nextDouble();
    final gaussian = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
    out[i] = (clip[i] + gaussian * noiseRms).clamp(-1.0, 1.0);
  }
  return out;
}

/// A [durationSeconds] slice of [track] starting at [offsetSeconds].
List<double> _clip(List<double> track, double offsetSeconds, double durationSeconds) {
  final start = (offsetSeconds * _kSampleRate).round();
  final end = start + (durationSeconds * _kSampleRate).round();
  return track.sublist(start, end);
}

/// Builds the 8-track reference index: full 8s fingerprints per track.
Map<String, List<LandmarkHash>> _buildIndex(Map<String, Float64List> tracks) => {
      for (final e in tracks.entries) e.key: LocalFingerprintEngine.extractLandmarks(e.value),
    };

void main() {
  late Map<String, Float64List> tracks;
  late Map<String, List<LandmarkHash>> indexed;

  setUpAll(() {
    tracks = {
      for (var i = 0; i < _kTrackPartials.length; i++)
        'track_${i + 1}': _synthChord(
          _kTrackPartials['track_${i + 1}']!,
          8.0,
          seed: 100 + i,
        ),
    };
    indexed = _buildIndex(tracks);
  });

  test('recall harness sanity: every reference track yields landmarks', () {
    // Guards the harness itself: if the synth ever changed so a track
    // produced almost no landmarks, the recall numbers below would be
    // meaningless. Measured reference counts are ~3,600-4,100 per 8s track.
    for (final e in indexed.entries) {
      expect(e.value.length, greaterThan(1000), reason: '${e.key} landmarks');
    }
  });

  test('recall: clean 4s clips identify their track (8/8)', () {
    // Measured 8/8 with the Python port; gate is the full 8/8 because the
    // worst clean match aligned 272 hashes against a required floor of 42.
    var hits = 0;
    for (final e in tracks.entries) {
      final match = LocalFingerprintEngine.matchSampleAgainstIndex(
        sampleHashes: LocalFingerprintEngine.extractLandmarks(_clip(e.value, 1.0, 4.0)),
        indexedTracks: indexed,
      );
      if (match?.trackId == e.key) hits++;
    }
    expect(hits, equals(8), reason: 'clean 4s clip recall');
  });

  test('recall: time-shifted 4s clips identify their track (>= 14/16)', () {
    // Same 4s window cut ~1s later (offset 2.0s) and at a fractional,
    // non-frame-aligned offset (1.37s; the 512-sample hop is ~46ms, so
    // 1.37s lands mid-frame). Measured 16/16 with the port; the gate is
    // 14/16 to leave room for FFT floating-point differences. Worst
    // shifted match aligned 272 hashes against a required floor of 42.
    var hits = 0;
    var attempts = 0;
    for (final offset in [2.0, 1.37]) {
      for (final e in tracks.entries) {
        final match = LocalFingerprintEngine.matchSampleAgainstIndex(
          sampleHashes: LocalFingerprintEngine.extractLandmarks(_clip(e.value, offset, 4.0)),
          indexedTracks: indexed,
        );
        attempts++;
        if (match?.trackId == e.key) hits++;
      }
    }
    expect(attempts, equals(16));
    expect(hits, greaterThanOrEqualTo(14), reason: 'shifted 4s clip recall');
  });

  test('recall: 4s clips with white noise at SNR 10 dB (>= 7/8)', () {
    // Room-noise proxy: white noise added at 10 dB SNR to the 4s clip.
    // Measured 8/8 with the port (worst match 190 aligned hashes vs a
    // required floor of 42); the gate is 7/8. Headroom measured but NOT
    // gated: the same clips at SNR 0 dB also scored 8/8.
    var hits = 0;
    for (final e in tracks.entries) {
      final noisy = _addWhiteNoiseAtSnr(_clip(e.value, 1.0, 4.0), 10);
      final match = LocalFingerprintEngine.matchSampleAgainstIndex(
        sampleHashes: LocalFingerprintEngine.extractLandmarks(noisy),
        indexedTracks: indexed,
      );
      if (match?.trackId == e.key) hits++;
    }
    expect(hits, greaterThanOrEqualTo(7), reason: 'noisy (SNR 10 dB) recall');
  });

  test('rejection: unrelated signal and pure noise return no match', () {
    // Unrelated chord: partials chosen to sit clear of every track's
    // partials (fundamentals 220-415 Hz and their 1.5x harmonics, each
    // sweeping +-40/60 Hz under the FM). A first candidate,
    // [180, 310, 590, 990], FAILED this check in the port: its 310 Hz
    // partial shares an FFT bin with track_6's 311.13 Hz fundamental for
    // the whole clip and aligned 30 hashes against a 25 floor — a real
    // near-coincidence weakness of the 2% relative floor against an
    // 8-track index, documented in docs/x1-recall.md. This chord clears it.
    final unrelated = _synthChord([150, 275, 520, 1100], 3.0);
    final unrelatedMatch = LocalFingerprintEngine.matchSampleAgainstIndex(
      sampleHashes: LocalFingerprintEngine.extractLandmarks(unrelated),
      indexedTracks: indexed,
    );
    expect(unrelatedMatch, isNull, reason: 'unrelated chord must not match');

    // Pure white noise must not match either.
    final noise = _synthChord(const [], 3.0, noiseLevel: 0.25, seed: 77);
    final noiseMatch = LocalFingerprintEngine.matchSampleAgainstIndex(
      sampleHashes: LocalFingerprintEngine.extractLandmarks(noise),
      indexedTracks: indexed,
    );
    expect(noiseMatch, isNull, reason: 'white noise must not match');
  });
}
