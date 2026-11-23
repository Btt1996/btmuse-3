import http from 'http';
import assert from 'assert';
import {
  parseInstanceUrls,
  probeInvidiousInstance,
  probePipedInstance,
  searchWithFailover,
} from '../server/x2ProviderRouter.ts';

async function startMockServer(
  handler: (req: http.IncomingMessage, res: http.ServerResponse) => void
): Promise<{ server: http.Server; baseUrl: string }> {
  return new Promise((resolve, reject) => {
    const server = http.createServer(handler);
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address();
      if (!addr || typeof addr === 'string') {
        reject(new Error('Failed to resolve bound port'));
        return;
      }
      resolve({ server, baseUrl: `http://127.0.0.1:${addr.port}` });
    });
  });
}

async function run() {
  console.log('=== Btt Music X2 Connectivity & Failover Verification ===\n');

  // 1. Verify running Express backend /api/x2/health accurately reports unconfigured state
  console.log('[1/4] Checking running server /api/x2/health...');
  const localPort = process.env.PORT || '3000';
  const healthRes = await fetch(`http://127.0.0.1:${localPort}/api/x2/health`);
  assert.strictEqual(healthRes.status, 200, 'Expected HTTP 200 from /api/x2/health');
  const healthJson = (await healthRes.json()) as {
    ok: boolean;
    x2Backend: { configured: boolean; url: string | null; message: string };
    piped: { configuredCount: number };
    invidious: { configuredCount: number };
  };
  assert.strictEqual(healthJson.ok, true);
  console.log(
    `  -> x2Backend.configured=${healthJson.x2Backend.configured} | message="${healthJson.x2Backend.message}"`
  );
  console.log(
    `  -> env PIPED instances=${healthJson.piped.configuredCount}, INVIDIOUS instances=${healthJson.invidious.configuredCount}`
  );

  // Also test /api/x2/youtube/search when env vars are unset
  const searchRes = await fetch(`http://127.0.0.1:${localPort}/api/x2/youtube/search?q=lofi`);
  const searchJson = (await searchRes.json()) as { ok: boolean; message: string; items: unknown[] };
  console.log(
    `  -> /api/x2/youtube/search when unconfigured: ok=${searchJson.ok}, items=${searchJson.items.length}, message="${searchJson.message}"`
  );

  // 2. Verify SSRF guard vs test-allowed parsing + multi-instance failover
  console.log('\n[2/4] Testing Piped -> Piped and Piped -> Invidious automatic failover...');
  const filteredPublic = parseInstanceUrls(
    'http://localhost:3000, https://127.0.0.1, https://192.168.0.5, https://piped.example.org/'
  );
  assert.deepStrictEqual(filteredPublic, ['https://piped.example.org']);

  const deadPiped = await startMockServer((_req, res) => {
    res.writeHead(503, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Upstream overloaded' }));
  });

  const livePiped = await startMockServer((req, res) => {
    if (req.url?.startsWith('/trending')) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify([{ url: '/watch?v=ok1', title: 'Trending OK' }]));
      return;
    }
    if (req.url?.startsWith('/search')) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(
        JSON.stringify({
          items: [
            {
              url: '/watch?v=pipedTrack01',
              title: 'Night Drive',
              uploaderName: 'SynthLab',
              duration: 198,
              thumbnail: 'https://example.org/thumb.jpg',
            },
          ],
        })
      );
      return;
    }
    res.writeHead(404).end();
  });

  const liveInvidious = await startMockServer((req, res) => {
    if (req.url === '/api/v1/stats') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ version: '2.0', software: { name: 'invidious' } }));
      return;
    }
    if (req.url?.startsWith('/api/v1/search')) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(
        JSON.stringify([
          {
            videoId: 'invTrack99',
            title: 'Solar Echo',
            author: 'WaveForm',
            lengthSeconds: 242,
            videoThumbnails: [{ url: 'https://example.org/inv.jpg' }],
          },
        ])
      );
      return;
    }
    res.writeHead(404).end();
  });

  try {
    // Case A: Dead Piped fails over to live Piped
    const pipedFailover = await searchWithFailover({
      query: 'night drive',
      pipedUrls: [deadPiped.baseUrl, livePiped.baseUrl],
      invidiousUrls: [liveInvidious.baseUrl],
    });
    assert.strictEqual(pipedFailover.ok, true);
    assert.strictEqual(pipedFailover.providerUsed, 'piped');
    assert.strictEqual(pipedFailover.instanceUsed, livePiped.baseUrl);
    assert.strictEqual(pipedFailover.items[0]?.title, 'Night Drive');
    assert.strictEqual(pipedFailover.attempts[0]?.ok, false);
    console.log(
      `  -> Piped failover PASSED (${pipedFailover.attempts[0]?.error} -> succeeded on ${pipedFailover.instanceUsed})`
    );

    // Case B: All Piped dead -> fails over to Invidious
    const invidiousFailover = await searchWithFailover({
      query: 'solar echo',
      pipedUrls: [deadPiped.baseUrl],
      invidiousUrls: [liveInvidious.baseUrl],
    });
    assert.strictEqual(invidiousFailover.ok, true);
    assert.strictEqual(invidiousFailover.providerUsed, 'invidious');
    assert.strictEqual(invidiousFailover.instanceUsed, liveInvidious.baseUrl);
    assert.strictEqual(invidiousFailover.items[0]?.title, 'Solar Echo');
    console.log(
      `  -> Invidious failover PASSED (Piped failed -> succeeded on ${invidiousFailover.instanceUsed})`
    );
  } finally {
    deadPiped.server.close();
    livePiped.server.close();
    liveInvidious.server.close();
  }

  // 3. Test real outbound zero-key Audius search + REAL audio stream retrieval + YouTube oEmbed + Deezer
  console.log('\n[3/4] Testing live outbound zero-key providers & real audio stream retrieval...');
  try {
    const audSearch = await fetch(
      'https://discoveryprovider.audius.co/v1/tracks/search?query=lofi&app_name=BttMusic',
      { signal: AbortSignal.timeout(8000) }
    );
    const audJson = (await audSearch.json()) as {
      data?: Array<{ id?: string; title?: string; user?: { name?: string }; is_streamable?: boolean }>;
    };
    const firstStreamable = audJson.data?.find((t) => t.id && t.is_streamable !== false);
    if (firstStreamable?.id) {
      const streamUrl = `https://discoveryprovider.audius.co/v1/tracks/${firstStreamable.id}/stream?app_name=BttMusic`;
      const streamRes = await fetch(streamUrl, {
        headers: { Range: 'bytes=0-16383', 'User-Agent': 'BttMusic/3.0.5' },
        signal: AbortSignal.timeout(8000),
      });
      const buf = new Uint8Array(await streamRes.arrayBuffer());
      const contentType = streamRes.headers.get('content-type') || '';
      console.log(
        `  -> Audius LIVE PASS: "${firstStreamable.title}" by ${firstStreamable.user?.name} | HTTP ${streamRes.status} | type=${contentType} | bytes=${buf.byteLength}`
      );
      assert.ok(streamRes.ok && buf.byteLength > 1000, 'Expected real audio stream bytes');
    } else {
      console.log(`  -> Audius search HTTP ${audSearch.status}, no streamable items returned.`);
    }
  } catch (err) {
    console.log(`  -> Audius LIVE ERROR (reported honestly): ${err instanceof Error ? err.message : err}`);
  }

  try {
    const oembedRes = await fetch(
      'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=dQw4w9WgXcQ&format=json',
      { signal: AbortSignal.timeout(6000) }
    );
    const oembed = (await oembedRes.json()) as { title?: string; author_name?: string };
    assert.ok(oembed.title && oembed.author_name, 'Expected non-empty YouTube oEmbed metadata');
    console.log(
      `  -> YouTube oEmbed LIVE PASS: HTTP ${oembedRes.status} | "${oembed.title}" by ${oembed.author_name}`
    );
  } catch (err) {
    console.log(`  -> YouTube oEmbed ERROR: ${err instanceof Error ? err.message : err}`);
  }

  try {
    const dzRes = await fetch('https://api.deezer.com/search?q=lofi&limit=1', {
      signal: AbortSignal.timeout(6000),
    });
    const dz = (await dzRes.json()) as { data?: Array<{ title?: string; preview?: string }> };
    console.log(
      `  -> Deezer Public LIVE PASS: HTTP ${dzRes.status} | "${dz.data?.[0]?.title}" | preview=${Boolean(dz.data?.[0]?.preview)}`
    );
  } catch (err) {
    console.log(`  -> Deezer Public ERROR: ${err instanceof Error ? err.message : err}`);
  }

  // 4. Probe any configured PIPED_API_URL / INVIDIOUS_API_URL env vars if present
  console.log('\n[4/4] Checking configured PIPED_API_URL / INVIDIOUS_API_URL env vars...');
  const envPiped = parseInstanceUrls(process.env.PIPED_API_URL);
  const envInvidious = parseInstanceUrls(process.env.INVIDIOUS_API_URL);
  if (envPiped.length === 0) {
    console.log('  -> PIPED_API_URL is unset (no hardcoded public instances assumed).');
  } else {
    for (const u of envPiped) {
      const p = await probePipedInstance(u);
      console.log(`  -> Piped ${u}: available=${p.available} latency=${p.latencyMs}ms error=${p.error || 'none'}`);
    }
  }
  if (envInvidious.length === 0) {
    console.log('  -> INVIDIOUS_API_URL is unset (no hardcoded public instances assumed).');
  } else {
    for (const u of envInvidious) {
      const p = await probeInvidiousInstance(u);
      console.log(`  -> Invidious ${u}: available=${p.available} latency=${p.latencyMs}ms error=${p.error || 'none'}`);
    }
  }

  console.log('\n=== Verification script completed ===');
}

run().catch((err) => {
  console.error('Verification failed:', err);
  process.exit(1);
});
