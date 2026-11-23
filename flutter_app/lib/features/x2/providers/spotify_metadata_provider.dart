import 'package:dio/dio.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/networking/api_client.dart';
import '../../../core/utilities/metadata_normalizer.dart';
import '../../../data/models/track.dart';
import '../../../data/models/x2_result.dart';
import '../../../data/repositories/library_repository.dart';
import 'library_matcher.dart';
import 'x2_provider.dart';

/// One track of a resolved Spotify playlist/album, with its library
/// match attached. [existingTrack] is the library track this playlist
/// entry is already in as (matched by normalized title + artist —
/// Spotify metadata has no audio hash), or null when it is new.
class SpotifyPlaylistTrack {
  final X2Result result;
  final Track? existingTrack;

  const SpotifyPlaylistTrack({required this.result, this.existingTrack});

  bool get isInLibrary => existingTrack != null;
}

/// A resolved Spotify playlist (or album): metadata + tracklist.
/// Metadata-only by design — Spotify audio is DRM-protected and is
/// never downloaded. Every [SpotifyPlaylistTrack.result] carries
/// `downloadAuthorized: false` and an authorization note that says so.
class SpotifyPlaylist {
  final String title;
  final String description;
  final String? coverUrl;
  final String externalUrl;
  final int totalTracks;
  final List<SpotifyPlaylistTrack> tracks;

  const SpotifyPlaylist({
    required this.title,
    required this.description,
    this.coverUrl,
    required this.externalUrl,
    required this.totalTracks,
    required this.tracks,
  });

  int get inLibraryCount => tracks.where((t) => t.isInLibrary).length;
}

/// One public playlist in a Spotify user's profile, as returned by
/// `GET /api/spotify/user`. Metadata only — no audio and no tracklist
/// (tap a playlist to resolve its tracks via [SpotifyMetadataProvider.fetchPlaylist]).
class SpotifyUserPlaylistSummary {
  final String id;
  final String name;
  final String description;
  final int trackCount;
  final String? coverUrl;
  final String ownerName;
  final String externalUrl;

  const SpotifyUserPlaylistSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.trackCount,
    this.coverUrl,
    required this.ownerName,
    required this.externalUrl,
  });

  factory SpotifyUserPlaylistSummary.fromJson(Map<String, dynamic> json) {
    return SpotifyUserPlaylistSummary(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Untitled playlist',
      description: (json['description'] as String?) ?? '',
      trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
      coverUrl: json['coverUrl'] as String?,
      ownerName: (json['ownerName'] as String?) ?? '',
      externalUrl: (json['externalUrl'] as String?) ?? '',
    );
  }
}

/// A Spotify user's public playlists, as returned by
/// `GET /api/spotify/user`. Client-credentials tokens can only see
/// public playlists; private ones never appear here.
class SpotifyUserPlaylists {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final List<SpotifyUserPlaylistSummary> playlists;

  const SpotifyUserPlaylists({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.playlists,
  });

  factory SpotifyUserPlaylists.fromJson(String userId, Map<String, dynamic> json) {
    final raw = (json['playlists'] as List<dynamic>?) ?? const [];
    return SpotifyUserPlaylists(
      userId: userId,
      displayName: (json['displayName'] as String?) ?? userId,
      avatarUrl: json['avatarUrl'] as String?,
      playlists: raw
          .whereType<Map<String, dynamic>>()
          .map(SpotifyUserPlaylistSummary.fromJson)
          .toList(),
    );
  }
}

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

  /// Extracts a Spotify user ID from a plain username, an
  /// `open.spotify.com/user/<id>` profile URL (query strings
  /// ignored), a `spotify:user:<id>` URI, or an `@username`.
  /// Returns null when the input is not any of those. Mirrors
  /// `parseSpotifyUserId` in
  /// `src/services/playlistImport/spotifyDiscoveryService.ts`.
  static String? parseUserId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final urlMatch = RegExp(
      r'open\.spotify\.com/user/([a-zA-Z0-9_.\-]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (urlMatch != null) return urlMatch.group(1);
    final uriMatch = RegExp(
      r'^spotify:user:([a-zA-Z0-9_.\-]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (uriMatch != null) return uriMatch.group(1);
    final clean = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    if (RegExp(r'^[a-zA-Z0-9_.\-]+$').hasMatch(clean)) return clean;
    return null;
  }

  /// Lists a Spotify user's PUBLIC playlists via the deployed Btt
  /// Music backend (`GET /api/spotify/user?userId=<id>`).
  ///
  /// The server resolves this with its own `SPOTIFY_CLIENT_ID` /
  /// `SPOTIFY_CLIENT_SECRET` environment credentials
  /// (client-credentials flow): the app never holds Spotify
  /// credentials and never sends any — the request carries only the
  /// user ID. Client-credentials tokens cannot see private
  /// playlists, so only public ones are ever returned.
  ///
  /// Requires a configured backend (`X2_BACKEND_URL` in Settings):
  /// there is deliberately no client-side fallback and no
  /// third-party proxy. A 422 from the server means the server has
  /// no Spotify credentials configured; its `details` text names
  /// the missing environment variables and is surfaced verbatim.
  Future<SpotifyUserPlaylists> fetchUserPlaylists(String userIdOrUrl) async {
    final userId = parseUserId(userIdOrUrl);
    if (userId == null) {
      throw const ValidationFailure(
        'Enter a Spotify username or profile link (e.g. open.spotify.com/user/spotify).',
        code: 'spotify_user_invalid',
      );
    }

    if (!_apiClient.isBackendConfigured) {
      throw const NetworkFailure(
        'Browsing a Spotify user\'s public playlists needs your deployed Btt Music backend (set X2_BACKEND_URL in Settings).',
        code: 'spotify_user_needs_backend',
      );
    }

    final backendUri = _apiClient.buildBackendUri('/api/spotify/user');
    final Map<String, dynamic> data;
    try {
      final res = await _apiClient.dio.get<Map<String, dynamic>>(
        backendUri.replace(queryParameters: {'userId': userId}).toString(),
        // Credentials are never sent from the app: the server uses its
        // own environment credentials for this route.
        options: Options(headers: _apiClient.backendHeaders()),
      );
      data = res.data ?? {};
    } on DioException catch (e) {
      final errData = e.response?.data;
      final serverMessage = errData is Map
          ? ((errData['details'] as String?) ?? (errData['error'] as String?))
          : null;
      throw NetworkFailure(
        serverMessage ??
            'Spotify user lookup failed (${e.response?.statusCode ?? 'network error'}).',
        cause: e,
      );
    }

    return SpotifyUserPlaylists.fromJson(userId, data);
  }

  /// Resolves a public Spotify playlist (or album) into its full
  /// tracklist via the deployed Btt Music backend
  /// (`POST /api/spotify/playlist`).
  ///
  /// Resolution chain, all server-side — the app never holds Spotify
  /// credentials and never sends any:
  ///
  /// 1. Primary: the backend's keyless Spotify embed resolver
  ///    (official embed widget, no keys).
  /// 2. Fallback: the official Spotify Web API, using the server's own
  ///    `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` environment
  ///    credentials when they exist on the server.
  ///
  /// Requires a configured backend (`X2_BACKEND_URL` in Settings):
  /// a single track link still resolves standalone via [resolveUrl]
  /// (oEmbed), but a tracklist cannot be fetched from the app alone —
  /// there is deliberately no client-side fallback and no third-party
  /// proxy. When [libraryRepository] is given, every track is matched
  /// against the local library (normalized title + artist) and
  /// [SpotifyPlaylistTrack.isInLibrary] marks the ones already owned.
  Future<SpotifyPlaylist> fetchPlaylist(
    Uri uri, {
    LibraryRepository? libraryRepository,
  }) async {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final typeIndex = segments.indexWhere((s) => s == 'playlist' || s == 'album');
    if (typeIndex < 0 || typeIndex + 1 >= segments.length) {
      throw const ValidationFailure(
        'That Spotify link is not a playlist or album. Paste a playlist or album link for a full tracklist, or a single track link to resolve its metadata.',
        code: 'spotify_not_playlist',
      );
    }
    final targetType = segments[typeIndex];
    final targetId = segments[typeIndex + 1];

    if (!_apiClient.isBackendConfigured) {
      throw const NetworkFailure(
        'Spotify playlist tracklists need your deployed Btt Music backend (set X2_BACKEND_URL in Settings). Single Spotify track links still resolve via oEmbed without a backend.',
        code: 'spotify_playlist_needs_backend',
      );
    }

    final backendUri = _apiClient.buildBackendUri('/api/spotify/playlist');
    final Map<String, dynamic> data;
    try {
      final res = await _apiClient.dio.post<Map<String, dynamic>>(
        backendUri.replace(queryParameters: {'id': targetId}).toString(),
        // Credentials are never sent from the app: the server uses its
        // own environment credentials for the official-API fallback.
        data: {'url': uri.toString(), 'id': targetId},
        options: Options(headers: _apiClient.backendHeaders()),
      );
      data = res.data ?? {};
    } on DioException catch (e) {
      final errData = e.response?.data;
      final serverMessage = errData is Map
          ? ((errData['details'] as String?) ?? (errData['error'] as String?))
          : null;
      throw NetworkFailure(
        serverMessage ??
            'Spotify playlist lookup failed (${e.response?.statusCode ?? 'network error'}).',
        cause: e,
      );
    }

    final rawTracks = (data['tracks'] as List<dynamic>?) ?? [];
    final playlistTitle = (data['playlistTitle'] as String?) ?? 'Spotify Playlist';
    final playlistCoverUrl = data['playlistCoverUrl'] as String?;
    final libraryTracks = libraryRepository == null
        ? const <Track>[]
        : await libraryRepository.getAllTracks();

    final tracks = <SpotifyPlaylistTrack>[];
    for (var i = 0; i < rawTracks.length; i++) {
      final item = rawTracks[i];
      if (item is! Map) continue;
      final artists = (item['artists'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      final norm = MetadataNormalizer.normalize(
        rawTitle: (item['title'] as String?) ?? 'Unknown Title',
        rawArtist: artists.isEmpty ? 'Unknown Artist' : artists.join(', '),
        rawAlbum: (item['album'] as String?) ?? playlistTitle,
      );
      final result = X2Result(
        id: 'sp_pl_${uri.toString().hashCode}_$i',
        providerId: id,
        providerLabel: displayName,
        title: norm.title,
        artist: norm.artist,
        album: norm.album,
        durationSeconds: ((item['durationMs'] as num?) ?? 0) ~/ 1000,
        artworkUrl: (item['artworkUrl'] as String?) ?? playlistCoverUrl,
        externalPageUrl: uri.toString(),
        audioAvailable: false,
        downloadAuthorized: false,
        authorizationNote:
            'Spotify metadata only — DRM-protected audio cannot be downloaded. Find an authorized copy in X2.',
      );
      final existing = libraryTracks.isEmpty
          ? null
          : LibraryMatcher.findInLibrary(
              libraryTracks,
              title: norm.title,
              artist: norm.artist,
            );
      tracks.add(SpotifyPlaylistTrack(result: result, existingTrack: existing));
    }

    return SpotifyPlaylist(
      title: playlistTitle,
      description: (data['playlistDescription'] as String?) ?? '',
      coverUrl: playlistCoverUrl,
      externalUrl: (data['externalUrl'] as String?) ??
          'https://open.spotify.com/$targetType/$targetId',
      totalTracks: (data['totalTracks'] as num?)?.toInt() ?? tracks.length,
      tracks: tracks,
    );
  }
}
