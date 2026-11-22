import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/core/services/btt_audio_handler.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/features/audio_settings/audio_settings_screen.dart';
import 'package:btmu/features/lyrics/lyrics_service.dart';
import 'package:btmu/features/lyrics/lyrics_view.dart';
import 'package:btmu/features/smart_remix/smart_remix_screen.dart';

enum _PlayerTab { player, lyrics }

class FullScreenPlayer extends ConsumerStatefulWidget {
  const FullScreenPlayer({super.key});

  @override
  ConsumerState<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends ConsumerState<FullScreenPlayer> {
  _PlayerTab _tab = _PlayerTab.player;

  // Created once per player lifetime; no provider registration exists for
  // lyrics yet (app_providers.dart is untouched by this change). Wiring a
  // lyricsServiceProvider there is a one-line follow-up for the coordinator.
  final LyricsService _lyricsService = LyricsService();

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final audioSettings = ref.watch(audioSettingsProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.94,
      decoration: const BoxDecoration(
        color: BttColors.bgObsidian,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: StreamBuilder<Track?>(
          stream: handler.currentTrackStream,
          initialData: handler.currentTrack,
          builder: (context, trackSnap) {
            final track = trackSnap.data;
            if (track == null) {
              return const Center(child: Text('No track selected'));
            }

            return StreamBuilder<PlaybackState>(
              stream: handler.playbackState,
              builder: (context, stateSnap) {
                final state = stateSnap.data;
                final playing = state?.playing ?? false;
                final position = state?.updatePosition ?? Duration.zero;
                final totalSeconds = track.durationSeconds > 0
                    ? track.durationSeconds
                    : (handler.mediaItem.value?.duration?.inSeconds ?? 180);
                final maxMs = (totalSeconds * 1000).toDouble().clamp(1000.0, 36000000.0);
                final currentMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: BttColors.borderStrong,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Text(
                            'NOW PLAYING',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  letterSpacing: 1.4,
                                  color: BttColors.textSecondary,
                                ),
                          ),
                          IconButton(
                            icon: Icon(
                              track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: track.isFavorite ? BttColors.goldAccent : BttColors.textSecondary,
                            ),
                            onPressed: () async {
                              await ref
                                  .read(libraryRepositoryProvider)
                                  .toggleFavorite(track.id, !track.isFavorite);
                              ref.invalidate(libraryTracksProvider);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildTabSwitcher(context),
                      const SizedBox(height: 14),
                      if (_tab == _PlayerTab.player) ...[
                        const Spacer(),
                        BttArtwork(
                          artworkPath: track.artworkPath,
                          artworkUrl: track.artworkUrl,
                          size: MediaQuery.of(context).size.width * 0.74,
                          radius: 26,
                        ),
                        const Spacer(),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${track.artist}  ·  ${track.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildSeekSection(context, handler, position, maxMs, currentMs),
                        const SizedBox(height: 14),
                        _buildTransportRow(handler, playing),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const AudioSettingsScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.graphic_eq_rounded, color: BttColors.goldAccent),
                              label: Text(
                                'Boost ${audioSettings.boostPercent}%',
                                style: const TextStyle(color: BttColors.textPrimary),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const SmartRemixScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.auto_awesome_rounded, color: BttColors.cyanAccent),
                              label: const Text(
                                'Smart Remix',
                                style: TextStyle(color: BttColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ] else ...[
                        // Lyrics load lazily: LyricsView is only built (and
                        // only fetches) once this tab is opened.
                        Expanded(
                          child: LyricsView(
                            track: track,
                            position: position,
                            duration: Duration(seconds: totalSeconds),
                            onSeek: (target) => handler.seek(target),
                            lyricsService: _lyricsService,
                            onClose: () => setState(() => _tab = _PlayerTab.player),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildSeekSection(context, handler, position, maxMs, currentMs),
                        const SizedBox(height: 14),
                        _buildTransportRow(handler, playing),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabSwitcher(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BttColors.borderSubtle),
      ),
      child: Row(
        children: [
          _buildTabButton(
            label: 'Player',
            icon: Icons.music_note_rounded,
            selected: _tab == _PlayerTab.player,
            onTap: () => setState(() => _tab = _PlayerTab.player),
          ),
          _buildTabButton(
            label: 'Lyrics',
            icon: Icons.mic_rounded,
            selected: _tab == _PlayerTab.lyrics,
            onTap: () => setState(() => _tab = _PlayerTab.lyrics),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? BttColors.cyanAccent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? BttColors.cyanAccent : BttColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? BttColors.cyanAccent : BttColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeekSection(
    BuildContext context,
    BttAudioHandler handler,
    Duration position,
    double maxMs,
    double currentMs,
  ) {
    return Column(
      children: [
        Slider(
          value: currentMs,
          min: 0.0,
          max: maxMs,
          onChanged: (v) => handler.seek(Duration(milliseconds: v.round())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(position), style: Theme.of(context).textTheme.labelSmall),
            Text(
              _fmt(Duration(milliseconds: maxMs.round())),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransportRow(BttAudioHandler handler, bool playing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(
            Icons.shuffle_rounded,
            color: handler.isShuffleEnabled
                ? BttColors.cyanAccent
                : BttColors.textMuted,
          ),
          onPressed: () => handler.setShuffleMode(
            handler.isShuffleEnabled
                ? AudioServiceShuffleMode.none
                : AudioServiceShuffleMode.all,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 38),
          onPressed: () => handler.skipToPrevious(),
        ),
        Container(
          width: 68,
          height: 68,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [BttColors.cyanAccent, BttColors.greenAccent],
            ),
          ),
          child: IconButton(
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: BttColors.bgObsidian,
              size: 36,
            ),
            onPressed: () => playing ? handler.pause() : handler.play(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, size: 38),
          onPressed: () => handler.skipToNext(),
        ),
        IconButton(
          icon: Icon(
            handler.repeatMode == AudioServiceRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: handler.repeatMode == AudioServiceRepeatMode.none
                ? BttColors.textMuted
                : BttColors.goldAccent,
          ),
          onPressed: () {
            final next = switch (handler.repeatMode) {
              AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
              AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
              _ => AudioServiceRepeatMode.none,
            };
            handler.setRepeatMode(next);
          },
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
