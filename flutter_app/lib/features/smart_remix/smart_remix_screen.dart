import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/data/models/smart_remix_config.dart';
import 'package:btmu/features/smart_remix/smart_remix_engine.dart';

class SmartRemixScreen extends ConsumerWidget {
  const SmartRemixScreen({super.key});

  String _modeLabel(SmartRemixMode mode) => switch (mode) {
        SmartRemixMode.smoothMix => 'Smooth Mix',
        SmartRemixMode.partyMix => 'Party Mix',
        SmartRemixMode.chillMix => 'Chill Mix',
        SmartRemixMode.energyMix => 'Energy Mix',
        SmartRemixMode.randomSmartMix => 'Random Smart Mix',
      };

  String _modeDesc(SmartRemixMode mode) => switch (mode) {
        SmartRemixMode.smoothMix => 'Chains tracks by closest tempo (BPM) and energy continuity.',
        SmartRemixMode.partyMix => 'Prioritizes upbeat, high-tempo, peak-energy tracks.',
        SmartRemixMode.chillMix => 'Sorts calmly from lowest acoustic intensity upward.',
        SmartRemixMode.energyMix => 'Drops highest energy tracks immediately up front.',
        SmartRemixMode.randomSmartMix => 'Shuffles cleanly with equal-power transitions.',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(smartRemixConfigProvider);
    final tracks = ref.watch(libraryTracksProvider).valueOrNull ?? [];
    final plan = SmartRemixEngine.buildMixOrder(tracks: tracks, mode: config.mode);
    final handler = ref.watch(audioHandlerProvider);

    Future<void> updateConfig(SmartRemixConfig next) async {
      ref.read(smartRemixConfigProvider.notifier).state = next;
      await handler.updateRemixConfig(next);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Remix Engine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          SwitchListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Enable Continuous Equal-Power Crossfade'),
            subtitle: Text('Crossfade overlap: ${config.crossfadeSeconds}s'),
            activeThumbColor: BttColors.accentPink,
            value: config.enabled,
            onChanged: (val) => updateConfig(config.copyWith(enabled: val)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BttColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BttColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crossfade Overlap (${config.crossfadeSeconds}s)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Slider(
                  min: 2,
                  max: 14,
                  divisions: 12,
                  value: config.crossfadeSeconds.toDouble(),
                  onChanged: (v) =>
                      updateConfig(config.copyWith(crossfadeSeconds: v.round())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Mix Mode', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          ...SmartRemixMode.values.map((m) {
            final selected = config.mode == m;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                tileColor: selected ? BttColors.bgCardHighlight : BttColors.bgCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: selected ? BttColors.accentPink : BttColors.borderSubtle,
                  ),
                ),
                title: Text(_modeLabel(m)),
                subtitle: Text(_modeDesc(m)),
                trailing: selected
                    ? const Icon(Icons.check_circle_rounded, color: BttColors.accentPink)
                    : null,
                onTap: () => updateConfig(config.copyWith(mode: m)),
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: plan.isEmpty
                ? null
                : () async {
                    await updateConfig(config.copyWith(enabled: true));
                    await handler.setTrackQueueAndPlay(
                      plan.map((e) => e.track).toList(),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Started ${_modeLabel(config.mode)} across ${plan.length} tracks.',
                          ),
                        ),
                      );
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: BttColors.accentPink,
              foregroundColor: BttColors.bgObsidian,
              minimumSize: const Size.fromHeight(50),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('Launch ${_modeLabel(config.mode)} (${plan.length} tracks)'),
          ),
          if (plan.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'Transition Order Preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...plan.take(12).map((entry) {
              final tag = entry.usesHeuristicFallback ? 'Est.' : 'Measured';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.track.title),
                subtitle: Text(
                  '${entry.track.artist} · ~${entry.effectiveBpm.round()} BPM ($tag) · Flow ${(entry.transitionScore * 100).round()}%',
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
