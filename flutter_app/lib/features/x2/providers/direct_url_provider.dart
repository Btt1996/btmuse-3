import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/audio_validator.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';

/// Direct Audio File URL & Podcast/Music RSS XML Feed Adapter (Zero API Keys).
class DirectUrlProvider implements X2Provider {
  final ApiClient _apiClient;

  DirectUrlProvider(this._apiClient);

  @override
  String get id => 'direct_url';

  @override
  String get displayName => 'Direct Audio / RSS';

  @override
  bool get supportsKeywordSearch => false;

  @override
  bool get supportsUrlResolution => true;

  @override
  bool get isMetadataOnly => false;

  @override
  bool canHandleUrl(Uri uri) {
    if (!ApiClient.isSafeExternalUrl(uri.toString())) return false;
    final host = uri.host.toLowerCase();
    // Leave specialized pages to dedicated adapters; accept direct audio/feed URLs AND generic HTTP links
    if (host.contains('youtube.com') ||
        host == 'youtu.be' ||
        host.contains('open.spotify.com') ||
        host.contains('soundcloud.com') ||
        host.contains('audius.co') ||
        host == 'vk.com' ||
        host.endsWith('.vk.com') ||
        host == 'vk.ru') {
      return false;
    }
    return true;
  }

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 5}) async => const [];

  @override
  Future<X2Result?> resolveUrl(Uri uri) async {
    if (!ApiClient.isSafeExternalUrl(uri.toString())) {
      throw const ValidationFailure('Unsafe or private network URL rejected.');
    }

    final lowerPath = uri.path.toLowerCase();
    if (lowerPath.endsWith('.rss') || lowerPath.endsWith('.xml') || lowerPath.contains('/feed')) {
      return _resolveRssAudioFeed(uri);
    }

    var contentType = '';
    var contentLen = 0;
    var ok = false;

    try {
      final head = await _apiClient.dio.head<void>(
        uri.toString(),
        options: Options(
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      ok = (head.statusCode ?? 0) >= 200 && (head.statusCode ?? 0) < 300;
      contentType = (head.headers.value('content-type') ?? '').toLowerCase();
      contentLen = int.tryParse(head.headers.value('content-length') ?? '0') ?? 0;
    } catch (_) {
      ok = false;
    }

    // Fallback to tiny Range GET when servers reject HEAD (405 Method Not Allowed / 403)
    if (!ok || contentType.isEmpty) {
      final probe = await _apiClient.dio.get<List<int>>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          headers: const {'Range': 'bytes=0-1023', 'User-Agent': 'BttMusic/2.00 (iOS)'},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final code = probe.statusCode ?? 0;
      ok = code == 200 || code == 206;
      contentType = (probe.headers.value('content-type') ?? '').toLowerCase();
      final totalFromRange = probe.headers.value('content-range')?.split('/').last;
      contentLen = int.tryParse(totalFromRange ?? probe.headers.value('content-length') ?? '0') ?? 0;

      // If it turned out to be an XML RSS feed without a .rss/.xml URL suffix, parse it cleanly
      if (ok && (contentType.contains('xml') || contentType.contains('rss'))) {
        return _resolveRssAudioFeed(uri);
      }
    }

    final ext = p.extension(uri.path).toLowerCase().replaceFirst('.', '');
    final isAudio = contentType.contains('audio/') ||
        contentType.contains('application/ogg') ||
        (contentType.contains('octet-stream') && AudioValidator.supportedExtensions.contains(ext)) ||
        (ok && AudioValidator.supportedExtensions.contains(ext) && !contentType.contains('text/html'));

    if (!ok || !isAudio) {
      throw ValidationFailure(
        'URL did not return a direct audio stream (received "${contentType.isEmpty ? 'unknown' : contentType}").',
      );
    }

    final baseTitle = Uri.decodeComponent(
      p.basenameWithoutExtension(uri.path).isEmpty
          ? 'Direct Audio (${uri.host})'
          : p.basenameWithoutExtension(uri.path),
    );

    return X2Result(
      id: 'dir_${uri.toString().hashCode}',
      providerId: id,
      providerLabel: displayName,
      title: baseTitle,
      artist: uri.host,
      album: 'Direct Web Audio',
      audioUrl: uri.toString(),
      externalPageUrl: uri.toString(),
      format: (ext.isEmpty ? 'MP3' : ext).toUpperCase(),
      fileSizeBytes: contentLen > 0 ? contentLen : null,
      audioAvailable: true,
      downloadAuthorized: true,
      authorizationNote:
          'Direct audio HTTP stream verified (${contentType.isEmpty ? ext : contentType}).',
    );
  }

  /// Resolves multiple items from an RSS/Podcast XML feed for batch selection in Import Center.
  Future<List<X2Result>> resolveAllFeedItems(Uri uri) async {
    final res = await _apiClient.dio.get<String>(
      uri.toString(),
      options: Options(responseType: ResponseType.plain),
    );
    final xml = res.data ?? '';
    return parseRssAudioEnclosures(xml, sourceHost: uri.host, feedUrl: uri.toString());
  }

  Future<X2Result?> _resolveRssAudioFeed(Uri uri) async {
    final items = await resolveAllFeedItems(uri);
    return items.isEmpty ? null : items.first;
  }

  static List<X2Result> parseRssAudioEnclosures(
    String xml, {
    required String sourceHost,
    required String feedUrl,
  }) {
    final channelTitle =
        RegExp(r'<channel>[\s\S]*?<title>(?:<!\[CDATA\[)?([^<\]]+)', caseSensitive: false)
                .firstMatch(xml)
                ?.group(1)
                ?.trim() ??
            sourceHost;

    final itemMatches = RegExp(r'<item>([\s\S]*?)</item>', caseSensitive: false).allMatches(xml);
    final results = <X2Result>[];

    for (final m in itemMatches.take(15)) {
      final block = m.group(1) ?? '';
      final encMatch = RegExp(
        r'''<enclosure[^>]+url=["']([^"']+)["'][^>]*type=["']audio\/[^"']+["']''',
        caseSensitive: false,
      ).firstMatch(block);
      final audioUrl = encMatch?.group(1);
      if (audioUrl == null || !ApiClient.isSafeExternalUrl(audioUrl)) continue;

      final title = RegExp(r'<title>(?:<!\[CDATA\[)?([^<\]]+)', caseSensitive: false)
              .firstMatch(block)
              ?.group(1)
              ?.trim() ??
          'Audio Feed Item';

      results.add(
        X2Result(
          id: 'rss_${audioUrl.hashCode}',
          providerId: 'direct_url',
          providerLabel: 'RSS Audio Feed',
          title: title,
          artist: channelTitle,
          album: 'Podcast / Audio RSS',
          audioUrl: audioUrl,
          externalPageUrl: feedUrl,
          format: 'MP3',
          audioAvailable: true,
          downloadAuthorized: true,
          authorizationNote: 'Public RSS audio enclosure parsed directly without API keys.',
        ),
      );
    }
    return results;
  }
}
