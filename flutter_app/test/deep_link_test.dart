import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/deep_link.dart';

void main() {
  group('parseBttDeepLink', () {
    test('share link opens X2 with the shared URL', () {
      final action = parseBttDeepLink(
        'bttmu://share?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3Dabc',
      );
      expect(action, isA<X2SearchDeepLink>());
      expect(
        (action as X2SearchDeepLink).query,
        'https://www.youtube.com/watch?v=abc',
      );
    });

    test('legacy youtube-import shape is handled like share', () {
      final action = parseBttDeepLink(
        'bttmu://youtube-import?url=https%3A%2F%2Fyoutu.be%2Fabc',
      );
      expect(action, isA<X2SearchDeepLink>());
      expect((action as X2SearchDeepLink).query, 'https://youtu.be/abc');
    });

    test('share without a url is unknown', () {
      expect(parseBttDeepLink('bttmu://share'), isA<UnknownDeepLink>());
      expect(parseBttDeepLink('bttmu://share?url=  '), isA<UnknownDeepLink>());
    });

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

    test('file URLs import only audio files', () {
      final mp3 = parseBttDeepLink(
        'file:///private/var/mobile/Documents/Inbox/song.mp3',
      );
      expect(mp3, isA<ImportFileDeepLink>());
      expect(
        (mp3 as ImportFileDeepLink).filePath,
        '/private/var/mobile/Documents/Inbox/song.mp3',
      );
      expect(
        parseBttDeepLink('file:///private/var/mobile/Documents/Inbox/note.txt'),
        isA<UnknownDeepLink>(),
      );
      expect(
        parseBttDeepLink('file:///private/var/mobile/Documents/Inbox/photo.jpg'),
        isA<UnknownDeepLink>(),
      );
    });

    test('other schemes and garbage are unknown', () {
      expect(parseBttDeepLink('https://example.com/song.mp3'), isA<UnknownDeepLink>());
      expect(parseBttDeepLink('not a link at all'), isA<UnknownDeepLink>());
      expect(parseBttDeepLink(''), isA<UnknownDeepLink>());
    });
  });

  group('isImportableShareFile', () {
    test('audio extensions pass, everything else fails', () {
      expect(isImportableShareFile('/tmp/song.mp3'), isTrue);
      expect(isImportableShareFile('/tmp/song.M4A'), isTrue);
      expect(isImportableShareFile('/tmp/song.flac'), isTrue);
      expect(isImportableShareFile('/tmp/song.wav'), isTrue);
      expect(isImportableShareFile('/tmp/song.ogg'), isTrue);
      expect(isImportableShareFile('/tmp/notes.txt'), isFalse);
      expect(isImportableShareFile('/tmp/photo.png'), isFalse);
      expect(isImportableShareFile('/tmp/noextension'), isFalse);
      expect(isImportableShareFile('/tmp/song.mp3.txt'), isFalse);
    });
  });
}
