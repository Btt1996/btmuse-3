export interface LyricLine {
  time: number; // in seconds
  text: string;
}

export interface SongLyrics {
  trackId: string;
  title: string;
  artist: string;
  syncedLyrics?: LyricLine[];
  plainLyrics?: string[];
  source: string;
  fetchedAt: number;
}

/**
 * Why the most recent `fetchLyricsForTrack` call returned null.
 * `null` means the last call succeeded (or was served from cache).
 * Mirrors the Flutter `LyricsFetchStatus` so both apps can tell "offline"
 * apart from "not catalogued on LRCLIB".
 */
export type LyricsFetchStatus = 'offline' | 'notFound' | null;

let lastFetchStatus: LyricsFetchStatus = null;

/** Status of the most recent `fetchLyricsForTrack` call (see above). */
export function getLastLyricsFetchStatus(): LyricsFetchStatus {
  return lastFetchStatus;
}

const LYRICS_CACHE_PREFIX = 'btt_lyrics_cache_';

/**
 * Clean artist and title for higher lyric matching rates
 */
function cleanSongTitle(title: string): string {
  return title
    .replace(/\s*[\(\[](official\s*(music\s*)?(video|audio|lyrics?(\s*video)?|visualizer)|lyrics?(\s*video)?|audio|visualizer|hq|hd|remix|feat\..*|ft\..*)[\)\]]/gi, '')
    .replace(/\.mp3$|\.m4a$|\.wav$|\.flac$/i, '')
    .trim();
}

function cleanArtistName(artist: string): string {
  const trimmed = artist.trim();
  if (!trimmed || trimmed.toLowerCase() === 'unknown artist' || trimmed.toLowerCase() === 'imported audio') return '';
  return trimmed.split(',')[0].split('&')[0].trim();
}

/**
 * Parses LRC format text "[00:12.34] line text" into sorted LyricLine array
 */
export function parseLrc(lrcText: string): LyricLine[] {
  if (!lrcText) return [];

  const lines = lrcText.split('\n');
  const result: LyricLine[] = [];
  // Regex to match timestamp e.g. [01:23.45] or [01:23]
  const timeRegex = /\[(\d{2}):(\d{2}(?:\.\d{1,3})?)\]/g;

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    const matches = Array.from(trimmed.matchAll(timeRegex));
    if (matches.length > 0) {
      const text = trimmed.replace(timeRegex, '').trim();
      for (const match of matches) {
        const minutes = parseInt(match[1], 10);
        const seconds = parseFloat(match[2]);
        const totalSeconds = minutes * 60 + seconds;
        result.push({
          time: totalSeconds,
          text: text || '♪',
        });
      }
    }
  }

  result.sort((a, b) => a.time - b.time);
  return result;
}

/**
 * Get cached lyrics for a track ID
 */
export function getCachedLyrics(trackId: string): SongLyrics | null {
  try {
    const cached = localStorage.getItem(`${LYRICS_CACHE_PREFIX}${trackId}`);
    if (cached) {
      return JSON.parse(cached) as SongLyrics;
    }
  } catch {
    // ignore
  }
  return null;
}

/**
 * Save lyrics to offline cache
 */
export function saveCachedLyrics(lyrics: SongLyrics): void {
  try {
    localStorage.setItem(`${LYRICS_CACHE_PREFIX}${lyrics.trackId}`, JSON.stringify(lyrics));
  } catch (err) {
    console.warn('Could not cache lyrics:', err);
  }
}

/**
 * A failed `fetch()` in the browser rejects with a TypeError on network
 * failure (no route, DNS failure, offline) — the only reliable
 * connection-level signal `fetch` gives. HTTP errors (404/500) do not
 * throw; they surface as `!resp.ok` and are not connection errors.
 */
function isConnectionError(err: unknown): boolean {
  return err instanceof TypeError;
}

/** Whether an LRCLIB result's title is the requested title after cleaning. */
function matchesTitle(entry: any, title: string): boolean {
  const candidate = entry?.trackName;
  if (typeof candidate !== 'string') return false;
  return cleanSongTitle(candidate).toLowerCase() === title.toLowerCase();
}

/**
 * Fetch lyrics for a song using LRCLIB free open API.
 *
 * Strategy A: exact match via `GET /api/get` with track/artist and the
 * duration when known. Strategy B: `GET /api/search` fallback, preferring
 * a title-matching result with synced lyrics, then any result with synced
 * lyrics, then the first result with any lyrics. The offline cache is
 * checked first unless `forceRefresh` is set (manual retry); on a forced
 * refresh that fails at the connection level, the stale cached lyrics are
 * returned instead of hiding lyrics the user already had. Returns null
 * when no lyrics can be found; use `getLastLyricsFetchStatus()` to tell
 * "offline" apart from "not catalogued".
 */
export async function fetchLyricsForTrack(
  trackId: string,
  rawTitle: string,
  rawArtist: string,
  durationSeconds?: number,
  forceRefresh = false
): Promise<SongLyrics | null> {
  // 1. Check local offline cache first
  const cached = getCachedLyrics(trackId);
  if (cached && !forceRefresh) {
    lastFetchStatus = null;
    return cached;
  }

  const title = cleanSongTitle(rawTitle);
  const artist = cleanArtistName(rawArtist);

  if (!title) {
    lastFetchStatus = 'notFound';
    return null;
  }

  try {
    let data: any = null;
    let sawConnectionError = false;

    // Strategy A: Exact match with duration if available
    const params = new URLSearchParams();
    params.set('track_name', title);
    if (artist) params.set('artist_name', artist);
    if (durationSeconds && durationSeconds > 0) {
      params.set('duration', Math.round(durationSeconds).toString());
    }

    try {
      const resp = await fetch(`https://lrclib.net/api/get?${params.toString()}`, {
        headers: {
          'Lrclib-Client': 'btmu/2.0.0 (https://btt1996.github.io)',
        },
      });

      if (resp.ok) {
        data = await resp.json();
      }
    } catch (err) {
      // Network error: record it and try the search fallback.
      if (isConnectionError(err)) sawConnectionError = true;
    }

    // Strategy B: Search fallback if exact get failed
    if (!data || (!data.syncedLyrics && !data.plainLyrics)) {
      try {
        const query = artist ? `${artist} ${title}` : title;
        const searchResp = await fetch(
          `https://lrclib.net/api/search?q=${encodeURIComponent(query)}`,
          {
            headers: {
              'Lrclib-Client': 'btmu/2.0.0 (https://btt1996.github.io)',
            },
          }
        );

        if (searchResp.ok) {
          const results = await searchResp.json();
          if (Array.isArray(results) && results.length > 0) {
            // Prefer a title-matching result with synced lyrics: search
            // relevance does not guarantee the top hit is this track
            // (a cover or remix can outrank it).
            data =
              results.find((r) => r.syncedLyrics && matchesTitle(r, title)) ||
              results.find((r) => r.syncedLyrics) ||
              results.find((r) => r.syncedLyrics || r.plainLyrics) ||
              null;
          }
        }
      } catch (err) {
        if (isConnectionError(err)) sawConnectionError = true;
      }
    }

    if (!data) {
      if (sawConnectionError && cached) {
        // Forced refresh while offline: keep showing the lyrics the
        // user already had instead of an empty state.
        lastFetchStatus = null;
        return cached;
      }
      lastFetchStatus = sawConnectionError ? 'offline' : 'notFound';
      return null;
    }

    const synced = data.syncedLyrics ? parseLrc(data.syncedLyrics) : undefined;
    const plain = data.plainLyrics
      ? data.plainLyrics.split('\n').map((l: string) => l.trim()).filter(Boolean)
      : undefined;

    if ((!synced || synced.length === 0) && (!plain || plain.length === 0)) {
      lastFetchStatus = 'notFound';
      return null;
    }

    const lyricsObj: SongLyrics = {
      trackId,
      title: data.trackName || rawTitle,
      artist: data.artistName || rawArtist,
      syncedLyrics: synced && synced.length > 0 ? synced : undefined,
      plainLyrics: plain,
      // Plain-only results are labelled without "(Synced)": the footer
      // must not claim sync the lyrics do not have.
      source: synced && synced.length > 0 ? 'LRCLIB (Synced)' : 'LRCLIB',
      fetchedAt: Date.now(),
    };

    lastFetchStatus = null;
    saveCachedLyrics(lyricsObj);
    return lyricsObj;
  } catch (err) {
    console.warn('Lyrics fetch failed:', err);
    if (cached) {
      lastFetchStatus = null;
      return cached;
    }
    lastFetchStatus = isConnectionError(err) ? 'offline' : 'notFound';
    return null;
  }
}
