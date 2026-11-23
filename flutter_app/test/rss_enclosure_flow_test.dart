import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/x2/providers/direct_url_provider.dart';

/// Inline sample feed — no real feed URL is ever fetched in these tests.
/// Exercises: CDATA titles, `type` before `url`, a missing `type`
/// (extension fallback), a non-audio enclosure (skipped), and both
/// duration spellings (`itunes:duration` MM:SS and plain `<duration>`).
const _sampleRss = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Open Independent Sessions</title>
    <item>
      <title><![CDATA[Session 01 - Live Room]]></title>
      <enclosure url="https://cdn.example.org/audio/session01.mp3" length="1234567" type="audio/mpeg" />
      <itunes:duration>4:05</itunes:duration>
    </item>
    <item>
      <title>Session 02 - Studio Take</title>
      <enclosure type="audio/mp4" length="2345678" url="https://cdn.example.org/audio/session02.m4a" />
      <duration>187</duration>
    </item>
    <item>
      <title>Session 03 - No Type Declared</title>
      <enclosure url="https://cdn.example.org/audio/session03.mp3" length="3456789" />
    </item>
    <item>
      <title>Show Notes Image</title>
      <enclosure url="https://cdn.example.org/img/cover.jpg" length="1234" type="image/jpeg" />
    </item>
  </channel>
</rss>
''';

class _StubAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // HEAD answers with an RSS content-type even though the URL has no
    // .rss/.xml suffix and no /feed path — the flow must still parse it
    // as a feed instead of rejecting it as "not audio".
    if (options.method == 'HEAD') {
      return ResponseBody.fromString(
        '',
        200,
        headers: {Headers.contentTypeHeader: ['application/rss+xml']},
      );
    }
    return ResponseBody.fromString(
      _sampleRss,
      200,
      headers: {Headers.contentTypeHeader: ['text/plain']},
    );
  }
}

void main() {
  group('DirectUrlProvider RSS enclosure flow', () {
    test('parseRssAudioEnclosures returns one result per audio enclosure with duration', () {
      final items = DirectUrlProvider.parseRssAudioEnclosures(
        _sampleRss,
        sourceHost: 'cdn.example.org',
        feedUrl: 'https://cdn.example.org/feed.rss',
      );

      // The image enclosure is skipped; the other three are audio.
      expect(items.length, 3);

      final first = items[0];
      expect(first.title, 'Session 01 - Live Room');
      expect(first.artist, 'Open Independent Sessions');
      expect(first.audioUrl, 'https://cdn.example.org/audio/session01.mp3');
      expect(first.durationSeconds, 245); // itunes:duration 4:05
      expect(first.format, 'MP3');
      expect(first.fileSizeBytes, 1234567);
      expect(first.downloadAuthorized, isTrue);

      final second = items[1];
      expect(second.title, 'Session 02 - Studio Take');
      expect(second.audioUrl, 'https://cdn.example.org/audio/session02.m4a');
      expect(second.durationSeconds, 187); // plain <duration> seconds
      expect(second.format, 'M4A');

      // No declared type: accepted because the URL ends in .mp3.
      final third = items[2];
      expect(third.title, 'Session 03 - No Type Declared');
      expect(third.durationSeconds, 0);
      expect(third.format, 'MP3');
    });

    test('parseRssDuration handles seconds, MM:SS and HH:MM:SS', () {
      expect(DirectUrlProvider.parseRssDuration('187'), 187);
      expect(DirectUrlProvider.parseRssDuration('4:05'), 245);
      expect(DirectUrlProvider.parseRssDuration('1:04:05'), 3845);
      expect(DirectUrlProvider.parseRssDuration(''), 0);
      expect(DirectUrlProvider.parseRssDuration(null), 0);
      expect(DirectUrlProvider.parseRssDuration('not-a-duration'), 0);
    });

    test('resolveUrl treats a HEAD-declared XML feed as RSS even without a feed suffix', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter();
      final provider = DirectUrlProvider(ApiClient(customDio: dio));

      final resolved = await provider.resolveUrl(
        Uri.parse('https://podcast.example.org/show'),
      );
      expect(resolved, isNotNull);
      expect(resolved!.title, 'Session 01 - Live Room');
      expect(resolved.audioUrl, 'https://cdn.example.org/audio/session01.mp3');
      expect(resolved.durationSeconds, 245);
    });

    test('resolveAllFeedItems returns every enclosure for batch import', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter();
      final provider = DirectUrlProvider(ApiClient(customDio: dio));

      final items = await provider.resolveAllFeedItems(
        Uri.parse('https://podcast.example.org/show/feed.rss'),
      );
      expect(items.length, 3);
      expect(
        items.map((r) => r.audioUrl).toList(),
        [
          'https://cdn.example.org/audio/session01.mp3',
          'https://cdn.example.org/audio/session02.m4a',
          'https://cdn.example.org/audio/session03.mp3',
        ],
      );
    });
  });
}
