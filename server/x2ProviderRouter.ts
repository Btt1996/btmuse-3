export interface InstanceProbeResult {
  provider: 'piped' | 'invidious';
  instanceUrl: string;
  available: boolean;
  latencyMs: number;
  statusCode?: number;
  error?: string;
}

export interface ProviderAttempt {
  provider: 'piped' | 'invidious';
  instanceUrl: string;
  stage: 'probe' | 'search' | 'resolve';
  ok: boolean;
  error?: string;
}

export interface NormalizedYoutubeSearchItem {
  id: string;
  title: string;
  artist: string;
  thumbnail: string | null;
  duration: number;
  url: string;
  provider: 'piped' | 'invidious';
  instanceUrl: string;
}

export interface FailoverSearchResult {
  ok: boolean;
  providerUsed: 'piped' | 'invidious' | null;
  instanceUsed: string | null;
  items: NormalizedYoutubeSearchItem[];
  attempts: ProviderAttempt[];
  message: string;
}

export function validateExternalInstanceUrl(
  rawUrl: string,
  allowLocalForTest = false
): string | null {
  try {
    const parsed = new URL(rawUrl.trim());
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null;
    }

    if (!allowLocalForTest) {
      const host = parsed.hostname.toLowerCase();
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
      const octets = host.split('.');
      if (octets.length === 4 && octets[0] === '172') {
        const second = parseInt(octets[1], 10);
        if (second >= 16 && second <= 31) return null;
      }
    }

    return parsed.toString().replace(/\/+$/, '');
  } catch {
    return null;
  }
}

export function parseInstanceUrls(
  rawEnvValue?: string,
  allowLocalForTest = false
): string[] {
  if (!rawEnvValue || !rawEnvValue.trim()) return [];
  const unique = new Set<string>();
  for (const part of rawEnvValue.split(',')) {
    const safe = validateExternalInstanceUrl(part, allowLocalForTest);
    if (safe) unique.add(safe);
  }
  return Array.from(unique);
}

export async function probePipedInstance(
  baseUrl: string,
  timeoutMs = 4500
): Promise<InstanceProbeResult> {
  const start = Date.now();
  try {
    const res = await fetch(`${baseUrl}/trending?region=US`, {
      headers: {
        'User-Agent': 'BttMusic/2.00 (HealthCheck)',
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(timeoutMs),
    });

    const contentType = (res.headers.get('content-type') || '').toLowerCase();
    if (!res.ok) {
      return {
        provider: 'piped',
        instanceUrl: baseUrl,
        available: false,
        latencyMs: Date.now() - start,
        statusCode: res.status,
        error: `HTTP ${res.status}`,
      };
    }
    if (!contentType.includes('json')) {
      return {
        provider: 'piped',
        instanceUrl: baseUrl,
        available: false,
        latencyMs: Date.now() - start,
        statusCode: res.status,
        error: `Unexpected non-JSON response (${contentType || 'unknown'})`,
      };
    }

    const payload = await res.json();
    if (!Array.isArray(payload)) {
      return {
        provider: 'piped',
        instanceUrl: baseUrl,
        available: false,
        latencyMs: Date.now() - start,
        statusCode: res.status,
        error: 'Piped trending payload is not a JSON list',
      };
    }

    return {
      provider: 'piped',
      instanceUrl: baseUrl,
      available: true,
      latencyMs: Date.now() - start,
      statusCode: res.status,
    };
  } catch (err: unknown) {
    return {
      provider: 'piped',
      instanceUrl: baseUrl,
      available: false,
      latencyMs: Date.now() - start,
      error: err instanceof Error ? err.message : 'Connection failed',
    };
  }
}

export async function probeInvidiousInstance(
  baseUrl: string,
  timeoutMs = 4500
): Promise<InstanceProbeResult> {
  const start = Date.now();
  try {
    const res = await fetch(`${baseUrl}/api/v1/stats`, {
      headers: {
        'User-Agent': 'BttMusic/2.00 (HealthCheck)',
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(timeoutMs),
    });

    const contentType = (res.headers.get('content-type') || '').toLowerCase();
    if (!res.ok) {
      return {
        provider: 'invidious',
        instanceUrl: baseUrl,
        available: false,
        latencyMs: Date.now() - start,
        statusCode: res.status,
        error: `HTTP ${res.status}`,
      };
    }
    if (!contentType.includes('json')) {
      return {
        provider: 'invidious',
        instanceUrl: baseUrl,
        available: false,
        latencyMs: Date.now() - start,
        statusCode: res.status,
        error: `Unexpected non-JSON response (${contentType || 'unknown'})`,
      };
    }

    const json = (await res.json()) as Record<string, unknown>;
    if (!json || typeof json !== 'object') {
      return {
        provider: 'invidious',
        instanceUrl: baseUrl,
        available: false,
        latencyMs: Date.now() - start,
        statusCode: res.status,
        error: 'Invalid Invidious stats JSON',
      };
    }

    return {
      provider: 'invidious',
      instanceUrl: baseUrl,
      available: true,
      latencyMs: Date.now() - start,
      statusCode: res.status,
    };
  } catch (err: unknown) {
    return {
      provider: 'invidious',
      instanceUrl: baseUrl,
      available: false,
      latencyMs: Date.now() - start,
      error: err instanceof Error ? err.message : 'Connection failed',
    };
  }
}

export async function searchWithFailover(params: {
  query: string;
  pipedUrls: string[];
  invidiousUrls: string[];
  timeoutMs?: number;
}): Promise<FailoverSearchResult> {
  const { query, pipedUrls, invidiousUrls, timeoutMs = 5500 } = params;
  const attempts: ProviderAttempt[] = [];

  if (pipedUrls.length === 0 && invidiousUrls.length === 0) {
    return {
      ok: false,
      providerUsed: null,
      instanceUsed: null,
      items: [],
      attempts,
      message:
        'Neither PIPED_API_URL nor INVIDIOUS_API_URL is configured. Configure at least one instance or paste a direct YouTube URL for zero-key oEmbed inspection.',
    };
  }

  // 1. Probe and execute against configured Piped instances with failover
  for (const baseUrl of pipedUrls) {
    const probe = await probePipedInstance(baseUrl, Math.min(timeoutMs, 4000));
    attempts.push({
      provider: 'piped',
      instanceUrl: baseUrl,
      stage: 'probe',
      ok: probe.available,
      error: probe.error,
    });
    if (!probe.available) continue;

    try {
      const sRes = await fetch(
        `${baseUrl}/search?q=${encodeURIComponent(query)}&filter=music_songs`,
        {
          headers: { 'User-Agent': 'BttMusic/2.00', Accept: 'application/json' },
          signal: AbortSignal.timeout(timeoutMs),
        }
      );
      if (!sRes.ok) {
        attempts.push({
          provider: 'piped',
          instanceUrl: baseUrl,
          stage: 'search',
          ok: false,
          error: `HTTP ${sRes.status}`,
        });
        continue;
      }

      const sJson = (await sRes.json()) as { items?: Array<Record<string, unknown>> };
      const rawItems = Array.isArray(sJson.items) ? sJson.items : [];
      const items: NormalizedYoutubeSearchItem[] = rawItems
        .slice(0, 12)
        .filter((item) => typeof item.url === 'string' && String(item.url).includes('/watch?v='))
        .map((item) => {
          const watchPath = String(item.url);
          const id = watchPath.replace('/watch?v=', '').split('&')[0];
          return {
            id,
            title: String(item.title || 'YouTube Track'),
            artist: String(item.uploaderName || 'YouTube Creator'),
            thumbnail: typeof item.thumbnail === 'string' ? item.thumbnail : null,
            duration: typeof item.duration === 'number' ? item.duration : 0,
            url: `https://www.youtube.com/watch?v=${id}`,
            provider: 'piped',
            instanceUrl: baseUrl,
          };
        });

      attempts.push({
        provider: 'piped',
        instanceUrl: baseUrl,
        stage: 'search',
        ok: true,
      });

      return {
        ok: true,
        providerUsed: 'piped',
        instanceUsed: baseUrl,
        items,
        attempts,
        message: `Retrieved ${items.length} result(s) via Piped (${baseUrl}).`,
      };
    } catch (err: unknown) {
      attempts.push({
        provider: 'piped',
        instanceUrl: baseUrl,
        stage: 'search',
        ok: false,
        error: err instanceof Error ? err.message : 'Search error',
      });
    }
  }

  // 2. Automatic Failover to Invidious instances
  for (const baseUrl of invidiousUrls) {
    const probe = await probeInvidiousInstance(baseUrl, Math.min(timeoutMs, 4000));
    attempts.push({
      provider: 'invidious',
      instanceUrl: baseUrl,
      stage: 'probe',
      ok: probe.available,
      error: probe.error,
    });
    if (!probe.available) continue;

    try {
      const iRes = await fetch(
        `${baseUrl}/api/v1/search?q=${encodeURIComponent(query)}&type=video`,
        {
          headers: { 'User-Agent': 'BttMusic/2.00', Accept: 'application/json' },
          signal: AbortSignal.timeout(timeoutMs),
        }
      );
      if (!iRes.ok) {
        attempts.push({
          provider: 'invidious',
          instanceUrl: baseUrl,
          stage: 'search',
          ok: false,
          error: `HTTP ${iRes.status}`,
        });
        continue;
      }

      const rawList = (await iRes.json()) as Array<Record<string, unknown>>;
      const items: NormalizedYoutubeSearchItem[] = (Array.isArray(rawList) ? rawList : [])
        .slice(0, 12)
        .filter((item) => typeof item.videoId === 'string')
        .map((item) => {
          const id = String(item.videoId);
          const thumbs = Array.isArray(item.videoThumbnails)
            ? (item.videoThumbnails[0] as Record<string, unknown>)
            : undefined;
          return {
            id,
            title: String(item.title || 'YouTube Video'),
            artist: String(item.author || 'YouTube Creator'),
            thumbnail: typeof thumbs?.url === 'string' ? thumbs.url : null,
            duration: typeof item.lengthSeconds === 'number' ? item.lengthSeconds : 0,
            url: `https://www.youtube.com/watch?v=${id}`,
            provider: 'invidious',
            instanceUrl: baseUrl,
          };
        });

      attempts.push({
        provider: 'invidious',
        instanceUrl: baseUrl,
        stage: 'search',
        ok: true,
      });

      return {
        ok: true,
        providerUsed: 'invidious',
        instanceUsed: baseUrl,
        items,
        attempts,
        message: `Retrieved ${items.length} result(s) via Invidious (${baseUrl}).`,
      };
    } catch (err: unknown) {
      attempts.push({
        provider: 'invidious',
        instanceUrl: baseUrl,
        stage: 'search',
        ok: false,
        error: err instanceof Error ? err.message : 'Search error',
      });
    }
  }

  return {
    ok: false,
    providerUsed: null,
    instanceUsed: null,
    items: [],
    attempts,
    message:
      'All configured Piped and Invidious instances failed or are currently unreachable.',
  };
}
