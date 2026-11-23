import 'package:dio/dio.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';

/// Jamendo independent-music catalog provider (Creative Commons tracks).
///
/// Authentication is a per-user `client_id` from the Jamendo developer
/// portal (https://devportal.jamendo.com) — no client secret is ever
/// needed or sent by the app. The ID is stored in the secure
/// credentials store and carried on `X2Config.jamendoClientId`.
///
/// Honesty contract (same pattern as SoundCloud / VK): when NO client
/// ID is configured, keyword search is NOT offered
/// (`supportsKeywordSearch` is false) and [searchTracks] throws an
/// [AuthorizationFailure] that names exactly where to set it
/// ("Jamendo client ID in Settings"). Nothing is faked, and no
/// client ID is ever invented.
class JamendoProvider implements X2Provider {
  final ApiClient _apiClient;

  /// Mutable on purpose: the app wires it to `X2Config` via the same
  /// `ref.listen` config-watch pattern `ApiClient` uses, so saving the
  /// ID in Settings takes effect without restarting the app.
  String? jamendoClientId;

  JamendoProvider(this._apiClient, {this.jamendoClientId});

  bool get _hasClientId =>
      jamendoClientId != null && jamendoClientId!.trim().isNotEmpty;

  @override
  String get id => 'jamendo';

  @override
  String get displayName => 'Jamendo';

  @override
  bool get supportsKeywordSearch => _hasClientId;

  @override
  bool get supportsUrlResolution => true;

  @override
  bool get isMetadataOnly => false;

  @override
  bool canHandleUrl(Uri uri) =>
      uri.host.toLowerCase().contains('jamendo.com');

  static const _missingClientId = AuthorizationFailure(
    'Jamendo keyword search needs a client ID. Set the Jamendo client ID in Settings to enable it.',
    code: 'jamendo_client_id_missing',
  );

  void _requireClientId() {
    if (!_hasClientId) throw _missingClientId;
  }

  static int _parseInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  X2Result? _resultFromTrack(Map<dynamic, dynamic> raw) {
    final trackId = raw['id']?.toString();
    if (trackId == null || trackId.isEmpty) return null;
    final streamUrl = (raw['audio'] as String?)?.trim();
    final downloadUrl = (raw['audiodownload'] as String?)?.trim();
    final audioUrl =
        (downloadUrl != null && downloadUrl.isNotEmpty) ? downloadUrl : streamUrl;
    if (audioUrl == null || audioUrl.isEmpty) return null;
    if (!ApiClient.isSafeExternalUrl(audioUrl)) return null;

    final norm = MetadataNormalizer.normalize(
      rawTitle: (raw['name'] as String?) ?? 'Jamendo Track',
      rawArtist: (raw['artist_name'] as String?) ?? 'Jamendo Artist',
      rawAlbum: (raw['album_name'] as String?) ?? 'Single',
    );
    final licenseUrl = (raw['license_ccurl'] as String?)?.trim();
    final hasDownload = downloadUrl != null && downloadUrl.isNotEmpty;

    return X2Result(
      id: 'jam_$trackId',
      providerId: id,
      providerLabel: displayName,
      title: norm.title,
      artist: norm.artist,
      album: norm.album,
      durationSeconds: _parseInt(raw['duration']),
      artworkUrl: (raw['album_image'] as String?) ?? (raw['image'] as String?),
      audioUrl: audioUrl,
      externalPageUrl: (raw['shareurl'] as String?) ?? 'https://www.jamendo.com/track/$trackId',
      format: 'MP3',
      audioAvailable: true,
      downloadAuthorized: hasDownload,
      licenseName: (licenseUrl != null && licenseUrl.isNotEmpty)
          ? 'Creative Commons'
          : null,
      authorizationNote: hasDownload
          ? 'Jamendo independent-music track (Creative Commons). Download link supplied by the Jamendo API.'
          : 'Jamendo independent-music track (Creative Commons). Stream URL only — no API download link was returned for this track.',
    );
  }

  Future<List<X2Result>> _fetchTracks(Map<String, dynamic> params) async {
    _requireClientId();
    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://api.jamendo.com/v3.0/tracks/',
      queryParameters: {
        'client_id': jamendoClientId!.trim(),
        'format': 'json',
        ...params,
      },
      options: Options(
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final results = (res.data?['results'] as List<dynamic>?) ?? const [];
    return results
        .whereType<Map<dynamic, dynamic>>()
        .map(_resultFromTrack)
        .whereType<X2Result>()
        .toList();
  }

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 12}) async {
    return _fetchTracks({'search': query, 'limit': limit});
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async {
    _requireClientId();
    // Track pages look like https://www.jamendo.com/track/{id}/<slug>.
    final segments = uri.pathSegments;
    final trackIndex = segments.indexOf('track');
    if (trackIndex < 0 || trackIndex + 1 >= segments.length) return null;
    final trackId = segments[trackIndex + 1];
    if (int.tryParse(trackId) == null) return null;
    final results = await _fetchTracks({'id': trackId, 'limit': 1});
    return results.isEmpty ? null : results.first;
  }
}
