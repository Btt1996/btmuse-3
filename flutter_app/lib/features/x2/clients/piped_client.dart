import 'package:dio/dio.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/clients/provider_diagnostics.dart';

/// Optional Piped API client supporting configurable instance lists,
/// pre-flight availability checks, strict timeouts, and automatic failover.
class PipedClient {
  final ApiClient _apiClient;
  final Duration timeout;

  PipedClient(
    this._apiClient, {
    this.timeout = const Duration(milliseconds: 4500),
  });

  Future<InstanceProbeResult> probeInstance(String rawBaseUrl) async {
    final baseUrl = rawBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final sw = Stopwatch()..start();
    try {
      final res = await _apiClient.dio.get<dynamic>(
        '$baseUrl/trending',
        queryParameters: const {'region': 'US'},
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
          provider: 'piped',
          instanceUrl: baseUrl,
          available: false,
          latencyMs: sw.elapsedMilliseconds,
          statusCode: status,
          error: 'HTTP $status',
        );
      }
      if (res.data is! List) {
        return InstanceProbeResult(
          provider: 'piped',
          instanceUrl: baseUrl,
          available: false,
          latencyMs: sw.elapsedMilliseconds,
          statusCode: status,
          error: 'Unexpected payload (expected Piped JSON array)',
        );
      }
      return InstanceProbeResult(
        provider: 'piped',
        instanceUrl: baseUrl,
        available: true,
        latencyMs: sw.elapsedMilliseconds,
        statusCode: status,
      );
    } catch (e) {
      sw.stop();
      return InstanceProbeResult(
        provider: 'piped',
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
        message: 'PIPED_API_URL is not configured.',
      );
    }

    final attempts = <ProviderAttempt>[];
    for (final rawUrl in instances) {
      final baseUrl = rawUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final probe = await probeInstance(baseUrl);
      attempts.add(
        ProviderAttempt(
          provider: 'piped',
          instanceUrl: baseUrl,
          stage: 'probe',
          ok: probe.available,
          error: probe.error,
        ),
      );
      if (!probe.available) continue;

      try {
        final res = await _apiClient.dio.get<dynamic>(
          '$baseUrl/search',
          queryParameters: {'q': query, 'filter': 'music_songs'},
          options: Options(
            sendTimeout: timeout,
            receiveTimeout: timeout,
            headers: const {'Accept': 'application/json'},
            validateStatus: (s) => s != null && s < 600,
          ),
        );
        final status = res.statusCode ?? 0;
        if (status < 200 || status >= 300 || res.data is! Map) {
          attempts.add(
            ProviderAttempt(
              provider: 'piped',
              instanceUrl: baseUrl,
              stage: 'search',
              ok: false,
              error: status >= 200 && status < 300
                  ? 'Invalid search JSON structure'
                  : 'HTTP $status',
            ),
          );
          continue;
        }

        final data = res.data as Map;
        final rawItems = (data['items'] as List<dynamic>?) ?? const [];
        final results = <X2Result>[];

        for (final item in rawItems.whereType<Map<dynamic, dynamic>>()) {
          final watchPath = item['url'] as String?;
          if (watchPath == null || !watchPath.contains('/watch?v=')) continue;
          final videoId = watchPath.replaceFirst('/watch?v=', '').split('&').first;
          if (videoId.isEmpty) continue;

          final norm = MetadataNormalizer.normalize(
            rawTitle: (item['title'] as String?) ?? 'YouTube Track',
            rawArtist: (item['uploaderName'] as String?) ?? 'Creator',
          );

          results.add(
            X2Result(
              id: 'piped_$videoId',
              providerId: 'youtube',
              providerLabel: 'YouTube (Piped)',
              title: norm.title,
              artist: norm.artist,
              album: 'Piped Index',
              durationSeconds: (item['duration'] as num?)?.toInt() ?? 0,
              artworkUrl: item['thumbnail'] as String?,
              externalPageUrl: 'https://www.youtube.com/watch?v=$videoId',
              audioAvailable: false,
              downloadAuthorized: false,
              authorizationNote:
                  'Retrieved via Piped (${Uri.tryParse(baseUrl)?.host ?? baseUrl}). Tap Find Authorized Source to acquire permitted audio.',
            ),
          );
          if (results.length >= limit) break;
        }

        attempts.add(
          ProviderAttempt(
            provider: 'piped',
            instanceUrl: baseUrl,
            stage: 'search',
            ok: true,
          ),
        );

        return FailoverClientResult(
          ok: true,
          providerUsed: 'piped',
          instanceUsed: baseUrl,
          items: results,
          attempts: attempts,
          message: 'Piped (${Uri.tryParse(baseUrl)?.host ?? baseUrl}) returned ${results.length} item(s).',
        );
      } catch (e) {
        attempts.add(
          ProviderAttempt(
            provider: 'piped',
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
      message: 'All configured Piped instances failed (${attempts.map((a) => a.formatSummary()).join('; ')}).',
    );
  }
}
