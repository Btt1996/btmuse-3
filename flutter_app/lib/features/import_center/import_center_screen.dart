import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:btmu/app/btt_page_route.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/core/config/x2_config.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/data/models/download_task.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/downloads/download_history_screen.dart';
import 'package:btmu/features/search/search_screen.dart';
import 'package:btmu/features/settings/settings_screen.dart';
import 'package:btmu/features/telegram/telegram_screen.dart';
import 'package:btmu/features/x2/providers/direct_url_provider.dart';
import 'package:btmu/features/x2/providers/soundcloud_provider.dart';
import 'package:btmu/features/x2/providers/spotify_metadata_provider.dart';
import 'package:btmu/features/x2/providers/vk_provider.dart';
import 'package:btmu/features/x2/providers/youtube_provider.dart';
import 'package:btmu/features/x2/youtube_bridge_service.dart';

class ImportCenterScreen extends ConsumerStatefulWidget {
  const ImportCenterScreen({super.key});

  @override
  ConsumerState<ImportCenterScreen> createState() => _ImportCenterScreenState();
}

class _ImportCenterScreenState extends ConsumerState<ImportCenterScreen> {
  bool _busyLocal = false;
  int _batchDone = 0;
  int _batchTotal = 0;
  String? _lastStatus;

  Future<void> _importLocal({required bool allowMultiple}) async {
    setState(() {
      _busyLocal = true;
      _batchDone = 0;
      _batchTotal = 0;
      _lastStatus = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg'],
        allowMultiple: allowMultiple,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _busyLocal = false);
        return;
      }

      final repo = ref.read(libraryRepositoryProvider);
      final files = result.files.where((f) => f.path != null).toList();
      if (mounted) setState(() => _batchTotal = files.length);

      var imported = 0;
      final failures = <String>[];
      var lastTitle = '';
      var lastDuration = 0;
      var hasArtwork = false;

      for (final pf in files) {
        try {
          final track = await repo.importFileIntoLibrary(
            sourceFile: File(pf.path!),
            rawTitle: p.basenameWithoutExtension(pf.name),
            sourceProvider: 'local_file',
          );
          imported++;
          lastTitle = track.title;
          lastDuration = track.durationSeconds;
          hasArtwork = track.artworkPath != null;
        } catch (e) {
          failures.add('${pf.name}: $e');
        }
        if (mounted) setState(() => _batchDone++);
      }

      ref.invalidate(libraryTracksProvider);
      ref.invalidate(storageStatsProvider);

      if (!mounted) return;
      final summary = imported == 1 && !allowMultiple
          ? 'Imported "$lastTitle" (${lastDuration}s${hasArtwork ? ' · cover embedded' : ''}).'
          : 'Imported $imported of ${files.length} audio file(s)${failures.isNotEmpty ? ' · ${failures.length} skipped' : ''}.';
      setState(() => _lastStatus = failures.isEmpty ? summary : '$summary\n${failures.first}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(summary)));
    } catch (e) {
      if (mounted) {
        setState(() => _lastStatus = 'File import failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyLocal = false);
    }
  }

  void _openVkSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BttColors.bgElevated,
      builder: (_) => const _VkImportSheet(),
    );
  }

  void _openYoutubeSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BttColors.bgElevated,
      builder: (_) => const _YoutubeImportSheet(),
    );
  }

  void _openSoundCloudSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BttColors.bgElevated,
      builder: (_) => const _SoundCloudImportSheet(),
    );
  }

  void _openSpotifySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BttColors.bgElevated,
      builder: (_) => const _SpotifyImportSheet(),
    );
  }

  void _openDirectUrlSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BttColors.bgElevated,
      builder: (_) => const _DirectUrlImportSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadManagerProvider);
    final activeDownloads = downloads.where((d) => d.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Center'),
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
            tooltip: 'Downloads Queue',
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
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BttColors.bgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BttColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All Audio Sources in One Place',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Import offline tracks from iPhone Files, Telegram bots, direct URLs/RSS podcasts, VK, SoundCloud, YouTube discovery, X1 song recognition, and X2 open acquisition.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_busyLocal && _batchTotal > 0) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _batchDone / _batchTotal),
                  const SizedBox(height: 4),
                  Text(
                    'Importing & extracting metadata: $_batchDone / $_batchTotal',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
                if (_lastStatus != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _lastStatus!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: BttColors.accentPink,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader('LOCAL IPHONE STORAGE'),
          const SizedBox(height: 8),
          _ImportOptionTile(
            icon: Icons.folder_open_rounded,
            accent: BttColors.accentPink,
            title: 'Import from iPhone Files',
            subtitle: 'Pick a single MP3, M4A, AAC, FLAC, WAV, or OGG with ID3 & artwork extraction',
            trailingLabel: 'Single',
            onTap: _busyLocal ? null : () => _importLocal(allowMultiple: false),
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.library_add_rounded,
            accent: BttColors.accentMagenta,
            title: 'Import Multiple Local Audio Files',
            subtitle: 'Batch import albums or folders with progress tracking and fingerprint indexing',
            trailingLabel: 'Batch',
            onTap: _busyLocal ? null : () => _importLocal(allowMultiple: true),
          ),
          const SizedBox(height: 18),
          _SectionHeader('MESSAGING & DIRECT WEB URLS'),
          const SizedBox(height: 8),
          _ImportOptionTile(
            icon: Icons.send_rounded,
            accent: BttColors.accentMagenta,
            title: 'Import from Telegram',
            subtitle: 'Connect your Telegram Bot token (iOS Keychain) and import bot audio & documents',
            trailingLabel: 'Bot API',
            onTap: () {
              Navigator.of(context).push(
                BttPageRoute<void>(builder: (_) => const TelegramScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.link_rounded,
            accent: BttColors.accentPink,
            title: 'Import from Supported Direct Audio URLs',
            subtitle: 'Verify direct MP3/M4A/FLAC/WAV/OGG links or Podcast RSS XML feeds and save offline',
            trailingLabel: 'Direct / RSS',
            onTap: _openDirectUrlSheet,
          ),
          const SizedBox(height: 18),
          _SectionHeader('PROVIDER SEARCH & METADATA HANDOFF'),
          const SizedBox(height: 8),
          _ImportOptionTile(
            icon: Icons.public_rounded,
            accent: BttColors.accentViolet,
            title: 'Search and Import from VK Music',
            subtitle: 'Inspect public VK audio links or search with your optional VK user session token',
            trailingLabel: 'VK',
            onTap: _openVkSheet,
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.ondemand_video_rounded,
            accent: BttColors.accentViolet,
            title: 'Search YouTube via Supported Providers',
            subtitle: 'Query configured Piped, Invidious, or X2 Companion instances + YouTube oEmbed links',
            trailingLabel: 'Piped / Inv',
            onTap: _openYoutubeSheet,
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.cloud_queue_rounded,
            accent: BttColors.accentPink,
            title: 'SoundCloud Track Lookup',
            subtitle: 'Resolve SoundCloud track URLs via zero-key oEmbed & view open-source alternatives',
            trailingLabel: 'oEmbed',
            onTap: _openSoundCloudSheet,
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.music_note_rounded,
            accent: BttColors.accentViolet,
            title: 'Import Spotify Playlist (Metadata)',
            subtitle: 'Paste a public Spotify playlist or album link, or browse a user\'s public playlists — metadata only, matched against your library',
            trailingLabel: 'Spotify',
            onTap: _openSpotifySheet,
          ),
          const SizedBox(height: 18),
          _SectionHeader('X1 & X2 INTELLIGENCE ENGINES'),
          const SizedBox(height: 8),
          _ImportOptionTile(
            icon: Icons.mic_rounded,
            accent: BttColors.accentPink,
            title: 'Identify Music Using X1',
            subtitle: 'On-device FFT constellation fingerprinting + zero-key public catalog verification',
            trailingLabel: 'X1 Engine',
            onTap: () => ref.read(currentTabIndexProvider.notifier).state = BttTab.x1,
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.travel_explore_rounded,
            accent: BttColors.accentViolet,
            title: 'Obtain Music Using X2',
            subtitle: 'Multi-source search across Audius, Deezer, Apple Open Catalog & authorized downloads',
            trailingLabel: 'X2 Engine',
            onTap: () => ref.read(currentTabIndexProvider.notifier).state = BttTab.x2,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: BttColors.textSecondary,
            letterSpacing: 1.1,
          ),
    );
  }
}

class _ImportOptionTile extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String trailingLabel;
  final VoidCallback? onTap;

  const _ImportOptionTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.trailingLabel,
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
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BttColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailingLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: accent),
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right_rounded, color: BttColors.textMuted, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VkImportSheet extends ConsumerStatefulWidget {
  const _VkImportSheet();

  @override
  ConsumerState<_VkImportSheet> createState() => _VkImportSheetState();
}

class _VkImportSheetState extends ConsumerState<_VkImportSheet> {
  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _tokenCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<X2Result> _results = [];

  @override
  void initState() {
    super.initState();
    ref.read(credentialsStoreProvider).getVkToken().then((t) {
      if (t != null && mounted) _tokenCtrl.text = t;
    });
  }

  Future<void> _runVkLookup() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
      final api = ref.read(apiClientProvider);
      final vk = VkProvider(api);
      final token = _tokenCtrl.text.trim();
      if (token.isNotEmpty) {
        await ref.read(credentialsStoreProvider).setVkToken(token);
      }

      final uri = Uri.tryParse(input);
      if (uri != null && uri.hasScheme && vk.canHandleUrl(uri)) {
        final item = await vk.resolveUrl(uri);
        if (mounted) {
          setState(() => _results = item != null ? [item] : []);
        }
      } else if (token.isNotEmpty) {
        final items = await vk.searchWithUserToken(input, vkAccessToken: token);
        if (mounted) {
          setState(() {
            _results = items;
            if (items.isEmpty) {
              _error = 'VK returned no tracks for "$input".';
            }
          });
        }
      } else {
        // F4 (Phase 4): do NOT call vk.searchTracks here. It always
        // throws AuthorizationFailure (vk_auth_required) — VK
        // permanently deprecated unauthenticated audio.search — so the
        // old `await vk.searchTracks(input);` could never show a
        // result; it only surfaced the same message through the catch
        // below. Keyword search without a token is a closed path, and
        // the sheet header already says so: set the honest message
        // directly instead of pretending a search ran. The working
        // paths stay above: paste a VK URL, or search with a token.
        if (mounted) {
          setState(() {
            _error =
                'VK keyword search needs a VK user token — unauthenticated '
                'audio.search was permanently deprecated by VK. Paste a '
                'public VK audio URL above, or search open sources in X2 instead.';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('VK Music Import & Link Lookup', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Paste a public VK link (no login needed for public OpenGraph metadata) or supply your own optional VK user token stored in Keychain. Keyword search needs a VK user token — without one, paste a VK audio link.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _inputCtrl,
                decoration: const InputDecoration(
                  hintText: 'https://vk.com/audio... or keyword (needs VK token)',
                  prefixIcon: Icon(Icons.public_rounded),
                ),
                onSubmitted: (_) => _runVkLookup(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tokenCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Optional VK User Access Token (for audio.search)',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _runVkLookup,
                icon: const Icon(Icons.search_rounded),
                label: Text(_loading ? 'Checking VK...' : 'Lookup VK Music'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: BttColors.warning, fontSize: 12.5)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    final q = _inputCtrl.text.trim();
                    Navigator.of(context).pop();
                    if (q.isNotEmpty) {
                      ref.read(pendingX2SearchQueryProvider.notifier).state = q;
                    }
                    ref.read(currentTabIndexProvider.notifier).state = BttTab.x2;
                  },
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: const Text('Search Open Sources in X2 Instead'),
                ),
              ],
              ..._results.map((r) => _SheetResultCard(result: r)),
            ],
          ),
        ),
      ),
    );
  }
}

class _YoutubeImportSheet extends ConsumerStatefulWidget {
  const _YoutubeImportSheet();

  @override
  ConsumerState<_YoutubeImportSheet> createState() => _YoutubeImportSheetState();
}

class _YoutubeImportSheetState extends ConsumerState<_YoutubeImportSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final TextEditingController _bridgeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<X2Result> _results = [];

  // Self-hosted bridge (optional, plan item 21). The bridge URL lives in
  // SecureCredentialsStore; the app never downloads YouTube audio itself
  // and does nothing here when no bridge is configured.
  bool _bridgeLoaded = false;
  String _bridgeUrl = '';
  bool _bridgeSaving = false;
  bool _bridgeTesting = false;
  String? _bridgeStatus;
  bool _bridgeBusy = false;
  String? _bridgeError;
  String _bridgeStage = '';
  double _bridgeProgress = 0.0;
  CancelToken? _bridgeCancelToken;

  @override
  void initState() {
    super.initState();
    _loadBridgeUrl();
  }

  Future<void> _loadBridgeUrl() async {
    final saved = await ref.read(credentialsStoreProvider).getYoutubeBridgeUrl();
    if (!mounted) return;
    setState(() {
      _bridgeUrl = saved;
      _bridgeCtrl.text = saved;
      _bridgeLoaded = true;
    });
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
      final yt = YoutubeProvider(ref.read(apiClientProvider));
      final uri = Uri.tryParse(q);
      if (uri != null && uri.hasScheme && yt.canHandleUrl(uri)) {
        final item = await yt.resolveUrl(uri);
        if (mounted) setState(() => _results = item != null ? [item] : []);
      } else {
        final items = await yt.searchTracks(q);
        if (mounted) setState(() => _results = items);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The pasted input is a YouTube URL (not keywords) — the only input
  /// the bridge can accept, since it extracts one URL at a time.
  bool get _inputIsYoutubeUrl {
    final uri = Uri.tryParse(_ctrl.text.trim());
    return uri != null &&
        uri.hasScheme &&
        YoutubeProvider(ref.read(apiClientProvider)).canHandleUrl(uri);
  }

  Future<void> _saveBridgeUrl() async {
    final raw = _bridgeCtrl.text.trim();
    if (raw.isNotEmpty && !X2Config.isValidBackendUrl(raw)) {
      setState(() => _bridgeStatus = 'That is not a valid http(s) bridge URL.');
      return;
    }
    setState(() => _bridgeSaving = true);
    try {
      await ref.read(credentialsStoreProvider).setYoutubeBridgeUrl(raw);
      if (mounted) {
        setState(() {
          _bridgeUrl = X2Config.normalizeSingleUrl(raw);
          _bridgeStatus = _bridgeUrl.isEmpty
              ? 'Bridge removed. YouTube audio import is unavailable.'
              : 'Bridge saved: $_bridgeUrl';
        });
      }
    } finally {
      if (mounted) setState(() => _bridgeSaving = false);
    }
  }

  Future<void> _testBridgeConnection() async {
    final base =
        _bridgeCtrl.text.trim().isNotEmpty ? _bridgeCtrl.text.trim() : _bridgeUrl;
    if (base.isEmpty) {
      setState(() => _bridgeStatus = 'Enter a bridge URL first.');
      return;
    }
    setState(() {
      _bridgeTesting = true;
      _bridgeStatus = 'Contacting bridge…';
    });
    try {
      final health =
          await YoutubeBridgeService(ref.read(apiClientProvider)).testConnection(base);
      if (mounted) setState(() => _bridgeStatus = health.detail);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _bridgeStatus = e.message);
    } finally {
      if (mounted) setState(() => _bridgeTesting = false);
    }
  }

  /// Sends the pasted YouTube URL to the user's OWN bridge server and
  /// imports the returned audio through the SAME X2 validation pipeline
  /// as any authorized download (content-type, magic bytes, size,
  /// duration plausibility, SHA-256 dedup). Only reachable when a bridge
  /// is configured and the input is a YouTube URL.
  Future<void> _importViaBridge() async {
    final raw = _ctrl.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !_inputIsYoutubeUrl) return;

    final api = ref.read(apiClientProvider);
    final cancelToken = CancelToken();
    _bridgeCancelToken = cancelToken;
    setState(() {
      _bridgeBusy = true;
      _bridgeError = null;
      _bridgeStatus = null;
      _bridgeStage = 'Asking your bridge to extract audio…';
      _bridgeProgress = 0.05;
    });

    X2Result? bridgeResult;

    try {
      final base = await ref.read(credentialsStoreProvider).getYoutubeBridgeUrl();
      if (base.isEmpty) {
        throw const NetworkFailure(
          'No YouTube bridge is configured.',
          code: 'youtube_bridge_not_configured',
        );
      }

      // Metadata first (oEmbed) so the imported track keeps the real
      // title/artist/artwork. A metadata failure does not block the
      // bridge — its own title is the fallback.
      X2Result? meta;
      try {
        meta = await YoutubeProvider(api).resolveUrl(uri);
      } catch (_) {
        meta = null;
      }

      final extraction = await YoutubeBridgeService(api).extract(
        bridgeBaseUrl: base,
        youtubeUrl: uri,
      );
      final ext = p
          .extension(Uri.parse(extraction.downloadUrl).path)
          .toLowerCase()
          .replaceFirst('.', '');
      final result = bridgeResult = X2Result(
        id: 'ytbridge_${uri.toString().hashCode}',
        providerId: 'youtube-bridge',
        providerLabel: 'YouTube (self-hosted bridge)',
        title: extraction.title,
        artist: meta?.artist ?? 'YouTube Creator',
        album: meta?.album ?? 'YouTube Reference',
        durationSeconds: meta?.durationSeconds ?? 0,
        artworkUrl: meta?.artworkUrl,
        audioUrl: extraction.downloadUrl,
        externalPageUrl: uri.toString(),
        format: ext.isEmpty ? 'm4a' : ext,
        audioAvailable: true,
        downloadAuthorized: true,
        authorizationNote:
            'Extracted by your own bridge server; validated like any X2 download.',
      );

      final track = await ref.read(x2AcquisitionEngineProvider).acquireTrack(
            result: result,
            cancelToken: cancelToken,
            // The URL was already checked against the user-configured
            // bridge host by YoutubeBridgeService; allow it here even
            // when the bridge is a LAN address.
            allowPrivateHost: true,
            onStageUpdate: (stage, progress, received, total) {
              if (mounted) {
                setState(() {
                  _bridgeStage = _stageLabel(stage);
                  _bridgeProgress = progress;
                });
              }
            },
          );

      await ref.read(downloadManagerProvider.notifier).recordExternalDownload(
            result: result,
            importedTrackId: track.id,
          );
      ref.invalidate(libraryTracksProvider);
      ref.invalidate(storageStatsProvider);
      if (mounted) {
        setState(() {
          _bridgeStage = 'Imported.';
          _bridgeProgress = 1.0;
          _bridgeStatus = 'Imported "${track.title}" into your library via your bridge.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "${track.title}" via your bridge.')),
        );
      }
    } on AppFailure catch (e) {
      final failed = bridgeResult;
      if (failed != null) {
        await ref.read(downloadManagerProvider.notifier).recordExternalDownload(
              result: failed,
              importedTrackId: null,
              errorMessage: e.message,
            );
      }
      if (mounted) setState(() => _bridgeError = e.message);
    } catch (e) {
      final failed = bridgeResult;
      if (failed != null) {
        await ref.read(downloadManagerProvider.notifier).recordExternalDownload(
              result: failed,
              importedTrackId: null,
              errorMessage: e.toString(),
            );
      }
      if (mounted) setState(() => _bridgeError = e.toString());
    } finally {
      _bridgeCancelToken = null;
      if (mounted) setState(() => _bridgeBusy = false);
    }
  }

  String _stageLabel(DownloadStage stage) {
    return switch (stage) {
      DownloadStage.resolving => 'Resolving bridge audio…',
      DownloadStage.downloading => 'Downloading from your bridge…',
      DownloadStage.processing => 'Validating audio…',
      DownloadStage.importing => 'Importing into library…',
      DownloadStage.completed => 'Imported.',
      _ => 'Working…',
    };
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _bridgeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('YouTube Supported Providers', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Direct YouTube links resolve standalone via zero-key oEmbed. Keyword search routes through PIPED_API_URL, INVIDIOUS_API_URL, or X2_BACKEND_URL with automatic failover. YouTube audio is never downloaded by the app itself — see the self-hosted bridge below.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  hintText: 'Search keywords or paste youtube.com / youtu.be URL',
                  prefixIcon: Icon(Icons.ondemand_video_rounded),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.search_rounded),
                label: Text(_loading ? 'Querying Providers...' : 'Search YouTube Providers'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: BttColors.warning, fontSize: 12.5)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      BttPageRoute<void>(builder: (_) => const SettingsScreen()),
                    );
                  },
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Configure Piped / Invidious / Backend in Settings'),
                ),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              Text('Self-hosted bridge (optional)',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Btt Music never downloads YouTube audio itself. If you run your own yt-dlp server (reference implementation: tools/ytdlp_server.py), paste its base URL below. Submitting a YouTube link sends it to YOUR server; the returned audio is imported through the same X2 validation (format, size, duration, duplicate check).',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bridgeCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'http://your-server:8000',
                  prefixIcon: Icon(Icons.dns_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _bridgeSaving || _bridgeBusy ? null : _saveBridgeUrl,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: Text(_bridgeSaving ? 'Saving…' : 'Save bridge URL'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _bridgeTesting || _bridgeBusy ? null : _testBridgeConnection,
                      icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                      label: Text(_bridgeTesting ? 'Testing…' : 'Test connection'),
                    ),
                  ),
                ],
              ),
              if (_bridgeStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  _bridgeStatus!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: BttColors.textSecondary,
                      ),
                ),
              ],
              if (_bridgeLoaded && _bridgeUrl.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'No bridge configured — YouTube audio import is unavailable.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: BttColors.textMuted,
                      ),
                ),
              ],
              if (_bridgeUrl.isNotEmpty && _inputIsYoutubeUrl) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _bridgeBusy ? null : _importViaBridge,
                  style: FilledButton.styleFrom(
                    backgroundColor: BttColors.accentPink,
                    foregroundColor: BttColors.bgObsidian,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    _bridgeBusy ? 'Importing via your bridge…' : 'Import via my bridge',
                  ),
                ),
              ],
              if (_bridgeUrl.isNotEmpty && !_inputIsYoutubeUrl) ...[
                const SizedBox(height: 8),
                Text(
                  'Paste a YouTube link above to import it via your bridge.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: BttColors.textMuted,
                      ),
                ),
              ],
              if (_bridgeBusy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _bridgeProgress),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _bridgeStage,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _bridgeCancelToken?.cancel('Cancelled by user'),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
              if (_bridgeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _bridgeError!,
                  style: const TextStyle(color: BttColors.danger, fontSize: 12.5),
                ),
              ],
              ..._results.map((r) => _SheetResultCard(result: r)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoundCloudImportSheet extends ConsumerStatefulWidget {
  const _SoundCloudImportSheet();

  @override
  ConsumerState<_SoundCloudImportSheet> createState() => _SoundCloudImportSheetState();
}

class _SoundCloudImportSheetState extends ConsumerState<_SoundCloudImportSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<X2Result> _results = [];

  Future<void> _lookup() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
      final sc = SoundCloudProvider(ref.read(apiClientProvider));
      final uri = Uri.tryParse(q);
      if (uri != null && uri.hasScheme && sc.canHandleUrl(uri)) {
        final item = await sc.resolveUrl(uri);
        if (mounted) {
          setState(() {
            _results = item != null ? [item] : [];
            if (item == null) {
              _error =
                  'SoundCloud could not resolve that URL — check it is a public track link.';
            }
          });
        }
      } else {
        // F4 (Phase 4): do NOT call sc.searchTracks here. It always
        // throws AuthorizationFailure (soundcloud_search_restricted) —
        // SoundCloud closed public API key registrations for keyword
        // search — so the old `await sc.searchTracks(q);` could never
        // show a result; it only surfaced the same message through
        // the catch below. Keyword search is a closed path (the sheet
        // header already says so): set the provider's honest message
        // directly and route the user to the URL-resolve path above,
        // which already works via zero-key oEmbed.
        if (mounted) {
          setState(() {
            _error =
                'SoundCloud closed public API key registrations for keyword search. '
                'Paste a SoundCloud track URL to inspect its metadata via zero-key '
                'oEmbed, or use Audius / X2 open sources.';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('SoundCloud Track & URL Lookup', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Paste any public SoundCloud track URL for zero-key oEmbed inspection. Keyword search is not available — hand keywords to open X2 sources (Audius, Deezer, iTunes) instead.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  hintText: 'https://soundcloud.com/artist/track',
                  prefixIcon: Icon(Icons.cloud_queue_rounded),
                ),
                onSubmitted: (_) => _lookup(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _lookup,
                icon: const Icon(Icons.search_rounded),
                label: Text(_loading ? 'Inspecting SoundCloud...' : 'Inspect SoundCloud'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: BttColors.warning, fontSize: 12.5)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    final q = _ctrl.text.trim();
                    Navigator.of(context).pop();
                    if (q.isNotEmpty) {
                      ref.read(pendingX2SearchQueryProvider.notifier).state = q;
                    }
                    ref.read(currentTabIndexProvider.notifier).state = BttTab.x2;
                  },
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: const Text('Search Open Sources in X2 Instead'),
                ),
              ],
              ..._results.map((r) => _SheetResultCard(result: r)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotifyImportSheet extends ConsumerStatefulWidget {
  const _SpotifyImportSheet();

  @override
  ConsumerState<_SpotifyImportSheet> createState() => _SpotifyImportSheetState();
}

class _SpotifyImportSheetState extends ConsumerState<_SpotifyImportSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  SpotifyPlaylist? _playlist;

  // Phase 5 (item 22): second mode — browse a user's public
  // playlists. The paste-link flow above stays exactly as-is.
  bool _browseUser = false;
  final TextEditingController _userCtrl = TextEditingController();
  bool _userLoading = false;
  String? _userError;
  SpotifyUserPlaylists? _userPlaylists;

  Future<void> _lookup() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _playlist = null;
    });

    try {
      final uri = Uri.tryParse(q);
      if (uri == null || !uri.hasScheme) {
        if (mounted) {
          setState(() => _error =
              'Paste a Spotify playlist or album link to fetch its tracklist.');
        }
        return;
      }
      final provider = SpotifyMetadataProvider(ref.read(apiClientProvider));
      final playlist = await provider.fetchPlaylist(
        uri,
        libraryRepository: ref.read(libraryRepositoryProvider),
      );
      if (mounted) setState(() => _playlist = playlist);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Lists a user's public playlists via the backend
  /// (`GET /api/spotify/user`). Only public playlists are ever
  /// returned — client-credentials access cannot see private ones.
  Future<void> _fetchUserPlaylists() async {
    final q = _userCtrl.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _userLoading = true;
      _userError = null;
      _userPlaylists = null;
      _playlist = null;
    });

    try {
      final provider = SpotifyMetadataProvider(ref.read(apiClientProvider));
      final result = await provider.fetchUserPlaylists(q);
      if (mounted) setState(() => _userPlaylists = result);
    } catch (e) {
      if (mounted) setState(() => _userError = e.toString());
    } finally {
      if (mounted) setState(() => _userLoading = false);
    }
  }

  /// Tapping a browsed playlist runs the EXISTING fetchPlaylist flow
  /// (same backend route, same per-track library matching and
  /// "Already in library" chips as the paste-link mode).
  Future<void> _openUserPlaylist(SpotifyUserPlaylistSummary summary) async {
    final uri = Uri.tryParse(summary.externalUrl);
    if (uri == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _playlist = null;
    });

    try {
      final provider = SpotifyMetadataProvider(ref.read(apiClientProvider));
      final playlist = await provider.fetchPlaylist(
        uri,
        libraryRepository: ref.read(libraryRepositoryProvider),
      );
      if (mounted) setState(() => _playlist = playlist);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _userCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Spotify Playlist Import',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Metadata only — Spotify audio is DRM-protected and is never downloaded. '
                'Tracklists come from your deployed Btt Music backend (set X2_BACKEND_URL in Settings). '
                'Tracks already in your library are flagged; find the rest as authorized copies in X2.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.link_rounded, size: 18),
                    label: Text('Paste link'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.person_rounded, size: 18),
                    label: Text('Browse user'),
                  ),
                ],
                selected: {_browseUser},
                onSelectionChanged: (selected) {
                  setState(() {
                    _browseUser = selected.first;
                    _error = null;
                    _userError = null;
                  });
                },
              ),
              if (!_browseUser) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    hintText: 'https://open.spotify.com/playlist/...',
                    prefixIcon: Icon(Icons.music_note_rounded),
                  ),
                  onSubmitted: (_) => _lookup(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _lookup,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(_loading ? 'Fetching playlist...' : 'Fetch Playlist'),
                ),
              ],
              if (_browseUser) ...[
                const SizedBox(height: 12),
                Text(
                  'Only public playlists are visible — private playlists cannot be seen through this lookup. Metadata only; Spotify audio is never downloaded.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Username or open.spotify.com/user/...',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                  onSubmitted: (_) => _fetchUserPlaylists(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _userLoading ? null : _fetchUserPlaylists,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(_userLoading ? 'Fetching playlists...' : 'Fetch Public Playlists'),
                ),
                if (_userError != null) ...[
                  const SizedBox(height: 12),
                  Text(_userError!,
                      style: const TextStyle(
                          color: BttColors.warning, fontSize: 12.5)),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: BttColors.warning, fontSize: 12.5)),
              ],
              if (_userPlaylists != null && playlist == null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    BttArtwork(
                      artworkUrl: _userPlaylists!.avatarUrl,
                      size: 48,
                      radius: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userPlaylists!.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${_userPlaylists!.playlists.length} public playlists',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_userPlaylists!.playlists.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'This user has no public playlists.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                ..._userPlaylists!.playlists.map(
                  (s) => _UserPlaylistTile(
                    summary: s,
                    onTap: _loading ? null : () => _openUserPlaylist(s),
                  ),
                ),
              ],
              if (_userPlaylists != null && playlist != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _playlist = null),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text(
                        'Back to ${_userPlaylists!.displayName}\'s playlists'),
                  ),
                ),
              ],
              if (playlist != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    BttArtwork(
                      artworkUrl: playlist.coverUrl,
                      size: 56,
                      radius: 12,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${playlist.tracks.length} tracks · ${playlist.inLibraryCount} already in library',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ...playlist.tracks.map(
                  (t) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (t.isInLibrary) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: BttColors.success, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Already in library',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: BttColors.success),
                            ),
                          ],
                        ),
                      ],
                      _SheetResultCard(result: t.result),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One public playlist in the "Browse user" list: cover art, name,
/// owner, and track count. Tapping it runs the existing
/// fetchPlaylist flow for that playlist.
class _UserPlaylistTile extends StatelessWidget {
  final SpotifyUserPlaylistSummary summary;
  final VoidCallback? onTap;

  const _UserPlaylistTile({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      child: Material(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BttColors.borderSubtle),
            ),
            child: Row(
              children: [
                BttArtwork(
                  artworkUrl: summary.coverUrl,
                  size: 56,
                  radius: 10,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${summary.ownerName} · ${summary.trackCount} tracks',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (summary.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          summary.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: BttColors.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectUrlImportSheet extends ConsumerStatefulWidget {
  const _DirectUrlImportSheet();

  @override
  ConsumerState<_DirectUrlImportSheet> createState() => _DirectUrlImportSheetState();
}

class _DirectUrlImportSheetState extends ConsumerState<_DirectUrlImportSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<X2Result> _items = [];

  Future<void> _verifyUrl() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return;

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) {
      setState(() => _error = 'Enter a valid http:// or https:// audio file or RSS feed URL.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });

    try {
      final provider = DirectUrlProvider(ref.read(apiClientProvider));
      final lowerPath = uri.path.toLowerCase();
      if (lowerPath.endsWith('.rss') || lowerPath.endsWith('.xml') || lowerPath.contains('/feed')) {
        final feedItems = await provider.resolveAllFeedItems(uri);
        if (mounted) {
          setState(() {
            _items = feedItems;
            if (feedItems.isEmpty) {
              _error = 'No audio enclosures (<enclosure type="audio/...">) found in RSS feed.';
            }
          });
        }
      } else {
        final single = await provider.resolveUrl(uri);
        if (mounted) {
          setState(() => _items = single != null ? [single] : []);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Direct Audio URL & RSS Podcast Import',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Verifies HTTP MIME headers, container magic bytes, and size before saving offline.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'https://example.com/track.mp3 or /feed.xml',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                onSubmitted: (_) => _verifyUrl(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _verifyUrl,
                style: FilledButton.styleFrom(
                  backgroundColor: BttColors.accentPink,
                  foregroundColor: BttColors.bgObsidian,
                ),
                icon: const Icon(Icons.verified_rounded),
                label: Text(_loading ? 'Inspecting Audio Stream...' : 'Verify Audio Link'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: BttColors.danger, fontSize: 12.5)),
              ],
              ..._items.map((r) => _SheetResultCard(result: r)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetResultCard extends ConsumerWidget {
  final X2Result result;
  const _SheetResultCard({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeMb = result.fileSizeBytes != null && result.fileSizeBytes! > 0
        ? ' · ${(result.fileSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: result.downloadAuthorized
              ? BttColors.success.withValues(alpha: 0.45)
              : BttColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BttArtwork(artworkUrl: result.artworkUrl, size: 48, radius: 10),
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
                    Text(
                      '${result.artist} · ${result.providerLabel}$sizeMb',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.authorizationNote,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: result.downloadAuthorized ? BttColors.success : BttColors.textMuted,
                ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: result.downloadAuthorized
                ? FilledButton.icon(
                    onPressed: () {
                      ref.read(downloadManagerProvider.notifier).enqueueX2Download(result);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Queued "${result.title}" for offline import.')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: BttColors.accentPink,
                      foregroundColor: BttColors.bgObsidian,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text('Download ${result.format ?? 'Audio'}'),
                  )
                : OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      ref.read(pendingX2SearchQueryProvider.notifier).state =
                          '${result.artist} ${result.title}'.trim();
                      ref.read(currentTabIndexProvider.notifier).state = BttTab.x2;
                    },
                    icon: const Icon(Icons.travel_explore_rounded, size: 18),
                    label: const Text('Find Authorized Source in X2'),
                  ),
          ),
        ],
      ),
    );
  }
}
