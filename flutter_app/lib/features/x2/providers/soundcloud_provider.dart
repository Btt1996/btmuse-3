import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';

/// Priority 4: SoundCloud Public Content Adapter (Zero developer client_id required).
/// Resolves SoundCloud track/playlist URLs directly via official SoundCloud oEmbed.
/// Explicitly reports SoundCloud's closed API registration for keyword search.
/// `supportsKeywordSearch` is false on purpose: search always throws the
/// restriction failure below, so the X2 engine must not offer it as a
/// searchable provider — URL paste is the only path, and no client-ID
/// Settings field can change that (registration is closed).
class SoundCloudProvider implements X2Provider {
  final ApiClient _apiClient;

  SoundCloudProvider(this._apiClient);

  @override
  String get id => 'soundcloud';

  @override
  String get displayName => 'SoundCloud';

  @override
  bool get supportsKeywordSearch => false;

  @override
  bool get supportsUrlResolution => true;

  @override
  bool get isMetadataOnly => true;

  @override
  bool canHandleUrl(Uri uri) => uri.host.toLowerCase().contains('soundcloud.com');

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 8}) async {
    throw const AuthorizationFailure(
      'SoundCloud closed public API key registrations for keyword search. Paste a SoundCloud track URL to inspect its metadata via zero-key oEmbed, or use Audius / X2 open sources.',
      code: 'soundcloud_search_restricted',
    );
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async {
    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://soundcloud.com/oembed',
      queryParameters: {'format': 'json', 'url': uri.toString()},
    );
    final data = res.data ?? {};
    if (data['title'] == null) return null;

    final norm = MetadataNormalizer.normalize(
      rawTitle: data['title'] as String,
      rawArtist: (data['author_name'] as String?) ?? 'SoundCloud Artist',
    );

    return X2Result(
      id: 'sc_${uri.toString().hashCode}',
      providerId: id,
      providerLabel: displayName,
      title: norm.title,
      artist: norm.artist,
      album: 'SoundCloud',
      artworkUrl: data['thumbnail_url'] as String?,
      externalPageUrl: uri.toString(),
      audioAvailable: false,
      downloadAuthorized: false,
      authorizationNote:
          'Resolved via SoundCloud public oEmbed (zero API keys). Offline saving requires creator download permission on soundcloud.com.',
    );
  }
}
