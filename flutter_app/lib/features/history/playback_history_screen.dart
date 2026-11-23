import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/data/models/track.dart';

/// Dedicated playback-history screen (Phase 6, item 27).
///
/// Flutter had download history (`HistoryRepository` /
/// `DownloadHistoryScreen`) and a Home "Recently Played" strip built
/// from `lastPlayedAtMs`, but no screen listing everything played. This
/// is that screen: every track with a `lastPlayedAtMs`, newest first,
/// tap-to-play, and a confirmed clear.
///
/// Playback recording (verified, not changed here): every real play path
/// funnels through `BttAudioHandler.playTrackAtIndex`, which calls
/// `LibraryRepository.recordPlayback` after a successful start
/// (`btt_audio_handler.dart:727`), and the two crossfade paths record
/// the incoming track the same way (`:824`, `:847`). Resume-after-pause
/// and seek do not re-record — starting a track counts once. A missing
/// file never records: the handler reports and skips it before the
/// record call.
///
/// Clear semantics: clearing nulls `last_played_at_ms` only. Play counts
/// are kept — they feed the duplicate scan's suggested keeper
/// (`DuplicateGroup.suggestedKeeper`: most-played wins) and the library
/// stats, so wiping them would silently change cleanup suggestions.
/// Clearing removes entries from this list and from Home's
/// "Recently Played" (same `lastPlayedAtMs != null` filter), and it
/// cannot be undone.
///
/// NOTE (layering): clearing lives in
/// `LibraryRepository.clearPlaybackHistory()` (Phase 6, coordinator move);
/// the screen calls it rather than running SQL inline.
class PlaybackHistoryScreen extends ConsumerWidget {
  const PlaybackHistoryScreen({super.key});

  Future<void> _confirmAndClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BttColors.bgElevated,
        title: const Text('Clear playback history?'),
        content: const Text(
          'This removes every track from Playback History and from '
          'Home’s Recently Played. Your tracks, playlists and play '
          'counts are kept — only the “last played” times are cleared. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BttColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(libraryRepositoryProvider).clearPlaybackHistory();
    ref.invalidate(libraryTracksProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playback history cleared.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(libraryTracksProvider);
    final handler = ref.watch(audioHandlerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playback History'),
        actions: [
          if ((tracksAsync.valueOrNull ?? const <Track>[])
              .any((t) => t.lastPlayedAtMs != null))
            TextButton(
              onPressed: () => _confirmAndClear(context, ref),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (tracks) {
          final history = tracks.where((t) => t.lastPlayedAtMs != null).toList()
            ..sort(
              (a, b) => (b.lastPlayedAtMs ?? 0).compareTo(a.lastPlayedAtMs ?? 0),
            );
          if (history.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 52,
                      color: BttColors.textMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No playback history yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Play a track and it will show up here, newest first. '
                      'Downloads have their own history under '
                      'Settings → Download Queue & History.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final t = history[idx];
              return _HistoryRow(
                track: t,
                isCurrent: handler.currentTrack?.id == t.id,
                onTap: () =>
                    handler.setTrackQueueAndPlay(history, initialIndex: idx),
              );
            },
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final VoidCallback onTap;

  const _HistoryRow({
    required this.track,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent ? BttColors.bgCardHighlight : BttColors.bgCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              BttArtwork(
                artworkPath: track.artworkPath,
                artworkUrl: track.artworkUrl,
                size: 52,
                radius: 12,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: isCurrent
                                ? BttColors.accentPink
                                : BttColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_playedAgo(track.lastPlayedAtMs!)}'
                      ' · played ${track.playCount}x',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.play_arrow_rounded,
                color: BttColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _playedAgo(int lastPlayedAtMs) {
  final played = DateTime.fromMillisecondsSinceEpoch(lastPlayedAtMs);
  final diff = DateTime.now().difference(played);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${played.year}-${two(played.month)}-${two(played.day)}';
}
