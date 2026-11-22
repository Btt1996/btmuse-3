import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';

/// Zero-Key Deezer Public Catalog Provider.
/// Supplies fast metadata, high-res artwork, and verified 30s preview streams without OAuth/API keys.
class DeezerProvider implements X2Provider {
  final ApiClient _apiClient;

  DeezerProvider(this._apiClient);

  @override
  String get id => 'deezer';

  @override
  String get displayName => 'Deezer Public';

  @override
  bool get supportsKeywordSearch => true;

  @override
  bool get supportsUrlResolution => false;

  @override
  bool get isMetadataOnly => true;

  @override
  bool canHandleUrl(Uri uri) => uri.host.toLowerCase().contains('deezer.com');

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 10}) async {
    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://api.deezer.com/search',
      queryParameters: {'q': query, 'limit': limit},
    );
    final data = (res.data?['data'] as List<dynamic>?) ?? [];
    return data.whereType<Map<dynamic, dynamic>>().map((raw) {
      final norm = MetadataNormalizer.normalize(
        rawTitle: (raw['title'] as String?) ?? 'Track',
        rawArtist: (raw['artist']?['name'] as String?) ?? 'Artist',
        rawAlbum: (raw['album']?['title'] as String?) ?? 'Single',
      );
      final preview = raw['preview'] as String?;
      return X2Result(
        id: 'dz_${raw['id']}',
        providerId: id,
        providerLabel: displayName,
        title: norm.title,
        artist: norm.artist,
        album: norm.album,
        durationSeconds: (raw['duration'] as num?)?.toInt() ?? 0,
        artworkUrl: (raw['album']?['cover_big'] as String?) ??
            (raw['album']?['cover_medium'] as String?),
        audioUrl: preview,
        externalPageUrl: raw['link'] as String?,
        format: 'MP3 Preview',
        audioAvailable: preview != null && preview.isNotEmpty,
        downloadAuthorized: false,
        authorizationNote: 'Public Deezer metadata & 30s verification preview (zero API key).',
      );
    }).toList();
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async => null;
}
