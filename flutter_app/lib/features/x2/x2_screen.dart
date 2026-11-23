import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:btmu/app/btt_page_route.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/player/mini_player.dart';
import 'package:btmu/features/telegram/telegram_screen.dart';

class X2Screen extends ConsumerStatefulWidget {
  const X2Screen({super.key});

  @override
  ConsumerState<X2Screen> createState() => _X2ScreenState();
}

class _X2ScreenState extends ConsumerState<X2Screen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final AudioPlayer _previewPlayer = AudioPlayer();

  bool _loading = false;
  List<X2Result> _results = [];
  Map<String, String> _providerErrors = {};
  bool _isUrlLookup = false;
  String _selectedFilter = 'all'; // all, authorized, metadata
  String? _playingPreviewUrl;
  // v3.0.5, item 11: download feedback is an inline line, never a
  // SnackBar overlaying the player.
  String? _status;

  Future<void> _executeSearch(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _loading = true;
      _providerErrors = {};
      _status = null;
    });
    try {
      final response = await ref.read(x2SearchEngineProvider).search(trimmed);
      if (mounted) {
        setState(() {
          _results = response.results;
          _providerErrors = response.providerErrors;
          _isUrlLookup = response.isUrlLookup;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePreview(String previewUrl) async {
    try {
      if (_playingPreviewUrl == previewUrl) {
        await _previewPlayer.stop();
        if (mounted) setState(() => _playingPreviewUrl = null);
        return;
      }
      if (mounted) setState(() => _playingPreviewUrl = previewUrl);
      await _previewPlayer.setUrl(previewUrl);
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
    _queryCtrl.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingQuery = ref.watch(pendingX2SearchQueryProvider);
    if (pendingQuery != null && pendingQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingX2SearchQueryProvider.notifier).state = null;
        _queryCtrl.text = pendingQuery;
        _executeSearch(pendingQuery);
      });
    }

    final visibleResults = _results.where((r) {
      if (_selectedFilter == 'authorized') return r.downloadAuthorized;
      if (_selectedFilter == 'metadata') return !r.downloadAuthorized;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('X2 Acquisition Engine'),
        actions: [
          IconButton(
            tooltip: 'Open Import Center',
            icon: Icon(Icons.add_circle_outline_rounded, color: BttColors.accentPink),
            onPressed: () {
              // X2 is a pushed route now: reveal the Import Center tab
              // underneath instead of switching tabs behind this route.
              ref.read(currentTabIndexProvider.notifier).state = BttTab.importCenter;
              Navigator.of(context).pop();
            },
          ),
          IconButton(
            tooltip: 'Telegram Audio Import',
            icon: Icon(Icons.send_rounded, color: BttColors.accentMagenta),
            onPressed: () {
              Navigator.of(context).push(
                BttPageRoute<void>(builder: (_) => const TelegramScreen()),
              );
            },
          ),
        ],
      ),
      // v3.0.5, item 11: the player stays visible during import flows.
      bottomNavigationBar: const MiniPlayer(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _queryCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _executeSearch,
              decoration: InputDecoration(
                hintText: 'Song, artist, VK / YouTube / SoundCloud / Audius / RSS URL',
                prefixIcon: const Icon(Icons.travel_explore_rounded),
                suffixIcon: IconButton(
                  icon: Icon(Icons.search_rounded, color: BttColors.accentPink),
                  onPressed: () => _executeSearch(_queryCtrl.text),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _filterButton('All (${_results.length})', 'all'),
                const SizedBox(width: 8),
                _filterButton(
                  'Authorized Downloads (${_results.where((r) => r.downloadAuthorized).length})',
                  'authorized',
                ),
                const SizedBox(width: 8),
                _filterButton('Metadata / Previews', 'metadata'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: BttColors.accentPink,
                      ),
                ),
              ),
            ),
          if (_providerErrors.isNotEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                width: double.infinity,
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
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${e.key}: ${e.value.replaceFirst(RegExp(r'^AppFailure\([^)]+\):\s*'), '')}',
                            style: TextStyle(color: BttColors.warning, fontSize: 11.5),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          Expanded(
            child: visibleResults.isEmpty && !_loading
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: BttColors.bgCard,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: BttColors.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Zero-Key Multi-Source Acquisition',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Prioritizes VK public link inspection, Telegram audio import, metadata-only YouTube/SoundCloud lookup, permissionless Audius 320kbps streams, Deezer/iTunes 30s verification previews, and Podcast RSS / Direct MP3/M4A/FLAC URLs—with ZERO mandatory developer API keys.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  BttPageRoute<void>(
                                    builder: (_) => const TelegramScreen(),
                                  ),
                                );
                              },
                              icon: Icon(Icons.send_rounded, color: BttColors.accentMagenta),
                              label: const Text('Import From Telegram Bot'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                    itemCount: visibleResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final r = visibleResults[idx];
                      final hasPreviewOnly =
                          !r.downloadAuthorized && r.audioAvailable && r.audioUrl != null;
                      return _X2ResultCard(
                        result: r,
                        highlightUrlLookup: _isUrlLookup && idx == 0,
                        isPreviewPlaying:
                            hasPreviewOnly && _playingPreviewUrl == r.audioUrl,
                        onTogglePreview:
                            hasPreviewOnly ? () => _togglePreview(r.audioUrl!) : null,
                        onDownload: () {
                          ref.read(downloadManagerProvider.notifier).enqueueX2Download(r);
                          setState(() => _status = 'Queued "${r.title}" for acquisition.');
                        },
                        onFindAuthorizedMatch: () {
                          final q = '${r.artist} ${r.title}'.trim();
                          _queryCtrl.text = q;
                          _executeSearch(q);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String label, String key) {
    final selected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedFilter = key),
      selectedColor: BttColors.accentPink.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: selected ? BttColors.accentPink : BttColors.textSecondary,
        fontSize: 12.5,
      ),
    );
  }
}

class _X2ResultCard extends StatelessWidget {
  final X2Result result;
  final bool highlightUrlLookup;
  final bool isPreviewPlaying;
  final VoidCallback? onTogglePreview;
  final VoidCallback onDownload;
  final VoidCallback onFindAuthorizedMatch;

  const _X2ResultCard({
    required this.result,
    required this.highlightUrlLookup,
    required this.isPreviewPlaying,
    required this.onTogglePreview,
    required this.onDownload,
    required this.onFindAuthorizedMatch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlightUrlLookup ? BttColors.bgCardHighlight : BttColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: result.downloadAuthorized
              ? BttColors.success.withValues(alpha: 0.35)
              : BttColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BttArtwork(artworkUrl: result.artworkUrl, size: 58, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${result.artist}  ·  ${result.providerLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.authorizationNote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: result.downloadAuthorized
                                ? BttColors.success
                                : BttColors.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onTogglePreview != null)
                OutlinedButton.icon(
                  onPressed: onTogglePreview,
                  icon: Icon(
                    isPreviewPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: BttColors.accentMagenta,
                    size: 18,
                  ),
                  label: Text(isPreviewPlaying ? 'Stop Preview' : 'Play 30s Preview'),
                ),
              if (result.downloadAuthorized)
                FilledButton.icon(
                  onPressed: onDownload,
                  style: FilledButton.styleFrom(
                    backgroundColor: BttColors.accentPink,
                    foregroundColor: BttColors.bgObsidian,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('Download ${result.format ?? 'Audio'}'),
                )
              else
                OutlinedButton.icon(
                  onPressed: onFindAuthorizedMatch,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Find Authorized Source'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
