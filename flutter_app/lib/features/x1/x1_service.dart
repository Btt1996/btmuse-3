import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/services/ios_audio_bridge.dart';
import 'package:btmu/data/models/x1_identification.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/features/x1/local_fingerprint_engine.dart';

class X1SampleAnalysis {
  final X1Identification? localMatch;
  final AcousticTelemetry telemetry;
  final int landmarkCount;

  const X1SampleAnalysis({
    required this.localMatch,
    required this.telemetry,
    required this.landmarkCount,
  });
}

class X1Service {
  final ApiClient _apiClient;
  final LibraryRepository _libraryRepo;
  final AudioRecorder _recorder = AudioRecorder();

  X1Service(this._apiClient, this._libraryRepo);

  Future<bool> hasMicrophonePermission() => _recorder.hasPermission();

  Future<int> getIndexedLibraryCount() => _libraryRepo.getIndexedFingerprintTrackCount();

  Future<int> indexAllLibraryTracks() async {
    final tracks = await _libraryRepo.getAllTracks();
    var count = 0;
    for (final t in tracks) {
      await _libraryRepo.indexTrackAudio(t);
      count++;
    }
    return count;
  }

  Future<String> startRecordingSample() async {
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      throw const AuthorizationFailure(
        'Microphone access was denied. Enable Microphone permission in iOS Settings.',
      );
    }
    final tempDir = await getTemporaryDirectory();
    final samplePath = p.join(
      tempDir.path,
      'x1_sample_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    // Record uncompressed 16-bit WAV at 11,025 Hz mono so local FFT constellation hashing works directly on-device
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        numChannels: 1,
        sampleRate: LocalFingerprintEngine.targetSampleRate,
      ),
      path: samplePath,
    );
    return samplePath;
  }

  Future<String?> stopRecordingSample() => _recorder.stop();

  /// Identifies captured audio locally using on-device Spectral Constellation Landmarks
  /// against SQLite indexed offline tracks—zero API keys, zero network calls required.
  Future<X1SampleAnalysis> analyzeAndMatchLocal(File audioFile) async {
    if (!await audioFile.exists()) {
      throw const ValidationFailure('Audio sample file was not captured.');
    }

    final tempDir = await getTemporaryDirectory();
    final isTempX1Sample = p.isWithin(tempDir.path, audioFile.path) &&
        p.basename(audioFile.path).startsWith('x1_sample_');

    try {
      var pcm = await IosAudioBridge.extractMonoPcm(filePath: audioFile.path, maxSeconds: 20);
      if (pcm.isEmpty) {
        pcm = LocalFingerprintEngine.decodeWavBytesToMonoFloat(await audioFile.readAsBytes());
      }

      if (pcm.isEmpty) {
        throw const ValidationFailure('Unable to decode PCM audio sample on-device.');
      }

      final telemetry = LocalFingerprintEngine.analyzeTelemetry(pcm);
      final landmarks = LocalFingerprintEngine.extractLandmarks(pcm);
      final hashSet = landmarks.map((l) => l.hash).toSet();

      final candidates = await _libraryRepo.loadFingerprintIndexForHashes(hashSet);
      final match = LocalFingerprintEngine.matchSampleAgainstIndex(
        sampleHashes: landmarks,
        indexedTracks: candidates,
      );

      if (match != null) {
        final track = await _libraryRepo.findById(match.trackId);
        if (track != null) {
          return X1SampleAnalysis(
            localMatch: X1Identification(
              provider: 'Local Spectral Constellation',
              title: track.title,
              artist: track.artist,
              album: track.album,
              durationSeconds: track.durationSeconds,
              artworkUrl: track.artworkUrl,
              matchedTrackId: track.id,
              isLocalLibraryMatch: true,
              confidence: match.confidence,
              detectedBpm: telemetry.estimatedBpm,
              dominantFrequencyHz: telemetry.dominantFrequencyHz,
              identifiedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
            telemetry: telemetry,
            landmarkCount: landmarks.length,
          );
        }
      }

      return X1SampleAnalysis(
        localMatch: null,
        telemetry: telemetry,
        landmarkCount: landmarks.length,
      );
    } finally {
      if (isTempX1Sample && await audioFile.exists()) {
        try {
          await audioFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Searches open, ZERO-API-KEY public music catalogs (Deezer Public API, iTunes Search,
  /// and MusicBrainz WS/2) using lyrics, song snippets, hummed titles, or artist hints.
  Future<List<X1Identification>> searchPublicMetadataCatalogs(String hintQuery) async {
    final trimmed = hintQuery.trim();
    if (trimmed.isEmpty) return const [];

    final matches = <X1Identification>[];

    await Future.wait([
      // 1. Deezer Public API (zero key, returns artwork + 30s verification preview)
      () async {
        try {
          final res = await _apiClient.dio.get<Map<String, dynamic>>(
            'https://api.deezer.com/search',
            queryParameters: {'q': trimmed, 'limit': 6},
          );
          final data = (res.data?['data'] as List<dynamic>?) ?? [];
          for (final raw in data.whereType<Map<dynamic, dynamic>>()) {
            matches.add(
              X1Identification(
                provider: 'Deezer Public Catalog',
                title: (raw['title'] as String?) ?? 'Track',
                artist: (raw['artist']?['name'] as String?) ?? 'Artist',
                album: (raw['album']?['title'] as String?) ?? 'Single',
                durationSeconds: (raw['duration'] as num?)?.toInt() ?? 0,
                artworkUrl: (raw['album']?['cover_big'] as String?) ??
                    (raw['album']?['cover_medium'] as String?),
                previewUrl: raw['preview'] as String?,
                externalId: raw['id']?.toString(),
                confidence: 0.82,
                identifiedAtMs: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }
        } catch (_) {}
      }(),

      // 2. MusicBrainz WS/2 (zero key, open encyclopedia with proper User-Agent)
      () async {
        try {
          final res = await _apiClient.dio.get<Map<String, dynamic>>(
            'https://musicbrainz.org/ws/2/recording',
            queryParameters: {'query': trimmed, 'fmt': 'json', 'limit': 5},
            options: Options(
              headers: const {'User-Agent': 'BttMusic/3.0 (ahmed96btt@gmail.com)'},
            ),
          );
          final recs = (res.data?['recordings'] as List<dynamic>?) ?? [];
          for (final raw in recs.whereType<Map<dynamic, dynamic>>()) {
            final credits = (raw['artist-credit'] as List<dynamic>?) ?? [];
            final artistName = credits.isNotEmpty
                ? ((credits.first as Map)['name'] as String? ?? 'Unknown Artist')
                : 'Unknown Artist';
            final releases = (raw['releases'] as List<dynamic>?) ?? [];
            final albumTitle = releases.isNotEmpty
                ? ((releases.first as Map)['title'] as String? ?? 'Single')
                : 'Single';
            matches.add(
              X1Identification(
                provider: 'MusicBrainz Open DB',
                title: (raw['title'] as String?) ?? 'Recording',
                artist: artistName,
                album: albumTitle,
                durationSeconds: ((raw['length'] as num?)?.toInt() ?? 0) ~/ 1000,
                externalId: raw['id'] as String?,
                confidence: ((raw['score'] as num?)?.toDouble() ?? 75.0) / 100.0,
                identifiedAtMs: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }
        } catch (_) {}
      }(),

      // 3. iTunes Search API (zero key)
      () async {
        try {
          final res = await _apiClient.dio.get<dynamic>(
            'https://itunes.apple.com/search',
            queryParameters: {'term': trimmed, 'media': 'music', 'entity': 'song', 'limit': 4},
          );
          final decoded = res.data is String ? jsonDecode(res.data as String) : res.data;
          final items = (decoded?['results'] as List<dynamic>?) ?? [];
          for (final raw in items.whereType<Map<dynamic, dynamic>>()) {
            matches.add(
              X1Identification(
                provider: 'Apple Open Catalog',
                title: (raw['trackName'] as String?) ?? 'Track',
                artist: (raw['artistName'] as String?) ?? 'Artist',
                album: (raw['collectionName'] as String?) ?? 'Single',
                durationSeconds: ((raw['trackTimeMillis'] as num?)?.toInt() ?? 0) ~/ 1000,
                artworkUrl: (raw['artworkUrl100'] as String?)?.replaceAll('100x100bb', '600x600bb'),
                previewUrl: raw['previewUrl'] as String?,
                externalId: raw['trackId']?.toString(),
                confidence: 0.80,
                identifiedAtMs: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }
        } catch (_) {}
      }(),
    ]);

    return matches;
  }

  void dispose() {
    _recorder.dispose();
  }
}
