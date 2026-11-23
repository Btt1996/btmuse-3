import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/features/x1/local_fingerprint_engine.dart';

// Phase 6 — Smart Remix measured-analysis verification.
//
// WHAT THIS TESTS
// `LocalFingerprintEngine.analyzeTelemetry` on synthetic PCM built
// in-memory at 11,025 Hz: periodic tone bursts at a known BPM, steady
// signals with no onsets, and sine waves at known amplitudes. The BPM
// expectations and the estimator's gates were measured FIRST with a
// faithful Python port of the Dart estimator (same 25 ms mean-absolute
// envelope at 40 fps, same lags 14–37, same mean-removal /
// overlap-normalisation / CV and peak gates) — see docs/x1-recall.md.
// The Dart test itself was NOT run in the authoring environment (no
// Dart/Flutter toolchain there); run `flutter test
// test/smart_remix_telemetry_test.dart` on CI or a dev machine.
//
// WHAT IT DOES NOT PROVE
// Synthetic bursts are the easy case: clean, perfectly periodic onsets.
// Real songs have syncopation, fills, breakdowns, and tempo drift, and
// real-song BPM accuracy is unmeasured until the device gate (Ahmed's
// iPhone XS Max). A passing test says the estimator is honest on clean
// periodic audio and refuses to invent a tempo where there is none —
// not that it reads real songs correctly.

const int _kSampleRate = 11025;

/// Periodic tone bursts: one Hann-bumped 440 Hz burst per beat.
/// [bpm] is the ground truth the estimator must recover.
Float64List _burstTrain(double bpm, double seconds, {double amplitude = 0.7}) {
  final n = (seconds * _kSampleRate).round();
  final out = Float64List(n);
  final beatPeriod = 60.0 / bpm;
  const burstSeconds = 0.12;
  for (var i = 0; i < n; i++) {
    final t = i / _kSampleRate;
    final intoBeat = t % beatPeriod;
    if (intoBeat < burstSeconds) {
      // Hann bump over the burst so onsets are smooth, not clicks.
      final bump =
          0.5 * (1.0 - math.cos(2.0 * math.pi * intoBeat / burstSeconds));
      out[i] = amplitude * bump * math.sin(2.0 * math.pi * 440.0 * t);
    }
  }
  return out;
}

/// Same synth as the X1 recall harness: FM modulation (+-40 Hz at 1.5 Hz)
/// + 0.3x harmonic overtone. Tonal, but with no beats — the estimator
/// must report no tempo for it.
Float64List _synthChord(List<double> freqsHz, double seconds) {
  final n = (seconds * _kSampleRate).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    var val = 0.0;
    final t = i / _kSampleRate;
    for (final f in freqsHz) {
      val += math.sin(2.0 * math.pi * (f + 40 * math.sin(2 * math.pi * 1.5 * t)) * t);
      val += 0.3 * math.sin(2.0 * math.pi * (f * 1.5) * t);
    }
    final norm = freqsHz.isEmpty ? 0.0 : val / freqsHz.length;
    out[i] = (norm * 0.65).clamp(-1.0, 1.0);
  }
  return out;
}

Float64List _sine(double freqHz, double seconds, double amplitude) {
  final n = (seconds * _kSampleRate).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amplitude * math.sin(2.0 * math.pi * freqHz * (i / _kSampleRate));
  }
  return out;
}

/// Minimal 16-bit mono WAV: 44-byte header + little-endian samples.
Uint8List _buildWav16Mono({required int sampleRate, required List<double> samples}) {
  final bytes = Uint8List(44 + samples.length * 2);
  final bd = ByteData.sublistView(bytes);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes[offset + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  bd.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, 1, Endian.little); // mono
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  bd.setUint16(32, 2, Endian.little); // block align
  bd.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bd.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes;
}

void main() {
  group('BPM estimation on periodic bursts', () {
    test('120 BPM burst train estimates within tolerance', () {
      // Port-measured: exactly 120.0. Tolerance 6 covers the 40 fps
      // quantisation (+/-~2 BPM) plus Dart/NumPy FFT-free arithmetic
      // differences in the envelope.
      final telemetry = LocalFingerprintEngine.analyzeTelemetry(
        _burstTrain(120, 8.0),
        sampleRate: _kSampleRate,
      );
      expect(telemetry.estimatedBpm, closeTo(120.0, 6.0));
    });

    test('90 BPM burst train estimates within tolerance', () {
      // Port-measured: 88.9 (quantisation: lag 27 -> 2400/27).
      final telemetry = LocalFingerprintEngine.analyzeTelemetry(
        _burstTrain(90, 8.0),
        sampleRate: _kSampleRate,
      );
      expect(telemetry.estimatedBpm, closeTo(90.0, 6.0));
    });

    test('100 BPM burst train estimates within tolerance', () {
      // Port-measured: exactly 100.0.
      final telemetry = LocalFingerprintEngine.analyzeTelemetry(
        _burstTrain(100, 8.0),
        sampleRate: _kSampleRate,
      );
      expect(telemetry.estimatedBpm, closeTo(100.0, 6.0));
    });
  });

  group('BPM estimation refuses signals with no onsets', () {
    test('steady 440 Hz sine reports no tempo (0), not a bogus fast BPM', () {
      // Pre-Phase-6 the raw autocorrelation returned 171.4 BPM for this
      // signal (lag 14, first argmax on a flat correlation) and that
      // value was stored as measured. Port-measured now: 0, via the
      // envelope-modulation gate (sine CV 0.001 vs gate 0.25).
      final telemetry = LocalFingerprintEngine.analyzeTelemetry(
        _sine(440.0, 8.0, 0.5),
        sampleRate: _kSampleRate,
      );
      expect(telemetry.estimatedBpm, equals(0.0));
    });

    test('silence reports no tempo and zero RMS', () {
      final telemetry = LocalFingerprintEngine.analyzeTelemetry(
        Float64List(8 * _kSampleRate),
        sampleRate: _kSampleRate,
      );
      expect(telemetry.estimatedBpm, equals(0.0));
      expect(telemetry.rmsEnergy, equals(0.0));
    });

    test('steady white noise reports no tempo', () {
      // Port-measured: envelope CV 0.034 and autocorr peak 0.127, both
      // far below the gates (0.25 / 0.30).
      final rng = math.Random(1);
      final noise = Float64List(8 * _kSampleRate);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = rng.nextDouble() - 0.5;
      }
      final telemetry = LocalFingerprintEngine.analyzeTelemetry(
        noise,
        sampleRate: _kSampleRate,
      );
      expect(telemetry.estimatedBpm, equals(0.0));
    });

    test('FM chord with no beats reports no tempo', () {
      // Tonal and loud, but the spectrum never pulses: port-measured
      // envelope CV 0.036, below the 0.25 gate.
      final telemetry = LocalFingerprintEngine.analyzeTelemetry(
        _synthChord([220, 440, 1320, 2640], 8.0),
        sampleRate: _kSampleRate,
      );
      expect(telemetry.estimatedBpm, equals(0.0));
    });

    test('clip shorter than 2 s reports no tempo', () {
      final telemetry = LocalFingerprintEngine.analyzeTelemetry(
        _burstTrain(120, 1.5),
        sampleRate: _kSampleRate,
      );
      expect(telemetry.estimatedBpm, equals(0.0));
    });
  });

  group('RMS energy scaling', () {
    test('RMS scales linearly with amplitude', () {
      // A sine of amplitude A has RMS A/sqrt(2): 0.25 -> ~0.177,
      // 0.5 -> ~0.354. The library maps this to energy_score as
      // rms * 2.2 clamped to [0.1, 1.0] (measured in the Python port:
      // amp 0.05 -> 0.10 floor, 0.25 -> 0.39, 0.5 -> 0.78, 0.7 -> 1.0
      // cap) — monotonic, so ordering is preserved, but the absolute
      // score is not a calibrated loudness measure.
      final quiet = LocalFingerprintEngine.analyzeTelemetry(
        _sine(440.0, 2.0, 0.25),
        sampleRate: _kSampleRate,
      );
      final loud = LocalFingerprintEngine.analyzeTelemetry(
        _sine(440.0, 2.0, 0.5),
        sampleRate: _kSampleRate,
      );
      expect(quiet.rmsEnergy, closeTo(0.177, 0.02));
      expect(loud.rmsEnergy, closeTo(0.354, 0.02));
      expect(loud.rmsEnergy, greaterThan(quiet.rmsEnergy * 1.9));
      expect(quiet.durationSeconds, closeTo(2.0, 0.01));
      expect(quiet.dominantFrequencyHz, closeTo(440.0, 25.0));
    });
  });

  group('WAV sample-rate guard', () {
    test('wavSampleRateHz reads the header rate', () {
      final wav11025 = _buildWav16Mono(
        sampleRate: 11025,
        samples: [0.0, 0.5, -0.5, 0.25],
      );
      final wav44100 = _buildWav16Mono(
        sampleRate: 44100,
        samples: [0.0, 0.5, -0.5, 0.25],
      );
      expect(LocalFingerprintEngine.wavSampleRateHz(wav11025), equals(11025));
      expect(LocalFingerprintEngine.wavSampleRateHz(wav44100), equals(44100));
      expect(LocalFingerprintEngine.wavSampleRateHz(Uint8List(10)), isNull);
      expect(
        LocalFingerprintEngine.wavSampleRateHz(
          Uint8List.fromList(List.filled(44, 0)),
        ),
        isNull,
      );
    });

    test('decodeWavBytesToMonoFloat decodes an 11,025 Hz WAV', () {
      final samples = [0.0, 0.5, -0.5, 0.25];
      final wav = _buildWav16Mono(sampleRate: 11025, samples: samples);
      final decoded = LocalFingerprintEngine.decodeWavBytesToMonoFloat(wav);
      expect(decoded.length, equals(samples.length));
      for (var i = 0; i < samples.length; i++) {
        expect(decoded[i], closeTo(samples[i], 0.001));
      }
    });
  });
}
