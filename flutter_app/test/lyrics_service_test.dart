import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/features/lyrics/lyrics_service.dart';

/// In-memory [LyricsCacheStore] for service tests: the repo has no
/// sqflite test double and `LocalDatabase` cannot be constructed in a
/// test (private constructor), so fetch/cache behaviour is exercised
/// through the service's injectable cache seam instead of SQLite.
class _FakeLyricsCacheStore implements LyricsCacheStore {
  final Map<String, SongLyrics> stored = {};

  @override
  Future<SongLyrics?> read(String trackId) async => stored[trackId];

  @override
  Future<void> write(SongLyrics lyrics) async {
    stored[lyrics.trackId] = lyrics;
  }
}

/// Dio that never touches the network: every request is answered (or
/// rejected) by an interceptor, and each requested path is recorded in
/// [calls] so tests can prove the network was (not) hit.
Dio _dioWith({
  Map<String, dynamic>? getResponse,
  List<dynamic>? searchResponse,
  DioExceptionType? failWith,
  required List<String> calls,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        calls.add(options.path);
        if (failWith != null) {
          handler.reject(
            DioException(requestOptions: options, type: failWith),
          );
          return;
        }
        if (options.path.contains('/get')) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: getResponse ?? <String, dynamic>{},
            ),
          );
          return;
        }
        handler.resolve(
          Response<List<dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: searchResponse ?? <dynamic>[],
          ),
        );
      },
    ),
  );
  return dio;
}

LyricsService _service({
  required _FakeLyricsCacheStore cache,
  required Dio dio,
}) =>
    LyricsService(dio: dio, cache: cache);

SongLyrics _cachedLyrics(String trackId, String firstLine) => SongLyrics(
      trackId: trackId,
      title: 'Dreams',
      artist: 'Fleetwood Mac',
      syncedLyrics: [LyricLine(time: 1.0, text: firstLine)],
      source: 'LRCLIB (Synced)',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
    );

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

    test('handles a zero timestamp and duplicate timestamps', () {
      final lines = parseLrc('[00:00.00] Intro\n[00:10.00][00:10.00] Echo');

      expect(lines.map((line) => line.time).toList(), [0.0, 10.0, 10.0]);
      expect(lines.first.text, 'Intro');
      expect(lines[1].text, 'Echo');
      expect(lines[2].text, 'Echo');
    });

    test('uses a music note for each timestamp-only entry on a shared line',
        () {
      final lines = parseLrc('[00:03.00][00:06.00]');

      expect(lines.length, 2);
      expect(lines.map((line) => line.text).toList(), ['♪', '♪']);
    });

    test('keeps text when the timestamp is not at the start', () {
      // Documents current behaviour (same in the React port): the parser
      // strips timestamps wherever they appear and keeps the rest.
      final lines = parseLrc('Intro [00:03.00]');

      expect(lines.length, 1);
      expect(lines[0].time, 3.0);
      expect(lines[0].text, 'Intro');
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

    test('strips official lyric video and official lyrics suffixes', () {
      expect(cleanSongTitle('Dreams (Official Lyric Video)'), 'Dreams');
      expect(cleanSongTitle('Dreams (Official Lyrics)'), 'Dreams');
      expect(cleanSongTitle('Dreams [Official Lyric Video]'), 'Dreams');
    });

    test('strips quality, remix and feature suffixes', () {
      expect(cleanSongTitle('Dreams (HQ)'), 'Dreams');
      expect(cleanSongTitle('Dreams [HD]'), 'Dreams');
      expect(cleanSongTitle('Dreams (Remix)'), 'Dreams');
      expect(cleanSongTitle('Dreams (feat. Someone)'), 'Dreams');
      expect(cleanSongTitle('Dreams (ft. Someone)'), 'Dreams');
    });

    test('strips stacked suffixes in one title', () {
      expect(
        cleanSongTitle('Dreams (feat. Someone) (Official Video)'),
        'Dreams',
      );
      expect(cleanSongTitle('Dreams (Official Video) (Remix)'), 'Dreams');
      expect(cleanSongTitle('Dreams [Official Audio]'), 'Dreams');
      expect(cleanSongTitle('Dreams (Visualizer)'), 'Dreams');
      expect(cleanSongTitle('Dreams (Audio)'), 'Dreams');
      expect(cleanSongTitle('Dreams (ft. Someone) [HD]'), 'Dreams');
    });

    test('strips trailing audio-file extensions', () {
      expect(cleanSongTitle('Dreams.mp3'), 'Dreams');
      expect(cleanSongTitle('Dreams.m4a'), 'Dreams');
      expect(cleanSongTitle('Dreams.wav'), 'Dreams');
      expect(cleanSongTitle('Dreams.flac'), 'Dreams');
    });

    test('strips an uppercase extension and leaves live versions alone', () {
      expect(cleanSongTitle('Dreams.MP3'), 'Dreams');
      expect(cleanSongTitle('Dreams.FLAC'), 'Dreams');
      expect(cleanSongTitle('Dreams (Live)'), 'Dreams (Live)');
      expect(cleanSongTitle('Dreams - Live'), 'Dreams - Live');
    });

    test('leaves a plain title untouched', () {
      expect(cleanSongTitle('Midnight City'), 'Midnight City');
      expect(cleanSongTitle('  Midnight City  '), 'Midnight City');
    });

    test('cleans to empty when the title is only a suffix', () {
      expect(cleanSongTitle('(Official Video)'), '');
      expect(cleanSongTitle('(Lyrics)'), '');
    });
  });

  group('cleanArtistName', () {
    test('returns empty for placeholder artists', () {
      expect(cleanArtistName(''), '');
      expect(cleanArtistName('Unknown Artist'), '');
      expect(cleanArtistName('Imported Audio'), '');
    });

    test('returns empty for placeholders with odd case or whitespace', () {
      expect(cleanArtistName('Unknown Artist '), '');
      expect(cleanArtistName('  unknown artist'), '');
      expect(cleanArtistName('IMPORTED AUDIO'), '');
      expect(cleanArtistName('   '), '');
    });

    test('keeps only the first artist of a collaboration', () {
      expect(cleanArtistName('Daft Punk, Pharrell Williams'), 'Daft Punk');
      expect(cleanArtistName('Simon & Garfunkel'), 'Simon');
      expect(cleanArtistName('  M83  '), 'M83');
    });

    test('trims surrounding whitespace before splitting', () {
      expect(
        cleanArtistName('  Daft Punk , Pharrell Williams'),
        'Daft Punk',
      );
      expect(cleanArtistName('A & B & C'), 'A');
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

    test('single-line lyrics activate at the line and stay active', () {
      const single = [LyricLine(time: 5.0, text: 'Only')];

      expect(activeLyricLineIndex(single, 4.7), -1);
      expect(activeLyricLineIndex(single, 4.8), 0);
      expect(activeLyricLineIndex(single, 500.0), 0);
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

    test('fromMap treats empty synced/plain payloads as absent', () {
      final restored = SongLyrics.fromMap(<String, dynamic>{
        'track_id': 'track-3',
        'title': 'T',
        'artist': 'A',
        'synced_json': '',
        'plain_text': '',
        'source': 'LRCLIB',
        'fetched_at_ms': 0,
      });

      expect(restored.syncedLyrics, isNull);
      expect(restored.plainLyrics, isNull);
      expect(restored.hasSyncedLyrics, isFalse);
      expect(restored.hasPlainLyrics, isFalse);
    });

    test('toMap stores null for absent lyrics', () {
      final original = SongLyrics(
        trackId: 'track-4',
        title: 'T',
        artist: 'A',
        source: 'LRCLIB',
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final map = original.toMap();

      expect(map['synced_json'], isNull);
      expect(map['plain_text'], isNull);
      expect(SongLyrics.fromMap(map).hasSyncedLyrics, isFalse);
      expect(SongLyrics.fromMap(map).hasPlainLyrics, isFalse);
    });
  });

  group('fetchLyricsForTrack (fake cache + intercepted Dio)', () {
    test('cache hit returns cached lyrics without hitting the network',
        () async {
      final cache = _FakeLyricsCacheStore();
      cache.stored['t1'] = _cachedLyrics('t1', 'Cached line');
      final calls = <String>[];
      final service = _service(
        cache: cache,
        dio: _dioWith(
          failWith: DioExceptionType.connectionError,
          calls: calls,
        ),
      );

      final result =
          await service.fetchLyricsForTrack('t1', 'Dreams', 'Fleetwood Mac');

      expect(result?.syncedLyrics?.first.text, 'Cached line');
      expect(calls, isEmpty);
      expect(service.lastFetchStatus, isNull);
    });

    test('cache miss fetches the exact match and saves it', () async {
      final cache = _FakeLyricsCacheStore();
      final calls = <String>[];
      final service = _service(
        cache: cache,
        dio: _dioWith(
          calls: calls,
          getResponse: <String, dynamic>{
            'trackName': 'Dreams',
            'artistName': 'Fleetwood Mac',
            'syncedLyrics': '[00:01.00] First\n[00:05.00] Second',
            'plainLyrics': 'First\nSecond',
          },
        ),
      );

      final result =
          await service.fetchLyricsForTrack('t1', 'Dreams', 'Fleetwood Mac');

      expect(result?.hasSyncedLyrics, isTrue);
      expect(result?.syncedLyrics?.length, 2);
      expect(result?.syncedLyrics?.first.text, 'First');
      expect(result?.source, 'LRCLIB (Synced)');
      expect(service.lastFetchStatus, isNull);
      // Exact match only: the search fallback must not run.
      expect(calls.length, 1);
      expect(calls.first, contains('/get'));
      expect(cache.stored['t1']?.syncedLyrics?.length, 2);

      // The saved lyrics are a cache hit even with the network down.
      final offline = _service(
        cache: cache,
        dio: _dioWith(
          failWith: DioExceptionType.connectionError,
          calls: <String>[],
        ),
      );
      final again = await offline.fetchLyricsForTrack(
        't1',
        'Dreams',
        'Fleetwood Mac',
      );
      expect(again?.syncedLyrics?.first.text, 'First');
    });

    test('plain-only result returns plain lyrics with a non-synced label',
        () async {
      final cache = _FakeLyricsCacheStore();
      final service = _service(
        cache: cache,
        dio: _dioWith(
          calls: <String>[],
          getResponse: <String, dynamic>{
            'trackName': 'No Sync',
            'artistName': 'Someone',
            'syncedLyrics': null,
            'plainLyrics': 'Line one\n\nLine two\n',
          },
        ),
      );

      final result =
          await service.fetchLyricsForTrack('t2', 'No Sync', 'Someone');

      expect(result?.hasSyncedLyrics, isFalse);
      expect(result?.syncedLyrics, isNull);
      expect(result?.plainLyrics, ['Line one', 'Line two']);
      expect(result?.source, 'LRCLIB');
      expect(cache.stored['t2']?.plainLyrics, ['Line one', 'Line two']);
    });

    test('empty exact match and empty search report notFound, not offline',
        () async {
      final service = _service(
        cache: _FakeLyricsCacheStore(),
        dio: _dioWith(
          calls: <String>[],
          getResponse: <String, dynamic>{},
          searchResponse: <dynamic>[],
        ),
      );

      final result = await service.fetchLyricsForTrack(
        't3',
        'Uncatalogued Song',
        'Nobody',
      );

      expect(result, isNull);
      expect(service.lastFetchStatus, LyricsFetchStatus.notFound);
    });

    test('connection errors on both strategies report offline', () async {
      final service = _service(
        cache: _FakeLyricsCacheStore(),
        dio: _dioWith(
          failWith: DioExceptionType.connectionError,
          calls: <String>[],
        ),
      );

      final result =
          await service.fetchLyricsForTrack('t4', 'Dreams', 'Fleetwood Mac');

      expect(result, isNull);
      expect(service.lastFetchStatus, LyricsFetchStatus.offline);
    });

    test('a receive timeout is offline, not "not catalogued"', () async {
      final service = _service(
        cache: _FakeLyricsCacheStore(),
        dio: _dioWith(
          failWith: DioExceptionType.receiveTimeout,
          calls: <String>[],
        ),
      );

      final result =
          await service.fetchLyricsForTrack('t4', 'Dreams', 'Fleetwood Mac');

      expect(result, isNull);
      expect(service.lastFetchStatus, LyricsFetchStatus.offline);
    });

    test('forceRefresh bypasses the cache and replaces it', () async {
      final cache = _FakeLyricsCacheStore();
      cache.stored['t5'] = _cachedLyrics('t5', 'Old line');
      final calls = <String>[];
      final service = _service(
        cache: cache,
        dio: _dioWith(
          calls: calls,
          getResponse: <String, dynamic>{
            'trackName': 'Dreams',
            'artistName': 'Fleetwood Mac',
            'syncedLyrics': '[00:01.00] New line',
          },
        ),
      );

      final result = await service.fetchLyricsForTrack(
        't5',
        'Dreams',
        'Fleetwood Mac',
        forceRefresh: true,
      );

      expect(result?.syncedLyrics?.first.text, 'New line');
      expect(calls, isNotEmpty);
      expect(cache.stored['t5']?.syncedLyrics?.first.text, 'New line');
    });

    test('forced refresh while offline returns the stale cached lyrics',
        () async {
      final cache = _FakeLyricsCacheStore();
      cache.stored['t6'] = _cachedLyrics('t6', 'Old line');
      final service = _service(
        cache: cache,
        dio: _dioWith(
          failWith: DioExceptionType.connectionError,
          calls: <String>[],
        ),
      );

      final result = await service.fetchLyricsForTrack(
        't6',
        'Dreams',
        'Fleetwood Mac',
        forceRefresh: true,
      );

      expect(result?.syncedLyrics?.first.text, 'Old line');
      expect(service.lastFetchStatus, isNull);
    });

    test('search fallback prefers the title-matching result over the top hit',
        () async {
      final service = _service(
        cache: _FakeLyricsCacheStore(),
        dio: _dioWith(
          calls: <String>[],
          getResponse: <String, dynamic>{},
          searchResponse: <dynamic>[
            <String, dynamic>{
              'trackName': 'Daydreams',
              'artistName': 'Someone Else',
              'syncedLyrics': '[00:01.00] Wrong song',
            },
            <String, dynamic>{
              'trackName': 'Dreams',
              'artistName': 'Fleetwood Mac',
              'syncedLyrics': '[00:01.00] Right song',
            },
          ],
        ),
      );

      final result =
          await service.fetchLyricsForTrack('t7', 'Dreams', 'Fleetwood Mac');

      expect(result?.syncedLyrics?.first.text, 'Right song');
    });

    test('search fallback takes the first synced result when no title matches',
        () async {
      final service = _service(
        cache: _FakeLyricsCacheStore(),
        dio: _dioWith(
          calls: <String>[],
          getResponse: <String, dynamic>{},
          searchResponse: <dynamic>[
            <String, dynamic>{
              'trackName': 'Other Song',
              'artistName': 'Someone Else',
              'syncedLyrics': '[00:01.00] Fallback',
            },
            <String, dynamic>{
              'trackName': 'Third Song',
              'artistName': 'Someone Else',
              'plainLyrics': 'Plain',
            },
          ],
        ),
      );

      final result =
          await service.fetchLyricsForTrack('t7', 'Dreams', 'Fleetwood Mac');

      expect(result?.syncedLyrics?.first.text, 'Fallback');
    });

    test('search fallback skips results with neither synced nor plain lyrics',
        () async {
      final service = _service(
        cache: _FakeLyricsCacheStore(),
        dio: _dioWith(
          calls: <String>[],
          getResponse: <String, dynamic>{},
          searchResponse: <dynamic>[
            <String, dynamic>{
              'trackName': 'Empty',
              'artistName': 'Someone Else',
              'syncedLyrics': null,
              'plainLyrics': null,
            },
            <String, dynamic>{
              'trackName': 'Dreams',
              'artistName': 'Fleetwood Mac',
              'plainLyrics': 'Plain only',
            },
          ],
        ),
      );

      final result =
          await service.fetchLyricsForTrack('t7', 'Dreams', 'Fleetwood Mac');

      expect(result?.hasSyncedLyrics, isFalse);
      expect(result?.plainLyrics, ['Plain only']);
    });

    test('a title that cleans to empty reports notFound without networking',
        () async {
      final calls = <String>[];
      final service = _service(
        cache: _FakeLyricsCacheStore(),
        dio: _dioWith(
          failWith: DioExceptionType.connectionError,
          calls: calls,
        ),
      );

      final result = await service.fetchLyricsForTrack(
        't8',
        '(Official Video)',
        'Someone',
      );

      expect(result, isNull);
      expect(service.lastFetchStatus, LyricsFetchStatus.notFound);
      expect(calls, isEmpty);
    });
  });
}
