import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:btmu/core/storage/local_database.dart';

/// One synced lyric line: [time] is seconds from the start of the track.
class LyricLine {
  final double time;
  final String text;

  const LyricLine({required this.time, required this.text});
}

/// Lyrics for one track, mirroring the React `SongLyrics` shape.
class SongLyrics {
  final String trackId;
  final String title;
  final String artist;
  final List<LyricLine>? syncedLyrics;
  final List<String>? plainLyrics;
  final String source;
  final DateTime fetchedAt;

  const SongLyrics({
    required this.trackId,
    required this.title,
    required this.artist,
    this.syncedLyrics,
    this.plainLyrics,
    required this.source,
    required this.fetchedAt,
  });

  bool get hasSyncedLyrics => syncedLyrics != null && syncedLyrics!.isNotEmpty;
  bool get hasPlainLyrics => plainLyrics != null && plainLyrics!.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'track_id': trackId,
        'title': title,
        'artist': artist,
        'synced_json': syncedLyrics == null
            ? null
            : jsonEncode(
                syncedLyrics!
                    .map((line) => {'time': line.time, 'text': line.text})
                    .toList(),
              ),
        'plain_text': plainLyrics?.join('\n'),
        'source': source,
        'fetched_at_ms': fetchedAt.millisecondsSinceEpoch,
      };

  factory SongLyrics.fromMap(Map<String, dynamic> map) {
    List<LyricLine>? synced;
    final syncedJson = map['synced_json'] as String?;
    if (syncedJson != null && syncedJson.isNotEmpty) {
      final decoded = jsonDecode(syncedJson) as List<dynamic>;
      synced = decoded
          .map(
            (entry) => LyricLine(
              time: (entry['time'] as num).toDouble(),
              text: entry['text'] as String,
            ),
          )
          .toList();
    }

    List<String>? plain;
    final plainText = map['plain_text'] as String?;
    if (plainText != null && plainText.isNotEmpty) {
      plain = plainText.split('\n');
    }

    return SongLyrics(
      trackId: map['track_id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      syncedLyrics: synced,
      plainLyrics: plain,
      source: map['source'] as String,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['fetched_at_ms'] as int?) ?? 0,
      ),
    );
  }
}

/// Why the most recent [LyricsService.fetchLyricsForTrack] call returned null.
///
/// `null` means the last call succeeded (or was served from cache).
enum LyricsFetchStatus {
  /// A network request failed at the connection level (no route to LRCLIB).
  offline,

  /// LRCLIB answered but has no lyrics for this track.
  notFound,
}

/// Minimal cache seam for [LyricsService].
///
/// Production uses the SQLite `lyrics_cache` table (via
/// [_SqliteLyricsCacheStore]); tests inject an in-memory fake. The service
/// only ever talks to this interface, so the cache path is unit-testable
/// without a sqflite test double (the repo has none) or a constructible
/// [LocalDatabase] (its constructor is private).
abstract class LyricsCacheStore {
  Future<SongLyrics?> read(String trackId);
  Future<void> write(SongLyrics lyrics);
}

/// SQLite-backed [LyricsCacheStore] over [LocalDatabase].
class _SqliteLyricsCacheStore implements LyricsCacheStore {
  final LocalDatabase _database;
  bool _tableReady = false;

  _SqliteLyricsCacheStore(this._database);

  /// Creates the cache table on first use.
  ///
  /// Done lazily with `CREATE TABLE IF NOT EXISTS` (same pattern as
  /// `LocalDatabase._createFingerprintTable`) so no change to
  /// `local_database.dart` and no database version bump is needed. If the
  /// coordinator prefers the table in `onCreate`/`onUpgrade` with a
  /// version bump, this method can move there unchanged.
  Future<void> _ensureLyricsTable() async {
    if (_tableReady) return;
    final db = await _database.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lyrics_cache (
        track_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        synced_json TEXT,
        plain_text TEXT,
        source TEXT NOT NULL,
        fetched_at_ms INTEGER NOT NULL
      );
    ''');
    _tableReady = true;
  }

  @override
  Future<SongLyrics?> read(String trackId) async {
    try {
      await _ensureLyricsTable();
      final db = await _database.database;
      final rows = await db.query(
        'lyrics_cache',
        where: 'track_id = ?',
        whereArgs: [trackId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return SongLyrics.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SongLyrics lyrics) async {
    try {
      await _ensureLyricsTable();
      final db = await _database.database;
      await db.insert(
        'lyrics_cache',
        lyrics.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Caching must never break playback or the lyrics view.
    }
  }
}

/// Cleans a raw track title for higher lyric-matching rates.
///
/// Faithful port of `cleanSongTitle` in `src/services/lyricsService.ts`:
/// strips "(Official Video / Official Audio / Official Music Video /
/// Lyrics / Lyric Video / Official Visualizer / HQ / HD / Remix /
/// feat. … / ft. …)" style suffixes and trailing audio-file extensions.
String cleanSongTitle(String title) {
  final cleaned = title.replaceAll(
    RegExp(
      r'''\s*[\(\[](official\s*(music\s*)?(video|audio|lyrics?(\s*video)?|visualizer)|lyrics?(\s*video)?|audio|visualizer|hq|hd|remix|feat\..*|ft\..*)[\)\]]''',
      caseSensitive: false,
    ),
    '',
  );
  return cleaned
      .replaceAll(
        RegExp(r'\.mp3$|\.m4a$|\.wav$|\.flac$', caseSensitive: false),
        '',
      )
      .trim();
}

/// Cleans a raw artist name for higher lyric-matching rates.
///
/// Faithful port of `cleanArtistName` in `src/services/lyricsService.ts`:
/// placeholder artists become empty, and only the first artist of a
/// collaboration is kept.
String cleanArtistName(String artist) {
  final trimmed = artist.trim();
  if (trimmed.isEmpty ||
      trimmed.toLowerCase() == 'unknown artist' ||
      trimmed.toLowerCase() == 'imported audio') {
    return '';
  }
  return trimmed.split(',').first.split('&').first.trim();
}

/// Parses LRC text ("[mm:ss.xx] line text") into time-sorted [LyricLine]s.
///
/// Faithful port of `parseLrc` in `src/services/lyricsService.ts`:
/// a line may carry several timestamps (one entry per timestamp), lines
/// without a timestamp are skipped, unsorted input is sorted by time, and
/// a timestamp with no text becomes '♪'.
List<LyricLine> parseLrc(String lrcText) {
  if (lrcText.isEmpty) return [];

  // Matches e.g. [01:23.45] or [01:23].
  final timeRegex = RegExp(r'\[(\d{2}):(\d{2}(?:\.\d{1,3})?)\]');
  final result = <LyricLine>[];

  for (final rawLine in lrcText.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final matches = timeRegex.allMatches(line).toList();
    if (matches.isEmpty) continue;

    final text = line.replaceAll(timeRegex, '').trim();
    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = double.parse(match.group(2)!);
      result.add(
        LyricLine(
          time: minutes * 60 + seconds,
          text: text.isEmpty ? '♪' : text,
        ),
      );
    }
  }

  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

/// Index of the synced line active at [currentSeconds], or -1.
///
/// Mirrors the React `LyricsView` rule: a line is active once playback is
/// within 0.2s before its timestamp.
int activeLyricLineIndex(List<LyricLine> lines, double currentSeconds) {
  var index = -1;
  for (var i = 0; i < lines.length; i++) {
    if (currentSeconds >= lines[i].time - 0.2) {
      index = i;
    } else {
      break;
    }
  }
  return index;
}

/// Fetches lyrics from the free LRCLIB API and caches them in SQLite.
///
/// Faithful port of `src/services/lyricsService.ts`, with two differences
/// forced by the platform: the cache lives in a `lyrics_cache` SQLite table
/// (same database as the library) instead of `localStorage`, and HTTP goes
/// through the app's existing client, dio. Every public method is null-safe:
/// any failure returns null (or does nothing) and never throws to the UI.
class LyricsService {
  static const String _baseUrl = 'https://lrclib.net/api';

  /// Identifies Btmus 3.0.5 to LRCLIB, as the API's docs request.
  static const String clientHeader = 'btmu/3.0.5 (https://btt1996.github.io)';

  final Dio _dio;
  final LyricsCacheStore _cache;

  /// Why the most recent fetch returned null; null after a success or a
  /// cache hit. Lets the UI tell "offline" apart from "not catalogued".
  LyricsFetchStatus? _lastStatus;
  LyricsFetchStatus? get lastFetchStatus => _lastStatus;

  LyricsService({Dio? dio, LocalDatabase? database, LyricsCacheStore? cache})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 15),
                headers: const {
                  'Lrclib-Client': clientHeader,
                  'Accept': 'application/json',
                },
              ),
            ),
        _cache = cache ??
            _SqliteLyricsCacheStore(database ?? LocalDatabase.instance);

  /// Returns cached lyrics for [trackId], or null on a miss or any error.
  Future<SongLyrics?> getCachedLyrics(String trackId) => _cache.read(trackId);

  /// Saves [lyrics] to the offline cache; silently ignored on any error.
  Future<void> saveCachedLyrics(SongLyrics lyrics) => _cache.write(lyrics);

  /// Fetches lyrics for a track, returning null when none can be found.
  ///
  /// Strategy A: exact match via `GET /api/get` with track/artist and the
  /// duration when known. Strategy B: `GET /api/search` fallback, preferring
  /// a title-matching result with synced lyrics, then any result with
  /// synced lyrics, then the first result with any lyrics. The offline cache
  /// is checked first unless [forceRefresh] is set (manual retry); on a
  /// forced refresh that fails at the connection level, the stale cached
  /// lyrics are returned instead of hiding lyrics the user already had.
  /// Never throws.
  Future<SongLyrics?> fetchLyricsForTrack(
    String trackId,
    String rawTitle,
    String rawArtist, {
    int? durationSeconds,
    bool forceRefresh = false,
  }) async {
    SongLyrics? cached;
    try {
      cached = await getCachedLyrics(trackId);
      if (cached != null && !forceRefresh) {
        _lastStatus = null;
        return cached;
      }

      final title = cleanSongTitle(rawTitle);
      final artist = cleanArtistName(rawArtist);
      if (title.isEmpty) {
        _lastStatus = LyricsFetchStatus.notFound;
        return null;
      }

      Map<String, dynamic>? data;
      var sawConnectionError = false;

      // Strategy A: exact match, with duration when available.
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '$_baseUrl/get',
          queryParameters: {
            'track_name': title,
            if (artist.isNotEmpty) 'artist_name': artist,
            if (durationSeconds != null && durationSeconds > 0)
              'duration': durationSeconds,
          },
        );
        final body = response.data;
        if (response.statusCode == 200 &&
            body != null &&
            (body['syncedLyrics'] != null || body['plainLyrics'] != null)) {
          data = body;
        }
      } on DioException catch (e) {
        if (_isConnectionError(e)) sawConnectionError = true;
      }

      // Strategy B: search fallback when the exact lookup came up empty.
      if (data == null) {
        try {
          final query = artist.isNotEmpty ? '$artist $title' : title;
          final response = await _dio.get<List<dynamic>>(
            '$_baseUrl/search',
            queryParameters: {'q': query},
          );
          final results = response.data;
          if (response.statusCode == 200 &&
              results != null &&
              results.isNotEmpty) {
            Map<String, dynamic>? picked;
            // Prefer a title-matching result with synced lyrics: search
            // relevance does not guarantee the top hit is this track
            // (a cover or remix can outrank it).
            for (final entry in results) {
              if (entry is Map<String, dynamic> &&
                  entry['syncedLyrics'] != null &&
                  _matchesTitle(entry, title)) {
                picked = entry;
                break;
              }
            }
            if (picked == null) {
              for (final entry in results) {
                if (entry is Map<String, dynamic> &&
                    entry['syncedLyrics'] != null) {
                  picked = entry;
                  break;
                }
              }
            }
            if (picked == null) {
              for (final entry in results) {
                if (entry is Map<String, dynamic> &&
                    (entry['syncedLyrics'] != null ||
                        entry['plainLyrics'] != null)) {
                  picked = entry;
                  break;
                }
              }
            }
            if (picked != null) {
              data = picked;
            }
          }
        } on DioException catch (e) {
          if (_isConnectionError(e)) sawConnectionError = true;
        }
      }

      if (data == null) {
        if (sawConnectionError && cached != null) {
          // Forced refresh while offline: keep showing the lyrics the
          // user already had instead of an empty state.
          _lastStatus = null;
          return cached;
        }
        _lastStatus = sawConnectionError
            ? LyricsFetchStatus.offline
            : LyricsFetchStatus.notFound;
        return null;
      }

      final syncedRaw = data['syncedLyrics'] as String?;
      final plainRaw = data['plainLyrics'] as String?;
      final synced = syncedRaw != null && syncedRaw.isNotEmpty
          ? parseLrc(syncedRaw)
          : <LyricLine>[];
      final plain = plainRaw == null
          ? <String>[]
          : plainRaw
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();

      if (synced.isEmpty && plain.isEmpty) {
        _lastStatus = LyricsFetchStatus.notFound;
        return null;
      }

      final lyrics = SongLyrics(
        trackId: trackId,
        title: _responseTitle(data, rawTitle),
        artist: _responseTitle(data, rawArtist, key: 'artistName'),
        syncedLyrics: synced.isEmpty ? null : synced,
        plainLyrics: plain.isEmpty ? null : plain,
        // Plain-only results are labelled without "(Synced)": the footer
        // must not claim sync the lyrics do not have.
        source: synced.isEmpty ? 'LRCLIB' : 'LRCLIB (Synced)',
        fetchedAt: DateTime.now(),
      );

      _lastStatus = null;
      await saveCachedLyrics(lyrics);
      return lyrics;
    } catch (_) {
      if (cached != null) {
        _lastStatus = null;
        return cached;
      }
      _lastStatus = LyricsFetchStatus.notFound;
      return null;
    }
  }

  static String _responseTitle(
    Map<String, dynamic> data,
    String fallback, {
    String key = 'trackName',
  }) {
    final value = data[key] as String?;
    if (value != null && value.trim().isNotEmpty) return value;
    return fallback;
  }

  /// Whether [entry]'s LRCLIB title is the requested [title] after the
  /// same cleaning applied to the query (suffixes/extensions stripped).
  static bool _matchesTitle(Map<String, dynamic> entry, String title) {
    final candidate = entry['trackName'] as String?;
    if (candidate == null) return false;
    return cleanSongTitle(candidate).toLowerCase() == title.toLowerCase();
  }

  /// Connection-level failures mean "offline", not "not catalogued".
  ///
  /// Timeouts and `unknown` (Dio's bucket for transport errors such as
  /// SocketException / TLS failures, and for malformed responses) count
  /// here: on a flaky mobile connection a stalled request is an offline
  /// signal, while a clean 4xx/5xx (`badResponse`) is not.
  static bool _isConnectionError(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.unknown;
}
