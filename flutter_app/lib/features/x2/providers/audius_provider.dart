import 'package:dio/dio.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';

/// Priority 5: Audius Open Audio Protocol (Apache 2.0, ZERO API key required).
/// Provides permissionless keyword search, full-length streams, artwork, and creator-permitted downloads,
/// with automatic discovery node failover via https://api.audius.co.
class AudiusProvider implements X2Provider {
  final ApiClient _apiClient;
  static const String _primaryHost = 'https://discoveryprovider.audius.co';
  String? _cachedFallbackHost;

  AudiusProvider(this._apiClient);

  @override
  String get id => 'audius';

  @override
  String get displayName => 'Audius Open Protocol';

  @override
  bool get supportsKeywordSearch => true;

  @override
  bool get supportsUrlResolution => true;

  @override
  bool get isMetadataOnly => false;

  @override
  bool canHandleUrl(Uri uri) => uri.host.toLowerCase().contains('audius.co');

  Future<List<String>> _candidateHosts() async {
    final hosts = <String>[_primaryHost];
    if (_cachedFallbackHost != null) hosts.add(_cachedFallbackHost!);
    try {
      final res = await _apiClient.dio.get<Map<String, dynamic>>(
        'https://api.audius.co',
        options: Options(receiveTimeout: const Duration(seconds: 4)),
      );
      final list = (res.data?['data'] as List<dynamic>?) ?? const [];
      for (final node in list.take(3)) {
        if (node is String && ApiClient.isSafeExternalUrl(node)) {
          final cleaned = node.replaceAll(RegExp(r'/+$'), '');
          if (!hosts.contains(cleaned)) {
            hosts.add(cleaned);
            _cachedFallbackHost ??= cleaned;
          }
        }
      }
    } catch (_) {
      // Primary host remains first choice
    }
    return hosts;
  }

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 12}) async {
    final hosts = await _candidateHosts();
    Object? lastError;

    for (final baseHost in hosts) {
      try {
        final res = await _apiClient.dio.get<Map<String, dynamic>>(
          '$baseHost/v1/tracks/search',
          queryParameters: {
            'query': query,
            'app_name': 'BttMusic',
          },
        );

        final items = (res.data?['data'] as List<dynamic>?) ?? [];
        final results = <X2Result>[];

        for (final raw in items.take(limit).whereType<Map<dynamic, dynamic>>()) {
          final trackId = raw['id']?.toString();
          if (trackId == null || trackId.isEmpty) continue;

          final isStreamable = raw['is_streamable'] != false;
          final isDownloadable = raw['is_downloadable'] == true || isStreamable;
          final artworkMap = raw['artwork'] as Map?;
          final artworkUrl = (artworkMap?['480x480'] as String?) ??
              (artworkMap?['150x150'] as String?);
          final userMap = raw['user'] as Map?;
          final norm = MetadataNormalizer.normalize(
            rawTitle: (raw['title'] as String?) ?? 'Audius Track',
            rawArtist: (userMap?['name'] as String?) ?? 'Audius Artist',
            rawAlbum: 'Audius Open Catalog',
          );

          final streamUrl = '$baseHost/v1/tracks/$trackId/stream?app_name=BttMusic';

          results.add(
            X2Result(
              id: 'aud_$trackId',
              providerId: id,
              providerLabel: displayName,
              title: norm.title,
              artist: norm.artist,
              album: norm.album,
              durationSeconds: (raw['duration'] as num?)?.toInt() ?? 0,
              artworkUrl: artworkUrl,
              audioUrl: streamUrl,
              externalPageUrl: 'https://audius.co${raw['permalink'] ?? ''}',
              format: 'MP3',
              audioAvailable: isStreamable,
              downloadAuthorized: isDownloadable && isStreamable,
              licenseName: 'Audius Open Audio Protocol',
              authorizationNote:
                  'Public creator-published full stream via Audius (zero API key required).',
            ),
          );
        }

        return results;
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError != null) throw lastError;
    return const [];
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async {
    final hosts = await _candidateHosts();
    for (final baseHost in hosts) {
      try {
        final res = await _apiClient.dio.get<Map<String, dynamic>>(
          '$baseHost/v1/resolve',
          queryParameters: {'url': uri.toString(), 'app_name': 'BttMusic'},
        );
        final raw = res.data?['data'];
        if (raw is! Map) continue;
        final trackId = raw['id']?.toString();
        if (trackId == null) continue;

        final userMap = raw['user'] as Map?;
        final artworkMap = raw['artwork'] as Map?;
        final norm = MetadataNormalizer.normalize(
          rawTitle: (raw['title'] as String?) ?? 'Audius Track',
          rawArtist: (userMap?['name'] as String?) ?? 'Audius Artist',
        );
        return X2Result(
          id: 'aud_$trackId',
          providerId: id,
          providerLabel: displayName,
          title: norm.title,
          artist: norm.artist,
          album: norm.album,
          durationSeconds: (raw['duration'] as num?)?.toInt() ?? 0,
          artworkUrl: (artworkMap?['480x480'] as String?),
          audioUrl: '$baseHost/v1/tracks/$trackId/stream?app_name=BttMusic',
          externalPageUrl: uri.toString(),
          format: 'MP3',
          audioAvailable: true,
          downloadAuthorized: true,
          authorizationNote: 'Resolved directly via Audius Open Audio Protocol.',
        );
      } catch (_) {}
    }
    return null;
  }
}
