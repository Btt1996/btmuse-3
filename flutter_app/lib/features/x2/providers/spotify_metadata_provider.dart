import '../../../core/networking/api_client.dart';
import '../../../core/utilities/metadata_normalizer.dart';
import '../../../data/models/x2_result.dart';
import 'x2_provider.dart';

class SpotifyMetadataProvider implements X2Provider {
  final ApiClient _apiClient;

  SpotifyMetadataProvider(this._apiClient);

  @override
  String get id => 'spotify';

  @override
  String get displayName => 'Spotify Metadata';

  @override
  bool get supportsKeywordSearch => false;

  @override
  bool get supportsUrlResolution => true;

  @override
  bool get isMetadataOnly => true;

  @override
  bool canHandleUrl(Uri uri) => uri.host.toLowerCase().contains('open.spotify.com');

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 8}) async => [];

  @override
  Future<X2Result?> resolveUrl(Uri uri) async {
    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://open.spotify.com/oembed',
      queryParameters: {'url': uri.toString()},
    );
    final data = res.data ?? {};
    if (data['title'] == null) return null;

    final norm = MetadataNormalizer.normalize(
      rawTitle: data['title'] as String,
      rawArtist: (data['author_name'] as String?) ?? 'Spotify Artist',
      rawAlbum: 'Spotify Reference',
    );
    return X2Result(
      id: 'sp_${uri.toString().hashCode}',
      providerId: id,
      providerLabel: displayName,
      title: norm.title,
      artist: norm.artist,
      album: norm.album,
      artworkUrl: data['thumbnail_url'] as String?,
      externalPageUrl: uri.toString(),
      audioAvailable: false,
      downloadAuthorized: false,
      authorizationNote:
          'Spotify metadata resolved via official oEmbed. DRM-protected audio cannot be ripped; search X2 open sources instead.',
    );
  }
}
