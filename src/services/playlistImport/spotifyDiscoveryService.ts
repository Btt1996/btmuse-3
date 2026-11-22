/**
 * Spotify Public Discovery & User Profile Explorer
 * Enables browsing public Spotify user profiles (e.g. /user/{userId}),
 * retrieving public playlists, exploring curated playlists, and one-click import.
 *
 * Discovery runs exclusively through the btmu server (`/api/spotify/user`).
 * There is intentionally NO client-side fallback: the previous fallback routed
 * Spotify embed pages through the third-party `api.allorigins.win` CORS proxy,
 * which sent user-supplied Spotify profile URLs (and the responses) to an
 * unrelated third party. That proxy path was removed (Phase 0 item 5). When the
 * server is unavailable this module throws an explicit "server unavailable"
 * error instead of silently degrading to a proxy or returning an empty result.
 */

import { NormalizedPlaylist, NormalizedTrackMetadata } from '../../types/playlistImport';
import { parseSpotifyTarget } from './x1Spotify';
import { isNativePlatform } from '../nativeAudioBridge';

export interface SpotifyPublicUser {
  id: string;
  displayName: string;
  profileUrl: string;
  avatarUrl?: string;
  playlists: SpotifyPublicPlaylistSummary[];
}

export interface SpotifyPublicPlaylistSummary {
  id: string;
  name: string;
  description?: string;
  trackCount: number;
  coverUrl?: string;
  ownerName: string;
  externalUrl: string;
}

/**
 * Clean and extract a Spotify username or user ID from input string:
 * - https://open.spotify.com/user/spotify?si=...
 * - spotify:user:spotify
 * - @spotify or just "spotify"
 */
export function parseSpotifyUserId(input: string): string | null {
  if (!input) return null;
  const trimmed = input.trim();

  const urlMatch = trimmed.match(/open\.spotify\.com\/user\/([a-zA-Z0-9_.-]+)/i);
  if (urlMatch) return urlMatch[1];

  const uriMatch = trimmed.match(/^spotify:user:([a-zA-Z0-9_.-]+)/i);
  if (uriMatch) return uriMatch[1];

  // Plain username
  const clean = trimmed.replace(/^@/, '');
  if (/^[a-zA-Z0-9_.-]+$/.test(clean)) {
    return clean;
  }

  return null;
}

/**
 * Discover public playlists for a Spotify user.
 * Server-side path only — throws an explicit error when the server is unavailable.
 */
export async function discoverUserPlaylists(
  usernameOrUrl: string
): Promise<SpotifyPublicUser> {
  const userId = parseSpotifyUserId(usernameOrUrl);
  if (!userId) {
    throw new Error('Please enter a valid Spotify username or profile URL.');
  }

  if (!isNativePlatform) {
    let serverError: Error;
    try {
      const res = await fetch(`/api/spotify/user?userId=${encodeURIComponent(userId)}`);
      const data = await res.json().catch(() => ({}));

      if (res.ok && data.playlists && Array.isArray(data.playlists)) {
        return {
          id: userId,
          displayName: data.displayName || userId,
          profileUrl: `https://open.spotify.com/user/${userId}`,
          avatarUrl: data.avatarUrl,
          playlists: data.playlists,
        };
      }

      if (data.details || data.error) {
        serverError = new Error(data.details || data.error);
      } else {
        serverError = new Error(
          `Spotify discovery server unavailable (HTTP ${res.status}). Check that the btmu server is running and try again.`
        );
      }
    } catch (err: unknown) {
      if (err instanceof Error && err.message.includes('Failed to fetch')) {
        serverError = new Error(
          'Spotify discovery server unavailable (network error). Check that the btmu server is running and try again.'
        );
      } else if (err instanceof Error) {
        serverError = err;
      } else {
        serverError = new Error(
          'Spotify discovery server unavailable. Check that the btmu server is running and try again.'
        );
      }
    }
    throw serverError;
  }

  // Native builds have no local server to call, and there is no client-side
  // fallback: never route Spotify embed pages through a third-party CORS proxy.
  throw new Error(
    'Spotify user discovery requires the btmu server, which is unavailable in this build.'
  );
}

/**
 * Searches curated and popular playlists matching query
 */
export async function searchSpotifyPlaylists(
  query: string
): Promise<SpotifyPublicPlaylistSummary[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];

  // If input is direct Spotify link or ID, return single summary
  const target = parseSpotifyTarget(trimmed);
  if (target && target.type === 'playlist') {
    return [
      {
        id: target.id,
        name: `Spotify Playlist (${target.id.substring(0, 8)}...)`,
        ownerName: 'Spotify User',
        trackCount: 0,
        externalUrl: `https://open.spotify.com/playlist/${target.id}`,
      },
    ];
  }

  // Common popular discovery presets if user searches generic genres
  const presetResults: Record<string, SpotifyPublicPlaylistSummary[]> = {
    chill: [
      {
        id: '37i9dQZF1DX4WYpdgoIcn6',
        name: 'Chill Hits',
        ownerName: 'Spotify',
        trackCount: 100,
        description: 'Kick back to the best new and recent chill hits.',
        coverUrl: 'https://i.scdn.co/image/ab67706f00000002b60db5d10442d99d1e389e87',
        externalUrl: 'https://open.spotify.com/playlist/37i9dQZF1DX4WYpdgoIcn6',
      },
      {
        id: '37i9dQZF1DXcBWIGoYBM5M',
        name: "Today's Top Hits",
        ownerName: 'Spotify',
        trackCount: 50,
        description: 'The hottest tracks right now.',
        coverUrl: 'https://i.scdn.co/image/ab67706f00000002fe24d7084be472288cd6ee6c',
        externalUrl: 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
      },
    ],
    lofi: [
      {
        id: '37i9dQZF1DXdLEN7aqioXM',
        name: 'lofi beats',
        ownerName: 'Spotify',
        trackCount: 150,
        description: 'Beats to relax and study to.',
        coverUrl: 'https://i.scdn.co/image/ab67706f000000025f187a05dd85de8e792e3a09',
        externalUrl: 'https://open.spotify.com/playlist/37i9dQZF1DXdLEN7aqioXM',
      },
    ],
    workout: [
      {
        id: '37i9dQZF1DX76Wlfdnj7AP',
        name: 'Beast Mode',
        ownerName: 'Spotify',
        trackCount: 75,
        description: 'High energy hip hop and electronic beats for heavy lifting.',
        coverUrl: 'https://i.scdn.co/image/ab67706f000000027b407b489d816cb1eeec6990',
        externalUrl: 'https://open.spotify.com/playlist/37i9dQZF1DX76Wlfdnj7AP',
      },
    ],
  };

  const lower = trimmed.toLowerCase();
  for (const [key, list] of Object.entries(presetResults)) {
    if (lower.includes(key)) return list;
  }

  return [];
}
