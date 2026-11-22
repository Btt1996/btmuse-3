import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/features/x2/providers/direct_url_provider.dart';

void main() {
  test('DirectUrlProvider extracts public RSS audio enclosures while blocking SSRF links', () {
    const xml = '''
    <rss version="2.0">
      <channel>
        <title>Open Independent Sessions</title>
        <item>
          <title><![CDATA[Session 01 - Live Room]]></title>
          <enclosure url="https://cdn.example.org/audio/session01.mp3" type="audio/mpeg" />
        </item>
        <item>
          <title>Internal SSRF Link</title>
          <enclosure url="http://127.0.0.1:8080/private.mp3" type="audio/mpeg" />
        </item>
      </channel>
    </rss>
    ''';

    final items = DirectUrlProvider.parseRssAudioEnclosures(
      xml,
      sourceHost: 'cdn.example.org',
      feedUrl: 'https://cdn.example.org/feed.rss',
    );

    expect(items.length, 1);
    expect(items.first.title, 'Session 01 - Live Room');
    expect(items.first.artist, 'Open Independent Sessions');
    expect(items.first.downloadAuthorized, isTrue);
    expect(items.first.audioUrl, 'https://cdn.example.org/audio/session01.mp3');
  });
}
