import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/data/models/x1_identification.dart';
import 'package:btmu/features/x1/local_fingerprint_engine.dart';
import 'package:btmu/features/x1/x1_service.dart';

class X1Screen extends ConsumerStatefulWidget {
  const X1Screen({super.key});

  @override
  ConsumerState<X1Screen> createState() => _X1ScreenState();
}

class _X1ScreenState extends ConsumerState<X1Screen> {
  final TextEditingController _hintCtrl = TextEditingController();
  final AudioPlayer _previewPlayer = AudioPlayer();

  bool _recording = false;
  bool _analyzing = false;
  bool _indexing = false;
  int _elapsedSeconds = 0;
  int _indexedCount = 0;
  Timer? _timer;

  AcousticTelemetry? _telemetry;
  int _landmarkCount = 0;
  X1Identification? _localMatch;
  List<X1Identification> _catalogMatches = [];
  String? _playingPreviewUrl;
  String? _statusMessage;
  String? _error;

  /// Distinct error states (Phase 5): microphone denial is shown as its own
  /// card with the Settings path, never as raw `e.toString()`; catalog
  /// failures are shown per provider instead of an empty list with no
  /// message. `url_launcher` is NOT a dependency (checked in pubspec.yaml
  /// at head af44019e), so the mic-denied card shows the Settings path as
  /// text instead of a button that opens Settings.
  bool _micDenied = false;
  bool _catalogSearched = false;
  bool _catalogAllFailed = false;
  bool _catalogTimedOut = false;
  Map<String, String> _catalogErrors = const {};

  /// Hint threshold for "try a longer sample": a 1s tonal snippet already
  /// yields ~475 landmarks and a 0.25s snippet ~75 (measured with the
  /// recall harness, docs/x1-recall.md), while silence yields 0. Below 100
  /// landmarks the sample holds under ~0.3s of usable tonal audio, so a
  /// longer (up to 8s) sample is the actionable fix — not a different song.
  static const int _lowLandmarkHintThreshold = 100;

  /// Appends the longer-sample hint to a no-match status when the sample
  /// was too thin to match reliably.
  String _noMatchStatus(String base) {
    if (_landmarkCount >= _lowLandmarkHintThreshold) return base;
    return '$base Only $_landmarkCount landmarks were extracted — try a '
        'longer sample (up to 8s) in a quieter spot and listen again.';
  }

  @override
  void initState() {
    super.initState();
    _refreshIndexCount();
  }

  Future<void> _refreshIndexCount() async {
    final count = await ref.read(x1ServiceProvider).getIndexedLibraryCount();
    if (mounted) setState(() => _indexedCount = count);
  }

  Future<void> _rebuildOfflineIndex() async {
    setState(() => _indexing = true);
    try {
      await ref.read(x1ServiceProvider).indexAllLibraryTracks();
      await _refreshIndexCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Indexed $_indexedCount local track(s) for offline recognition.')),
        );
      }
    } finally {
      if (mounted) setState(() => _indexing = false);
    }
  }

  Future<void> _toggleListen() async {
    final x1 = ref.read(x1ServiceProvider);
    if (_recording) {
      await _finishRecordingAndAnalyze();
      return;
    }

    setState(() {
      _error = null;
      _micDenied = false;
      _localMatch = null;
      _telemetry = null;
      _statusMessage = 'Capturing 11 kHz WAV audio on-device (tap again after 5–8s)...';
      _elapsedSeconds = 0;
    });

    try {
      await x1.startRecordingSample();
      setState(() => _recording = true);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsedSeconds++);
        if (_elapsedSeconds >= 8) {
          unawaited(_finishRecordingAndAnalyze());
        }
      });
    } catch (e) {
      setState(() {
        _recording = false;
        _statusMessage = null;
        // Mic denial gets its own card (with the Settings path); every
        // other recording failure is a plain message, never raw toString().
        if (X1Service.isMicrophoneDenial(e)) {
          _micDenied = true;
          _error = null;
        } else {
          _error = X1Service.describeError(e);
        }
      });
    }
  }

  Future<void> _finishRecordingAndAnalyze() async {
    _timer?.cancel();
    setState(() {
      _recording = false;
      _analyzing = true;
      _statusMessage = 'Extracting FFT spectral constellation landmarks locally...';
    });

    try {
      final x1 = ref.read(x1ServiceProvider);
      final recordedPath = await x1.stopRecordingSample();
      if (recordedPath == null) {
        setState(() {
          _analyzing = false;
          _error = 'No microphone audio file captured.';
        });
        return;
      }

      final analysis = await x1.analyzeAndMatchLocal(File(recordedPath));
      if (mounted) {
        setState(() {
          _analyzing = false;
          _localMatch = analysis.localMatch;
          _telemetry = analysis.telemetry;
          _landmarkCount = analysis.landmarkCount;
          _statusMessage = analysis.localMatch == null
              ? _noMatchStatus(
                  'No local offline library match found ($_landmarkCount landmarks extracted). Enter a lyric or title hint below to verify via open catalogs.')
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _statusMessage = null;
          _error = X1Service.describeError(e);
        });
      }
    }
  }

  Future<void> _pickAudioClip() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'flac', 'ogg'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    setState(() {
      _analyzing = true;
      _error = null;
      _micDenied = false;
      _localMatch = null;
      _statusMessage = 'Analyzing audio clip locally on-device...';
    });

    try {
      final analysis = await ref.read(x1ServiceProvider).analyzeAndMatchLocal(File(path));
      if (mounted) {
        setState(() {
          _analyzing = false;
          _localMatch = analysis.localMatch;
          _telemetry = analysis.telemetry;
          _landmarkCount = analysis.landmarkCount;
          _statusMessage = analysis.localMatch == null
              ? _noMatchStatus(
                  'Checked local library ($path). No local match; use public catalog lookup below.')
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _statusMessage = null;
          _error = X1Service.describeError(e);
        });
      }
    }
  }

  Future<void> _searchOpenCatalogs() async {
    final q = _hintCtrl.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _analyzing = true;
      _error = null;
      _catalogSearched = false;
      _catalogAllFailed = false;
      _catalogTimedOut = false;
      _catalogErrors = const {};
    });
    try {
      final result = await ref.read(x1ServiceProvider).searchPublicMetadataCatalogs(q);
      if (mounted) {
        setState(() {
          _catalogMatches = result.matches;
          _catalogErrors = result.providerErrors;
          _catalogAllFailed = result.allProvidersFailed;
          _catalogTimedOut = result.anyProviderTimedOut;
          _catalogSearched = true;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _error = X1Service.describeError(e);
        });
      }
    }
  }

  Future<void> _togglePreview(String previewUrl) async {
    if (_playingPreviewUrl == previewUrl) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _playingPreviewUrl = null);
      return;
    }
    setState(() => _playingPreviewUrl = previewUrl);
    await _previewPlayer.setUrl(previewUrl);
    await _previewPlayer.play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hintCtrl.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('X1 Recognition'),
        actions: [
          TextButton.icon(
            onPressed: _indexing ? null : _rebuildOfflineIndex,
            icon: _indexing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fingerprint_rounded, color: BttColors.success, size: 18),
            label: Text(
              '$_indexedCount Indexed',
              style: const TextStyle(color: BttColors.textPrimary),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: BttColors.bgCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _recording ? BttColors.accentPink : BttColors.borderSubtle,
              ),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _analyzing ? null : _toggleListen,
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _recording
                            ? const [BttColors.accentMagenta, BttColors.danger]
                            : const [BttColors.accentViolet, BttColors.accentMagenta, BttColors.accentPink],
                      ),
                    ),
                    child: Icon(
                      _recording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 44,
                      color: BttColors.bgObsidian,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _recording
                      ? 'Listening Locally... ${_elapsedSeconds}s / 8s'
                      : (_analyzing ? 'Processing Audio...' : 'Offline Spectral Matching'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  _statusMessage ??
                      'Self-contained FFT constellation matcher & acoustic DSP analyzer. Zero AudD, ACRCloud, or paid API keys required.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: (_recording || _analyzing) ? null : _pickAudioClip,
                  icon: const Icon(Icons.audio_file_rounded),
                  label: const Text('Identify Local Clip'),
                ),
              ],
            ),
          ),
          if (_telemetry != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BttColors.bgElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BttColors.borderSubtle),
              ),
              child: Text(
                'DSP Telemetry: ${_telemetry!.durationSeconds.toStringAsFixed(1)}s · RMS ${(_telemetry!.rmsEnergy * 100).toStringAsFixed(0)}% · Peak ~${_telemetry!.dominantFrequencyHz.round()} Hz · Tempo ~${_telemetry!.estimatedBpm.round()} BPM · $_landmarkCount landmarks',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
          if (_micDenied) ...[
            const SizedBox(height: 12),
            _ErrorCard(
              title: 'Microphone access denied',
              body:
                  'Btmus needs microphone access to listen. Enable it in '
                  'Settings → Privacy & Security → Microphone → Btmus, then '
                  'tap the microphone again.',
              accent: BttColors.danger,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorCard(
              title: 'Something went wrong',
              body: _error!,
              accent: BttColors.danger,
            ),
          ],
          if (_localMatch != null) ...[
            const SizedBox(height: 14),
            _MatchCard(
              match: _localMatch!,
              isPreviewPlaying: false,
              onTogglePreview: null,
              onFindInX2: () {
                ref.read(pendingX2SearchQueryProvider.notifier).state = _localMatch!.x2SearchQuery;
                ref.read(currentTabIndexProvider.notifier).state = BttTab.x2;
              },
            ),
          ],
          const SizedBox(height: 22),
          Text(
            'Open Public Catalog Verification (Zero API Keys)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Verify unfamiliar songs via MusicBrainz, Deezer & iTunes public catalogs with instant 30s audio preview confirmation.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hintCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchOpenCatalogs(),
            decoration: InputDecoration(
              hintText: 'Lyrics phrase, song title, or artist cue',
              prefixIcon: const Icon(Icons.music_note_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search_rounded, color: BttColors.accentPink),
                onPressed: _searchOpenCatalogs,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_catalogSearched && _catalogAllFailed) ...[
            _ErrorCard(
              title: "Couldn't reach the open catalogs — check your connection",
              body:
                  'None of the open catalogs answered. The providers that failed:\n'
                  '${_catalogErrors.entries.map((e) => '• ${e.key}: ${e.value}').join('\n')}',
              accent: BttColors.danger,
            ),
            const SizedBox(height: 12),
          ],
          if (_catalogSearched &&
              !_catalogAllFailed &&
              _catalogMatches.isEmpty) ...[
            _ErrorCard(
              title: 'No catalog results for that hint',
              body: _catalogTimedOut
                  ? 'The catalogs that answered found nothing, and some catalogs timed out. Try different lyrics or a title.'
                  : 'The catalogs that answered found nothing for that hint. Try different lyrics or a title.',
              accent: BttColors.warning,
            ),
            const SizedBox(height: 12),
          ],
          if (_catalogSearched &&
              !_catalogAllFailed &&
              _catalogMatches.isNotEmpty &&
              _catalogErrors.isNotEmpty) ...[
            _ErrorCard(
              title: _catalogTimedOut
                  ? 'Some catalogs timed out — showing results from the ones that answered'
                  : 'Some catalogs did not answer — showing results from the ones that did',
              body: _catalogErrors.entries
                  .map((e) => '• ${e.key}: ${e.value}')
                  .join('\n'),
              accent: BttColors.warning,
            ),
            const SizedBox(height: 12),
          ],
          ..._catalogMatches.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MatchCard(
                match: m,
                isPreviewPlaying: _playingPreviewUrl == m.previewUrl && m.previewUrl != null,
                onTogglePreview: m.previewUrl == null ? null : () => _togglePreview(m.previewUrl!),
                onFindInX2: () {
                  ref.read(pendingX2SearchQueryProvider.notifier).state = m.x2SearchQuery;
                  ref.read(currentTabIndexProvider.notifier).state = BttTab.x2;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final X1Identification match;
  final bool isPreviewPlaying;
  final VoidCallback? onTogglePreview;
  final VoidCallback onFindInX2;

  const _MatchCard({
    required this.match,
    required this.isPreviewPlaying,
    required this.onTogglePreview,
    required this.onFindInX2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BttColors.bgCardHighlight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: match.isLocalLibraryMatch
              ? BttColors.success.withValues(alpha: 0.5)
              : BttColors.accentPink.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BttArtwork(artworkUrl: match.artworkUrl, size: 58, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(match.title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '${match.artist} · ${match.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      '${match.provider} · ${(match.confidence * 100).round()}% match',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: BttColors.accentPink,
                          ),
                    ),
                  ],
                ),
              ),
              if (onTogglePreview != null)
                IconButton(
                  tooltip: 'Play 30s verification preview',
                  icon: Icon(
                    isPreviewPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                    color: BttColors.accentMagenta,
                    size: 32,
                  ),
                  onPressed: onTogglePreview,
                ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onFindInX2,
            style: FilledButton.styleFrom(
              backgroundColor: BttColors.accentPink,
              foregroundColor: BttColors.bgObsidian,
              minimumSize: const Size.fromHeight(44),
            ),
            icon: const Icon(Icons.travel_explore_rounded, size: 18),
            label: const Text('Find this song in X2'),
          ),
        ],
      ),
    );
  }
}

/// Small error-state card in the existing card style (BttColors surfaces
/// and borders). Used for the distinct X1 states — microphone denial,
/// catalog unreachable, partial catalog failure, and generic failures —
/// so an error is never a bare red text line or a raw exception string.
class _ErrorCard extends StatelessWidget {
  final String title;
  final String body;
  final Color accent;

  const _ErrorCard({
    required this.title,
    required this.body,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
