import 'package:dio/dio.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/clients/provider_diagnostics.dart';

/// Optional Invidious API client supporting configurable instance lists,
/// pre-flight health checks (`/api/v1/stats`), strict timeouts, and failover.
class InvidiousClient {
  final ApiClient _apiClient;
  final Duration timeout;

  InvidiousClient(
    this._apiClient, {
    this.timeout = const Duration(milliseconds: 4500),
  });

  Future<InstanceProbeResult> probeInstance(String rawBaseUrl) async {
    final baseUrl = rawBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final sw = Stopwatch()..start();
    try {
      final res = await _apiClient.dio.get<dynamic>(
        '$baseUrl/api/v1/stats',
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: const {
            'User-Agent': 'BttMusic/2.00 (HealthCheck)',
            'Accept': 'application/json',
          },
          validateStatus: (s) => s != null && s < 600,
        ),
      );
      sw.stop();
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return InstanceProbeResult(
          provider: 'invidious',
          instanceUrl: baseUrl,
          available: false,
          latencyMs: sw.elapsedMilliseconds,
          statusCode: status,
          error: 'HTTP $status',
        );
      }
      if (res.data is! Map) {
        return InstanceProbeResult(
          provider: 'invidious',
          instanceUrl: baseUrl,
          available: false,
          latencyMs: sw.elapsedMilliseconds,
          statusCode: status,
          error: 'Unexpected payload (expected Invidious JSON object)',
        );
      }
      return InstanceProbeResult(
        provider: 'invidious',
        instanceUrl: baseUrl,
        available: true,
        latencyMs: sw.elapsedMilliseconds,
        statusCode: status,
      );
    } catch (e) {
      sw.stop();
      return InstanceProbeResult(
        provider: 'invidious',
        instanceUrl: baseUrl,
        available: false,
        latencyMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  Future<FailoverClientResult> search(
    String query,
    List<String> instances, {
    int limit = 10,
  }) async {
    if (instances.isEmpty) {
      return const FailoverClientResult(
        ok: false,
        items: [],
        attempts: [],
        message: 'INVIDIOUS_API_URL is not configured.',
      );
    }

    final attempts = <ProviderAttempt>[];
    for (final rawUrl in instances) {
      final baseUrl = rawUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final probe = await probeInstance(baseUrl);
      attempts.add(
        ProviderAttempt(
          provider: 'invidious',
          instanceUrl: baseUrl,
          stage: 'probe',
          ok: probe.available,
          error: probe.error,
        ),
      );
      if (!probe.available) continue;

      try {
        final res = await _apiClient.dio.get<dynamic>(
          '$baseUrl/api/v1/search',
          queryParameters: {'q': query, 'type': 'video'},
          options: Options(
            sendTimeout: timeout,
            receiveTimeout: timeout,
            headers: const {'Accept': 'application/json'},
            validateStatus: (s) => s != null && s < 600,
          ),
        );
        final status = res.statusCode ?? 0;
        if (status < 200 || status >= 300 || res.data is! List) {
          attempts.add(
            ProviderAttempt(
              provider: 'invidious',
              instanceUrl: baseUrl,
              stage: 'search',
              ok: false,
              error: status >= 200 && status < 300
                  ? 'Invalid search JSON list'
                  : 'HTTP $status',
            ),
          );
          continue;
        }

        final rawItems = res.data as List<dynamic>;
        final results = <X2Result>[];

        for (final item in rawItems.whereType<Map<dynamic, dynamic>>()) {
          final videoId = item['videoId'] as String?;
          if (videoId == null || videoId.isEmpty) continue;

          final thumbs = item['videoThumbnails'] as List<dynamic>?;
          final firstThumb = (thumbs != null && thumbs.isNotEmpty && thumbs.first is Map)
              ? (thumbs.first as Map)['url'] as String?
              : null;

          final norm = MetadataNormalizer.normalize(
            rawTitle: (item['title'] as String?) ?? 'YouTube Video',
            rawArtist: (item['author'] as String?) ?? 'YouTube Creator',
          );

          results.add(
            X2Result(
              id: 'inv_$videoId',
              providerId: 'youtube',
              providerLabel: 'YouTube (Invidious)',
              title: norm.title,
              artist: norm.artist,
              album: 'Invidious Index',
              durationSeconds: (item['lengthSeconds'] as num?)?.toInt() ?? 0,
              artworkUrl: firstThumb,
              externalPageUrl: 'https://www.youtube.com/watch?v=$videoId',
              audioAvailable: false,
              downloadAuthorized: false,
              authorizationNote:
                  'Retrieved via Invidious (${Uri.tryParse(baseUrl)?.host ?? baseUrl}). Tap Find Authorized Source to acquire permitted audio.',
            ),
          );
          if (results.length >= limit) break;
        }

        attempts.add(
          ProviderAttempt(
            provider: 'invidious',
            instanceUrl: baseUrl,
            stage: 'search',
            ok: true,
          ),
        );

        return FailoverClientResult(
          ok: true,
          providerUsed: 'invidious',
          instanceUsed: baseUrl,
          items: results,
          attempts: attempts,
          message:
              'Invidious (${Uri.tryParse(baseUrl)?.host ?? baseUrl}) returned ${results.length} item(s).',
        );
      } catch (e) {
        attempts.add(
          ProviderAttempt(
            provider: 'invidious',
            instanceUrl: baseUrl,
            stage: 'search',
            ok: false,
            error: e.toString(),
          ),
        );
      }
    }

    return FailoverClientResult(
      ok: false,
      items: const [],
      attempts: attempts,
      message:
          'All configured Invidious instances failed (${attempts.map((a) => a.formatSummary()).join('; ')}).',
    );
  }
}
