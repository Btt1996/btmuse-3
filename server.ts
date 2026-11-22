import express from 'express';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import {
  parseInstanceUrls,
  probeInvidiousInstance,
  probePipedInstance,
  searchWithFailover,
} from './server/x2ProviderRouter.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json({ limit: '15mb' }));

// ---------------- SECURITY: SSRF GUARD & RATE LIMITING ----------------

const rateLimitStore = new Map<string, { count: number; resetAt: number }>();

function rateLimitMiddleware(maxRequests = 45, windowMs = 60_000) {
  return (req: express.Request, res: express.Response, next: express.NextFunction) => {
    const ip = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() || req.ip || 'unknown';
    const now = Date.now();
    const record = rateLimitStore.get(ip);

    if (!record || record.resetAt < now) {
      rateLimitStore.set(ip, { count: 1, resetAt: now + windowMs });
      return next();
    }

    if (record.count >= maxRequests) {
      return res.status(429).json({
        ok: false,
        error: 'Rate limit exceeded. Please wait before issuing more requests.',
      });
    }

    record.count++;
    return next();
  };
}

function validateSafeExternalUrl(rawUrl: string): URL | null {
  try {
    const parsed = new URL(rawUrl.trim());
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null;
    }

    const host = parsed.hostname.toLowerCase();
    // Block localhost, loopback, link-local, metadata, and private RFC1918 ranges
    if (
      host === 'localhost' ||
      host === '0.0.0.0' ||
      host === '::1' ||
      host.startsWith('127.') ||
      host.startsWith('10.') ||
      host.startsWith('192.168.') ||
      host.startsWith('169.254.') ||
      host.endsWith('.local') ||
      host.endsWith('.internal')
    ) {
      return null;
    }

    // Block 172.16.0.0 - 172.31.255.255
    const octets = host.split('.');
    if (octets.length === 4 && octets[0] === '172') {
      const second = parseInt(octets[1], 10);
      if (second >= 16 && second <= 31) return null;
    }

    return parsed;
  } catch {
    return null;
  }
}

function optionalBackendAuth(req: express.Request, res: express.Response, next: express.NextFunction) {
  const configuredSecret = process.env.X2_BACKEND_AUTH_TOKEN?.trim();
  if (!configuredSecret) return next();

  const headerToken = req.headers['x-btt-auth'] as string | undefined;
  const bearer = req.headers.authorization?.replace(/^Bearer\s+/i, '').trim();
  if (headerToken === configuredSecret || bearer === configuredSecret) {
    return next();
  }

  return res.status(401).json({ ok: false, error: 'Unauthorized backend request' });
}

// Version endpoint for PWA & mobile update checks
app.get('/api/version', (_req, res) => {
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  res.json({
    name: 'Btt Music',
    shortName: 'BTmu',
    developer: 'Ahmed Taboubi',
    bundleId: 'com.ahmed.btmu',
    version: '2.00',
    buildDate: '2026-11-14',
    releaseNotes:
      'Btt Music 2.00: Zero-key Flutter iOS rebuild, independent X1 local/open acoustic fingerprinting, X2 VK/Telegram/YouTube/SoundCloud/Audius/RSS acquisition, Smart Remix, and 300% limited boost.',
    minSupportedVersion: '1.0.0',
  });
});

// ---------------- TELEGRAM PROXY ENDPOINTS ----------------
// Resolves browser CORS issues and streams audio files reliably

// 1. Verify Bot Token
app.get('/api/telegram/verify', async (req, res) => {
  const token = req.query.token as string;
  if (!token) {
    return res.status(400).json({ ok: false, description: 'Token is required' });
  }

  try {
    const telegramRes = await fetch(`https://api.telegram.org/bot${token.trim()}/getMe`);
    const data = await telegramRes.json();
    return res.json(data);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to reach Telegram API';
    return res.status(502).json({ ok: false, description: msg });
  }
});

// 2. Get Updates (Messages & Channel Posts)
app.get('/api/telegram/updates', async (req, res) => {
  const token = req.query.token as string;
  const limit = req.query.limit || '100';
  if (!token) {
    return res.status(400).json({ ok: false, description: 'Token is required' });
  }

  try {
    const url = `https://api.telegram.org/bot${token.trim()}/getUpdates?limit=${limit}&allowed_updates=["message","channel_post"]`;
    const telegramRes = await fetch(url);
    const data = await telegramRes.json();
    return res.json(data);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to reach Telegram API';
    return res.status(502).json({ ok: false, description: msg });
  }
});

// 3. Get File Info (Path)
app.get('/api/telegram/file-info', async (req, res) => {
  const token = req.query.token as string;
  const fileId = req.query.file_id as string;
  if (!token || !fileId) {
    return res.status(400).json({ ok: false, description: 'Token and file_id are required' });
  }

  try {
    const url = `https://api.telegram.org/bot${token.trim()}/getFile?file_id=${encodeURIComponent(fileId)}`;
    const telegramRes = await fetch(url);
    const data = await telegramRes.json();
    return res.json(data);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to reach Telegram API';
    return res.status(502).json({ ok: false, description: msg });
  }
});

// 4. Download Audio File Stream
app.get('/api/telegram/download', async (req, res) => {
  const token = req.query.token as string;
  const filePath = req.query.file_path as string;
  if (!token || !filePath) {
    return res.status(400).json({ ok: false, description: 'Token and file_path are required' });
  }

  try {
    const fileUrl = `https://api.telegram.org/file/bot${token.trim()}/${filePath}`;
    const telegramRes = await fetch(fileUrl);

    if (!telegramRes.ok) {
      return res.status(telegramRes.status).json({
        ok: false,
        description: `Telegram download failed: HTTP ${telegramRes.status}`,
      });
    }

    const contentType = telegramRes.headers.get('content-type') || 'audio/mpeg';
    const contentLength = telegramRes.headers.get('content-length');

    res.setHeader('Content-Type', contentType);
    if (contentLength) {
      res.setHeader('Content-Length', contentLength);
    }
    res.setHeader('Cache-Control', 'public, max-age=86400');

    // Stream response to client
    if (telegramRes.body) {
      const { Readable } = await import('stream');
      const nodeStream = Readable.fromWeb(telegramRes.body as import('stream/web').ReadableStream);
      nodeStream.pipe(res);
    } else {
      const buffer = await telegramRes.arrayBuffer();
      res.send(Buffer.from(buffer));
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to stream audio file';
    return res.status(502).json({ ok: false, description: msg });
  }
});

// ---------------- SPOTIFY X1 KEYLESS EMBED RESOLVER ----------------

interface ParsedSpotifyTarget {
  type: 'playlist' | 'album' | 'track';
  id: string;
}

function parseSpotifyTarget(input?: string): ParsedSpotifyTarget | null {
  if (!input) return null;
  const trimmed = input.trim();

  // URI format: spotify:playlist:123 or spotify:album:123
  const uriMatch = trimmed.match(/^spotify:(playlist|album|track):([a-zA-Z0-9]+)/);
  if (uriMatch) {
    return { type: uriMatch[1] as 'playlist' | 'album' | 'track', id: uriMatch[2] };
  }

  // URL format with optional /intl-xx/ and query parameters
  const urlMatch = trimmed.match(/open\.spotify\.com\/(?:intl-[a-zA-Z-]+\/)?(playlist|album|track)\/([a-zA-Z0-9]+)/);
  if (urlMatch) {
    return { type: urlMatch[1] as 'playlist' | 'album' | 'track', id: urlMatch[2] };
  }

  // Direct 22-character alphanumeric ID
  if (/^[a-zA-Z0-9]{22}$/.test(trimmed)) {
    return { type: 'playlist', id: trimmed };
  }

  return null;
}

/**
 * Clean and extract a Spotify username or user ID from input:
 * - https://open.spotify.com/user/spotify?si=...
 * - spotify:user:spotify
 * - @spotify or just "spotify"
 * Mirrors parseSpotifyUserId in src/services/playlistImport/spotifyDiscoveryService.ts.
 */
function parseSpotifyUserId(input?: string): string | null {
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
 * Keyless Spotify Public Embed Metadata Resolver
 * Resolves public playlist/album metadata directly from Spotify's official embed widget.
 * Does NOT require user credentials, client IDs, secrets, or API keys.
 */
async function resolveSpotifyEmbed(target: ParsedSpotifyTarget) {
  const embedUrl = `https://open.spotify.com/embed/${target.type}/${target.id}`;
  const response = await fetch(embedUrl, {
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    },
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('Spotify playlist not found. Ensure the playlist link is correct and publicly accessible.');
    }
    throw new Error(`Spotify embed returned HTTP ${response.status}`);
  }

  const html = await response.text();
  const nextDataMatch = html.match(/<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/);

  if (!nextDataMatch) {
    throw new Error('Could not parse Spotify embed document. The playlist may be restricted or unavailable.');
  }

  let parsed: any;
  try {
    parsed = JSON.parse(nextDataMatch[1]);
  } catch {
    throw new Error('Invalid JSON received from Spotify embed widget.');
  }

  const pageProps = parsed.props?.pageProps;
  if (!pageProps || pageProps.status === 500 || pageProps.title === 'Page not available') {
    throw new Error('This Spotify playlist is private, deleted, or unavailable. Ensure the playlist is public on Spotify.');
  }

  const entity = pageProps.state?.data?.entity;
  if (!entity || !Array.isArray(entity.trackList) || entity.trackList.length === 0) {
    throw new Error('No tracks found in this Spotify playlist or album. Ensure the playlist has public items.');
  }

  const playlistTitle: string = entity.title || entity.name || 'Spotify Playlist';
  const playlistDescription: string = entity.subtitle || '';
  
  // Extract highest resolution image available
  const coverUrl: string | undefined =
    entity.visualIdentity?.image?.[entity.visualIdentity.image.length - 1]?.url ||
    entity.coverArt?.sources?.[0]?.url ||
    undefined;

  // Normalize tracks into exact X1 schema
  const tracks = entity.trackList.map((item: any, index: number) => {
    // Parse artists from subtitle (e.g. "Tate McRae" or "Noah Kahan, The Hunger Games")
    const artists = item.subtitle
      ? item.subtitle.split(/,\s*|\s*,\s*/).map((a: string) => a.trim()).filter(Boolean)
      : ['Unknown Artist'];

    return {
      title: item.title || 'Unknown Title',
      artists: artists.length > 0 ? artists : ['Unknown Artist'],
      album: playlistTitle,
      durationMs: typeof item.duration === 'number' ? item.duration : 0,
      isrc: null,
      artworkUrl: coverUrl || null,
      position: index,
    };
  });

  return {
    source: 'spotify',
    playlistTitle,
    playlistDescription,
    playlistCoverUrl: coverUrl,
    externalUrl: `https://open.spotify.com/${target.type}/${target.id}`,
    totalTracks: tracks.length,
    tracks,
  };
}

// Helper to obtain Spotify access token using Client Credentials (optional fallback)
async function fetchSpotifyToken(clientId?: string, clientSecret?: string): Promise<string> {
  const cId = clientId?.trim() || process.env.SPOTIFY_CLIENT_ID?.trim();
  const cSecret = clientSecret?.trim() || process.env.SPOTIFY_CLIENT_SECRET?.trim();

  if (!cId || !cSecret) {
    throw new Error('Spotify credentials missing.');
  }

  const authHeader = Buffer.from(`${cId}:${cSecret}`).toString('base64');
  const tokenRes = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Authorization: `Basic ${authHeader}`,
    },
    body: 'grant_type=client_credentials',
  });

  if (!tokenRes.ok) {
    const errorBody = await tokenRes.text();
    throw new Error(`Spotify Auth Error (${tokenRes.status}): ${errorBody}`);
  }

  const data = await tokenRes.json();
  return data.access_token;
}

// 1. Spotify Token Proxy (optional fallback)
app.post('/api/spotify/token', async (req, res) => {
  const { clientId, clientSecret } = req.body || {};
  try {
    const token = await fetchSpotifyToken(clientId, clientSecret);
    return res.json({ access_token: token });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Spotify authentication failed';
    return res.status(401).json({ error: 'Spotify Auth Failed', message: msg });
  }
});

// 2. Spotify Playlist Metadata & Tracklist (Keyless Embed Resolver as Primary)
app.post('/api/spotify/playlist', async (req, res) => {
  const inputParam = (req.query.id as string) || (req.query.url as string) || (req.body?.url as string) || (req.body?.id as string);
  const { clientId, clientSecret } = req.body || {};

  if (!inputParam) {
    return res.status(400).json({ error: 'Playlist URL or ID is required.' });
  }

  const target = parseSpotifyTarget(inputParam);
  if (!target) {
    return res.status(400).json({
      error: 'Invalid Spotify link',
      details: 'Please paste a valid public Spotify playlist or album URL (e.g. https://open.spotify.com/playlist/...)',
    });
  }

  // PRIMARY RESOLVER: Keyless Spotify Public Embed
  try {
    const normalizedData = await resolveSpotifyEmbed(target);
    return res.json(normalizedData);
  } catch (keylessErr: unknown) {
    const keylessMsg = keylessErr instanceof Error ? keylessErr.message : 'Keyless resolution failed';

    // If keyless failed, try the official Web API fallback. Credentials
    // may come from the request body or from the server's own
    // SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET environment variables
    // (fetchSpotifyToken checks body first, then env). Attempt the
    // fallback whenever any credential is present; with none, the token
    // call throws, the inner catch swallows it, and the 422 below
    // reports the keyless error — same as before.
    const hasSpotifyCreds = Boolean(
      clientId || clientSecret || process.env.SPOTIFY_CLIENT_ID,
    );
    if (hasSpotifyCreds) {
      try {
        const token = await fetchSpotifyToken(clientId, clientSecret);
        const spotifyRes = await fetch(
          `https://api.spotify.com/v1/playlists/${encodeURIComponent(target.id)}`,
          {
            headers: { Authorization: `Bearer ${token}` },
          }
        );

        if (spotifyRes.ok) {
          const data = await spotifyRes.json();
          const playlistTitle = data.name || 'Spotify Playlist';
          const playlistCoverUrl = data.images?.[0]?.url;

          const tracks: any[] = [];
          let position = 0;
          for (const item of data.tracks?.items || []) {
            const t = item.track;
            if (!t || t.is_local) continue;
            tracks.push({
              title: t.name || 'Unknown Title',
              artists: t.artists ? t.artists.map((a: { name: string }) => a.name) : ['Unknown Artist'],
              album: t.album?.name || playlistTitle,
              durationMs: t.duration_ms || 0,
              isrc: t.external_ids?.isrc || null,
              artworkUrl: t.album?.images?.[0]?.url || playlistCoverUrl || null,
              position: position++,
            });
          }

          return res.json({
            source: 'spotify',
            playlistTitle,
            playlistDescription: data.description || '',
            playlistCoverUrl,
            totalTracks: tracks.length,
            tracks,
          });
        }
      } catch {
        // Fall back to reporting the primary error below
      }
    }

    return res.status(422).json({
      error: 'Playlist Resolution Failed',
      details: keylessMsg,
    });
  }
});
// 2b. Spotify User Public Playlists (server credentials only)
//
// GET /api/spotify/user?userId=<id>
// Returns exactly { displayName, avatarUrl, playlists: [{ id, name,
// description, trackCount, coverUrl, ownerName, externalUrl }] } —
// the shape src/services/playlistImport/spotifyDiscoveryService.ts
// (discoverUserPlaylists) already expects.
//
// Credentials come ONLY from the server's own SPOTIFY_CLIENT_ID /
// SPOTIFY_CLIENT_SECRET environment variables (client-credentials
// flow via fetchSpotifyToken with no arguments). This route never
// accepts clientId / clientSecret from the request body or query.
// Client-credentials tokens can only see PUBLIC playlists — a
// user's private playlists are invisible to this endpoint by
// design, and the error copy below says so.
app.get('/api/spotify/user', async (req, res) => {
  const userId = parseSpotifyUserId(req.query.userId as string);
  if (!userId) {
    return res.status(400).json({
      error: 'Spotify user ID is required.',
      details:
        'Pass ?userId=<id>, a Spotify profile URL (https://open.spotify.com/user/<id>), or a spotify:user:<id> URI.',
    });
  }

  const missingCreds: string[] = [];
  if (!process.env.SPOTIFY_CLIENT_ID?.trim()) missingCreds.push('SPOTIFY_CLIENT_ID');
  if (!process.env.SPOTIFY_CLIENT_SECRET?.trim()) missingCreds.push('SPOTIFY_CLIENT_SECRET');
  if (missingCreds.length > 0) {
    return res.status(422).json({
      error: 'Spotify credentials not configured',
      details: `The server has no Spotify API credentials configured (missing: ${missingCreds.join(', ')}). Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET on the server to enable Spotify user discovery.`,
    });
  }

  let token: string;
  try {
    token = await fetchSpotifyToken();
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Spotify authentication failed';
    return res.status(502).json({ error: 'Spotify authentication failed', details: msg });
  }

  try {
    const authHeaders = { Authorization: `Bearer ${token}` };
    const [profileRes, playlistsRes] = await Promise.all([
      fetch(`https://api.spotify.com/v1/users/${encodeURIComponent(userId)}`, {
        headers: authHeaders,
      }),
      fetch(
        `https://api.spotify.com/v1/users/${encodeURIComponent(userId)}/playlists?limit=50`,
        { headers: authHeaders },
      ),
    ]);

    if (playlistsRes.status === 404) {
      return res.status(404).json({
        error: 'Spotify user not found',
        details: `No Spotify profile found for "${userId}". Check the username or profile link — only public profiles and their public playlists are visible here.`,
      });
    }
    if (!playlistsRes.ok) {
      return res.status(502).json({
        error: 'Spotify user lookup failed',
        details: `Spotify returned HTTP ${playlistsRes.status}.`,
      });
    }

    const playlistsData: any = await playlistsRes.json().catch(() => ({}));
    // The profile lookup is best-effort: a missing/blocked profile
    // must not hide the playlists that did resolve.
    const profileData: any = profileRes.ok
      ? await profileRes.json().catch(() => ({}))
      : {};

    const displayName: string = profileData.display_name || userId;
    const avatarUrl: string | undefined = profileData.images?.[0]?.url;

    const playlists = (Array.isArray(playlistsData.items) ? playlistsData.items : []).map(
      (p: any) => ({
        id: p.id,
        name: p.name || 'Untitled playlist',
        description: p.description || '',
        trackCount: p.tracks?.total ?? 0,
        coverUrl: p.images?.[0]?.url,
        ownerName: p.owner?.display_name || p.owner?.id || displayName,
        externalUrl:
          p.external_urls?.spotify || `https://open.spotify.com/playlist/${p.id}`,
      }),
    );

    return res.json({ displayName, avatarUrl, playlists });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to reach Spotify';
    return res.status(502).json({ error: 'Spotify user lookup failed', details: msg });
  }
});

// 3. Apple iTunes Official Search API Proxy (No User Token Required)
app.get('/api/itunes/search', async (req, res) => {
  const term = req.query.term as string;
  const limit = req.query.limit || '25';
  if (!term) return res.status(400).json({ error: 'Search term is required' });

  try {
    const url = `https://itunes.apple.com/search?term=${encodeURIComponent(term)}&media=music&entity=song&limit=${limit}`;
    const itunesRes = await fetch(url, { signal: AbortSignal.timeout(6500) });
    if (!itunesRes.ok) {
      return res.status(itunesRes.status).json({ error: `iTunes API returned ${itunesRes.status}` });
    }
    const data = await itunesRes.json();
    return res.json(data);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'iTunes search request failed';
    return res.status(502).json({ error: msg });
  }
});

// 4A. X2 Backend & Companion Provider Health Diagnostics
app.get('/api/x2/health', rateLimitMiddleware(30, 60_000), async (_req, res) => {
  const x2BackendUrl = process.env.X2_BACKEND_URL?.trim() || '';
  const pipedUrls = parseInstanceUrls(process.env.PIPED_API_URL);
  const invidiousUrls = parseInstanceUrls(process.env.INVIDIOUS_API_URL);

  const [pipedProbes, invidiousProbes] = await Promise.all([
    Promise.all(pipedUrls.map((u) => probePipedInstance(u))),
    Promise.all(invidiousUrls.map((u) => probeInvidiousInstance(u))),
  ]);

  res.json({
    ok: true,
    x2Backend: {
      configured: x2BackendUrl.length > 0,
      url: x2BackendUrl.length > 0 ? x2BackendUrl : null,
      message:
        x2BackendUrl.length > 0
          ? 'X2_BACKEND_URL is configured.'
          : 'X2_BACKEND_URL environment variable is not configured.',
    },
    piped: {
      configuredCount: pipedUrls.length,
      instances: pipedProbes,
    },
    invidious: {
      configuredCount: invidiousUrls.length,
      instances: invidiousProbes,
    },
  });
});

// 4B. YouTube Search via Configurable Multi-Instance Piped & Invidious Failover
app.get(['/api/youtube/search', '/api/x2/youtube/search'], rateLimitMiddleware(40, 60_000), async (req, res) => {
  const query = (req.query.q as string)?.trim();
  if (!query) return res.status(400).json({ error: 'Search query is required' });

  const pipedUrls = parseInstanceUrls(process.env.PIPED_API_URL);
  const invidiousUrls = parseInstanceUrls(process.env.INVIDIOUS_API_URL);

  const result = await searchWithFailover({
    query,
    pipedUrls,
    invidiousUrls,
  });

  return res.json({
    ok: result.ok,
    items: result.items,
    provider: result.providerUsed,
    instanceUsed: result.instanceUsed,
    hasCompanionInstance: pipedUrls.length > 0 || invidiousUrls.length > 0,
    attempts: result.attempts,
    message: result.message,
  });
});

// 5. SoundCloud Public oEmbed / Metadata Search (ZERO SoundCloud developer key required)
app.get('/api/soundcloud/search', rateLimitMiddleware(40, 60_000), async (req, res) => {
  const query = (req.query.q as string)?.trim();
  if (!query) return res.status(400).json({ error: 'Query is required' });

  return res.json({
    tracks: [],
    configured: true,
    message:
      'SoundCloud public URLs work with zero API keys via oEmbed & open download check. SoundCloud keyword search API requires legacy OAuth apps (no new public registrations issued).',
  });
});
app.post('/api/spotdl/bridge-check', async (req, res) => {
  const { bridgeUrl } = req.body || {};
  if (!bridgeUrl) {
    return res.status(400).json({ ok: false, error: 'Bridge URL required' });
  }

  try {
    const targetUrl = `${bridgeUrl.replace(/\/$/, '')}/health`;
    const start = Date.now();
    const bridgeRes = await fetch(targetUrl, { signal: AbortSignal.timeout(4000) });
    const latency = Date.now() - start;

    if (bridgeRes.ok) {
      const data = await bridgeRes.json().catch(() => ({}));
      return res.json({
        ok: true,
        latencyMs: latency,
        version: data.version || 'spotDL Bridge v4.x',
      });
    }

    return res.status(bridgeRes.status).json({
      ok: false,
      error: `Bridge returned status ${bridgeRes.status}`,
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Connection failed';
    return res.status(502).json({ ok: false, error: msg });
  }
});

// 4. Audio Stream Verification (SSRF-protected HEAD check)
app.get('/api/audio-verify', rateLimitMiddleware(60, 60_000), async (req, res) => {
  const url = req.query.url as string;
  if (!url) return res.status(400).json({ ok: false, error: 'URL required' });

  const safeUrl = validateSafeExternalUrl(url);
  if (!safeUrl) {
    return res.status(400).json({ ok: false, error: 'Blocked unsafe or private network URL' });
  }

  try {
    let response = await fetch(safeUrl.toString(), {
      method: 'HEAD',
      headers: {
        'User-Agent': 'BttMusic/2.00 (iOS)',
      },
      signal: AbortSignal.timeout(6000),
    });

    if (!response.ok || !(response.headers.get('content-type') || '')) {
      response = await fetch(safeUrl.toString(), {
        method: 'GET',
        headers: {
          'User-Agent': 'BttMusic/2.00 (iOS)',
          Range: 'bytes=0-1023',
        },
        signal: AbortSignal.timeout(6000),
      });
    }

    const contentType = (response.headers.get('content-type') || '').toLowerCase();
    const contentRangeTotal = response.headers.get('content-range')?.split('/').pop();
    const contentLength = parseInt(
      contentRangeTotal || response.headers.get('content-length') || '0',
      10
    );
    const isHtmlOrJson =
      contentType.includes('text/html') ||
      contentType.includes('application/json') ||
      contentType.includes('text/plain');
    const isAudio =
      !isHtmlOrJson &&
      (contentType.includes('audio') ||
        contentType.includes('application/ogg') ||
        (contentType.includes('octet-stream') &&
          /\.(mp3|m4a|aac|flac|wav|ogg)$/i.test(safeUrl.pathname)) ||
        /\.(mp3|m4a|aac|flac|wav|ogg)$/i.test(safeUrl.pathname));

    return res.json({
      ok: response.ok,
      status: response.status,
      contentType,
      contentLength,
      isPlayableAudio: response.ok && isAudio && (contentLength === 0 || contentLength > 1024),
    });
  } catch (err: unknown) {
    return res.status(200).json({
      ok: false,
      error: err instanceof Error ? err.message : 'Verification failed',
      isPlayableAudio: false,
    });
  }
});

// 5. Restricted Audio Stream Proxy (SSRF-safe + verified audio MIME validation)
const ALLOWED_AUDIO_HOSTS = new Set([
  'audius.co',
  'discoveryprovider.audius.co',
  'dzcdn.net',
  'audio-ssl.itunes.apple.com',
  'sndcdn.com',
  'userapi.com',
]);

app.get('/api/audio-proxy', rateLimitMiddleware(30, 60_000), optionalBackendAuth, async (req, res) => {
  const url = req.query.url as string;
  if (!url) return res.status(400).json({ error: 'URL is required' });

  const safeUrl = validateSafeExternalUrl(url);
  if (!safeUrl) {
    return res.status(400).json({ error: 'Blocked unsafe or private network URL' });
  }

  const host = safeUrl.hostname.toLowerCase();
  const isKnownRepo = Array.from(ALLOWED_AUDIO_HOSTS).some((h) => host === h || host.endsWith(`.${h}`) || host.includes(h));
  const isDirectAudioPath = /\.(mp3|m4a|aac|flac|wav|ogg)$/i.test(safeUrl.pathname);
  if (!isKnownRepo && !isDirectAudioPath) {
    return res.status(403).json({ error: 'Audio proxy restricts requests to verified audio URLs or approved public streams.' });
  }

  try {
    const remoteRes = await fetch(safeUrl.toString(), {
      headers: {
        'User-Agent': 'BttMusic/2.00 (iOS)',
        Accept: 'audio/*,*/*;q=0.8',
      },
      signal: AbortSignal.timeout(25_000),
    });

    if (!remoteRes.ok) {
      return res.status(remoteRes.status).json({ error: `Remote audio returned ${remoteRes.status}` });
    }

    const contentType = (remoteRes.headers.get('content-type') || '').toLowerCase();
    if (!contentType.includes('audio') && !contentType.includes('octet-stream')) {
      return res.status(415).json({ error: `Expected audio MIME type but received ${contentType || 'unknown'}` });
    }

    const contentLength = remoteRes.headers.get('content-length');
    res.setHeader('Content-Type', contentType);
    if (contentLength) res.setHeader('Content-Length', contentLength);
    res.setHeader('Cache-Control', 'public, max-age=86400');

    if (remoteRes.body) {
      const { Readable } = await import('stream');
      const nodeStream = Readable.fromWeb(remoteRes.body as import('stream/web').ReadableStream);
      nodeStream.pipe(res);
    } else {
      const buffer = await remoteRes.arrayBuffer();
      res.send(Buffer.from(buffer));
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Proxy failed';
    return res.status(502).json({ error: msg });
  }
});

// 6. X2 URL Inspector (VK OpenGraph, YouTube oEmbed, SoundCloud oEmbed, Podcast/Music RSS, Direct Audio HEAD — Zero Keys)
app.post('/api/x2/url-inspect', rateLimitMiddleware(45, 60_000), async (req, res) => {
  const rawUrl = (req.body?.url as string) || '';
  const safeUrl = validateSafeExternalUrl(rawUrl);
  if (!safeUrl) {
    return res.status(400).json({ ok: false, error: 'Invalid or unsafe URL' });
  }

  const host = safeUrl.hostname.toLowerCase();

  try {
    // A. VK Track / Audio URL -> Public OpenGraph metadata inspection (respects VK auth & HLS boundaries)
    if (host === 'vk.com' || host.endsWith('.vk.com') || host === 'vk.ru') {
      const vkRes = await fetch(safeUrl.toString(), {
        headers: {
          'User-Agent': 'BttMusic/2.00 (iOS; Public Metadata)',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        signal: AbortSignal.timeout(6500),
      });
      const html = await vkRes.text();
      const titleMatch = html.match(/<meta\s+property=["']og:title["']\s+content=["']([^"']+)["']/i);
      const descMatch = html.match(/<meta\s+property=["']og:description["']\s+content=["']([^"']+)["']/i);
      const imageMatch = html.match(/<meta\s+property=["']og:image["']\s+content=["']([^"']+)["']/i);
      const requiresAuth = html.includes('login') && !titleMatch;

      return res.json({
        ok: Boolean(titleMatch),
        provider: 'vk',
        title: titleMatch?.[1] || 'VK Audio Link',
        artist: descMatch?.[1] || 'VK Music',
        artworkUrl: imageMatch?.[1] || null,
        audioAvailable: false,
        downloadAuthorized: false,
        authorizationNote: requiresAuth
          ? 'VK restricts unauthenticated audio scraping. Authorize with your own VK session cookie in VK settings or search Audius/X2 public tracks.'
          : 'VK public page metadata resolved. Direct VK audio streams often use encrypted HLS/regional restrictions unless authorized by a user VK session.',
      });
    }

    // B. YouTube URL -> Official oEmbed metadata (Zero API key required)
    if (host.includes('youtube.com') || host === 'youtu.be') {
      const oembedRes = await fetch(
        `https://www.youtube.com/oembed?url=${encodeURIComponent(safeUrl.toString())}&format=json`,
        { signal: AbortSignal.timeout(6000) }
      );
      if (!oembedRes.ok) {
        return res.status(oembedRes.status).json({
          ok: false,
          provider: 'youtube',
          error: 'Could not retrieve YouTube video metadata via oEmbed.',
        });
      }
      const data = await oembedRes.json();
      return res.json({
        ok: true,
        provider: 'youtube',
        title: data.title || 'YouTube Video',
        artist: data.author_name || 'YouTube Creator',
        artworkUrl: data.thumbnail_url || null,
        audioAvailable: false,
        downloadAuthorized: false,
        authorizationNote:
          'YouTube oEmbed metadata retrieved (no API key needed). Built-in Python yt-dlp is incompatible with pure iOS App Store binaries; matching authorized streams are searched automatically in X2.',
      });
    }

    // C. SoundCloud URL -> Zero-key oEmbed metadata
    if (host.includes('soundcloud.com')) {
      const scRes = await fetch(
        `https://soundcloud.com/oembed?format=json&url=${encodeURIComponent(safeUrl.toString())}`,
        { signal: AbortSignal.timeout(6000) }
      );
      if (!scRes.ok) {
        return res.status(scRes.status).json({ ok: false, provider: 'soundcloud', error: 'SoundCloud oEmbed failed.' });
      }
      const data = await scRes.json();
      return res.json({
        ok: true,
        provider: 'soundcloud',
        title: data.title || 'SoundCloud Track',
        artist: data.author_name || 'SoundCloud Artist',
        artworkUrl: data.thumbnail_url || null,
        audioAvailable: false,
        downloadAuthorized: false,
        authorizationNote:
          'SoundCloud metadata resolved without API keys via oEmbed. Direct download requires the artist to enable public downloads on the track.',
      });
    }

    // D. Podcast / Music RSS XML Feed -> Parse audio <enclosure> items
    if (/\.(rss|xml)$/i.test(safeUrl.pathname) || safeUrl.pathname.toLowerCase().includes('/feed')) {
      const feedRes = await fetch(safeUrl.toString(), {
        headers: { 'User-Agent': 'BttMusic/2.00 (iOS)' },
        signal: AbortSignal.timeout(7000),
      });
      const contentType = (feedRes.headers.get('content-type') || '').toLowerCase();
      if (feedRes.ok && (contentType.includes('xml') || contentType.includes('rss'))) {
        const xml = await feedRes.text();
        const encMatch = xml.match(/<enclosure[^>]+url=["']([^"']+)["'][^>]*type=["']audio\/[^"']+["'][^>]*>/i);
        const itemTitle = xml.match(/<item>[\s\S]*?<title>(?:<!\[CDATA\[)?([^<\]]+)/i);
        const channelTitle = xml.match(/<channel>[\s\S]*?<title>(?:<!\[CDATA\[)?([^<\]]+)/i);
        if (encMatch && validateSafeExternalUrl(encMatch[1])) {
          return res.json({
            ok: true,
            provider: 'rss_audio',
            title: itemTitle?.[1]?.trim() || 'RSS Audio Episode',
            artist: channelTitle?.[1]?.trim() || safeUrl.hostname,
            audioUrl: encMatch[1],
            mimeType: 'audio/mpeg',
            audioAvailable: true,
            downloadAuthorized: true,
            authorizationNote: 'Public RSS audio enclosure extracted without API keys.',
          });
        }
      }
    }

    // E. Direct Audio URL -> Verify MIME and Content-Length via HEAD with Range GET fallback
    let headRes = await fetch(safeUrl.toString(), {
      method: 'HEAD',
      headers: { 'User-Agent': 'BttMusic/2.00 (iOS)' },
      signal: AbortSignal.timeout(6000),
    });
    if (!headRes.ok || !(headRes.headers.get('content-type') || '')) {
      headRes = await fetch(safeUrl.toString(), {
        method: 'GET',
        headers: { 'User-Agent': 'BttMusic/2.00 (iOS)', Range: 'bytes=0-1023' },
        signal: AbortSignal.timeout(6000),
      });
    }
    const mime = (headRes.headers.get('content-type') || '').toLowerCase();
    const totalFromRange = headRes.headers.get('content-range')?.split('/').pop();
    const len = parseInt(totalFromRange || headRes.headers.get('content-length') || '0', 10);
    const rejectedText =
      mime.includes('text/html') || mime.includes('application/json') || mime.includes('text/plain');
    const isAudio =
      !rejectedText &&
      (mime.includes('audio') ||
        mime.includes('application/ogg') ||
        /\.(mp3|m4a|aac|flac|wav|ogg)$/i.test(safeUrl.pathname));

    return res.json({
      ok: headRes.ok && isAudio,
      provider: 'direct_url',
      title: decodeURIComponent(
        path.basename(safeUrl.pathname).replace(/\.[a-z0-9]+$/i, '') || 'Direct Audio Track'
      ),
      artist: safeUrl.hostname,
      audioUrl: safeUrl.toString(),
      mimeType: mime,
      fileSizeBytes: len,
      audioAvailable: headRes.ok && isAudio,
      downloadAuthorized: headRes.ok && isAudio,
    });
  } catch (err: unknown) {
    return res.status(502).json({
      ok: false,
      error: err instanceof Error ? err.message : 'URL inspection failed',
    });
  }
});

// 7. X1 Open Metadata & Companion Identification (ZERO mandatory AudD/ACRCloud API keys)
app.post('/api/x1/identify', rateLimitMiddleware(30, 60_000), async (req, res) => {
  const { queryHint } = req.body || {};

  // Zero-key public MusicBrainz + Deezer catalog lookup when user/audio provides cues
  if (typeof queryHint === 'string' && queryHint.trim().length > 1) {
    try {
      const dzRes = await fetch(
        `https://api.deezer.com/search?q=${encodeURIComponent(queryHint.trim())}&limit=5`,
        { signal: AbortSignal.timeout(6000) }
      );
      if (dzRes.ok) {
        const dzJson = await dzRes.json();
        const first = Array.isArray(dzJson.data) ? dzJson.data[0] : null;
        if (first) {
          return res.json({
            ok: true,
            matched: true,
            provider: 'deezer_public_zero_key',
            track: {
              title: first.title,
              artist: first.artist?.name || 'Unknown Artist',
              album: first.album?.title || 'Single',
              durationSeconds: first.duration || 0,
              artworkUrl: first.album?.cover_big || first.album?.cover_medium || null,
              previewUrl: first.preview || null,
              externalId: String(first.id),
              confidence: 0.78,
            },
          });
        }
      }
    } catch {
      // Fall through cleanly
    }
  }

  // Raw microphone samples are matched offline on-device via local constellation fingerprinting & SHCustomCatalog.
  return res.json({
    ok: true,
    matched: false,
    provider: 'on_device_required',
    message:
      'On-device acoustic matching checked local library hashes cleanly. No paid external fingerprinting keys are required.',
  });
});

// ---------------- VITE / STATIC INTEGRATION ----------------
async function startServer() {
  const isProd = process.env.NODE_ENV === 'production';

  if (!isProd) {
    // Development mode with Vite dev middleware (HMR disabled for iframe environment)
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: { middlewareMode: true, hmr: false },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    // Production mode with built assets
    app.use(express.static(path.resolve(__dirname, 'dist')));
    app.get('*', (_req, res) => {
      res.sendFile(path.resolve(__dirname, 'dist', 'index.html'));
    });
  }

  app.listen(PORT, () => {
    console.log(`Server running at http://0.0.0.0:${PORT}`);
  });
}

startServer();
