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

    // A feed served without a .rss/.xml suffix (or without /feed in the
    // path) still parses as RSS when the server says so via HEAD.
    if (ok &&
        (contentType.contains('xml') || contentType.contains('rss'))) {
      return _resolveRssAudioFeed(uri);
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

  /// Parses an RSS duration value: plain seconds ("187"), "MM:SS"
  /// ("4:05") or "HH:MM:SS" ("1:04:05"). Returns 0 when absent/unparseable.
  static int parseRssDuration(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return 0;
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    final parts = text.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return 0;
    final nums = parts.cast<int>();
    var total = 0;
    for (final n in nums) {
      total = total * 60 + n;
    }
    return total;
  }

  static String _formatFromTypeOrUrl(String? mimeType, String audioUrl) {
    final type = (mimeType ?? '').toLowerCase();
    const byType = {
      'audio/mpeg': 'MP3',
      'audio/mp3': 'MP3',
      'audio/mp4': 'M4A',
      'audio/x-m4a': 'M4A',
      'audio/aac': 'AAC',
      'audio/ogg': 'OGG',
      'audio/opus': 'OPUS',
      'audio/x-wav': 'WAV',
      'audio/wav': 'WAV',
      'audio/flac': 'FLAC',
      'audio/x-flac': 'FLAC',
    };
    if (byType.containsKey(type)) return byType[type]!;
    final ext = p.extension(Uri.tryParse(audioUrl)?.path ?? '').toLowerCase().replaceFirst('.', '');
    if (ext.isNotEmpty) return ext.toUpperCase();
    return 'MP3';
  }

  static String? _attrValue(String tag, String name) {
    final match = RegExp(
      '''$name\\s*=\\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1);
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
      // Enclosure attributes may appear in any order, and `type` may be
      // absent; extract url/type independently instead of requiring
      // `url=... type="audio/..."` in one fixed order.
      final enclosureTag = RegExp(r'<enclosure[^>]*>', caseSensitive: false)
          .firstMatch(block)
          ?.group(0);
      if (enclosureTag == null) continue;
      final audioUrl = _attrValue(enclosureTag, 'url');
      if (audioUrl == null || !ApiClient.isSafeExternalUrl(audioUrl)) continue;
      final mimeType = _attrValue(enclosureTag, 'type');
      final ext = p
          .extension(Uri.tryParse(audioUrl)?.path ?? '')
          .toLowerCase()
          .replaceFirst('.', '');
      // A declared non-audio type is not an audio enclosure. With no
      // type at all, accept only a known audio extension.
      if (mimeType != null && mimeType.isNotEmpty) {
        if (!mimeType.toLowerCase().startsWith('audio/')) continue;
      } else if (!AudioValidator.supportedExtensions.contains(ext)) {
        continue;
      }

      final title = RegExp(r'<title>(?:<!\[CDATA\[)?([^<\]]+)', caseSensitive: false)
              .firstMatch(block)
              ?.group(1)
              ?.trim() ??
          'Audio Feed Item';
      final durationRaw =
          RegExp(r'<(?:itunes:)?duration>([^<]+)</(?:itunes:)?duration>', caseSensitive: false)
                  .firstMatch(block)
                  ?.group(1);
      final length = int.tryParse(_attrValue(enclosureTag, 'length') ?? '');

      results.add(
        X2Result(
          id: 'rss_${audioUrl.hashCode}',
          providerId: 'direct_url',
          providerLabel: 'RSS Audio Feed',
          title: title,
          artist: channelTitle,
          album: 'Podcast / Audio RSS',
          durationSeconds: parseRssDuration(durationRaw),
          audioUrl: audioUrl,
          externalPageUrl: feedUrl,
          format: _formatFromTypeOrUrl(mimeType, audioUrl),
          fileSizeBytes: length,
          audioAvailable: true,
          downloadAuthorized: true,
          authorizationNote: 'Public RSS audio enclosure parsed directly without API keys.',
        ),
      );
    }
    return results;
  }
}
