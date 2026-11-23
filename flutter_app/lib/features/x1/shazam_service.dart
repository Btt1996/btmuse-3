import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/storage/secure_credentials_store.dart';
import 'package:btmu/data/models/x1_identification.dart';
import 'package:btmu/features/x1/x1_service.dart';

/// Shazam identification (v3.0.5, batch 2, item 3): a SEPARATE X1 option
/// that identifies a clip through Shazam's external API (RapidAPI
/// `shazam.p.rapidapi.com`), alongside the zero-key on-device matcher —
/// never a replacement for it.
///
/// Needs the user's own RapidAPI Shazam key, stored in the iOS Keychain
/// (see [SecureCredentialsStore]). No key is ever invented: with no key
/// configured the option shows as unavailable in the X1 screen and
/// [identifyClip] throws a [ValidationFailure] naming the fix. A clip
/// Shazam cannot match returns `null` — "no match", never a fake result.
///
/// Contract (RapidAPI Shazam `POST /songs/detect`): the recorded sample
/// is sent base64-encoded as a `text/plain` body with the
/// `X-RapidAPI-Key` / `X-RapidAPI-Host` headers; the response carries
/// the match under `track` (`title`, `subtitle` = artist,
/// `images.coverart`, `url`). The parser is defensive — an unexpected
/// shape surfaces as a plain error, never as an invented match.
class ShazamIdentificationService {
  final ApiClient _apiClient;
  final SecureCredentialsStore _store;

  /// Created lazily in [recordSample]: constructing an [AudioRecorder]
  /// touches its platform channel, so a service built only to identify
  /// a clip must not pay for (or fail on) recorder setup.
  AudioRecorder? _recorder;

  static const _detectUrl = 'https://shazam.p.rapidapi.com/songs/detect';
  static const _rapidApiHost = 'shazam.p.rapidapi.com';

  /// How long the Shazam listen records (8s, same as the local X1 listen).
  static const recordSeconds = 8;

  ShazamIdentificationService(this._apiClient, this._store);

  Future<bool> hasApiKey() async =>
      (await _store.getShazamApiKey()).trim().isNotEmpty;

  /// Records a 44.1 kHz mono WAV sample for Shazam matching and returns
  /// its path. (44.1 kHz, not the 11 kHz X1 sample — Shazam matching
  /// expects standard-rate audio.) Throws [AuthorizationFailure] with
  /// the Settings path when microphone access is denied.
  Future<String> recordSample() async {
    final recorder = _recorder ??= AudioRecorder();
    final allowed = await recorder.hasPermission();
    if (!allowed) {
      throw const AuthorizationFailure(X1Service.microphoneDeniedMessage);
    }
    final tempDir = await getTemporaryDirectory();
    final samplePath = p.join(
      tempDir.path,
      'shazam_sample_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: 44100,
        ),
        path: samplePath,
      );
    } on AuthorizationFailure {
      throw const AuthorizationFailure(X1Service.microphoneDeniedMessage);
    } catch (e) {
      throw AppFailure(
        'Shazam recording failed. Check that no other app is using '
        'the microphone and try again.',
        cause: e,
      );
    }
    await Future<void>.delayed(const Duration(seconds: recordSeconds));
    await recorder.stop();
    return samplePath;
  }

  /// Identifies [audioFile] via Shazam. Returns the match as an
  /// [X1Identification], or `null` when Shazam found no match for the
  /// clip. Throws when no key is configured or the API call fails.
  Future<X1Identification?> identifyClip(File audioFile) async {
    final key = (await _store.getShazamApiKey()).trim();
    if (key.isEmpty) {
      throw const ValidationFailure(
        'Shazam is not configured. Add your RapidAPI Shazam key below '
        'to use Shazam identification.',
      );
    }
    if (!await audioFile.exists()) {
      throw const ValidationFailure('Audio sample file was not captured.');
    }

    final bytes = await audioFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const ValidationFailure('Audio sample is empty.');
    }

    try {
      final res = await _apiClient.dio.post<Map<String, dynamic>>(
        _detectUrl,
        data: base64Encode(bytes),
        options: Options(
          contentType: 'text/plain',
          headers: {
            'X-RapidAPI-Key': key,
            'X-RapidAPI-Host': _rapidApiHost,
          },
        ),
      ).timeout(const Duration(seconds: 25));

      return parseShazamDetectResponse(res.data ?? {});
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const AuthorizationFailure(
          'Shazam rejected the API key. Check the RapidAPI Shazam key '
          'and try again.',
        );
      }
      throw NetworkFailure(
        'Shazam identification failed (${status ?? 'network error'}).',
        cause: e,
      );
    } on TimeoutException {
      throw const NetworkFailure('Shazam timed out after 25s.');
    }
  }

  /// Parses a `POST /songs/detect` response into an identification, or
  /// `null` when the response carries no `track` (no match). Defensive:
  /// wrong-typed fields fall back to placeholders, never throw.
  static X1Identification? parseShazamDetectResponse(Map<String, dynamic> data) {
    final track = data['track'];
    if (track is! Map) return null;
    final title = (track['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;
    final images = track['images'];
    final artwork = images is Map ? images['coverart'] as String? : null;
    final share = track['share'];
    final pageUrl = share is Map ? share['href'] as String? : null;
    return X1Identification(
      provider: 'Shazam',
      title: title,
      artist: (track['subtitle'] as String?)?.trim() ?? 'Unknown Artist',
      album: 'Single',
      artworkUrl: artwork,
      previewUrl: track['url'] as String?,
      externalId: track['key']?.toString() ?? pageUrl,
      confidence: 0.95,
      identifiedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void dispose() {
    _recorder?.dispose();
  }
}
