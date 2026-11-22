import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../core/storage/local_database.dart';
import '../models/playlist.dart';
import '../models/track.dart';

class PlaylistRepository {
  final LocalDatabase _db;
  static const _uuid = Uuid();

  PlaylistRepository(this._db);

  Future<List<Playlist>> getAllPlaylists() async {
    final db = await _db.database;
    final rows = await db.query('playlists', orderBy: 'updated_at_ms DESC');
    final playlists = <Playlist>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final trackRows = await db.query(
        'playlist_tracks',
        columns: ['track_id'],
        where: 'playlist_id = ?',
        whereArgs: [id],
        orderBy: 'position ASC',
      );
      playlists.add(
        Playlist.fromMap(
          row,
          trackIds: trackRows.map((r) => r['track_id'] as String).toList(),
        ),
      );
    }
    return playlists;
  }

  Future<Playlist> createPlaylist({required String name, String description = ''}) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final playlist = Playlist(
      id: _uuid.v4(),
      name: name.trim(),
      description: description.trim(),
      createdAtMs: now,
      updatedAtMs: now,
    );
    await db.insert('playlists', playlist.toMap());
    return playlist;
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    final db = await _db.database;
    final countRow = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next_pos FROM playlist_tracks WHERE playlist_id = ?',
      [playlistId],
    );
    final nextPos = (countRow.first['next_pos'] as int?) ?? 0;
    await db.rawInsert(
      'INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)',
      [playlistId, trackId, nextPos],
    );
    await db.update(
      'playlists',
      {'updated_at_ms': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final db = await _db.database;
    await db.delete(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, trackId],
    );
  }

  Future<void> deletePlaylist(String playlistId) async {
    final db = await _db.database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }

  // MARK: - Playlist export / import (Phase 6, item 27)
  //
  // Own versioned format — deliberately NOT the backup format
  // (`BackupService`, version 2, whole-library document). A playlist
  // export is one playlist only:
  //
  //   {app: 'btmu', format: 'btmu-playlist', version: 1, exportedAt,
  //    playlist: {name, description},
  //    tracks: [{title, artist, album, durationSeconds, sha256}]}
  //
  // M3U is offered as a lossy interchange format alongside it: no
  // SHA-256, no album, matching by `#EXTINF` artist/title only. JSON is
  // the faithful format; M3U is for players that only speak M3U.
  //
  // Import matches each entry against the library tracks the caller
  // passes in, SHA-256 first (exact audio) then the same
  // lower-cased `title|artist` key `BackupService` uses. Nothing is
  // silently dropped: every entry lands in exactly one bucket of
  // [PlaylistImportResult] (added / already-in-this-import / missing /
  // skipped-malformed), and the UI must show that summary. Import never
  // overwrites an existing playlist: a colliding name gets an
  // " (imported)" suffix instead.

  static const int playlistExportVersion = 1;

  /// Builds the JSON export document for [playlist] with its resolved
  /// [tracks] (tracks whose library rows are gone are the caller's
  /// responsibility — pass only resolvable tracks). Pure: no I/O.
  static String exportPlaylistJson({
    required Playlist playlist,
    required List<Track> tracks,
  }) {
    final doc = <String, Object?>{
      'app': 'btmu',
      'format': 'btmu-playlist',
      'version': playlistExportVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'playlist': <String, Object?>{
        'name': playlist.name,
        'description': playlist.description,
      },
      'tracks': tracks
          .map((t) => <String, Object?>{
                'title': t.title,
                'artist': t.artist,
                'album': t.album,
                'durationSeconds': t.durationSeconds,
                'sha256': t.sha256,
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  /// Builds the M3U export. The file line after each `#EXTINF` is the
  /// stored file's base name only — absolute on-device paths never leave
  /// the device. Import matches on the `#EXTINF` artist/title and
  /// ignores the file line.
  static String exportPlaylistM3u({
    required Playlist playlist,
    required List<Track> tracks,
  }) {
    final buf = StringBuffer('#EXTM3U\n#PLAYLIST:${_m3uEscape(playlist.name)}\n');
    for (final t in tracks) {
      buf.writeln(
        '#EXTINF:${t.durationSeconds},${_m3uEscape(t.artist)} - ${_m3uEscape(t.title)}',
      );
      buf.writeln(_m3uEscape(p.basename(t.localFilePath)));
    }
    return buf.toString();
  }

  /// M3U lines must not contain raw newlines; a newline inside a title
  /// would corrupt the next entry's parse.
  static String _m3uEscape(String value) =>
      value.replaceAll('\r', ' ').replaceAll('\n', ' ');

  /// Suggested file name for a JSON export, e.g.
  /// `btmu-playlist-road-trip-20261122.json`.
  static String exportFileNameJson(Playlist playlist, [DateTime? at]) =>
      'btmu-playlist-${_slug(playlist.name)}-${_dateStamp(at)}.json';

  /// Suggested file name for an M3U export.
  static String exportFileNameM3u(Playlist playlist, [DateTime? at]) =>
      'btmu-playlist-${_slug(playlist.name)}-${_dateStamp(at)}.m3u';

  static String _dateStamp([DateTime? at]) {
    final d = (at ?? DateTime.now()).toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}';
  }

  static String _slug(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'playlist' : slug;
  }

  /// Imports a JSON playlist export ([PlaylistExportDocument.parseJson])
  /// into a new playlist. [libraryTracks] is the current library; the
  /// repository does not re-read it, so callers pass the already-loaded
  /// list (and tests can inject fakes without a database).
  Future<PlaylistImportResult> importPlaylistJson(
    String json, {
    required List<Track> libraryTracks,
  }) async {
    return importPlaylistDocument(
      PlaylistExportDocument.parseJson(json),
      libraryTracks: libraryTracks,
    );
  }

  /// Imports an M3U playlist ([PlaylistExportDocument.parseM3u]) into a
  /// new playlist. [fallbackName] is used when the M3U carries no
  /// `#PLAYLIST:` header (e.g. the picked file's base name).
  Future<PlaylistImportResult> importPlaylistM3u(
    String m3u, {
    required List<Track> libraryTracks,
    String? fallbackName,
  }) async {
    return importPlaylistDocument(
      PlaylistExportDocument.parseM3u(m3u, fallbackName: fallbackName),
      libraryTracks: libraryTracks,
    );
  }

  /// Shared import core: resolves [doc] against [libraryTracks], creates
  /// a new playlist (name made unique, never overwriting), and adds every
  /// matched track. Every entry is accounted for in the result.
  Future<PlaylistImportResult> importPlaylistDocument(
    PlaylistExportDocument doc, {
    required List<Track> libraryTracks,
  }) async {
    final bySha = <String, Track>{};
    final byKey = <String, Track>{};
    for (final t in libraryTracks) {
      if (t.sha256.isNotEmpty) bySha[t.sha256] = t;
      byKey[_matchKey(t.title, t.artist)] = t;
    }

    final name = await _uniquePlaylistName(doc.name);
    final created = await createPlaylist(name: name, description: doc.description);

    final result = PlaylistImportResult(
      playlistId: created.id,
      playlistName: created.name,
    );
    final addedIds = <String>{};
    for (final entry in doc.tracks) {
      // Empty title: nothing to match on at all — malformed, counted.
      // An entry WITH a title but no artist (e.g. a bare M3U path line,
      // or an `#EXTINF` with no "Artist - Title" separator) is NOT
      // malformed: it is a real reference that simply has no library
      // match, so it lands in missingLabels with its title as the label.
      if (entry.title.trim().isEmpty) {
        result.skipped++;
        continue;
      }
      final match = _findMatch(entry, bySha, byKey);
      if (match == null) {
        result.missingLabels.add(
          entry.artist.trim().isEmpty
              ? entry.title
              : '${entry.title} — ${entry.artist}',
        );
        continue;
      }
      if (!addedIds.add(match.id)) {
        result.duplicates++;
        continue;
      }
      await addTrackToPlaylist(created.id, match.id);
      result.added++;
    }
    return result;
  }

  Track? _findMatch(
    PlaylistTrackEntry entry,
    Map<String, Track> bySha,
    Map<String, Track> byKey,
  ) {
    if (entry.sha256.isNotEmpty) {
      final byHash = bySha[entry.sha256];
      if (byHash != null) return byHash;
    }
    return byKey[_matchKey(entry.title, entry.artist)];
  }

  /// Same match key as `BackupService.trackKeyFor`: lower-cased
  /// `title|artist`, trimmed. One rule for both formats.
  static String _matchKey(String title, String artist) =>
      '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';

  /// A name that does not collide with an existing playlist: the
  /// requested name when free, otherwise `"<name> (imported)"`,
  /// `"<name> (imported 2)"`, … An empty requested name becomes
  /// "Imported playlist".
  Future<String> _uniquePlaylistName(String requested) async {
    final existing = (await getAllPlaylists())
        .map((pl) => pl.name.trim().toLowerCase())
        .toSet();
    final base = requested.trim().isEmpty ? 'Imported playlist' : requested.trim();
    if (!existing.contains(base.toLowerCase())) return base;
    var n = 1;
    while (true) {
      final candidate = n == 1 ? '$base (imported)' : '$base (imported $n)';
      if (!existing.contains(candidate.toLowerCase())) return candidate;
      n++;
    }
  }
}

/// Thrown when a playlist export file is structurally malformed (not
/// JSON, wrong `app`/`format`/`version`, wrong-typed fields). Entry-level
/// problems (empty title) do not throw — they are skipped and
/// counted in [PlaylistImportResult.skipped].
class PlaylistFormatException implements Exception {
  final String message;
  const PlaylistFormatException(this.message);

  @override
  String toString() => 'PlaylistFormatException: $message';
}

/// One track entry inside a playlist export document.
class PlaylistTrackEntry {
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final String sha256;

  const PlaylistTrackEntry({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
    required this.sha256,
  });
}

/// A validated playlist export document (JSON or M3U). Parse with
/// [parseJson] / [parseM3u], which reject malformed input instead of
/// guessing.
class PlaylistExportDocument {
  final String name;
  final String description;
  final List<PlaylistTrackEntry> tracks;
  final DateTime? exportedAt;

  const PlaylistExportDocument({
    required this.name,
    required this.description,
    required this.tracks,
    required this.exportedAt,
  });

  static PlaylistExportDocument parseJson(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw PlaylistFormatException('Not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PlaylistFormatException(
        'Playlist export must be a JSON object with app, format, version, '
        'playlist and tracks.',
      );
    }
    if (decoded['app'] != 'btmu') {
      throw const PlaylistFormatException(
        'Not a btmu playlist export (top-level "app" must be "btmu").',
      );
    }
    if (decoded['format'] != 'btmu-playlist') {
      throw const PlaylistFormatException(
        'Not a btmu playlist export (top-level "format" must be '
        '"btmu-playlist" — a full-library backup uses a different format).',
      );
    }
    final version = decoded['version'];
    if (version is! int) {
      throw const PlaylistFormatException(
        'Playlist export "version" must be an integer (1).',
      );
    }
    if (version != PlaylistRepository.playlistExportVersion) {
      throw PlaylistFormatException(
        'Unsupported playlist export version $version (supported: '
        '${PlaylistRepository.playlistExportVersion}).',
      );
    }

    DateTime? exportedAt;
    final exportedRaw = decoded['exportedAt'];
    if (exportedRaw != null) {
      if (exportedRaw is! String) {
        throw const PlaylistFormatException(
          'Playlist export "exportedAt" must be an ISO 8601 string.',
        );
      }
      exportedAt = DateTime.tryParse(exportedRaw);
      if (exportedAt == null) {
        throw const PlaylistFormatException(
          'Playlist export "exportedAt" is not a valid ISO 8601 date.',
        );
      }
    }

    final playlistRaw = decoded['playlist'];
    if (playlistRaw is! Map<String, dynamic>) {
      throw const PlaylistFormatException(
        'Playlist export "playlist" must be an object with a name.',
      );
    }
    final name = playlistRaw['name'];
    if (name != null && name is! String) {
      throw const PlaylistFormatException(
        'Playlist export "playlist.name" must be a string.',
      );
    }
    final description = playlistRaw['description'];
    if (description != null && description is! String) {
      throw const PlaylistFormatException(
        'Playlist export "playlist.description" must be a string.',
      );
    }

    final tracksRaw = decoded['tracks'];
    if (tracksRaw is! List) {
      throw const PlaylistFormatException(
        'Playlist export "tracks" must be a list.',
      );
    }
    final tracks = <PlaylistTrackEntry>[];
    for (var i = 0; i < tracksRaw.length; i++) {
      final raw = tracksRaw[i];
      if (raw is! Map<String, dynamic>) {
        throw PlaylistFormatException(
          'Playlist track entry #$i must be a JSON object.',
        );
      }
      tracks.add(_entryFromJson(raw, i));
    }

    return PlaylistExportDocument(
      name: (name as String?) ?? '',
      description: (description as String?) ?? '',
      tracks: tracks,
      exportedAt: exportedAt,
    );
  }

  static PlaylistTrackEntry _entryFromJson(Map<String, dynamic> json, int index) {
    String reqString(String key) {
      final v = json[key];
      if (v == null) return '';
      if (v is! String) {
        throw PlaylistFormatException(
          'Playlist track #$index: "$key" must be a string.',
        );
      }
      return v;
    }

    int reqInt(String key) {
      final v = json[key];
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      throw PlaylistFormatException(
        'Playlist track #$index: "$key" must be a number.',
      );
    }

    return PlaylistTrackEntry(
      title: reqString('title'),
      artist: reqString('artist'),
      album: reqString('album'),
      durationSeconds: reqInt('durationSeconds'),
      sha256: reqString('sha256'),
    );
  }

  /// Parses an M3U / M3U8 playlist. `#PLAYLIST:` supplies the name when
  /// present, otherwise [fallbackName] (or "Imported playlist").
  /// `#EXTINF:<secs>,Artist - Title` entries match by artist/title; the
  /// file line after each `#EXTINF` is ignored for matching (it is a
  /// device-local path on the exporting device). A bare file/path line
  /// with no preceding `#EXTINF` cannot be matched to an artist, so it
  /// is kept as a missing entry labelled with the line itself — never
  /// silently dropped.
  static PlaylistExportDocument parseM3u(String m3u, {String? fallbackName}) {
    var name = (fallbackName ?? '').trim();
    final tracks = <PlaylistTrackEntry>[];
    final missingBareLines = <String>[];
    String? pendingArtist;
    String? pendingTitle;
    int pendingDuration = 0;

    void flushPending() {
      if (pendingTitle != null) {
        tracks.add(
          PlaylistTrackEntry(
            title: pendingTitle!,
            artist: pendingArtist ?? '',
            album: '',
            durationSeconds: pendingDuration,
            sha256: '',
          ),
        );
        pendingTitle = null;
        pendingArtist = null;
        pendingDuration = 0;
      }
    }

    for (final rawLine in m3u.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#PLAYLIST:')) {
        final parsed = line.substring('#PLAYLIST:'.length).trim();
        if (parsed.isNotEmpty) name = parsed;
        continue;
      }
      if (line.startsWith('#EXTINF:')) {
        flushPending();
        final rest = line.substring('#EXTINF:'.length);
        final comma = rest.indexOf(',');
        if (comma < 0) {
          // Malformed EXTINF: keep the whole remainder as the title so
          // the entry is reported missing instead of vanishing.
          pendingTitle = rest.trim();
          pendingArtist = '';
          pendingDuration = 0;
          continue;
        }
        pendingDuration = int.tryParse(rest.substring(0, comma).trim()) ?? 0;
        final label = rest.substring(comma + 1).trim();
        final sep = label.indexOf(' - ');
        if (sep >= 0) {
          pendingArtist = label.substring(0, sep).trim();
          pendingTitle = label.substring(sep + 3).trim();
        } else {
          pendingArtist = '';
          pendingTitle = label;
        }
        continue;
      }
      if (line.startsWith('#')) continue;
      if (pendingTitle != null) {
        // File line belonging to the preceding #EXTINF: matching uses
        // the EXTINF artist/title, the path itself is not trusted.
        flushPending();
        continue;
      }
      // Bare path line with no #EXTINF: unmatchable, but counted.
      missingBareLines.add(line);
    }
    flushPending();

    // Bare lines surface as missing entries (empty artist ⇒ no match ⇒
    // counted in PlaylistImportResult.missingLabels with this label).
    // Their label keeps the file name so the user can tell what failed.
    for (final bare in missingBareLines) {
      tracks.add(
        PlaylistTrackEntry(
          title: bare,
          artist: '',
          album: '',
          durationSeconds: 0,
          sha256: '',
        ),
      );
    }

    return PlaylistExportDocument(
      name: name.isEmpty ? 'Imported playlist' : name,
      description: '',
      tracks: tracks,
      exportedAt: null,
    );
  }
}

/// What a playlist import did. Every entry of the imported file is
/// accounted for exactly once: [added] + [duplicates] + [skipped] +
/// [missingLabels].length == entries in the file.
class PlaylistImportResult {
  final String playlistId;
  final String playlistName;

  /// Entries matched to a library track and added to the new playlist.
  int added = 0;

  /// Entries whose track was already added by an earlier entry in the
  /// same file (same track listed twice). Not added twice.
  int duplicates = 0;

  /// Entries with an empty title. Nothing to match on — malformed.
  int skipped = 0;

  /// Labels (`"Title — Artist"`) of entries with no library match.
  /// Those tracks are not in this library — the user must import the
  /// audio first. Nothing here is silent: the UI shows this list.
  final List<String> missingLabels = [];

  PlaylistImportResult({required this.playlistId, required this.playlistName});

  int get totalEntries => added + duplicates + skipped + missingLabels.length;

  String get summary {
    final lines = <String>[
      '$added track${added == 1 ? '' : 's'} added to "$playlistName"',
    ];
    if (duplicates > 0) {
      lines.add('$duplicates duplicate ${duplicates == 1 ? 'entry' : 'entries'} in the file (added once)');
    }
    if (missingLabels.isNotEmpty) {
      lines.add(
        '${missingLabels.length} not in your library: '
        '${missingLabels.take(5).join('; ')}'
        '${missingLabels.length > 5 ? ' (and ${missingLabels.length - 5} more)' : ''}',
      );
    }
    if (skipped > 0) {
      lines.add('$skipped malformed ${skipped == 1 ? 'entry' : 'entries'} skipped (empty title)');
    }
    return lines.join('\n');
  }
}
