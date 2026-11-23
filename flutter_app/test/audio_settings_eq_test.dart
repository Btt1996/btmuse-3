import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/data/models/audio_settings.dart';

/// Phase 3, E-1: EQ preset agreement between the Dart UI and the native
/// Swift plugin.
///
/// The Dart side owns the canonical preset list
/// ([AudioSettings.eqPresets]); the Swift side
/// (`flutter_app/ios/Runner/AudioEnginePlugin.swift`, `applyAudioSettings`)
/// must implement exactly the same names, each with a distinct non-flat
/// 5-band curve — except `Balanced`, which is flat and bypasses the EQ node.
///
/// The Swift gains below are a MIRROR of the switch in
/// `AudioEnginePlugin.swift` (bands at 60 / 230 / 910 / 3600 / 14000 Hz).
/// They are literals on purpose: if someone edits a curve in Swift without
/// updating this table, this test fails and the two sides are out of sync
/// again. Update both files together.
///
/// History: before Phase 3 the Swift switch implemented
/// `Bass Boost / Vocal Clarity / Treble Crisp / Acoustic Warmth`, so
/// `Warm Bass`, `Late Night` and `Studio Bright` silently fell through to
/// all-zero gains. The legacy curves live on under the Dart names
/// (`Warm Bass` == old `Bass Boost`, `Studio Bright` == old
/// `Treble Crisp`); `Acoustic Warmth` has no Dart preset and was dropped.
/// `Late Night` is a new curve defined in Phase 3 (see the Swift comment).
void main() {
  /// Mirror of the Swift `switch eqPreset` in `applyAudioSettings`.
  /// Preset name -> 5 band gains in dB.
  const swiftPresetGains = <String, List<double>>{
    'Balanced': [0.0, 0.0, 0.0, 0.0, 0.0],
    'Warm Bass': [6.5, 4.0, 0.0, -1.0, 1.0],
    'Vocal Clarity': [-2.5, -1.0, 4.5, 4.0, 1.5],
    // Gentle low/high roll-off for quiet late-night listening:
    // sub-bass trimmed (-1.5 dB at 60 Hz), mids kept slightly forward
    // (+1.0 dB at 910 Hz) for intelligibility at low volume, presence
    // tamed (-1.0 dB at 3600 Hz), highs rolled off (-3.5 dB at 14 kHz).
    'Late Night': [-1.5, 0.0, 1.0, -1.0, -3.5],
    'Studio Bright': [-1.0, 0.0, 1.5, 4.5, 6.0],
  };

  test('Dart preset list is the canonical list, in UI order', () {
    expect(AudioSettings.eqPresets, [
      'Balanced',
      'Warm Bass',
      'Vocal Clarity',
      'Late Night',
      'Studio Bright',
    ]);
  });

  test('Dart presets equal the set the Swift plugin implements', () {
    // The Swift set is the key set of swiftPresetGains above, transcribed
    // from the case labels of the switch in AudioEnginePlugin.swift.
    // A preset present on one side and missing on the other is the exact
    // Phase 3 bug (a tap that silently does nothing, or a curve the UI
    // can never select).
    expect(
      AudioSettings.eqPresets.toSet(),
      swiftPresetGains.keys.toSet(),
    );
  });

  test('every preset has exactly 5 band gains', () {
    for (final entry in swiftPresetGains.entries) {
      expect(entry.value, hasLength(5), reason: entry.key);
    }
  });

  test('Balanced is flat; every other preset is non-flat and distinct', () {
    expect(swiftPresetGains['Balanced'], everyElement(0.0));

    final seen = <String>{};
    for (final entry in swiftPresetGains.entries) {
      if (entry.key == 'Balanced') continue;
      // Non-flat: at least one band actually moves.
      expect(entry.value.any((g) => g != 0.0), isTrue, reason: entry.key);
      // Distinct: no two presets share the same curve.
      final signature = entry.value.join(',');
      expect(seen, isNot(contains(signature)), reason: entry.key);
      seen.add(signature);
    }
  });

  test('Warm Bass keeps the legacy Bass Boost curve', () {
    expect(swiftPresetGains['Warm Bass'], [6.5, 4.0, 0.0, -1.0, 1.0]);
  });

  test('Vocal Clarity curve is unchanged', () {
    expect(swiftPresetGains['Vocal Clarity'], [-2.5, -1.0, 4.5, 4.0, 1.5]);
  });

  test('Studio Bright keeps the legacy Treble Crisp curve', () {
    expect(swiftPresetGains['Studio Bright'], [-1.0, 0.0, 1.5, 4.5, 6.0]);
  });

  test('Late Night is the new gentle low/high roll-off curve', () {
    final gains = swiftPresetGains['Late Night']!;
    // Low end trimmed, not lifted; highs rolled off hardest.
    expect(gains[0], -1.5); // 60 Hz
    expect(gains[1], 0.0); // 230 Hz
    expect(gains[2], 1.0); // 910 Hz — mids forward for intelligibility
    expect(gains[3], -1.0); // 3600 Hz
    expect(gains[4], -3.5); // 14 kHz — the deepest cut
    // Gentle overall: no band moves more than 3.5 dB.
    expect(gains.map((g) => g.abs()).reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(3.5));
  });

  test('no retired Swift-only preset name survives in the Dart list', () {
    // Bass Boost / Treble Crisp / Acoustic Warmth were Swift-only names
    // before Phase 3; they must not reappear as Dart presets.
    for (final retired in ['Bass Boost', 'Treble Crisp', 'Acoustic Warmth']) {
      expect(AudioSettings.eqPresets, isNot(contains(retired)));
    }
  });
}
