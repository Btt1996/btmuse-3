import 'dart:convert';
import '../../../core/networking/api_client.dart';
import '../../../core/utilities/metadata_normalizer.dart';
import '../../../data/models/x2_result.dart';
import 'x2_provider.dart';

class ItunesMetadataProvider implements X2Provider {
  final ApiClient _apiClient;

  ItunesMetadataProvider(this._apiClient);

  @override
  String get id => 'itunes';

  @override
  String get displayName => 'Apple Catalog';

  @override
  bool get supportsKeywordSearch => true;

  @override
  bool get supportsUrlResolution => false;

  @override
  bool get isMetadataOnly => true;

  @override
  bool canHandleUrl(Uri uri) => uri.host.toLowerCase().contains('music.apple.com');

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 10}) async {
    final res = await _apiClient.dio.get<dynamic>(
      'https://itunes.apple.com/search',
      queryParameters: {
        'term': query,
        'media': 'music',
        'entity': 'song',
        'limit': limit,
      },
    );

    final decoded = res.data is String ? jsonDecode(res.data as String) : res.data;
    final results = (decoded?['results'] as List<dynamic>?) ?? [];

    return results.whereType<Map<dynamic, dynamic>>().map((raw) {
      final art = (raw['artworkUrl100'] as String?)?.replaceAll('100x100bb', '600x600bb');
      final norm = MetadataNormalizer.normalize(
        rawTitle: (raw['trackName'] as String?) ?? 'Track',
        rawArtist: (raw['artistName'] as String?) ?? 'Artist',
        rawAlbum: (raw['collectionName'] as String?) ?? 'Single',
      );
      return X2Result(
        id: 'itunes_${raw['trackId']}',
        providerId: id,
        providerLabel: displayName,
        title: norm.title,
        artist: norm.artist,
        album: norm.album,
        durationSeconds: ((raw['trackTimeMillis'] as num?)?.toInt() ?? 0) ~/ 1000,
        artworkUrl: art,
        audioUrl: raw['previewUrl'] as String?,
        externalPageUrl: raw['trackViewUrl'] as String?,
        format: 'M4A Preview',
        audioAvailable: (raw['previewUrl'] as String?)?.isNotEmpty == true,
        downloadAuthorized: false,
        authorizationNote:
            'Official catalog metadata & 30s preview only. Full offline download is not authorized directly from Apple Music.',
      );
    }).toList();
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async => null;
}
