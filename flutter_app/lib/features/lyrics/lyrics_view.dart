import 'dart:async';

import 'package:flutter/material.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/features/lyrics/lyrics_service.dart';

/// Synced-lyrics view for the fullscreen player.
///
/// Faithful port of `src/components/player/LyricsView.tsx`: loads lyrics for
/// the current track, highlights the line matching the playback position,
/// auto-scrolls it into view (paused while the user is scrolling, resuming
/// 2.5s after the last user scroll), falls back to plain lyrics, and shows
/// distinct empty states for "not found" and "offline". Tapping a synced
/// line seeks to it via [onSeek]. Dark-only, Plus Jakarta Sans via the app
/// theme, BT gradient palette (violet → magenta → pink-red).
class LyricsView extends StatefulWidget {
  final Track track;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final LyricsService lyricsService;
  final VoidCallback? onClose;

  const LyricsView({
    super.key,
    required this.track,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.lyricsService,
    this.onClose,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const _userScrollResumeDelay = Duration(milliseconds: 2500);

  final ScrollController _scrollController = ScrollController();

  SongLyrics? _lyrics;
  bool _isLoading = false;
  bool _hasSearched = false;
  bool _isOffline = false;
  bool _userScrolling = false;
  Timer? _scrollResumeTimer;
  int _lastScrolledIndex = -1;
  List<GlobalKey> _lineKeys = const [];

  /// Monotonic load generation: a slow fetch for a previous track must
  /// never overwrite the lyrics of the track that replaced it (the React
  /// view guards this with its `isCancelled` flag; the Flutter view had
  /// no equivalent until this guard).
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _loadLyrics();
    }
  }

  @override
  void dispose() {
    _scrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _hasSearched = false;
      _isOffline = false;
    });
    final result = await widget.lyricsService.fetchLyricsForTrack(
      widget.track.id,
      widget.track.title,
      widget.track.artist,
      durationSeconds:
          widget.duration.inSeconds > 0 ? widget.duration.inSeconds : null,
      forceRefresh: forceRefresh,
    );
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _lyrics = result;
      _isLoading = false;
      _hasSearched = true;
      _isOffline =
          result == null &&
          widget.lyricsService.lastFetchStatus == LyricsFetchStatus.offline;
      _lastScrolledIndex = -1;
      _lineKeys = List.generate(
        result?.syncedLyrics?.length ?? 0,
        (_) => GlobalKey(),
      );
    });
    // A new track's lyrics open at the top: the shared ScrollController
    // otherwise keeps the previous track's scroll offset, so a scrolled
    // list would open mid-song. Registered before the build's
    // ensure-visible callback, so auto-scroll to the active line (synced
    // lyrics) still wins for the current position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _loadGeneration) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  int get _activeIndex {
    final synced = _lyrics?.syncedLyrics;
    if (synced == null || synced.isEmpty) return -1;
    return activeLyricLineIndex(
      synced,
      widget.position.inMilliseconds / 1000.0,
    );
  }

  void _maybeScrollToActive() {
    final index = _activeIndex;
    if (index < 0 || _userScrolling || index == _lastScrolledIndex) return;
    _lastScrolledIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= _lineKeys.length) return;
      final context = _lineKeys[index].currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      _userScrolling = true;
      _scrollResumeTimer?.cancel();
      _scrollResumeTimer = Timer(_userScrollResumeDelay, () {
        if (!mounted) return;
        // Reset the scrolled index so the next build re-centres on the
        // active line: without this, auto-scroll stayed suppressed after
        // the user paused scrolling, because the active index already
        // equalled _lastScrolledIndex and _maybeScrollToActive returned
        // early until the next line change.
        setState(() {
          _userScrolling = false;
          _lastScrolledIndex = -1;
        });
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _maybeScrollToActive();

    return Container(
      decoration: BoxDecoration(
        color: BttColors.bgElevated,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: BttColors.accentPink.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildBody(context)),
          if (_lyrics != null) _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: BttColors.accentPink,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.mic_rounded,
              size: 15,
              color: BttColors.bgObsidian,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'LYRICS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.6,
                  color: BttColors.accentPink,
                ),
          ),
          if (_lyrics?.hasSyncedLyrics ?? false) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BttColors.accentPink,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'SYNCED',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: BttColors.bgObsidian,
                ),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: _isLoading
                  ? BttColors.textMuted
                  : BttColors.accentPink,
            ),
            tooltip: 'Refresh lyrics',
            onPressed:
                _isLoading ? null : () => _loadLyrics(forceRefresh: true),
          ),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: BttColors.textMuted),
              tooltip: 'Close lyrics',
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: BttColors.accentPink,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Searching lyrics for ${widget.track.title}…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final lyrics = _lyrics;
    if (lyrics != null && lyrics.hasSyncedLyrics) {
      return NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: lyrics.syncedLyrics!.length,
          itemBuilder: (context, index) {
            final line = lyrics.syncedLyrics![index];
            final isActive = index == _activeIndex;
            final isPast = index < _activeIndex;
            return GestureDetector(
              key: _lineKeys[index],
              onTap: () => widget.onSeek(
                Duration(milliseconds: (line.time * 1000).round()),
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: isActive
                    ? BoxDecoration(
                        color: BttColors.accentPink.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: Text(
                  line.text,
                  style: TextStyle(
                    fontSize: isActive ? 21 : 17,
                    fontWeight:
                        isActive ? FontWeight.w800 : FontWeight.w500,
                    height: 1.4,
                    color: isActive
                        ? BttColors.accentPink
                        : isPast
                            ? BttColors.textSecondary
                            : BttColors.textMuted,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    if (lyrics != null && lyrics.hasPlainLyrics) {
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: lyrics.plainLyrics!.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            lyrics.plainLyrics![index],
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  height: 1.5,
                ),
          ),
        ),
      );
    }

    if (_hasSearched) {
      return _buildEmptyState(context);
    }

    return const SizedBox.shrink();
  }

  Widget _buildEmptyState(BuildContext context) {
    final offline = _isOffline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: BttColors.accentPink.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                offline ? Icons.wifi_off_rounded : Icons.music_note_rounded,
                size: 26,
                color: BttColors.accentPink,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              offline ? "You're offline" : "Couldn't find lyrics",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              offline
                  ? 'Lyrics need an internet connection. Check your connection and try again.'
                  : 'Lyrics for "${widget.track.title}" are not yet catalogued on LRCLIB.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : () => _loadLyrics(forceRefresh: true),
              style: FilledButton.styleFrom(
                backgroundColor: BttColors.accentPink,
                foregroundColor: BttColors.bgObsidian,
              ),
              child: Text(offline ? 'Try Again' : 'Search Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final lyrics = _lyrics!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: BttColors.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Source: ${lyrics.source}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (lyrics.hasSyncedLyrics)
            const Text(
              'Tap line to jump',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: BttColors.accentPink,
              ),
            ),
        ],
      ),
    );
  }
}
