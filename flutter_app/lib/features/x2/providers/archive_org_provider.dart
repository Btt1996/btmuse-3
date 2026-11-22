import 'package:dio/dio.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';

/// Internet Archive public-library provider (zero API key required).
///
/// Flow (same shape as the SwiftUI reference app's Archive adapter):
///   1. `advancedsearch.php` — keyword search restricted to audio items,
///      returning identifiers (+ title/creator when the index has them).
///   2. `metadata/{identifier}` — per-item metadata + file list.
///   3. Pick downloadable MP3 files only: a file qualifies when its
///      `format` is `MP3` or `VBR MP3` and the item is public (items
///      flagged `access-restricted-item` are skipped, never imported).
///
/// `downloadAuthorized` is true ONLY for items returned by the Archive
/// search (public library items). No key, no account, no backend.
class ArchiveOrgProvider implements X2Provider {
  final ApiClient _apiClient;

  ArchiveOrgProvider(this._apiClient);

  @override
  String get id => 'archive_org';

  @override
  String get displayName => 'Internet Archive';

  @override
  bool get supportsKeywordSearch => true;

  @override
  bool get supportsUrlResolution => true;

  @override
  bool get isMetadataOnly => false;

  @override
  bool canHandleUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'archive.org' || host.endsWith('.archive.org');
  }

  static String _stringField(Object? value, [String fallback = '']) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
    }
    return fallback;
  }

  static bool _isPublicItem(Map<dynamic, dynamic> metadata) {
    // Restricted / dark items are never treated as public library items.
    final restricted = _stringField(metadata['access-restricted-item']).toLowerCase();
    if (restricted == 'true') return false;
    final dark = _stringField(metadata['is_dark']).toLowerCase();
    if (dark == 'true') return false;
    return true;
  }

  static bool _isMp3Format(Object? format) {
    final normalized = _stringField(format).toUpperCase();
    return normalized == 'MP3' || normalized == 'VBR MP3';
  }

  static String _downloadUrl(String identifier, String fileName) {
    final encoded = fileName
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    return 'https://archive.org/download/$identifier/$encoded';
  }

  static int _parseInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static int _parseDurationSeconds(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) {
      final asDouble = double.tryParse(value.trim());
      if (asDouble != null) return asDouble.toInt();
    }
    return 0;
  }

  /// Picks the first downloadable MP3 file from a metadata `files` list.
  /// Non-MP3 files (FLAC, PDF, JPEG, …) are skipped. Returns null when
  /// the item has no MP3 file at all.
  static Map<dynamic, dynamic>? pickMp3File(List<dynamic> files) {
    for (final raw in files.whereType<Map<dynamic, dynamic>>()) {
      if (_isMp3Format(raw['format'])) return raw;
    }
    return null;
  }

  X2Result? _resultFromMetadata(
    String identifier,
    Map<dynamic, dynamic> metadata, {
    String? preferredFileName,
    String? pageUrl,
  }) {
    if (!_isPublicItem(metadata)) return null;
    final files = (metadata['files'] as List<dynamic>?) ?? const [];
    Map<dynamic, dynamic>? chosen;
    if (preferredFileName != null) {
      for (final raw in files.whereType<Map<dynamic, dynamic>>()) {
        final name = _stringField(raw['name']);
        if (name == preferredFileName && _isMp3Format(raw['format'])) {
          chosen = raw;
          break;
        }
      }
    }
    chosen ??= pickMp3File(files);
    if (chosen == null) return null;

    final fileName = _stringField(chosen['name']);
    if (fileName.isEmpty) return null;
    final audioUrl = _downloadUrl(identifier, fileName);
    if (!ApiClient.isSafeExternalUrl(audioUrl)) return null;

    final title = _stringField(metadata['title'], identifier);
    final creator = _stringField(metadata['creator'], 'Internet Archive');
    final norm = MetadataNormalizer.normalize(
      rawTitle: title,
      rawArtist: creator,
      rawAlbum: 'Internet Archive',
    );
    final licenseUrl = _stringField(metadata['licenseurl']);

    return X2Result(
      id: 'ia_${audioUrl.hashCode}',
      providerId: id,
      providerLabel: displayName,
      title: norm.title,
      artist: norm.artist,
      album: norm.album,
      durationSeconds: _parseDurationSeconds(chosen['length']),
      artworkUrl: null,
      audioUrl: audioUrl,
      externalPageUrl: pageUrl ?? 'https://archive.org/details/$identifier',
      format: 'MP3',
      fileSizeBytes: _parseInt(chosen['size']) > 0 ? _parseInt(chosen['size']) : null,
      audioAvailable: true,
      downloadAuthorized: true,
      licenseName: licenseUrl.isEmpty ? null : licenseUrl,
      authorizationNote:
          'Public library item from the Internet Archive public library (archive.org) — freely downloadable MP3.',
    );
  }

  Future<Map<dynamic, dynamic>?> _fetchMetadata(String identifier) async {
    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://archive.org/metadata/$identifier',
      options: Options(
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final data = res.data;
    if (data == null) return null;
    // The metadata endpoint returns {metadata: {...}, files: [...]} at
    // the top level; merge so _resultFromMetadata sees one map.
    final merged = <dynamic, dynamic>{};
    final meta = data['metadata'];
    if (meta is Map) merged.addAll(meta);
    merged['files'] = data['files'];
    return merged;
  }

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 12}) async {
    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://archive.org/advancedsearch.php',
      queryParameters: {
        'q': '($query) AND mediatype:(audio)',
        'fl[]': const ['identifier', 'title', 'creator'],
        'rows': limit,
        'output': 'json',
      },
      options: Options(
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final docs = (res.data?['response']?['docs'] as List<dynamic>?) ?? const [];
    // Fetch per-item metadata in parallel: sequential fetches can exceed
    // the 9 s provider timeout when several items are slow. One bad item
    // must not fail the whole search, so each fetch resolves to null on
    // failure, and results keep the search order.
    final fetched = await Future.wait(
      docs.whereType<Map<dynamic, dynamic>>().take(limit).map((doc) async {
        final identifier = _stringField(doc['identifier']);
        if (identifier.isEmpty) return null;
        try {
          final metadata = await _fetchMetadata(identifier);
          if (metadata == null) return null;
          // Prefer the indexed title/creator when the metadata call is
          // missing them; the metadata map itself wins otherwise.
          metadata.putIfAbsent('title', () => doc['title']);
          metadata.putIfAbsent('creator', () => doc['creator']);
          return _resultFromMetadata(identifier, metadata);
        } catch (_) {
          return null;
        }
      }),
    );
    return fetched.whereType<X2Result>().toList();
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async {
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    String? identifier;
    String? preferredFile;
    if (segments.first == 'details' && segments.length >= 2) {
      identifier = segments[1];
    } else if (segments.first == 'download' && segments.length >= 2) {
      identifier = segments[1];
      if (segments.length >= 3) {
        preferredFile = Uri.decodeComponent(segments.sublist(2).join('/'));
      }
    } else if (segments.first == 'embed' && segments.length >= 2) {
      identifier = segments[1];
    } else {
      return null;
    }
    if (identifier == null || identifier.isEmpty) return null;
    final metadata = await _fetchMetadata(identifier);
    if (metadata == null) return null;
    return _resultFromMetadata(
      identifier,
      metadata,
      preferredFileName: preferredFile,
      pageUrl: uri.toString(),
    );
  }
}
