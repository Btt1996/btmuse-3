/**
 * Per-playlist export / import in the `btmu-playlist` v1 format
 * (Phase 7: React port of the Flutter format from Phase 6, item 27 —
 * `flutter_app/lib/data/repositories/playlist_repository.dart`).
 *
 * The format is deliberately NOT the backup format (`exportLibraryBackup`,
 * whole-library document). A playlist export is one playlist only:
 *
 *   {app: 'btmu', format: 'btmu-playlist', version: 1, exportedAt,
 *    playlist: {name, description},
 *    tracks: [{title, artist, album, durationSeconds, sha256}]}
 *
 * M3U is offered as a lossy interchange format alongside it: no
 * SHA-256, no album, matching by `#EXTINF` artist/title only. JSON is
 * the faithful format; M3U is for players that only speak M3U.
 *
 * One honest React-side limit, stated where the code cannot hide it:
 * React tracks carry no SHA-256 content hash. `Track.fileHash` is a
 * Telegram `fileUniqueId`, NOT a content hash, so it must never be
 * written into the `sha256` field (a false hash would match nothing
 * on the Flutter side and would be a lie in the file). Export therefore
 * writes `sha256: ''`, and import matches on the lower-cased
 * `title|artist` key only — the same key `BackupService` uses. A
 * Flutter export imported here still resolves every track whose
 * title/artist is in this library; its `sha256` values are simply
 * not usable as a match key on this side.
 *
 * Import never overwrites an existing playlist: a colliding name gets
 * an " (imported)" suffix instead (see `uniquePlaylistName`).
 * Nothing is silently dropped: every entry lands in exactly one
 * bucket of `PlaylistImportResolution` (matched / duplicate-in-file /
 * missing / skipped-malformed), and the UI must show that summary.
 *
 * Pure functions only — no I/O, no context. The view owns the file
 * download (Blob + anchor, same pattern as SettingsScreen's backup
 * export) and the file pick (hidden `<input type="file">`).
 */

import { Playlist, Track } from '../types/music';

export const playlistExportVersion = 1;

/** Thrown when a playlist export file is structurally malformed. */
export class PlaylistFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PlaylistFormatError';
  }
}

export interface PlaylistExportTrackEntry {
  title: string;
  artist: string;
  album: string;
  durationSeconds: number;
  sha256: string;
}

export interface PlaylistExportDocument {
  name: string;
  description: string;
  tracks: PlaylistExportTrackEntry[];
  exportedAt: string | null;
}

/** What a playlist import did. Every entry of the imported file is
 *  accounted for exactly once: matchedTrackIds.length + duplicates +
 *  skipped + missingLabels.length == entries in the file. */
export interface PlaylistImportResolution {
  /** Library track ids matched, in file order, duplicates removed. */
  matchedTrackIds: string[];
  /** Entries whose track was already matched by an earlier entry in
   *  the same file (same track listed twice). Not added twice. */
  duplicates: number;
  /** Entries with an empty title. Nothing to match on — malformed. */
  skipped: number;
  /** Labels (`"Title — Artist"`) of entries with no library match.
   *  Those tracks are not in this library — the user must import the
   *  audio first. */
  missingLabels: string[];
  totalEntries: number;
}

/**
 * Builds the JSON export document for `playlist` with its resolved
 * `tracks` (tracks whose library rows are gone are the caller's
 * responsibility — pass only resolvable tracks). Pure: no I/O.
 */
export function buildPlaylistExportJson(
  playlist: Pick<Playlist, 'name' | 'description'>,
  tracks: Track[],
): string {
  const doc = {
    app: 'btmu',
    format: 'btmu-playlist',
    version: playlistExportVersion,
    exportedAt: new Date().toISOString(),
    playlist: {
      name: playlist.name,
      description: playlist.description ?? '',
    },
    tracks: tracks.map((t) => ({
      title: t.title,
      artist: t.artist,
      album: t.album,
      durationSeconds: Math.round(t.duration || 0),
      // No SHA-256 on the React side (see the module doc comment):
      // an empty string, never Track.fileHash (a Telegram id).
      sha256: '',
    })),
  };
  return JSON.stringify(doc, null, 2);
}

/**
 * Builds the M3U export. The file line after each `#EXTINF` is the
 * stored file's name only — absolute on-device paths never leave the
 * device. Import matches on the `#EXTINF` artist/title and ignores
 * the file line.
 */
export function buildPlaylistExportM3u(
  playlist: Pick<Playlist, 'name'>,
  tracks: Track[],
): string {
  const lines = ['#EXTM3U', `#PLAYLIST:${m3uEscape(playlist.name)}`];
  for (const t of tracks) {
    lines.push(
      `#EXTINF:${Math.round(t.duration || 0)},${m3uEscape(t.artist)} - ${m3uEscape(t.title)}`,
    );
    lines.push(m3uEscape(t.fileName));
  }
  return lines.join('\n') + '\n';
}

/** M3U lines must not contain raw newlines; a newline inside a title
 *  would corrupt the next entry's parse. */
function m3uEscape(value: string): string {
  return value.replace(/\r/g, ' ').replace(/\n/g, ' ');
}

/** Suggested file name for a JSON export, e.g.
 *  `btmu-playlist-road-trip-20261122.json`. */
export function exportPlaylistFileNameJson(playlistName: string, at = new Date()): string {
  return `btmu-playlist-${slug(playlistName)}-${dateStamp(at)}.json`;
}

/** Suggested file name for an M3U export. */
export function exportPlaylistFileNameM3u(playlistName: string, at = new Date()): string {
  return `btmu-playlist-${slug(playlistName)}-${dateStamp(at)}.m3u`;
}

function dateStamp(at: Date): string {
  const two = (n: number) => n.toString().padStart(2, '0');
  return `${at.getUTCFullYear()}${two(at.getUTCMonth() + 1)}${two(at.getUTCDate())}`;
}

function slug(name: string): string {
  const s = name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return s === '' ? 'playlist' : s;
}

/**
 * Parses a JSON playlist export. Rejects malformed input instead of
 * guessing (mirrors `PlaylistExportDocument.parseJson` on the Flutter
 * side). Entry-level problems (empty title) do not throw — they are
 * skipped and counted when the document is resolved.
 */
export function parsePlaylistExportJson(text: string): PlaylistExportDocument {
  let decoded: unknown;
  try {
    decoded = JSON.parse(text);
  } catch {
    throw new PlaylistFormatError('Not valid JSON.');
  }
  if (typeof decoded !== 'object' || decoded === null || Array.isArray(decoded)) {
    throw new PlaylistFormatError(
      'Playlist export must be a JSON object with app, format, version, playlist and tracks.',
    );
  }
  const doc = decoded as Record<string, unknown>;
  if (doc.app !== 'btmu') {
    throw new PlaylistFormatError(
      'Not a btmu playlist export (top-level "app" must be "btmu").',
    );
  }
  if (doc.format !== 'btmu-playlist') {
    throw new PlaylistFormatError(
      'Not a btmu playlist export (top-level "format" must be "btmu-playlist" — a full-library backup uses a different format).',
    );
  }
  if (typeof doc.version !== 'number' || !Number.isInteger(doc.version)) {
    throw new PlaylistFormatError('Playlist export "version" must be an integer (1).');
  }
  if (doc.version !== playlistExportVersion) {
    throw new PlaylistFormatError(
      `Unsupported playlist export version ${doc.version} (supported: ${playlistExportVersion}).`,
    );
  }

  let exportedAt: string | null = null;
  if (doc.exportedAt != null) {
    if (typeof doc.exportedAt !== 'string' || Number.isNaN(Date.parse(doc.exportedAt))) {
      throw new PlaylistFormatError(
        'Playlist export "exportedAt" must be an ISO 8601 string.',
      );
    }
    exportedAt = doc.exportedAt;
  }

  if (typeof doc.playlist !== 'object' || doc.playlist === null || Array.isArray(doc.playlist)) {
    throw new PlaylistFormatError(
      'Playlist export "playlist" must be an object with a name.',
    );
  }
  const playlistRaw = doc.playlist as Record<string, unknown>;
  if (playlistRaw.name != null && typeof playlistRaw.name !== 'string') {
    throw new PlaylistFormatError('Playlist export "playlist.name" must be a string.');
  }
  if (playlistRaw.description != null && typeof playlistRaw.description !== 'string') {
    throw new PlaylistFormatError(
      'Playlist export "playlist.description" must be a string.',
    );
  }

  if (!Array.isArray(doc.tracks)) {
    throw new PlaylistFormatError('Playlist export "tracks" must be a list.');
  }
  const tracks = doc.tracks.map((raw, i) => entryFromJson(raw, i));

  return {
    name: (playlistRaw.name as string | undefined) ?? '',
    description: (playlistRaw.description as string | undefined) ?? '',
    tracks,
    exportedAt,
  };
}

function entryFromJson(raw: unknown, index: number): PlaylistExportTrackEntry {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw new PlaylistFormatError(`Playlist track entry #${index} must be a JSON object.`);
  }
  const entry = raw as Record<string, unknown>;
  const reqString = (key: string): string => {
    const v = entry[key];
    if (v == null) return '';
    if (typeof v !== 'string') {
      throw new PlaylistFormatError(`Playlist track #${index}: "${key}" must be a string.`);
    }
    return v;
  };
  const reqInt = (key: string): number => {
    const v = entry[key];
    if (v == null) return 0;
    if (typeof v === 'number') return Math.trunc(v);
    throw new PlaylistFormatError(`Playlist track #${index}: "${key}" must be a number.`);
  };
  return {
    title: reqString('title'),
    artist: reqString('artist'),
    album: reqString('album'),
    durationSeconds: reqInt('durationSeconds'),
    sha256: reqString('sha256'),
  };
}

/**
 * Parses an M3U / M3U8 playlist (mirrors
 * `PlaylistExportDocument.parseM3u` on the Flutter side). `#PLAYLIST:`
 * supplies the name when present, otherwise `fallbackName` (or
 * "Imported playlist"). `#EXTINF:<secs>,Artist - Title` entries match
 * by artist/title; the file line after each `#EXTINF` is ignored for
 * matching. A bare file/path line with no preceding `#EXTINF` cannot
 * be matched to an artist, so it is kept as a missing entry labelled
 * with the line itself — never silently dropped.
 */
export function parsePlaylistExportM3u(text: string, fallbackName?: string): PlaylistExportDocument {
  let name = (fallbackName ?? '').trim();
  const tracks: PlaylistExportTrackEntry[] = [];
  const missingBareLines: string[] = [];
  let pendingArtist: string | null = null;
  let pendingTitle: string | null = null;
  let pendingDuration = 0;

  const flushPending = () => {
    if (pendingTitle !== null) {
      tracks.push({
        title: pendingTitle,
        artist: pendingArtist ?? '',
        album: '',
        durationSeconds: pendingDuration,
        sha256: '',
      });
      pendingTitle = null;
      pendingArtist = null;
      pendingDuration = 0;
    }
  };

  for (const rawLine of text.split('\n')) {
    const line = rawLine.trim();
    if (line === '') continue;
    if (line.startsWith('#PLAYLIST:')) {
      const parsed = line.substring('#PLAYLIST:'.length).trim();
      if (parsed !== '') name = parsed;
      continue;
    }
    if (line.startsWith('#EXTINF:')) {
      flushPending();
      const rest = line.substring('#EXTINF:'.length);
      const comma = rest.indexOf(',');
      if (comma < 0) {
        // Malformed EXTINF: keep the whole remainder as the title so
        // the entry is reported missing instead of vanishing.
        pendingTitle = rest.trim();
        pendingArtist = '';
        pendingDuration = 0;
        continue;
      }
      pendingDuration = parseInt(rest.substring(0, comma).trim(), 10) || 0;
      const label = rest.substring(comma + 1).trim();
      const sep = label.indexOf(' - ');
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
    if (pendingTitle !== null) {
      // File line belonging to the preceding #EXTINF: matching uses
      // the EXTINF artist/title, the path itself is not trusted.
      flushPending();
      continue;
    }
    // Bare path line with no #EXTINF: unmatchable, but counted.
    missingBareLines.push(line);
  }
  flushPending();

  // Bare lines surface as missing entries (empty artist ⇒ no match ⇒
  // counted in the resolution's missingLabels with this label).
  // Their label keeps the file name so the user can tell what failed.
  for (const bare of missingBareLines) {
    tracks.push({
      title: bare,
      artist: '',
      album: '',
      durationSeconds: 0,
      sha256: '',
    });
  }

  return {
    name: name === '' ? 'Imported playlist' : name,
    description: '',
    tracks,
    exportedAt: null,
  };
}

/**
 * Resolves an export document against the current library. Matches on
 * the lower-cased `title|artist` key only — the React library has no
 * SHA-256 index (see the module doc comment), so a document's `sha256`
 * values cannot be used here. Pure: no I/O.
 */
export function resolvePlaylistImport(
  doc: PlaylistExportDocument,
  libraryTracks: Track[],
): PlaylistImportResolution {
  const byKey = new Map<string, Track>();
  for (const t of libraryTracks) {
    byKey.set(matchKey(t.title, t.artist), t);
  }

  const matchedTrackIds: string[] = [];
  const addedIds = new Set<string>();
  const missingLabels: string[] = [];
  let duplicates = 0;
  let skipped = 0;

  for (const entry of doc.tracks) {
    // Empty title: nothing to match on at all — malformed, counted.
    // An entry WITH a title but no artist is NOT malformed: it is a
    // real reference that simply has no library match, so it lands in
    // missingLabels with its title as the label.
    if (entry.title.trim() === '') {
      skipped++;
      continue;
    }
    const match = byKey.get(matchKey(entry.title, entry.artist));
    if (!match) {
      missingLabels.push(
        entry.artist.trim() === '' ? entry.title : `${entry.title} — ${entry.artist}`,
      );
      continue;
    }
    if (addedIds.has(match.id)) {
      duplicates++;
      continue;
    }
    addedIds.add(match.id);
    matchedTrackIds.push(match.id);
  }

  return {
    matchedTrackIds,
    duplicates,
    skipped,
    missingLabels,
    totalEntries:
      matchedTrackIds.length + duplicates + skipped + missingLabels.length,
  };
}

/** Same match key as the Flutter side: lower-cased `title|artist`,
 *  trimmed. One rule for both formats. */
function matchKey(title: string, artist: string): string {
  return `${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}`;
}

/**
 * A name that does not collide with an existing playlist: the
 * requested name when free, otherwise `"<name> (imported)"`,
 * `"<name> (imported 2)"`, … An empty requested name becomes
 * "Imported playlist".
 */
export function uniquePlaylistName(requested: string, existingNames: string[]): string {
  const existing = new Set(existingNames.map((n) => n.trim().toLowerCase()));
  const base = requested.trim() === '' ? 'Imported playlist' : requested.trim();
  if (!existing.has(base.toLowerCase())) return base;
  let n = 1;
  for (;;) {
    const candidate = n === 1 ? `${base} (imported)` : `${base} (imported ${n})`;
    if (!existing.has(candidate.toLowerCase())) return candidate;
    n++;
  }
}

/** One-line-per-fact import summary, mirroring the Flutter
 *  `PlaylistImportResult.summary`. */
export function importSummary(
  playlistName: string,
  resolution: PlaylistImportResolution,
): string {
  const lines = [
    `${resolution.matchedTrackIds.length} track${resolution.matchedTrackIds.length === 1 ? '' : 's'} added to "${playlistName}"`,
  ];
  if (resolution.duplicates > 0) {
    lines.push(
      `${resolution.duplicates} duplicate ${resolution.duplicates === 1 ? 'entry' : 'entries'} in the file (added once)`,
    );
  }
  if (resolution.missingLabels.length > 0) {
    lines.push(
      `${resolution.missingLabels.length} not in your library: ${resolution.missingLabels.slice(0, 5).join('; ')}` +
        (resolution.missingLabels.length > 5
          ? ` (and ${resolution.missingLabels.length - 5} more)`
          : ''),
    );
  }
  if (resolution.skipped > 0) {
    lines.push(
      `${resolution.skipped} malformed ${resolution.skipped === 1 ? 'entry' : 'entries'} skipped (empty title)`,
    );
  }
  return lines.join('\n');
}
