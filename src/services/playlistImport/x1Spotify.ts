import { NormalizedPlaylist, NormalizedTrackMetadata } from '../../types/playlistImport';
import { isNativePlatform } from '../nativeAudioBridge';

export interface SpotifyConfig {
  clientId?: string;
  clientSecret?: string;
}

export interface ParsedSpotifyTarget {
  type: 'playlist' | 'album' | 'track';
  id: string;
}

/**
 * Extracts Spotify target (type and ID) from various URL and URI forms:
 * - https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=...
 * - https://open.spotify.com/intl-fr/playlist/37i9dQZF1DXcBWIGoYBM5M
 * - https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy
 * - spotify:playlist:37i9dQZF1DXcBWIGoYBM5M
 * - 37i9dQZF1DXcBWIGoYBM5M
 */
export function parseSpotifyTarget(input: string): ParsedSpotifyTarget | null {
  if (!input) return null;
  const trimmed = input.trim();

  // URI format: spotify:playlist:123 or spotify:album:123
  const uriMatch = trimmed.match(/^spotify:(playlist|album|track):([a-zA-Z0-9]+)/);
  if (uriMatch) {
    return { type: uriMatch[1] as 'playlist' | 'album' | 'track', id: uriMatch[2] };
  }

  // URL format with optional /intl-xx/ and query parameters
  const urlMatch = trimmed.match(
    /open\.spotify\.com\/(?:intl-[a-zA-Z-]+\/)?(playlist|album|track)\/([a-zA-Z0-9]+)/
  );
  if (urlMatch) {
    return { type: urlMatch[1] as 'playlist' | 'album' | 'track', id: urlMatch[2] };
  }

  // Direct 22-character alphanumeric ID
  if (/^[a-zA-Z0-9]{22}$/.test(trimmed)) {
    return { type: 'playlist', id: trimmed };
  }

  return null;
}

export function parseSpotifyPlaylistId(input: string): string | null {
  const target = parseSpotifyTarget(input);
  return target ? target.id : null;
}

/**
 * X1: Resolves Spotify playlist or album metadata without asking the user for API credentials.
 * Resolution runs exclusively through the btmu server-side keyless embed resolver
 * (`POST /api/spotify/playlist`).
 *
 * There is intentionally NO client-side fallback: the previous fallback routed
 * Spotify embed pages through the third-party `api.allorigins.win` CORS proxy,
 * which sent user-supplied Spotify URLs (and the responses) to an unrelated
 * third party. That proxy path was removed (Phase 0 item 5). When the server is
 * unavailable this function throws an explicit "server unavailable" error
 * instead of silently degrading to a proxy.
 *
 * Conforms to exact X1 normalized schema:
 * {
 *   source: "spotify",
 *   playlistTitle: string,
 *   tracks: [
 *     { title, artists, album, durationMs, isrc, artworkUrl, position }
 *   ]
 * }
 */
export async function fetchSpotifyPlaylist(
  playlistUrlOrId: string,
  config?: SpotifyConfig
): Promise<NormalizedPlaylist> {
  const target = parseSpotifyTarget(playlistUrlOrId);
  if (!target) {
    throw new Error(
      'Invalid Spotify link. Please paste a valid Spotify playlist or album URL (e.g. https://open.spotify.com/playlist/...)'
    );
  }

  // Server-side path only: the local server endpoint runs the keyless embed resolver.
  if (!isNativePlatform) {
    let serverError: Error;
    try {
      const res = await fetch(`/api/spotify/playlist?id=${encodeURIComponent(target.id)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          url: playlistUrlOrId,
          id: target.id,
          clientId: config?.clientId?.trim() || undefined,
          clientSecret: config?.clientSecret?.trim() || undefined,
        }),
      });

      const data = await res.json().catch(() => ({}));

      if (res.ok && data.tracks && Array.isArray(data.tracks) && data.tracks.length > 0) {
        return {
          source: 'spotify',
          playlistTitle: data.playlistTitle || 'Spotify Playlist',
          playlistDescription: data.playlistDescription || '',
          playlistCoverUrl: data.playlistCoverUrl || undefined,
          externalUrl: data.externalUrl || `https://open.spotify.com/${target.type}/${target.id}`,
          totalTracks: data.totalTracks || data.tracks.length,
          tracks: data.tracks,
        };
      }

      if (data.details || data.error) {
        serverError = new Error(data.details || data.error);
      } else {
        serverError = new Error(
          `Spotify resolution server unavailable (HTTP ${res.status}). Check that the btmu server is running and try again.`
        );
      }
    } catch (err: unknown) {
      if (err instanceof Error && err.message.includes('Failed to fetch')) {
        serverError = new Error(
          'Spotify resolution server unavailable (network error). Check that the btmu server is running and try again.'
        );
      } else if (err instanceof Error) {
        serverError = err;
      } else {
        serverError = new Error(
          'Spotify resolution server unavailable. Check that the btmu server is running and try again.'
        );
      }
    }
    throw serverError;
  }

  // Native builds have no local server to call, and there is no client-side
  // fallback: never route Spotify embed pages through a third-party CORS proxy.
  throw new Error(
    'Spotify playlist resolution requires the btmu server, which is unavailable in this build. Import the playlist while the server is reachable, or use a direct audio URL or Telegram import instead.'
  );
}
