import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/downloads/download_history_screen.dart';
import 'package:btmu/features/search/search_screen.dart';
import 'package:btmu/features/settings/settings_screen.dart';
import 'package:btmu/features/telegram/telegram_screen.dart';
import 'package:btmu/features/x2/providers/direct_url_provider.dart';
import 'package:btmu/features/x2/providers/soundcloud_provider.dart';
import 'package:btmu/features/x2/providers/vk_provider.dart';
import 'package:btmu/features/x2/providers/youtube_provider.dart';

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
                MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
              );
            },
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Downloads Queue',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DownloadHistoryScreen()),
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
                          color: BttColors.cyanAccent,
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
            accent: BttColors.cyanAccent,
            title: 'Import from iPhone Files',
            subtitle: 'Pick a single MP3, M4A, AAC, FLAC, WAV, or OGG with ID3 & artwork extraction',
            trailingLabel: 'Single',
            onTap: _busyLocal ? null : () => _importLocal(allowMultiple: false),
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.library_add_rounded,
            accent: BttColors.greenAccent,
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
            accent: BttColors.greenAccent,
            title: 'Import from Telegram',
            subtitle: 'Connect your Telegram Bot token (iOS Keychain) and import bot audio & documents',
            trailingLabel: 'Bot API',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TelegramScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.link_rounded,
            accent: BttColors.cyanAccent,
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
            accent: BttColors.goldAccent,
            title: 'Search and Import from VK Music',
            subtitle: 'Inspect public VK audio links or search with your optional VK user session token',
            trailingLabel: 'VK',
            onTap: _openVkSheet,
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.ondemand_video_rounded,
            accent: BttColors.goldAccent,
            title: 'Search YouTube via Supported Providers',
            subtitle: 'Query configured Piped, Invidious, or X2 Companion instances + YouTube oEmbed links',
            trailingLabel: 'Piped / Inv',
            onTap: _openYoutubeSheet,
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.cloud_queue_rounded,
            accent: BttColors.cyanAccent,
            title: 'Search SoundCloud',
            subtitle: 'Resolve SoundCloud track URLs via zero-key oEmbed & view open-source alternatives',
            trailingLabel: 'oEmbed',
            onTap: _openSoundCloudSheet,
          ),
          const SizedBox(height: 18),
          _SectionHeader('X1 & X2 INTELLIGENCE ENGINES'),
          const SizedBox(height: 8),
          _ImportOptionTile(
            icon: Icons.mic_rounded,
            accent: BttColors.cyanAccent,
            title: 'Identify Music Using X1',
            subtitle: 'On-device FFT constellation fingerprinting + zero-key public catalog verification',
            trailingLabel: 'X1 Engine',
            onTap: () => ref.read(currentTabIndexProvider.notifier).state = BttTab.x1,
          ),
          const SizedBox(height: 10),
          _ImportOptionTile(
            icon: Icons.travel_explore_rounded,
            accent: BttColors.goldAccent,
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
        if (mounted) setState(() => _results = items);
      } else {
        await vk.searchTracks(input);
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
                'Paste a public VK link (no login needed for public OpenGraph metadata) or supply your own optional VK user token stored in Keychain.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _inputCtrl,
                decoration: const InputDecoration(
                  hintText: 'https://vk.com/audio... or song keyword',
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
  bool _loading = false;
  String? _error;
  List<X2Result> _results = [];

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
              Text('YouTube Supported Providers', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Direct YouTube links resolve standalone via zero-key oEmbed. Keyword search routes through PIPED_API_URL, INVIDIOUS_API_URL, or X2_BACKEND_URL with automatic failover.',
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
                      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                    );
                  },
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Configure Piped / Invidious / Backend in Settings'),
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
        if (mounted) setState(() => _results = item != null ? [item] : []);
      } else {
        await sc.searchTracks(q);
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
                'Paste any public SoundCloud track URL for zero-key oEmbed inspection, or hand off keywords to open X2 sources (Audius, Deezer, iTunes).',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  hintText: 'https://soundcloud.com/artist/track or query',
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
                  backgroundColor: BttColors.cyanAccent,
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
              ? BttColors.greenAccent.withValues(alpha: 0.45)
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
                  color: result.downloadAuthorized ? BttColors.greenAccent : BttColors.textMuted,
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
                      backgroundColor: BttColors.cyanAccent,
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
