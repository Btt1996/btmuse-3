import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/deep_link.dart';

void main() {
  group('parseBttDeepLink', () {
    test('siri play / shuffle', () {
      final play = parseBttDeepLink('bttmu://siri/play');
      expect(play, isA<SiriPlayDeepLink>());
      expect((play as SiriPlayDeepLink).shuffle, isFalse);
      final shuffle = parseBttDeepLink('bttmu://siri/shuffle');
      expect(shuffle, isA<SiriPlayDeepLink>());
      expect((shuffle as SiriPlayDeepLink).shuffle, isTrue);
    });

    test('siri playlist carries the name', () {
      final action = parseBttDeepLink('bttmu://siri/playlist?name=Road%20Trip');
      expect(action, isA<SiriPlaylistDeepLink>());
      expect((action as SiriPlaylistDeepLink).playlistName, 'Road Trip');
      expect(
        parseBttDeepLink('bttmu://siri/playlist'),
        isA<UnknownDeepLink>(),
      );
    });

    test('unknown siri path and unknown hosts are unknown', () {
      expect(parseBttDeepLink('bttmu://siri/dance'), isA<UnknownDeepLink>());
      expect(parseBttDeepLink('bttmu://other?url=x'), isA<UnknownDeepLink>());
    });

    test('removed share links are unknown', () {
      // The Share Extension / Open In feature was removed (2026-11-23):
      // its `bttmu://share` and `bttmu://youtube-import` shapes no
      // longer resolve to anything.
      expect(
        parseBttDeepLink(
          'bttmu://share?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3Dabc',
        ),
        isA<UnknownDeepLink>(),
      );
      expect(
        parseBttDeepLink('bttmu://youtube-import?url=https%3A%2F%2Fyoutu.be%2Fabc'),
        isA<UnknownDeepLink>(),
      );
      expect(
        parseBttDeepLink('file:///private/var/mobile/Documents/Inbox/song.mp3'),
        isA<UnknownDeepLink>(),
      );
    });

    test('other schemes and garbage are unknown', () {
      expect(parseBttDeepLink('https://example.com/song.mp3'), isA<UnknownDeepLink>());
      expect(parseBttDeepLink('not a link at all'), isA<UnknownDeepLink>());
      expect(parseBttDeepLink(''), isA<UnknownDeepLink>());
    });
  });
}
