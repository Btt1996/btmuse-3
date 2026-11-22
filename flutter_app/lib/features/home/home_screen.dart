import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/btt_page_route.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/app/widgets/btt_logo_mark.dart';
import 'package:btmu/app/widgets/btt_press_scale.dart';
import 'package:btmu/app/widgets/staggered_entrance.dart';
import 'package:btmu/app/widgets/track_tile.dart';
import 'package:btmu/features/audio_settings/audio_settings_screen.dart';
import 'package:btmu/features/downloads/download_history_screen.dart';
import 'package:btmu/features/search/search_screen.dart';
import 'package:btmu/features/settings/settings_screen.dart';
import 'package:btmu/features/smart_remix/smart_remix_screen.dart';
import 'package:btmu/features/telegram/telegram_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(libraryTracksProvider);
    final downloads = ref.watch(downloadManagerProvider);
    final activeDownloads = downloads.where((d) => d.isActive).length;
    final audioHandler = ref.watch(audioHandlerProvider);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: BttColors.bgObsidian,
          titleSpacing: 16,
          title: Row(
            children: [
              const BttLogoMark(size: 36, rounded: true),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Btt Music', style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    'BTmu 2.00 · Offline Hi-Fi',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: BttColors.cyanAccent,
                        ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Universal Search',
              onPressed: () {
                Navigator.of(context).push(
                  BttPageRoute<void>(builder: (_) => const SearchScreen()),
                );
              },
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: 'Downloads',
              onPressed: () {
                Navigator.of(context).push(
                  BttPageRoute<void>(builder: (_) => const DownloadHistoryScreen()),
                );
              },
              icon: Badge(
                isLabelVisible: activeDownloads > 0,
                label: Text('$activeDownloads'),
                child: const Icon(Icons.downloading_rounded),
              ),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  BttPageRoute<void>(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Primary engine quick access grid (2x2 clean cards)
              Row(
                children: [
                  Expanded(
                    child: _EngineCard(
                      title: 'X1 Recognize',
                      subtitle: 'Identify playing audio',
                      icon: Icons.mic_rounded,
                      accent: BttColors.cyanAccent,
                      onTap: () => ref.read(currentTabIndexProvider.notifier).state = BttTab.x1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EngineCard(
                      title: 'X2 Discover',
                      subtitle: 'Multi-source search & URL',
                      icon: Icons.travel_explore_rounded,
                      accent: BttColors.goldAccent,
                      onTap: () => ref.read(currentTabIndexProvider.notifier).state = BttTab.x2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _EngineCard(
                      title: 'Telegram Sync',
                      subtitle: 'Import bot audio',
                      icon: Icons.send_rounded,
                      accent: BttColors.greenAccent,
                      onTap: () {
                        Navigator.of(context).push(
                          BttPageRoute<void>(builder: (_) => const TelegramScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EngineCard(
                      title: 'Smart Remix',
                      subtitle: 'Equal-power DJ flow',
                      icon: Icons.auto_awesome_rounded,
                      accent: BttColors.cyanAccent,
                      onTap: () {
                        Navigator.of(context).push(
                          BttPageRoute<void>(builder: (_) => const SmartRemixScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () =>
                    ref.read(currentTabIndexProvider.notifier).state = BttTab.importCenter,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: BttColors.bgCardHighlight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: BttColors.greenAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle_rounded, color: BttColors.greenAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Import Center',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Files, Batch, Telegram, VK, YouTube, SoundCloud, URLs, X1 & X2',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: BttColors.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    BttPageRoute<void>(builder: (_) => const AudioSettingsScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: BttColors.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: BttColors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.graphic_eq_rounded, color: BttColors.goldAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Extreme Volume & Limiter',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '100%–300% soft-knee peak limited DSP boost',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: BttColors.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              tracksAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error loading tracks: $err'),
                ),
                data: (tracks) {
                  if (tracks.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: BttColors.bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: BttColors.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your offline vault is ready',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Import MP3/M4A/FLAC/WAV files from iOS Files, scan Telegram bot chats, or search creative commons audio in X2 Discovery.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: () =>
                                    ref.read(currentTabIndexProvider.notifier).state =
                                        BttTab.importCenter,
                                icon: const Icon(Icons.add_circle_rounded),
                                label: const Text('Import Center'),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    ref.read(currentTabIndexProvider.notifier).state = BttTab.x2,
                                icon: const Icon(Icons.search_rounded),
                                label: const Text('Explore X2'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }

                  final recentlyPlayed = tracks
                      .where((t) => t.lastPlayedAtMs != null)
                      .toList()
                    ..sort((a, b) => (b.lastPlayedAtMs ?? 0).compareTo(a.lastPlayedAtMs ?? 0));

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (recentlyPlayed.isNotEmpty) ...[
                        Text(
                          'Recently Played',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 158,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: recentlyPlayed.take(8).length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, idx) {
                              final t = recentlyPlayed[idx];
                              return StaggeredEntrance(
                                index: idx,
                                key: ValueKey(t.id),
                                child: BttPressScale(
                                  child: GestureDetector(
                                    onTap: () => audioHandler.setTrackQueueAndPlay(
                                      recentlyPlayed,
                                      initialIndex: idx,
                                    ),
                                    child: SizedBox(
                                      width: 112,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          BttArtwork(
                                            artworkPath: t.artworkPath,
                                            artworkUrl: t.artworkUrl,
                                            size: 112,
                                            radius: 16,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            t.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(fontSize: 13.5),
                                          ),
                                          Text(
                                            t.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Additions (${tracks.length})',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          TextButton(
                            onPressed: () => audioHandler.setTrackQueueAndPlay(tracks),
                            child: const Text('Play All'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...tracks.take(10).toList().asMap().entries.map((entry) {
                        final idx = entry.key;
                        final track = entry.value;
                        return StaggeredEntrance(
                          index: idx,
                          key: ValueKey(track.id),
                          child: BttPressScale(
                            child: TrackTile(
                              track: track,
                              isCurrent: audioHandler.currentTrack?.id == track.id,
                              onTap: () => audioHandler.setTrackQueueAndPlay(
                                tracks,
                                initialIndex: idx,
                              ),
                              onFavoriteToggle: () async {
                                await ref
                                    .read(libraryRepositoryProvider)
                                    .toggleFavorite(track.id, !track.isFavorite);
                                ref.invalidate(libraryTracksProvider);
                              },
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _EngineCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _EngineCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BttColors.bgCard,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BttColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 26),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
