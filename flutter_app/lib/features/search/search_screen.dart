import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/track_tile.dart';
import 'package:btmu/data/models/x2_result.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final AudioPlayer _previewPlayer = AudioPlayer();

  List<X2Result> _onlineResults = [];
  Map<String, String> _providerErrors = {};
  bool _searchingOnline = false;
  String? _error;
  String? _playingPreviewUrl;

  Future<void> _runOnlineSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _onlineResults = [];
        _providerErrors = {};
        _error = null;
      });
      return;
    }
    setState(() {
      _searchingOnline = true;
      _error = null;
      _providerErrors = {};
    });
    try {
      final response = await ref.read(x2SearchEngineProvider).search(query);
      if (mounted) {
        setState(() {
          _onlineResults = response.results;
          _providerErrors = response.providerErrors;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _searchingOnline = false);
    }
  }

  Future<void> _togglePreview(String url) async {
    try {
      if (_playingPreviewUrl == url) {
        await _previewPlayer.stop();
        if (mounted) setState(() => _playingPreviewUrl = null);
        return;
      }
      if (mounted) setState(() => _playingPreviewUrl = url);
      await _previewPlayer.setUrl(url);
      await _previewPlayer.play();
    } catch (e) {
      if (mounted) {
        setState(() => _playingPreviewUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview stream failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _ctrl.text.trim().toLowerCase();
    final localTracks = ref.watch(libraryTracksProvider).valueOrNull ?? [];
    final localMatches = query.isEmpty
        ? localTracks.take(5).toList()
        : localTracks
            .where((t) =>
                t.title.toLowerCase().contains(query) ||
                t.artist.toLowerCase().contains(query) ||
                t.album.toLowerCase().contains(query))
            .toList();
    final handler = ref.watch(audioHandlerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Universal Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: _runOnlineSearch,
              decoration: InputDecoration(
                hintText: 'Search your library & X2 discovery',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded, color: BttColors.cyanAccent),
                  onPressed: () => _runOnlineSearch(_ctrl.text),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              children: [
                Text(
                  'LOCAL OFFLINE LIBRARY (${localMatches.length})',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: BttColors.greenAccent,
                        letterSpacing: 1.1,
                      ),
                ),
                const SizedBox(height: 8),
                if (localMatches.isEmpty)
                  Text(
                    'No matching local files on device.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  ...localMatches.asMap().entries.map(
                        (e) => TrackTile(
                          track: e.value,
                          isCurrent: handler.currentTrack?.id == e.value.id,
                          onTap: () => handler.setTrackQueueAndPlay(
                            localMatches,
                            initialIndex: e.key,
                          ),
                        ),
                      ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ONLINE X2 DISCOVERY (${_onlineResults.length})',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: BttColors.cyanAccent,
                            letterSpacing: 1.1,
                          ),
                    ),
                    if (_searchingOnline)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: BttColors.danger)),
                if (_providerErrors.isNotEmpty && !_searchingOnline)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: BttColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: BttColors.warning.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _providerErrors.entries
                          .map(
                            (e) => Text(
                              '${e.key}: ${e.value.replaceFirst(RegExp(r'^AppFailure\([^)]+\):\s*'), '')}',
                              style: const TextStyle(color: BttColors.warning, fontSize: 11.5),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                if (_onlineResults.isEmpty && !_searchingOnline)
                  Text(
                    'Tap search on keyboard or arrow button to query X2 online providers.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  ..._onlineResults.map((res) {
                    final hasPreviewOnly =
                        !res.downloadAuthorized && res.audioAvailable && res.audioUrl != null;
                    final playing = hasPreviewOnly && _playingPreviewUrl == res.audioUrl;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(res.title),
                      subtitle: Text('${res.artist} · ${res.providerLabel}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasPreviewOnly)
                            IconButton(
                              tooltip: playing ? 'Stop 30s Preview' : 'Play 30s Preview',
                              icon: Icon(
                                playing ? Icons.stop_circle_rounded : Icons.play_circle_rounded,
                                color: BttColors.goldAccent,
                              ),
                              onPressed: () => _togglePreview(res.audioUrl!),
                            ),
                          if (res.downloadAuthorized)
                            IconButton(
                              tooltip: 'Download Offline',
                              icon: const Icon(Icons.download_rounded, color: BttColors.cyanAccent),
                              onPressed: () {
                                ref.read(downloadManagerProvider.notifier).enqueueX2Download(res);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Queued ${res.title}')),
                                );
                              },
                            )
                          else
                            IconButton(
                              tooltip: 'Open in X2 Acquisition',
                              icon: const Icon(Icons.travel_explore_rounded,
                                  color: BttColors.textMuted),
                              onPressed: () {
                                ref.read(pendingX2SearchQueryProvider.notifier).state =
                                    '${res.artist} ${res.title}'.trim();
                                Navigator.of(context).pop();
                                ref.read(currentTabIndexProvider.notifier).state = BttTab.x2;
                              },
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
