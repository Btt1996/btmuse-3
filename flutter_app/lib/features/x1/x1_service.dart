import 'dart:async';
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

/// Typed result of an open-catalog search.
///
/// Previously `searchPublicMetadataCatalogs` returned a bare list and
/// swallowed every per-provider failure with `catch (_) {}`, so a total
/// network failure was indistinguishable from "no results". Callers now get
/// both the matches and, keyed by provider display name, a short reason for
/// every catalog that failed — including timeouts — so the UI can say which
/// catalogs failed and why instead of showing an empty list with no message.
class X1CatalogSearchResult {
  final List<X1Identification> matches;

  /// Provider display name -> short human-readable failure reason.
  /// Empty when every attempted provider answered (even with zero results).
  final Map<String, String> providerErrors;

  const X1CatalogSearchResult({
    required this.matches,
    required this.providerErrors,
  });

  /// True when every attempted provider failed: the search produced no
  /// matches *because* the catalogs were unreachable, not because the
  /// hint matched nothing. (Exactly three providers are attempted per
  /// non-empty query; an empty query returns no matches and no errors.)
  bool get allProvidersFailed => matches.isEmpty && providerErrors.length == 3;

  /// True when at least one provider failed by timing out (as opposed to
  /// e.g. a DNS/connection error). The UI shows a distinct timeout message.
  bool get anyProviderTimedOut =>
      providerErrors.values.any((reason) => reason.startsWith('Timed out'));
}

class X1Service {
  final ApiClient _apiClient;
  final LibraryRepository _libraryRepo;
  final AudioRecorder _recorder = AudioRecorder();

  /// Per-provider timeout for open-catalog searches. Same `.timeout(...)`
  /// pattern as `X2SearchEngine.providerTimeout` (9s there); X1 uses 10s
  /// per the Phase 5 plan so a slow catalog cannot hang the screen.
  final Duration catalogProviderTimeout;

  X1Service(
    this._apiClient,
    this._libraryRepo, {
    this.catalogProviderTimeout = const Duration(seconds: 10),
  });

  /// Message shown when microphone access is denied. Names the fix
  /// (enable Microphone in iOS Settings) instead of a bare denial.
  static const String microphoneDeniedMessage =
      'Microphone access was denied. Enable Microphone in iOS Settings: '
      'Settings → Privacy & Security → Microphone → Btmus.';

  /// True when [error] is a microphone-denial failure, as opposed to any
  /// other recording failure. Denial is always an [AuthorizationFailure]
  /// thrown by [startRecordingSample]; the message check covers the same
  /// failure surfacing wrapped in another [AppFailure].
  static bool isMicrophoneDenial(Object error) {
    if (error is AuthorizationFailure) return true;
    return error is AppFailure &&
        error.message.contains('Microphone access was denied');
  }

  /// User-facing text for a failure: the [AppFailure.message] when the
  /// error is one, so the UI never shows raw `AppFailure(code): ...` or
  /// `e.toString()` output. Non-[AppFailure] errors fall back to
  /// `toString()` unchanged.
  static String describeError(Object error) =>
      error is AppFailure ? error.message : error.toString();

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
      throw const AuthorizationFailure(microphoneDeniedMessage);
    }
    final tempDir = await getTemporaryDirectory();
    final samplePath = p.join(
      tempDir.path,
      'x1_sample_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    // Record uncompressed 16-bit WAV at 11,025 Hz mono so local FFT constellation hashing works directly on-device
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: LocalFingerprintEngine.targetSampleRate,
        ),
        path: samplePath,
      );
    } on AuthorizationFailure {
      // Denial surfacing from the recorder itself, not the permission
      // check above: keep the distinct denial type and fix-naming message.
      throw const AuthorizationFailure(microphoneDeniedMessage);
    } catch (e) {
      // Any other recorder failure is NOT a denial: report it as such so
      // the UI does not send the user to Settings for a transient failure.
      throw AppFailure(
        'Microphone recording failed. Check that no other app is using '
        'the microphone and try again.',
        cause: e,
      );
    }
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
  ///
  /// Each provider gets [catalogProviderTimeout] (default 10s) and runs in
  /// parallel. A provider failure — timeout, network error, bad response —
  /// is recorded in [X1CatalogSearchResult.providerErrors] under its display
  /// name instead of being swallowed, so callers can distinguish "no
  /// results" from "catalogs unreachable" and say which catalogs failed.
  /// Only the X1Screen calls this (verified by grep at head af44019e),
  /// so the return type changed from `List<X1Identification>` to
  /// [X1CatalogSearchResult] with the screen updated in the same change.
  Future<X1CatalogSearchResult> searchPublicMetadataCatalogs(String hintQuery) async {
    final trimmed = hintQuery.trim();
    if (trimmed.isEmpty) {
      return const X1CatalogSearchResult(matches: [], providerErrors: {});
    }

    final matches = <X1Identification>[];
    final providerErrors = <String, String>{};
    final timeoutSeconds = catalogProviderTimeout.inSeconds;

    // Short, user-facing reason for a provider failure. Timeouts get a
    // distinct message (starting with 'Timed out') so the UI can tell a
    // slow catalog apart from a connection failure.
    String describeProviderError(String provider, Object error) {
      if (error is TimeoutException) {
        return 'Timed out after ${timeoutSeconds}s — no response from $provider.';
      }
      if (error is DioException) {
        final detail = error.message?.trim();
        if (detail != null && detail.isNotEmpty) return detail;
        return 'Request to $provider failed (${error.type.name}).';
      }
      return error.toString();
    }

    await Future.wait([
      // 1. Deezer Public API (zero key, returns artwork + 30s verification preview)
      () async {
        try {
          final res = await _apiClient.dio.get<Map<String, dynamic>>(
            'https://api.deezer.com/search',
            queryParameters: {'q': trimmed, 'limit': 6},
          ).timeout(catalogProviderTimeout);
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
        } catch (e) {
          providerErrors['Deezer'] = describeProviderError('Deezer', e);
        }
      }(),

      // 2. MusicBrainz WS/2 (zero key, open encyclopedia with proper User-Agent)
      () async {
        try {
          final res = await _apiClient.dio.get<Map<String, dynamic>>(
            'https://musicbrainz.org/ws/2/recording',
            queryParameters: {'query': trimmed, 'fmt': 'json', 'limit': 5},
            options: Options(
              headers: const {'User-Agent': 'BttMusic/3.0.5 (ahmed96btt@gmail.com)'},
            ),
          ).timeout(catalogProviderTimeout);
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
        } catch (e) {
          providerErrors['MusicBrainz'] = describeProviderError('MusicBrainz', e);
        }
      }(),

      // 3. iTunes Search API (zero key)
      () async {
        try {
          final res = await _apiClient.dio.get<dynamic>(
            'https://itunes.apple.com/search',
            queryParameters: {'term': trimmed, 'media': 'music', 'entity': 'song', 'limit': 4},
          ).timeout(catalogProviderTimeout);
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
        } catch (e) {
          providerErrors['iTunes'] = describeProviderError('iTunes', e);
        }
      }(),
    ]);

    return X1CatalogSearchResult(matches: matches, providerErrors: providerErrors);
  }

  void dispose() {
    _recorder.dispose();
  }
}
