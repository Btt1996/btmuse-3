import 'package:dio/dio.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/clients/invidious_client.dart';
import 'package:btmu/features/x2/clients/piped_client.dart';
import 'package:btmu/features/x2/clients/provider_diagnostics.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';

/// Priority 3: YouTube Discovery & URL Adapter (Zero Google API key required).
/// - URL resolution works standalone via official zero-key https://www.youtube.com/oembed.
/// - Keyword search checks:
///   1. Configured Piped instances (`PIPED_API_URL`) with probe & failover
///   2. Configured Invidious instances (`INVIDIOUS_API_URL`) with probe & failover
///   3. Deployed Btt Music companion backend (`X2_BACKEND_URL`) if configured
/// - Never invents a backend URL and never simulates downloads or fake tracks.
class YoutubeProvider implements X2Provider {
  final ApiClient _apiClient;
  final PipedClient _pipedClient;
  final InvidiousClient _invidiousClient;

  YoutubeProvider(
    this._apiClient, {
    PipedClient? pipedClient,
    InvidiousClient? invidiousClient,
  })  : _pipedClient = pipedClient ?? PipedClient(_apiClient),
        _invidiousClient = invidiousClient ?? InvidiousClient(_apiClient);

  @override
  String get id => 'youtube';

  @override
  String get displayName => 'YouTube';

  @override
  bool get supportsKeywordSearch => true;

  @override
  bool get supportsUrlResolution => true;

  @override
  bool get isMetadataOnly => true;

  @override
  bool canHandleUrl(Uri uri) {
    final h = uri.host.toLowerCase();
    return h.contains('youtube.com') || h == 'youtu.be';
  }

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 8}) async {
    final diagnosticNotes = <String>[];

    // 1. Direct Piped instances with availability check + multi-instance failover
    if (_apiClient.pipedInstances.isNotEmpty) {
      final pipedRes = await _pipedClient.search(
        query,
        _apiClient.pipedInstances,
        limit: limit,
      );
      if (pipedRes.ok && pipedRes.items.isNotEmpty) {
        return pipedRes.items;
      }
      diagnosticNotes.add(pipedRes.message);
    }

    // 2. Direct Invidious failover across configured instances
    if (_apiClient.invidiousInstances.isNotEmpty) {
      final invRes = await _invidiousClient.search(
        query,
        _apiClient.invidiousInstances,
        limit: limit,
      );
      if (invRes.ok && invRes.items.isNotEmpty) {
        return invRes.items;
      }
      diagnosticNotes.add(invRes.message);
    }

    // 3. Optional deployed X2 companion backend failover (only if X2_BACKEND_URL is explicitly configured)
    if (_apiClient.isBackendConfigured) {
      try {
        final uri = _apiClient.buildBackendUri('/api/x2/youtube/search');
        final res = await _apiClient.dio.get<Map<String, dynamic>>(
          uri.toString(),
          queryParameters: {'q': query, 'limit': limit},
          options: Options(headers: _apiClient.backendHeaders()),
        );
        final data = res.data ?? {};
        final items = (data['items'] as List<dynamic>?) ?? [];
        if (data['ok'] == true && items.isNotEmpty) {
          return items.whereType<Map<dynamic, dynamic>>().map((item) {
            final norm = MetadataNormalizer.normalize(
              rawTitle: (item['title'] as String?) ?? 'YouTube Track',
              rawArtist: (item['artist'] as String?) ?? 'Creator',
            );
            final providerTag = (item['provider'] as String?) ?? 'companion';
            return X2Result(
              id: 'yt_${item['id']}',
              providerId: id,
              providerLabel: '$displayName ($providerTag)',
              title: norm.title,
              artist: norm.artist,
              album: 'YouTube Reference',
              durationSeconds: (item['duration'] as num?)?.toInt() ?? 0,
              artworkUrl: item['thumbnail'] as String?,
              externalPageUrl: item['url'] as String?,
              audioAvailable: false,
              downloadAuthorized: false,
              authorizationNote:
                  'Resolved via X2_BACKEND_URL ($providerTag). Tap Find Authorized Source to acquire permitted audio.',
            );
          }).toList();
        }
        final serverMsg = data['message'] as String?;
        if (serverMsg != null && serverMsg.isNotEmpty) {
          diagnosticNotes.add('Backend: $serverMsg');
        }
      } catch (e) {
        diagnosticNotes.add('Backend request failed: $e');
      }
    }

    // 4. Honest failure reporting (never fabricate results or invent a backend URL)
    if (_apiClient.pipedInstances.isEmpty &&
        _apiClient.invidiousInstances.isEmpty &&
        !_apiClient.isBackendConfigured) {
      throw const NetworkFailure(
        'Not configured: Set PIPED_API_URL, INVIDIOUS_API_URL, or X2_BACKEND_URL in Settings to enable YouTube keyword search (pasting direct YouTube URLs works standalone via oEmbed).',
        code: 'youtube_not_configured',
      );
    }

    throw NetworkFailure(
      diagnosticNotes.isNotEmpty
          ? diagnosticNotes.join(' | ')
          : 'YouTube discovery returned no results from configured providers.',
      code: 'youtube_providers_unavailable',
    );
  }

  /// Helper exposing raw probe/attempt history for diagnostics or tests.
  Future<FailoverClientResult> searchWithAttemptTrace(String query, {int limit = 8}) async {
    if (_apiClient.pipedInstances.isNotEmpty) {
      final pipedRes = await _pipedClient.search(
        query,
        _apiClient.pipedInstances,
        limit: limit,
      );
      if (pipedRes.ok) return pipedRes;

      if (_apiClient.invidiousInstances.isNotEmpty) {
        final invRes = await _invidiousClient.search(
          query,
          _apiClient.invidiousInstances,
          limit: limit,
        );
        return FailoverClientResult(
          ok: invRes.ok,
          providerUsed: invRes.providerUsed,
          instanceUsed: invRes.instanceUsed,
          items: invRes.items,
          attempts: [...pipedRes.attempts, ...invRes.attempts],
          message: invRes.ok ? invRes.message : '${pipedRes.message} | ${invRes.message}',
        );
      }
      return pipedRes;
    }

    if (_apiClient.invidiousInstances.isNotEmpty) {
      return _invidiousClient.search(
        query,
        _apiClient.invidiousInstances,
        limit: limit,
      );
    }

    return const FailoverClientResult(
      ok: false,
      items: [],
      attempts: [],
      message: 'Neither PIPED_API_URL nor INVIDIOUS_API_URL is configured.',
    );
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async {
    // Directly query YouTube's public zero-key oEmbed endpoint from iOS
    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://www.youtube.com/oembed',
      queryParameters: {'url': uri.toString(), 'format': 'json'},
    );
    final data = res.data ?? {};
    var rawTitle = data['title'] as String?;
    if (rawTitle == null || rawTitle.trim().isEmpty) {
      final html = data['html'] as String?;
      if (html != null) {
        final match = RegExp(r'title="([^"]+)"').firstMatch(html);
        rawTitle = match?.group(1);
      }
    }
    if (rawTitle == null || rawTitle.trim().isEmpty) return null;

    final norm = MetadataNormalizer.normalize(
      rawTitle: rawTitle,
      rawArtist: (data['author_name'] as String?) ?? 'YouTube Creator',
    );
    return X2Result(
      id: 'yt_url_${uri.toString().hashCode}',
      providerId: id,
      providerLabel: displayName,
      title: norm.title,
      artist: norm.artist,
      album: 'YouTube URL Reference',
      artworkUrl: data['thumbnail_url'] as String?,
      externalPageUrl: uri.toString(),
      audioAvailable: false,
      downloadAuthorized: false,
      authorizationNote:
          'YouTube oEmbed metadata retrieved with zero API keys. Matching open audio sources searched automatically.',
    );
  }
}
