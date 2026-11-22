import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/core/services/btt_audio_handler.dart';
import 'package:btmu/data/models/track.dart';

/// "Up Next" — the live playback queue, shown as a bottom sheet from the
/// full-screen player.
///
/// Reads the queue from [BttAudioHandler.queueStream] (initial data:
/// [BttAudioHandler.currentTracks]) and the current track from
/// [BttAudioHandler.currentTrackStream], so the list follows queue edits
/// made anywhere in the app. Every row action calls the agreed Phase 3
/// queue API on the handler — [BttAudioHandler.playTrackAtIndex],
/// [BttAudioHandler.removeFromQueue], [BttAudioHandler.moveQueueItem],
/// [BttAudioHandler.clearQueue] — which owns re-publishing the queue to
/// audio_service and persisting it (Q-1/Q-2).
///
/// INTEGRATION NOTE (W2): `queueStream` does not exist on the handler at
/// head c3caecd — it is the queue stream the handler worker is adding in
/// parallel. The name was chosen to match the existing
/// `currentTrackStream` / `settingsStream` pattern, and deliberately NOT
/// `queue`, which audio_service's [QueueHandler] already owns as a
/// `ValueStream<List<MediaItem>>`. If the handler lands a differently
/// named stream, update the one [StreamBuilder] below. The current track
/// is identified by id comparison against `currentTrack` because the
/// handler exposes no current-index getter. The sheet subscribes to
/// `queueStream` exactly once (one StreamBuilder wraps header + list),
/// so it also works if the stream is single-subscription.
Future<void> showUpNextSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BttColors.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const UpNextSheet(),
  );
}

class UpNextSheet extends ConsumerWidget {
  const UpNextSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: SafeArea(
        child: StreamBuilder<List<Track>>(
          stream: handler.queueStream,
          initialData: handler.currentTracks,
          builder: (context, queueSnap) {
            final queue = queueSnap.data ?? handler.currentTracks;
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: BttColors.borderStrong,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Up Next',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${queue.length} track${queue.length == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: queue.isEmpty
                                ? null
                                : () => _confirmClear(context, handler),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: queue.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                size: 44,
                                color: BttColors.textMuted,
                              ),
                              SizedBox(height: 12),
                              Text('Nothing queued yet'),
                              SizedBox(height: 4),
                              Text(
                                'Tracks you play will appear here.',
                                style: TextStyle(
                                  color: BttColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : StreamBuilder<Track?>(
                          stream: handler.currentTrackStream,
                          initialData: handler.currentTrack,
                          builder: (context, trackSnap) {
                            final currentId = trackSnap.data?.id;
                            return ReorderableListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              // No default handles: each row owns its drag
                              // handle (ReorderableDragStartListener) so a
                              // vertical drag starting anywhere else still
                              // scrolls / dismisses the sheet instead of
                              // starting a reorder.
                              buildDefaultDragHandles: false,
                              itemCount: queue.length,
                              proxyDecorator: (child, index, animation) =>
                                  AnimatedBuilder(
                                animation: animation,
                                builder: (context, child) => Material(
                                  color: Colors.transparent,
                                  child: child,
                                ),
                                child: child,
                              ),
                              onReorder: (oldIndex, newIndex) async {
                                // ReorderableListView reports newIndex as
                                // the position *after* the dragged item is
                                // removed.
                                if (oldIndex < newIndex) newIndex -= 1;
                                await handler.moveQueueItem(
                                  oldIndex,
                                  newIndex,
                                );
                              },
                              itemBuilder: (context, index) {
                                final track = queue[index];
                                final isCurrent = track.id == currentId;
                                return _QueueRow(
                                  key: ValueKey(track.id),
                                  track: track,
                                  index: index,
                                  isCurrent: isCurrent,
                                  onTap: () async {
                                    HapticFeedback.lightImpact();
                                    await handler.playTrackAtIndex(index);
                                  },
                                  onRemove: () async {
                                    HapticFeedback.lightImpact();
                                    await handler.removeFromQueue(index);
                                  },
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    BttAudioHandler handler,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BttColors.bgCard,
        title: const Text('Clear the queue?'),
        content: const Text(
          'This removes every track from Up Next.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Clear',
              style: TextStyle(color: BttColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await handler.clearQueue();
    }
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  final Track track;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isCurrent
            ? BttColors.accentPink.withValues(alpha: 0.12)
            : BttColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? BttColors.accentPink.withValues(alpha: 0.45)
              : BttColors.borderSubtle,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 10, right: 4),
        leading: BttArtwork(
          artworkPath: track.artworkPath,
          artworkUrl: track.artworkUrl,
          size: 44,
          radius: 10,
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            color:
                isCurrent ? BttColors.accentPink : BttColors.textPrimary,
          ),
        ),
        subtitle: Text(
          '${track.artist} · ${_fmtDuration(track.durationSeconds)}'
          '${isCurrent ? ' · Playing now' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isCurrent
                ? BttColors.accentPink.withValues(alpha: 0.85)
                : BttColors.textSecondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCurrent)
              const Icon(
                Icons.graphic_eq_rounded,
                color: BttColors.accentPink,
                size: 18,
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: BttColors.textSecondary,
              tooltip: 'Remove from queue',
              onPressed: onRemove,
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(
                Icons.drag_handle_rounded,
                color: BttColors.textMuted,
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
