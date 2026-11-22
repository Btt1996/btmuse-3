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
        _error = e.toString();
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
              ? 'No local offline library match found ($_landmarkCount landmarks extracted). Enter a lyric or title hint below to verify via open catalogs.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _statusMessage = null;
          _error = e.toString();
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
              ? 'Checked local library ($path). No local match; use public catalog lookup below.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _statusMessage = null;
          _error = e.toString();
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
    });
    try {
      final results = await ref.read(x1ServiceProvider).searchPublicMetadataCatalogs(q);
      if (mounted) {
        setState(() {
          _catalogMatches = results;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _error = e.toString();
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
                : const Icon(Icons.fingerprint_rounded, color: BttColors.greenAccent, size: 18),
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
                color: _recording ? BttColors.cyanAccent : BttColors.borderSubtle,
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
                            ? const [BttColors.goldAccent, BttColors.danger]
                            : const [BttColors.cyanAccent, BttColors.greenAccent],
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
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: BttColors.danger)),
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
                icon: const Icon(Icons.search_rounded, color: BttColors.cyanAccent),
                onPressed: _searchOpenCatalogs,
              ),
            ),
          ),
          const SizedBox(height: 12),
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
              ? BttColors.greenAccent.withValues(alpha: 0.5)
              : BttColors.cyanAccent.withValues(alpha: 0.35),
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
                            color: BttColors.cyanAccent,
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
                    color: BttColors.goldAccent,
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
              backgroundColor: BttColors.goldAccent,
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
