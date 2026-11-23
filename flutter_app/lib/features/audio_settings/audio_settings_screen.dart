import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/core/utilities/volume_dsp_math.dart';
import 'package:btmu/data/models/audio_settings.dart';

class AudioSettingsScreen extends ConsumerStatefulWidget {
  const AudioSettingsScreen({super.key});

  @override
  ConsumerState<AudioSettingsScreen> createState() =>
      _AudioSettingsScreenState();
}

class _AudioSettingsScreenState extends ConsumerState<AudioSettingsScreen> {
  /// Boost level restored when the booster is switched back on, so
  /// turning it off and on again does not silently reset the user to
  /// 150%. Only ever holds a value > 1.0.
  double _lastBoostMultiplier = 1.5;

  Future<void> _apply(AudioSettings next) async {
    ref.read(audioSettingsProvider.notifier).state = next;
    await ref.read(audioHandlerProvider).applyAudioSettings(next);
  }

  /// Raw (pre-normalization) gain of a multiplier, in dB: 20·log10(m).
  /// At 300% this is +9.54 dB. Since v3.0.5 the normalization pad no
  /// longer subtracts from an explicit boost, so at 300% the net gain
  /// the user hears is the full +9.54 dB (the limiter still caps peaks,
  /// so loud passages gain less than the number — the honest label below
  /// says exactly that).
  static double _rawGainDb(double multiplier) {
    if (multiplier <= 0.0001) return -96.0;
    return 20.0 * (math.log(multiplier) / math.ln10);
  }

  static String _fmtDb(double value) =>
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} dB';

  Future<void> _setBoosterEnabled(bool on, AudioSettings settings) async {
    if (on) {
      await _apply(
        settings.copyWith(
          volumeMultiplier: _lastBoostMultiplier.clamp(1.25, 3.0),
        ),
      );
    } else {
      await _apply(settings.copyWith(volumeMultiplier: 1.0));
    }
  }

  Future<void> _setMultiplier(double value) async {
    final clamped = value.clamp(1.0, 3.0);
    if (clamped > 1.0) {
      setState(() => _lastBoostMultiplier = clamped);
    }
    final settings = ref.read(audioSettingsProvider);
    await _apply(settings.copyWith(volumeMultiplier: clamped));
  }

  /// Turning the limiter off while the booster is above 100% is the one
  /// path to unclipped 300% gain, so it requires an explicit confirmation
  /// instead of a bare toggle (E-2).
  Future<void> _onLimiterChanged(bool value, AudioSettings settings) async {
    if (!value && settings.volumeMultiplier > 1.0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: BttColors.bgCard,
          title: const Text('Turn off the peak limiter?'),
          content: Text(
            'The booster is at ${settings.boostPercent}% '
            '(${_fmtDb(_rawGainDb(settings.volumeMultiplier))} of digital gain). '
            'Without the limiter, loud passages can clip and distort — '
            'the DynamicsProcessor ceiling no longer protects the output. '
            'Keep the limiter on unless you know the track has headroom.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep limiter on'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Turn off anyway',
                style: TextStyle(color: BttColors.danger),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _apply(settings.copyWith(limiterEnabled: value));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(audioSettingsProvider);

    final dsp = VolumeDspMath.evaluateGain(
      multiplier: settings.volumeMultiplier,
      limiterEnabled: settings.limiterEnabled,
      normalizationOffsetDb: VolumeDspMath.effectiveNormalizationOffsetDb(
        multiplier: settings.volumeMultiplier,
        normalizeVolume: settings.normalizeVolume,
      ),
    );

    // E-2 boost honesty: show BOTH the raw multiplier gain and the
    // effective overall gain, not just the net number. Since v3.0.5 the
    // normalization pad no longer subtracts from an explicit boost, so
    // at 300% the net IS +9.5 dB; the pad only shows below 100%.
    final boosterOn = settings.volumeMultiplier > 1.0;
    final rawGainDb = _rawGainDb(settings.volumeMultiplier);
    final gainBreakdown = boosterOn
        ? '${settings.boostPercent}% · ${_fmtDb(rawGainDb)} gain = ${_fmtDb(dsp.gainDb)} net (full boost — normalization does not subtract while boosting)'
        : settings.normalizeVolume
            ? '${settings.boostPercent}% · ${_fmtDb(rawGainDb)} gain − 1.5 dB normalization = ${_fmtDb(dsp.gainDb)} net'
            : '${settings.boostPercent}% · ${_fmtDb(rawGainDb)} gain = ${_fmtDb(dsp.gainDb)} net (normalization off)';

    // Crossfade (S-3) now lives on AudioSettings — see the crossfade card
    // below. INTEGRATION NOTE (W2): `crossfadeEnabled` (bool, default
    // false) and `crossfadeSeconds` (double, default 6) are the fields the
    // handler worker is adding to AudioSettings in parallel, replacing
    // SmartRemixConfig.crossfadeSeconds. If they land as int seconds,
    // change the slider callback below from `crossfadeSeconds: v` to
    // `crossfadeSeconds: v.round()`.
    final crossfadeSeconds = settings.crossfadeSeconds.toDouble().clamp(2.0, 14.0);

    return Scaffold(
      appBar: AppBar(title: const Text('Audio Engine & Boost')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: BttColors.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: settings.isExtremeBoost
                    ? BttColors.accentMagenta.withValues(alpha: 0.6)
                    : BttColors.borderSubtle,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pre-Amp Boost', style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      boosterOn ? '${settings.boostPercent}%' : 'Off',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            color: !boosterOn
                                ? BttColors.textMuted
                                : settings.isExtremeBoost
                                    ? BttColors.accentMagenta
                                    : BttColors.accentPink,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  gainBreakdown,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Limiter: ${dsp.limiterEngaged ? 'Engaged (-1 dBFS ceiling)' : 'Idle'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Volume Booster'),
                  subtitle: Text(
                    boosterOn
                        ? 'On — boosting above unity gain'
                        : 'Off — playing at 100% (unity gain)',
                  ),
                  value: boosterOn,
                  activeThumbColor: BttColors.accentPink,
                  onChanged: (val) => _setBoosterEnabled(val, settings),
                ),
                Slider(
                  min: 1.0,
                  max: 3.0,
                  divisions: 40,
                  value: settings.volumeMultiplier.clamp(1.0, 3.0),
                  activeColor:
                      settings.isExtremeBoost ? BttColors.accentMagenta : BttColors.accentPink,
                  onChanged: boosterOn ? (v) => _setMultiplier(v) : null,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AudioSettings.boostPresets.map((preset) {
                    final active = (settings.volumeMultiplier - preset).abs() < 0.03;
                    return ChoiceChip(
                      label: Text('${(preset * 100).round()}%'),
                      selected: active,
                      onSelected:
                          boosterOn ? (_) => _setMultiplier(preset) : null,
                      selectedColor: BttColors.accentMagenta.withValues(alpha: 0.25),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  '300% is +9.5 dB of digital gain, not 3× perceived loudness.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: BttColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (settings.isExtremeBoost) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BttColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BttColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.hearing_rounded, color: BttColors.warning),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: const Text(
                      'Prolonged high-SPL listening over headphones can cause hearing fatigue. iOS hardware & Headphone Safety limits still govern final speaker/DAC voltage.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (dsp.clippingRisk) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BttColors.danger.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BttColors.danger.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: BttColors.danger),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: const Text(
                      'Clipping risk detected with peak limiter disabled. Enable the Soft-Knee Peak Limiter below.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SwitchListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Soft-Knee Peak Limiter'),
            subtitle: const Text('Uses native AudioUnit DynamicsProcessor above 100%'),
            value: settings.limiterEnabled,
            activeThumbColor: BttColors.success,
            onChanged: (val) => _onLimiterChanged(val, settings),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Volume Normalization'),
            subtitle: const Text(
              'Balances loudness across quiet tracks at normal volume. '
              'It never subtracts from an explicit boost — 300% always '
              'delivers its full +9.5 dB.',
            ),
            value: settings.normalizeVolume,
            activeThumbColor: BttColors.accentPink,
            onChanged: (val) => _apply(settings.copyWith(normalizeVolume: val)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: BttColors.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: BttColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Crossfade', style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      settings.crossfadeEnabled
                          ? '${crossfadeSeconds.toStringAsFixed(0)}s'
                          : 'Off',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            color: settings.crossfadeEnabled
                                ? BttColors.accentPink
                                : BttColors.textMuted,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Overlap the end of one track with the start of the next (equal-power). Moved here from Smart Remix — it no longer needs Smart Remix enabled.',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Crossfade between tracks'),
                  subtitle: Text(
                    settings.crossfadeEnabled
                        ? 'On — ${crossfadeSeconds.toStringAsFixed(0)}s overlap'
                        : 'Off — tracks end with a clean stop/start',
                  ),
                  value: settings.crossfadeEnabled,
                  activeThumbColor: BttColors.accentPink,
                  onChanged: (val) =>
                      _apply(settings.copyWith(crossfadeEnabled: val)),
                ),
                Slider(
                  min: 2,
                  max: 14,
                  divisions: 12,
                  value: crossfadeSeconds,
                  activeColor: BttColors.accentPink,
                  onChanged: settings.crossfadeEnabled
                      ? (v) => _apply(settings.copyWith(crossfadeSeconds: v))
                      : null,
                ),
                Text(
                  'Overlap: ${crossfadeSeconds.toStringAsFixed(0)}s',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Equalizer Profile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AudioSettings.eqPresets.map((preset) {
              return ChoiceChip(
                label: Text(preset),
                selected: settings.eqPreset == preset,
                onSelected: (_) => _apply(settings.copyWith(eqPreset: preset)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
