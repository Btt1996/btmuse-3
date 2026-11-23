import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/features/player/full_screen_player.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  /// Same flight shuttle as FullScreenPlayer: renders the artwork without
  /// any of the sheet's clipping, and morphs the corner radius 10 (mini)
  /// ↔ 26 (fullscreen) along the flight so the morph reads as one
  /// continuous shape change.
  static Widget _artworkFlightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final hero = toHeroContext.widget as Hero;
    final radius = Tween<double>(
      begin: flightDirection == HeroFlightDirection.push ? 10.0 : 26.0,
      end: flightDirection == HeroFlightDirection.push ? 26.0 : 10.0,
    ).animate(animation);
    return AnimatedBuilder(
      animation: radius,
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius.value),
          child: child,
        ),
      ),
      child: hero.child,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);

    return StreamBuilder<Track?>(
      stream: handler.currentTrackStream,
      initialData: handler.currentTrack,
      builder: (context, trackSnap) {
        final track = trackSnap.data;
        if (track == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, stateSnap) {
            final state = stateSnap.data;
            final playing = state?.playing ?? false;
            // Gradient micro-scrubber progress (same duration fallback
            // as the fullscreen player).
            final position = state?.updatePosition ?? Duration.zero;
            final totalSeconds = track.durationSeconds > 0
                ? track.durationSeconds
                : (handler.mediaItem.value?.duration?.inSeconds ?? 180);
            final maxMs =
                (totalSeconds * 1000).toDouble().clamp(1000.0, 36000000.0);
            final progress = maxMs > 0
                ? (position.inMilliseconds.toDouble().clamp(0.0, maxMs) / maxMs)
                : 0.0;

            return GestureDetector(
              onTap: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  // The fullscreen player owns the dismiss gesture itself
                  // (spring snap-back / fling-out); the sheet's native drag
                  // must not double-handle it.
                  enableDrag: false,
                  builder: (_) => const FullScreenPlayer(),
                );
              },
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: BttColors.bgCardHighlight,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: BttColors.borderStrong),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Hero(
                          tag: 'artwork-${track.id}',
                          flightShuttleBuilder: _artworkFlightShuttle,
                          child: BttArtwork(
                            artworkPath: track.artworkPath,
                            artworkUrl: track.artworkUrl,
                            size: 44,
                            radius: 10,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14.5),
                              ),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: BttColors.accentGradient,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x59F70E42),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              if (playing) {
                                handler.pause();
                              } else {
                                handler.play();
                              }
                            },
                          ),
                        ),
                        IconButton(
                          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: BttColors.textSecondary,
                            size: 26,
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            handler.skipToNext();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(
                          children: [
                            Container(height: 3, color: BttColors.borderStrong),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress,
                              child: Container(
                                height: 3,
                                decoration: const BoxDecoration(
                                  gradient: BttColors.accentGradient,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
