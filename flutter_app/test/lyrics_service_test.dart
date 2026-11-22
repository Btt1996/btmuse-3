import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/features/lyrics/lyrics_service.dart';

void main() {
  group('parseLrc', () {
    test('parses timestamps with and without fractions', () {
      final lines = parseLrc(
        '[00:12.34] First line\n[01:23] Second line',
      );

      expect(lines.length, 2);
      expect(lines[0].time, closeTo(12.34, 0.001));
      expect(lines[0].text, 'First line');
      expect(lines[1].time, 83.0);
      expect(lines[1].text, 'Second line');
    });

    test('expands multiple timestamps on one line into one entry each', () {
      final lines = parseLrc('[00:10.00][00:20.00] Chorus');

      expect(lines.length, 2);
      expect(lines[0].time, 10.0);
      expect(lines[1].time, 20.0);
      expect(lines[0].text, 'Chorus');
      expect(lines[1].text, 'Chorus');
    });

    test('sorts unsorted input by time', () {
      final lines = parseLrc(
        '[00:30.00] Late\n[00:05.00] Early\n[00:15.00] Middle',
      );

      expect(
        lines.map((line) => line.text).toList(),
        ['Early', 'Middle', 'Late'],
      );
      expect(lines.map((line) => line.time).toList(), [5.0, 15.0, 30.0]);
    });

    test('returns an empty list for empty text', () {
      expect(parseLrc(''), isEmpty);
      expect(parseLrc('   \n  \n'), isEmpty);
    });

    test('skips malformed lines and metadata tags', () {
      final lines = parseLrc(
        '[ar:Some Artist]\n'
        '[ti:Some Title]\n'
        'A line with no timestamp\n'
        '[12:34 A line with an unclosed timestamp\n'
        '[ab:cd] Not a time\n'
        '[00:07.50] Only valid line',
      );

      expect(lines.length, 1);
      expect(lines[0].time, 7.5);
      expect(lines[0].text, 'Only valid line');
    });

    test('uses a music note for a timestamp-only line', () {
      final lines = parseLrc('[00:03.00]');

      expect(lines.length, 1);
      expect(lines[0].text, '♪');
    });

    test('accepts one to three fractional digits', () {
      final lines = parseLrc(
        '[00:01.5] One\n[00:02.25] Two\n[00:03.125] Three',
      );

      expect(lines.map((line) => line.time).toList(), [1.5, 2.25, 3.125]);
    });
  });

  group('cleanSongTitle', () {
    test('strips official video/audio/lyrics suffixes', () {
      expect(cleanSongTitle('Dreams (Official Video)'), 'Dreams');
      expect(cleanSongTitle('Dreams (Official Audio)'), 'Dreams');
      expect(cleanSongTitle('Dreams [Official Music Video]'), 'Dreams');
      expect(cleanSongTitle('Dreams (Lyrics)'), 'Dreams');
      expect(cleanSongTitle('Dreams (Lyric Video)'), 'Dreams');
      expect(cleanSongTitle('Dreams (Official Visualizer)'), 'Dreams');
    });

    test('strips quality, remix and feature suffixes', () {
      expect(cleanSongTitle('Dreams (HQ)'), 'Dreams');
      expect(cleanSongTitle('Dreams [HD]'), 'Dreams');
      expect(cleanSongTitle('Dreams (Remix)'), 'Dreams');
      expect(cleanSongTitle('Dreams (feat. Someone)'), 'Dreams');
      expect(cleanSongTitle('Dreams (ft. Someone)'), 'Dreams');
    });

    test('strips trailing audio-file extensions', () {
      expect(cleanSongTitle('Dreams.mp3'), 'Dreams');
      expect(cleanSongTitle('Dreams.m4a'), 'Dreams');
      expect(cleanSongTitle('Dreams.wav'), 'Dreams');
      expect(cleanSongTitle('Dreams.flac'), 'Dreams');
    });

    test('leaves a plain title untouched', () {
      expect(cleanSongTitle('Midnight City'), 'Midnight City');
      expect(cleanSongTitle('  Midnight City  '), 'Midnight City');
    });
  });

  group('cleanArtistName', () {
    test('returns empty for placeholder artists', () {
      expect(cleanArtistName(''), '');
      expect(cleanArtistName('Unknown Artist'), '');
      expect(cleanArtistName('Imported Audio'), '');
    });

    test('keeps only the first artist of a collaboration', () {
      expect(cleanArtistName('Daft Punk, Pharrell Williams'), 'Daft Punk');
      expect(cleanArtistName('Simon & Garfunkel'), 'Simon');
      expect(cleanArtistName('  M83  '), 'M83');
    });
  });

  group('activeLyricLineIndex', () {
    const lines = [
      LyricLine(time: 10.0, text: 'One'),
      LyricLine(time: 20.0, text: 'Two'),
      LyricLine(time: 30.0, text: 'Three'),
    ];

    test('returns -1 before the first line and for empty lyrics', () {
      expect(activeLyricLineIndex(lines, 0.0), -1);
      expect(activeLyricLineIndex(lines, 9.7), -1);
      expect(activeLyricLineIndex(const [], 15.0), -1);
    });

    test('activates a line 0.2s before its timestamp', () {
      expect(activeLyricLineIndex(lines, 9.8), 0);
      expect(activeLyricLineIndex(lines, 19.8), 1);
    });

    test('tracks the latest passed line and sticks to the last one', () {
      expect(activeLyricLineIndex(lines, 15.0), 0);
      expect(activeLyricLineIndex(lines, 25.0), 1);
      expect(activeLyricLineIndex(lines, 30.0), 2);
      expect(activeLyricLineIndex(lines, 240.0), 2);
    });
  });

  group('SongLyrics cache serialization', () {
    test('toMap/fromMap round-trips synced and plain lyrics', () {
      final original = SongLyrics(
        trackId: 'track-1',
        title: 'Dreams',
        artist: 'Fleetwood Mac',
        syncedLyrics: const [
          LyricLine(time: 12.34, text: 'First line'),
          LyricLine(time: 83.0, text: 'Second line'),
        ],
        plainLyrics: const ['First line', 'Second line'],
        source: 'LRCLIB (Synced)',
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
      );

      final restored = SongLyrics.fromMap(original.toMap());

      expect(restored.trackId, 'track-1');
      expect(restored.title, 'Dreams');
      expect(restored.artist, 'Fleetwood Mac');
      expect(restored.source, 'LRCLIB (Synced)');
      expect(restored.fetchedAt.millisecondsSinceEpoch, 1790000000000);
      expect(restored.syncedLyrics?.length, 2);
      expect(restored.syncedLyrics?[0].time, closeTo(12.34, 0.001));
      expect(restored.syncedLyrics?[0].text, 'First line');
      expect(restored.syncedLyrics?[1].time, 83.0);
      expect(restored.plainLyrics, ['First line', 'Second line']);
    });

    test('toMap/fromMap round-trips plain-only lyrics', () {
      final original = SongLyrics(
        trackId: 'track-2',
        title: 'No Sync',
        artist: 'Someone',
        plainLyrics: const ['Only plain text'],
        source: 'LRCLIB (Synced)',
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
      );

      final restored = SongLyrics.fromMap(original.toMap());

      expect(restored.syncedLyrics, isNull);
      expect(restored.hasSyncedLyrics, isFalse);
      expect(restored.hasPlainLyrics, isTrue);
      expect(restored.plainLyrics, ['Only plain text']);
    });
  });
}
