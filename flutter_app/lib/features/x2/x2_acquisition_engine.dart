import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/audio_validator.dart';
import 'package:btmu/data/models/download_task.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/data/repositories/library_repository.dart';

/// Downloads one authorized [X2Result] and imports it into the library.
///
/// Validation order (plan item 20) — every step runs BEFORE the import,
/// and every failure throws instead of silently dropping the track:
///   1. the result must be download-authorized;
///   2. the audio URL must be a safe public URL — unless [allowPrivateHost]
///      is set (see below);
///   3. the HTTP content-type must not be HTML/JSON/text or video;
///   4. the download must be (near-)complete per content-length;
///   5. [AudioValidator.inspectFile] must accept the magic bytes and the
///      file must be at least 4096 bytes;
///   6. the file size must be plausible for the declared duration
///      (below ~1 KB/s no real music codec produces audio);
///   7. [LibraryRepository.importFileIntoLibrary] hashes the file
///      (SHA-256) and rejects duplicates with [DuplicateTrackFailure].
/// Progress is reported through [onStageUpdate] at every stage, and the
/// temporary file is always deleted, on success (moved into the library)
/// and on failure.
class X2AcquisitionEngine {
  final ApiClient _apiClient;
  final LibraryRepository _libraryRepo;

  X2AcquisitionEngine(this._apiClient, this._libraryRepo);

  Future<Track> acquireTrack({
    required X2Result result,
    required CancelToken cancelToken,
    required void Function(DownloadStage stage, double progress, int received, int total)
        onStageUpdate,
    // True ONLY when the caller has already verified the URL against a
    // user-configured trusted host — i.e. the self-hosted YouTube bridge
    // (YoutubeBridgeService), which allows the bridge's own host
    // (often a LAN address) or a public URL. Never true for
    // provider-supplied URLs: those always go through the SSRF guard.
    bool allowPrivateHost = false,
  }) async {
    if (!result.downloadAuthorized) {
      throw AuthorizationFailure(result.authorizationNote);
    }

    final url = result.audioUrl;
    final parsedAudioUrl = url == null ? null : Uri.tryParse(url);
    final urlIsUsable = url != null &&
        parsedAudioUrl != null &&
        (parsedAudioUrl.scheme == 'http' || parsedAudioUrl.scheme == 'https') &&
        parsedAudioUrl.host.isNotEmpty &&
        (allowPrivateHost || ApiClient.isSafeExternalUrl(url));
    if (url == null || !urlIsUsable) {
      throw const ValidationFailure('Result does not expose a safe external audio URL.');
    }

    onStageUpdate(DownloadStage.resolving, 0.05, 0, result.fileSizeBytes ?? 0);

    final tempDir = await getTemporaryDirectory();
    final safeExt = (result.format ?? 'mp3').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final tempFile = File(
      p.join(tempDir.path, 'x2_${DateTime.now().millisecondsSinceEpoch}.${safeExt.isEmpty ? 'mp3' : safeExt}'),
    );

    try {
      onStageUpdate(DownloadStage.downloading, 0.08, 0, result.fileSizeBytes ?? 0);

      final response = await _apiClient.dio.download(
        url,
        tempFile.path,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          headers: const {
            'User-Agent': 'BttMusic/3.0.5 (iOS)',
            'Accept': 'audio/*,application/octet-stream;q=0.9,*/*;q=0.5',
          },
        ),
        onReceiveProgress: (received, total) {
          final effectiveTotal = total > 0 ? total : (result.fileSizeBytes ?? 0);
          final progress = effectiveTotal > 0 ? (received / effectiveTotal).clamp(0.08, 0.90) : 0.45;
          onStageUpdate(DownloadStage.downloading, progress, received, effectiveTotal);
        },
      );

      final contentType = (response.headers.value('content-type') ?? '').toLowerCase();
      if (contentType.contains('text/html') ||
          contentType.contains('application/json') ||
          contentType.contains('text/plain') ||
          contentType.contains('video/')) {
        throw ValidationFailure(
          'Provider returned non-audio content ($contentType) instead of an audio stream.',
        );
      }

      final actualSize = await tempFile.length();
      final headerLen = int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
      if (headerLen > 4096 && actualSize < (headerLen * 0.90)) {
        throw ValidationFailure(
          'Incomplete download: received $actualSize of $headerLen bytes.',
        );
      }

      final inspect = await AudioValidator.inspectFile(tempFile, minBytes: 4096);
      if (!inspect.isValid) {
        throw ValidationFailure(inspect.reason ?? 'Downloaded payload is not a valid audio file.');
      }

      // Duration plausibility (plan item 20): a declared duration implies
      // a minimum plausible payload. Below ~1 KB/s (about 8 kbps) no real
      // music codec produces audio, so such a file is truncated or
      // garbage even when its header bytes look valid. Results with an
      // unknown duration (0) skip this check — it only fires on a
      // provider-declared duration that the bytes cannot support.
      final declaredSeconds = result.durationSeconds;
      if (declaredSeconds > 0 && actualSize < declaredSeconds * 1000) {
        throw ValidationFailure(
          'Downloaded file is too small for its declared duration '
          '($actualSize bytes for $declaredSeconds s).',
        );
      }

      onStageUpdate(DownloadStage.processing, 0.92, actualSize, actualSize);
      onStageUpdate(DownloadStage.importing, 0.96, actualSize, actualSize);

      final track = await _libraryRepo.importFileIntoLibrary(
        sourceFile: tempFile,
        rawTitle: result.title,
        rawArtist: result.artist,
        rawAlbum: result.album,
        artworkUrl: result.artworkUrl,
        durationSeconds: result.durationSeconds,
        sourceProvider: result.providerId,
        deleteSourceAfterCopy: true,
      );

      onStageUpdate(DownloadStage.completed, 1.0, track.fileSizeBytes, track.fileSizeBytes);
      return track;
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }
}
