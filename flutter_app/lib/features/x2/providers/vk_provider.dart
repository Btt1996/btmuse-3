import 'package:dio/dio.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';

/// Priority 1: VK Music Retrieval Adapter.
/// - Works standalone from iOS for public VK track/playlist URLs via direct OpenGraph inspection.
/// - Also supports optional X2_BACKEND_URL `/api/x2/url-inspect` and optional user VK access token.
/// - Honestly reports when VK keyword search / audio retrieval is blocked by VK API auth or encrypted HLS.
class VkProvider implements X2Provider {
  final ApiClient _apiClient;

  VkProvider(this._apiClient);

  @override
  String get id => 'vk';

  @override
  String get displayName => 'VK Music';

  @override
  bool get supportsKeywordSearch => true;

  @override
  bool get supportsUrlResolution => true;

  @override
  bool get isMetadataOnly => true;

  @override
  bool canHandleUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'vk.com' || host.endsWith('.vk.com') || host == 'vk.ru';
  }

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 10}) async {
    throw const AuthorizationFailure(
      'VK permanently deprecated unauthenticated audio.search. Paste a public VK audio URL directly, or open VK Music Import in the Import Center for URL inspection.',
      code: 'vk_auth_required',
    );
  }

  /// Searches using a user-provided VK access token (stored only when user chooses to enter one).
  Future<List<X2Result>> searchWithUserToken(
    String query, {
    required String vkAccessToken,
    int limit = 12,
  }) async {
    final token = vkAccessToken.trim();
    if (token.isEmpty) {
      throw const ValidationFailure('Enter a VK user access token first.');
    }

    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://api.vk.com/method/audio.search',
      queryParameters: {
        'q': query,
        'count': limit,
        'access_token': token,
        'v': '5.131',
      },
      options: Options(
        headers: const {'User-Agent': 'VKAndroidApp/5.52-4543 (Android 11; SDK 30)'},
      ),
    );

    final data = res.data ?? {};
    if (data['error'] != null) {
      final errMsg = (data['error'] as Map)['error_msg']?.toString() ?? 'VK API error';
      throw AuthorizationFailure('VK API rejected search: $errMsg');
    }

    final items = (data['response']?['items'] as List<dynamic>?) ?? const [];
    final results = <X2Result>[];
    for (final raw in items.whereType<Map<dynamic, dynamic>>()) {
      final url = (raw['url'] as String?) ?? '';
      final isDirectMp3 = url.isNotEmpty && !url.contains('.m3u8');
      final norm = MetadataNormalizer.normalize(
        rawTitle: (raw['title'] as String?) ?? 'VK Track',
        rawArtist: (raw['artist'] as String?) ?? 'VK Artist',
        rawAlbum: 'VK Audio',
      );
      results.add(
        X2Result(
          id: 'vk_api_${raw['owner_id']}_${raw['id']}',
          providerId: id,
          providerLabel: displayName,
          title: norm.title,
          artist: norm.artist,
          album: norm.album,
          durationSeconds: (raw['duration'] as num?)?.toInt() ?? 0,
          audioUrl: url.isNotEmpty ? url : null,
          format: isDirectMp3 ? 'MP3' : 'HLS (m3u8)',
          audioAvailable: url.isNotEmpty,
          downloadAuthorized: isDirectMp3,
          authorizationNote: isDirectMp3
              ? 'Authorized direct MP3 returned from your VK user session.'
              : (url.contains('.m3u8')
                  ? 'VK returned encrypted HLS (.m3u8) stream rather than downloadable MP3.'
                  : 'VK restricted stream URL for this track.'),
        ),
      );
    }
    return results;
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async {
    // 1. Direct OpenGraph inspection from iOS first (no backend required)
    try {
      final res = await _apiClient.dio.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: const {
            'User-Agent': 'BttMusic/3.0 (iOS; Public Metadata)',
            'Accept-Language': 'en-US,en;q=0.9',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final html = res.data ?? '';
      final titleMatch =
          RegExp(r'''<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']''', caseSensitive: false)
              .firstMatch(html);
      final descMatch = RegExp(
        r'''<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      final imageMatch = RegExp(
        r'''<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(html);

      if (titleMatch != null) {
        final norm = MetadataNormalizer.normalize(
          rawTitle: titleMatch.group(1)!,
          rawArtist: descMatch?.group(1) ?? 'VK Music',
          rawAlbum: 'VK Reference',
        );
        return X2Result(
          id: 'vk_${uri.toString().hashCode}',
          providerId: id,
          providerLabel: displayName,
          title: norm.title,
          artist: norm.artist,
          album: norm.album,
          artworkUrl: imageMatch?.group(1),
          externalPageUrl: uri.toString(),
          audioAvailable: false,
          downloadAuthorized: false,
          authorizationNote:
              'VK public page metadata resolved. Direct VK audio streams require a VK user session and often use encrypted HLS.',
        );
      }
    } catch (_) {
      // Fall back to companion server if configured
    }

    // 2. Companion server OpenGraph proxy fallback if X2_BACKEND_URL is configured
    if (_apiClient.isBackendConfigured) {
      try {
        final res = await _apiClient.dio.post<Map<String, dynamic>>(
          _apiClient.buildBackendUri('/api/x2/url-inspect').toString(),
          data: {'url': uri.toString()},
        );
        final data = res.data ?? {};
        final norm = MetadataNormalizer.normalize(
          rawTitle: (data['title'] as String?) ?? 'VK Audio Link',
          rawArtist: (data['artist'] as String?) ?? 'VK Music',
          rawAlbum: 'VK Reference',
        );
        return X2Result(
          id: 'vk_${uri.toString().hashCode}',
          providerId: id,
          providerLabel: displayName,
          title: norm.title,
          artist: norm.artist,
          album: norm.album,
          artworkUrl: data['artworkUrl'] as String?,
          externalPageUrl: uri.toString(),
          audioAvailable: data['audioAvailable'] == true,
          downloadAuthorized: data['downloadAuthorized'] == true,
          authorizationNote: (data['authorizationNote'] as String?) ??
              'VK metadata resolved via X2_BACKEND_URL.',
        );
      } catch (_) {}
    }

    return X2Result(
      id: 'vk_${uri.toString().hashCode}',
      providerId: id,
      providerLabel: displayName,
      title: 'VK Audio Link (Restricted)',
      artist: 'VK Music',
      album: 'VK Reference',
      externalPageUrl: uri.toString(),
      audioAvailable: false,
      downloadAuthorized: false,
      authorizationNote:
          'VK blocked unauthenticated access to this link. Open VK Music in Import Center to use an optional user session token or search open X2 sources.',
    );
  }
}
