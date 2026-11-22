import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/btt_page_route.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/data/models/smart_remix_config.dart';
import 'package:btmu/features/audio_settings/audio_settings_screen.dart';
import 'package:btmu/features/smart_remix/smart_remix_engine.dart';

class SmartRemixScreen extends ConsumerWidget {
  const SmartRemixScreen({super.key});

  String _modeLabel(SmartRemixMode mode) => switch (mode) {
        SmartRemixMode.smoothMix => 'Smooth Mix',
        SmartRemixMode.partyMix => 'Party Mix',
        SmartRemixMode.chillMix => 'Chill Mix',
        SmartRemixMode.energyMix => 'Energy Mix',
        SmartRemixMode.randomSmartMix => 'Random Smart Mix',
        SmartRemixMode.arcMix => 'Arc Mix',
      };

  String _modeDesc(SmartRemixMode mode) => switch (mode) {
        SmartRemixMode.smoothMix => 'Chains tracks by closest tempo (BPM) and energy continuity.',
        SmartRemixMode.partyMix => 'Prioritizes upbeat, high-tempo, peak-energy tracks.',
        SmartRemixMode.chillMix => 'Sorts calmly from lowest acoustic intensity upward.',
        SmartRemixMode.energyMix => 'Drops highest energy tracks immediately up front.',
        SmartRemixMode.randomSmartMix => 'Shuffles cleanly with equal-power transitions.',
        SmartRemixMode.arcMix => 'Warm-up, build, peak, then cooldown — the full energy arc.',
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

    Future<void> saveMixAsPlaylist() async {
      if (plan.isEmpty) return;
      final defaultName = 'Smart Mix — ${_modeLabel(config.mode)}';
      final nameCtrl = TextEditingController(text: defaultName);
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save mix as playlist'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Playlist name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (name == null || name.isEmpty) return;
      try {
        final repo = ref.read(playlistRepositoryProvider);
        final playlist = await repo.createPlaylist(
          name: name,
          description:
              'Smart Remix · ${_modeLabel(config.mode)} · ${plan.length} tracks',
        );
        // Sequential awaits: addTrackToPlaylist appends at
        // MAX(position) + 1, so awaiting each insert in plan order
        // preserves the computed energy-arc order in the playlist.
        for (final entry in plan) {
          await repo.addTrackToPlaylist(playlist.id, entry.track.id);
        }
        ref.invalidate(playlistsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved "$name" with ${plan.length} tracks.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save playlist: $e')),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Remix Engine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // Crossfade moved to Audio settings in Phase 3 (S-3): it is a
          // first-class playback setting on AudioSettings now, not part of
          // Smart Remix. This tile links there instead of duplicating the
          // control. SmartRemixConfig.crossfadeSeconds is removed by the
          // handler worker (W2); nothing on this screen reads it anymore.
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: BttColors.borderSubtle),
            ),
            leading: const Icon(Icons.tune_rounded, color: BttColors.accentPink),
            title: const Text('Crossfade'),
            subtitle: const Text(
              'Crossfade now lives in Audio settings and works for any queue — no Smart Remix needed.',
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: BttColors.textSecondary,
            ),
            onTap: () {
              Navigator.of(context).push(
                BttPageRoute<void>(
                  builder: (_) => const AudioSettingsScreen(),
                ),
              );
            },
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
                    // Phase 3: SmartRemixConfig.enabled was dropped as
                    // vestigial — the launch action itself is the remix.
                    // (Previously this persisted config.copyWith(enabled: true).)
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
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: plan.isEmpty ? null : saveMixAsPlaylist,
            style: OutlinedButton.styleFrom(
              foregroundColor: BttColors.accentPink,
              side: const BorderSide(color: BttColors.accentPink),
              minimumSize: const Size.fromHeight(50),
            ),
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text('Save mix as playlist (${plan.length} tracks)'),
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
              // The "~" marks a heuristic estimate only: a measured BPM
              // is shown bare, so estimates are never presented as
              // measured values.
              final bpmLabel = entry.usesHeuristicFallback
                  ? '~${entry.effectiveBpm.round()} BPM'
                  : '${entry.effectiveBpm.round()} BPM';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.track.title),
                subtitle: Text(
                  '${entry.track.artist} · $bpmLabel ($tag) · Flow ${(entry.transitionScore * 100).round()}%',
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
