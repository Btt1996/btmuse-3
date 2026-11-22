import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/core/utilities/volume_dsp_math.dart';
import 'package:btmu/data/models/audio_settings.dart';

class AudioSettingsScreen extends ConsumerWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(audioSettingsProvider);
    final handler = ref.watch(audioHandlerProvider);

    final dsp = VolumeDspMath.evaluateGain(
      multiplier: settings.volumeMultiplier,
      limiterEnabled: settings.limiterEnabled,
      normalizationOffsetDb: settings.normalizeVolume ? -1.5 : 0.0,
    );

    Future<void> apply(AudioSettings next) async {
      ref.read(audioSettingsProvider.notifier).state = next;
      await handler.applyAudioSettings(next);
    }

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
                    ? BttColors.goldAccent.withValues(alpha: 0.6)
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
                      '${settings.boostPercent}%',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            color: settings.isExtremeBoost
                                ? BttColors.goldAccent
                                : BttColors.cyanAccent,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Gain: +${dsp.gainDb.toStringAsFixed(1)} dB · Limiter: ${dsp.limiterEngaged ? 'Engaged (-1 dBFS ceiling)' : 'Idle'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 12),
                Slider(
                  min: 1.0,
                  max: 3.0,
                  divisions: 40,
                  value: settings.volumeMultiplier.clamp(1.0, 3.0),
                  activeColor:
                      settings.isExtremeBoost ? BttColors.goldAccent : BttColors.cyanAccent,
                  onChanged: (v) => apply(settings.copyWith(volumeMultiplier: v)),
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
                      onSelected: (_) => apply(settings.copyWith(volumeMultiplier: preset)),
                      selectedColor: BttColors.goldAccent.withValues(alpha: 0.25),
                    );
                  }).toList(),
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
              child: const Row(
                children: [
                  Icon(Icons.hearing_rounded, color: BttColors.warning),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Prolonged high-SPL listening over headphones can cause hearing fatigue. iOS hardware & Headphone Safety limits still govern final speaker/DAC voltage.',
                      style: TextStyle(fontSize: 12.5),
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
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: BttColors.danger),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Clipping risk detected with peak limiter disabled. Enable the Soft-Knee Peak Limiter below.',
                      style: TextStyle(fontSize: 12.5),
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
            activeThumbColor: BttColors.greenAccent,
            onChanged: (val) => apply(settings.copyWith(limiterEnabled: val)),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Volume Normalization'),
            subtitle: const Text('Balances loudness differences across quiet tracks'),
            value: settings.normalizeVolume,
            activeThumbColor: BttColors.cyanAccent,
            onChanged: (val) => apply(settings.copyWith(normalizeVolume: val)),
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
                onSelected: (_) => apply(settings.copyWith(eqPreset: preset)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
