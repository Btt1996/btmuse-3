import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/btt_motion.dart';
import 'package:btmu/app/btt_page_route.dart';
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

class _FullScreenPlayerState extends ConsumerState<FullScreenPlayer>
    with SingleTickerProviderStateMixin {
  _PlayerTab _tab = _PlayerTab.player;

  // Created once per player lifetime; no provider registration exists for
  // lyrics yet (app_providers.dart is untouched by this change). Wiring a
  // lyricsServiceProvider there is a one-line follow-up for the coordinator.
  final LyricsService _lyricsService = LyricsService();

  /// Spring for snap-back and fling-out. Damping ratio
  /// ζ = 28 / (2·√300) ≈ 0.81: slightly underdamped, so it settles fast
  /// with no visible bounce — iOS-sheet-like, not springy.
  static const SpringDescription _kDismissSpring = SpringDescription(
    mass: 1.0,
    stiffness: 300.0,
    damping: 28.0,
  );

  /// Dismiss when the sheet has travelled 25% of its height, or the
  /// downward release velocity exceeds 500 px/s (Item 2).
  static const double _kDismissFraction = 0.25;
  static const double _kDismissVelocity = 500.0;

  /// Drag fraction (of sheet height) at which the drag visuals saturate
  /// (artwork scale 0.94, sheet opacity 0.85, dim, radius, tilt). 0.35 puts
  /// full feedback just past the 0.25 dismiss threshold, so the gesture
  /// reads clearly before the point of no return.
  static const double _kDragVisualSaturation = 0.35;

  /// Entrance: artwork 0.92 → 1.0 + fade-in, 350 ms, easeOutCubic.
  late final AnimationController _entranceController;

  /// Dismiss drag: value 0..1 = drag offset as a fraction of sheet height.
  /// Driven directly by the gesture; animated only via [SpringSimulation]
  /// (animateWith), so fling duration is velocity-aware by construction.
  late final AnimationController _dragController;

  /// One listenable for the artwork builder (entrance + drag).
  late final Listenable _artworkAnimations;

  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: BttMotion.entranceDuration,
    );
    // Duration is nominal: this controller is only ever driven with
    // animateWith(SpringSimulation), which ignores it.
    _dragController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _artworkAnimations =
        Listenable.merge([_entranceController, _dragController]);
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _dragController.dispose();
    super.dispose();
  }

  double _sheetHeightOf(BuildContext context) =>
      MediaQuery.of(context).size.height * 0.94;

  // -- Dismiss gesture --------------------------------------------------------

  void _onDragStart(DragStartDetails details) {
    // A fresh drag wins over a spring-back still in flight.
    _dragController.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final height = _sheetHeightOf(context);
    if (height <= 0) return;
    _dragController.value =
        (_dragController.value + details.delta.dy / height).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isDismissing) return;
    final height = _sheetHeightOf(context);
    final offset = _dragController.value * height;
    final velocity = details.primaryVelocity ?? 0.0;
    if (offset > height * _kDismissFraction || velocity > _kDismissVelocity) {
      _flingOut(velocity / height);
    } else if (_dragController.value > 0.0 || velocity < 0.0) {
      _springBack(velocity / height);
    }
  }

  void _onDragCancel() {
    if (!_isDismissing && _dragController.value > 0.0) _springBack(0.0);
  }

  Future<void> _flingOut(double velocity) async {
    if (_isDismissing) return;
    _isDismissing = true;
    HapticFeedback.mediumImpact();
    final simulation = SpringSimulation(
      _kDismissSpring,
      _dragController.value,
      1.0,
      velocity.clamp(-4.0, 4.0),
    );
    try {
      await _dragController.animateWith(simulation);
    } catch (_) {
      // Controller disposed mid-flight (e.g. barrier-tap dismiss): ignore.
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _springBack(double velocity) async {
    final simulation = SpringSimulation(
      _kDismissSpring,
      _dragController.value,
      0.0,
      velocity.clamp(-4.0, 4.0),
    );
    try {
      await _dragController.animateWith(simulation);
    } catch (_) {
      // Disposed mid-flight: nothing to restore.
    }
  }

  /// Vertical-drag detector for the non-scrollable regions. The lyrics
  /// ListView is never wrapped in this: it must keep scrolling.
  Widget _buildDismissDetector({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onVerticalDragCancel: _onDragCancel,
      child: child,
    );
  }

  /// Hero flight shuttle: renders the artwork without any of the sheet's
  /// clipping, and morphs the corner radius 10 (mini) ↔ 26 (fullscreen)
  /// along the flight so the morph reads as one continuous shape change.
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
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final audioSettings = ref.watch(audioSettingsProvider);

    // The StreamBuilder subtree is passed as AnimatedBuilder.child so the
    // drag animation never rebuilds it — only the transform/opacity/dim
    // above it repaints each frame.
    return AnimatedBuilder(
      animation: _dragController,
      builder: (context, child) {
        final sheetHeight = _sheetHeightOf(context);
        final dragOffset = _dragController.value * sheetHeight;
        final dragProgress =
            (_dragController.value / _kDragVisualSaturation).clamp(0.0, 1.0);
        return SizedBox(
          height: sheetHeight,
          child: Stack(
            children: [
              // Drag-following dim: sits behind the sheet, so as the sheet
              // drops it darkens exactly the background being revealed.
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color:
                        Colors.black.withValues(alpha: 0.45 * dragProgress),
                  ),
                ),
              ),
              Opacity(
                opacity: 1.0 - 0.15 * dragProgress,
                child: Transform.translate(
                  offset: Offset(0, dragOffset),
                  child: Container(
                    height: sheetHeight,
                    decoration: BoxDecoration(
                      color: BttColors.bgObsidian,
                      borderRadius: BorderRadius.vertical(
                        // Radius eases open (28 → 36) as the sheet detaches
                        // from the screen edges.
                        top: Radius.circular(28.0 + 8.0 * dragProgress),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: child!,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    _buildDismissDetector(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_tab == _PlayerTab.player) ...[
                      Expanded(
                        // Player tab is fully non-scrollable: the whole
                        // sheet is a dismiss zone here.
                        child: _buildDismissDetector(
                          child: Column(
                            children: [
                              const Spacer(),
                              _buildArtwork(track),
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
                                        BttPageRoute<void>(
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
                                        BttPageRoute<void>(
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
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // Lyrics load lazily: LyricsView is only built (and
                      // only fetches) once this tab is opened.
                      // NOTE: the lyrics ListView is deliberately NOT wrapped
                      // in the dismiss detector — it must keep scrolling.
                      // The header above and the seek/transport block below
                      // are the dismiss zones in this tab.
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
                      _buildDismissDetector(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 14),
                            _buildSeekSection(context, handler, position, maxMs, currentMs),
                            const SizedBox(height: 14),
                            _buildTransportRow(handler, playing),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Artwork with the entrance (scale 0.92 → 1.0 + fade, 350 ms,
  /// easeOutCubic) and the drag feedback (scale → 0.94, restrained tilt and
  /// parallax lag) composed on one easing family so open, drag and dismiss
  /// feel like a single continuous motion.
  Widget _buildArtwork(Track track) {
    return AnimatedBuilder(
      animation: _artworkAnimations,
      builder: (context, child) {
        final easedEntrance =
            BttMotion.entranceCurve.transform(_entranceController.value);
        final entranceScale = 0.92 + 0.08 * easedEntrance;
        final dragProgress =
            (_dragController.value / _kDragVisualSaturation).clamp(0.0, 1.0);
        final dragScale = 1.0 - 0.06 * dragProgress;
        final dragOffset = _dragController.value * _sheetHeightOf(context);
        return Opacity(
          opacity: easedEntrance,
          child: Transform.scale(
            scale: entranceScale * dragScale,
            child: Transform.translate(
              // Parallax lag: the artwork trails the sheet by 6% of the
              // drag, so it feels weighted rather than glued on.
              offset: Offset(0, -dragOffset * 0.06),
              child: Transform.rotate(
                // Restrained tilt: 0.02 rad (~1.1°) at full drag.
                angle: 0.02 * dragProgress,
                child: child,
              ),
            ),
          ),
        );
      },
      child: Hero(
        tag: 'artwork-${track.id}',
        flightShuttleBuilder: _artworkFlightShuttle,
        child: BttArtwork(
          artworkPath: track.artworkPath,
          artworkUrl: track.artworkUrl,
          size: MediaQuery.of(context).size.width * 0.74,
          radius: 26,
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
          onPressed: () {
            HapticFeedback.lightImpact();
            handler.skipToPrevious();
          },
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
          icon: const Icon(Icons.skip_next_rounded, size: 38),
          onPressed: () {
            HapticFeedback.lightImpact();
            handler.skipToNext();
          },
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
