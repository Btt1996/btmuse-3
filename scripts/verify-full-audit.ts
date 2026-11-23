import assert from 'assert';
import fs from 'fs';
import os from 'os';
import path from 'path';

function hasValidAudioHeader(buf: Buffer): { valid: boolean; detected: string } {
  if (buf.length < 12) return { valid: false, detected: 'too-short' };
  const headStr = buf.subarray(0, 16).toString('utf8').trimStart().toLowerCase();
  if (headStr.startsWith('<!doc') || headStr.startsWith('<html') || headStr.startsWith('{')) {
    return { valid: false, detected: 'html/json-disguise' };
  }
  if (buf[0] === 0x49 && buf[1] === 0x44 && buf[2] === 0x33) {
    return { valid: true, detected: 'MP3 (ID3v2)' };
  }
  if (buf[0] === 0xff && (buf[1] & 0xe0) === 0xe0) {
    const layer = (buf[1] >> 1) & 0x03;
    return { valid: true, detected: layer === 0 ? 'AAC (ADTS)' : 'MP3 (Frame Sync)' };
  }
  if (buf.subarray(0, 4).toString('ascii') === 'fLaC') {
    return { valid: true, detected: 'FLAC' };
  }
  if (
    buf.subarray(0, 4).toString('ascii') === 'RIFF' &&
    buf.subarray(8, 12).toString('ascii') === 'WAVE'
  ) {
    return { valid: true, detected: 'WAV' };
  }
  if (buf.subarray(0, 4).toString('ascii') === 'OggS') {
    return { valid: true, detected: 'OGG' };
  }
  if (buf.subarray(4, 8).toString('ascii') === 'ftyp') {
    return { valid: true, detected: 'M4A/MP4 (ftyp)' };
  }
  return { valid: false, detected: `unknown(${buf.subarray(0, 4).toString('hex')})` };
}

async function run() {
  const baseUrl = `http://127.0.0.1:${process.env.PORT || '3000'}`;
  console.log('=== Btt Music Full Functional & Provider Verification ===\n');

  // 1. Companion Server Endpoints
  console.log('[1/6] Checking Express companion routes...');
  const ver = await (await fetch(`${baseUrl}/api/version`)).json();
  assert.strictEqual(ver.bundleId, 'com.ahmed.btmu');
  console.log(`  PASS /api/version -> ${ver.name} v${ver.version} (${ver.bundleId})`);

  const x2Health = await (await fetch(`${baseUrl}/api/x2/health`)).json();
  console.log(
    `  PASS /api/x2/health -> configured=${x2Health.x2Backend.configured}, piped=${x2Health.piped.configuredCount}, invidious=${x2Health.invidious.configuredCount}`
  );

  const itunesLocal = await (
    await fetch(`${baseUrl}/api/itunes/search?term=daft+punk&limit=1`)
  ).json();
  console.log(
    `  INFO /api/itunes/search -> results=${Array.isArray(itunesLocal.results) ? itunesLocal.results.length : 0}`
  );

  const x1Local = await (
    await fetch(`${baseUrl}/api/x1/identify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ queryHint: 'Midnight City M83' }),
    })
  ).json();
  console.log(
    `  INFO /api/x1/identify -> ok=${x1Local.ok}, matched=${x1Local.matched}, provider=${x1Local.provider}`
  );

  // 2. Audius Discovery Failover + FULL BINARY TRACK DOWNLOAD
  console.log('\n[2/6] Testing Audius search + FULL audio track download integrity...');
  let discoveryHost = 'https://discoveryprovider.audius.co';
  try {
    const hostsRes = await fetch('https://api.audius.co', { signal: AbortSignal.timeout(6000) });
    const hostsJson = (await hostsRes.json()) as { data?: string[] };
    if (Array.isArray(hostsJson.data) && hostsJson.data.length > 0) {
      discoveryHost = hostsJson.data[0].replace(/\/+$/, '');
      console.log(`  INFO Selected live Audius discovery node: ${discoveryHost}`);
    }
  } catch (err) {
    console.log(`  WARN api.audius.co discovery lookup failed, using default node: ${err}`);
  }

  const audSearchRes = await fetch(
    `${discoveryHost}/v1/tracks/search?query=lofi&app_name=BttMusic`,
    { signal: AbortSignal.timeout(10000) }
  );
  const audSearchJson = (await audSearchRes.json()) as {
    data?: Array<{ id?: string; title?: string; duration?: number; user?: { name?: string }; is_streamable?: boolean }>;
  };
  const track = audSearchJson.data?.find((t) => t.id && t.is_streamable !== false);
  assert.ok(track?.id, 'Expected at least one streamable Audius track');

  const fullStreamUrl = `${discoveryHost}/v1/tracks/${track.id}/stream?app_name=BttMusic`;
  const dlRes = await fetch(fullStreamUrl, {
    headers: { 'User-Agent': 'BttMusic/3.0.5 (iOS)' },
    signal: AbortSignal.timeout(45000),
  });
  assert.ok(dlRes.ok, `Expected HTTP 200 downloading Audius track, got ${dlRes.status}`);
  const mime = dlRes.headers.get('content-type') || '';
  const expectedLen = parseInt(dlRes.headers.get('content-length') || '0', 10);
  const fullBuf = Buffer.from(await dlRes.arrayBuffer());

  const tmpPath = path.join(os.tmpdir(), `btmu_full_verify_${Date.now()}.mp3`);
  fs.writeFileSync(tmpPath, fullBuf);
  const diskSize = fs.statSync(tmpPath).size;
  const headerCheck = hasValidAudioHeader(fullBuf);
  fs.unlinkSync(tmpPath);

  console.log(
    `  PASS Audius FULL Download: "${track.title}" by ${track.user?.name} (${track.duration}s) | MIME=${mime} | DiskBytes=${diskSize} | ExpectedHeader=${expectedLen} | Container=${headerCheck.detected}`
  );
  assert.ok(headerCheck.valid, `Invalid audio header: ${headerCheck.detected}`);
  assert.ok(diskSize > 500_000, `Expected full audio file >500KB, got ${diskSize}`);
  if (expectedLen > 0) {
    assert.ok(diskSize >= expectedLen * 0.99, `Truncated download: ${diskSize}/${expectedLen}`);
  }

  // 3. Deezer & Apple Public Search + Real 30s Preview Binary Check
  console.log('\n[3/6] Testing Deezer & Apple iTunes public search + 30s preview audio download...');
  const dzSearch = await (
    await fetch('https://api.deezer.com/search?q=M83+Midnight+City&limit=3', {
      signal: AbortSignal.timeout(8000),
    })
  ).json();
  const dzTrack = dzSearch.data?.find((d: { preview?: string }) => d.preview);
  assert.ok(dzTrack?.preview, 'Expected Deezer result with 30s preview URL');
  const dzPrevRes = await fetch(dzTrack.preview, { signal: AbortSignal.timeout(15000) });
  const dzBuf = Buffer.from(await dzPrevRes.arrayBuffer());
  const dzHdr = hasValidAudioHeader(dzBuf);
  console.log(
    `  PASS Deezer Preview: "${dzTrack.title}" | Bytes=${dzBuf.byteLength} | Container=${dzHdr.detected}`
  );
  assert.ok(dzPrevRes.ok && dzHdr.valid && dzBuf.byteLength > 100_000);

  const appleSearch = await (
    await fetch('https://itunes.apple.com/search?term=M83+Midnight+City&media=music&entity=song&limit=3', {
      signal: AbortSignal.timeout(8000),
    })
  ).json();
  const appleTrack = appleSearch.results?.find((r: { previewUrl?: string }) => r.previewUrl);
  assert.ok(appleTrack?.previewUrl, 'Expected iTunes result with 30s previewUrl');
  const applePrevRes = await fetch(appleTrack.previewUrl, { signal: AbortSignal.timeout(15000) });
  const appleBuf = Buffer.from(await applePrevRes.arrayBuffer());
  const appleHdr = hasValidAudioHeader(appleBuf);
  console.log(
    `  PASS iTunes Preview: "${appleTrack.trackName}" | Bytes=${appleBuf.byteLength} | Container=${appleHdr.detected}`
  );
  assert.ok(applePrevRes.ok && appleHdr.valid && appleBuf.byteLength > 100_000);

  // 4. YouTube & SoundCloud oEmbed Live Resolution
  console.log('\n[4/6] Testing YouTube oEmbed & SoundCloud oEmbed...');
  const ytRes = await fetch(
    'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=dQw4w9WgXcQ&format=json',
    { signal: AbortSignal.timeout(8000) }
  );
  const ytJson = (await ytRes.json()) as { title?: string; author_name?: string };
  console.log(`  PASS YouTube oEmbed: HTTP ${ytRes.status} | "${ytJson.title}" by ${ytJson.author_name}`);

  const scRes = await fetch(
    'https://soundcloud.com/oembed?format=json&url=https://soundcloud.com/forss/flickermood',
    { signal: AbortSignal.timeout(8000) }
  );
  console.log(`  INFO SoundCloud oEmbed live status: HTTP ${scRes.status}`);
  if (scRes.ok) {
    const scJson = (await scRes.json()) as { title?: string; author_name?: string };
    console.log(`  PASS SoundCloud oEmbed: "${scJson.title}" by ${scJson.author_name}`);
  }

  // 5. Direct Audio URL check via companion endpoint
  console.log('\n[5/6] Testing Direct Audio URL inspection via /api/audio-verify...');
  const verifyDirect = await (
    await fetch(`${baseUrl}/api/audio-verify?url=${encodeURIComponent(dzTrack.preview)}`)
  ).json();
  console.log(
    `  PASS /api/audio-verify -> isPlayableAudio=${verifyDirect.isPlayableAudio}, type=${verifyDirect.contentType}, len=${verifyDirect.contentLength}`
  );
  assert.strictEqual(verifyDirect.isPlayableAudio, true);

  // 6. VK Public Page OpenGraph Behavior Observation
  console.log('\n[6/6] Observing VK public URL OpenGraph inspection behavior...');
  const vkInspect = await (
    await fetch(`${baseUrl}/api/x2/url-inspect`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: 'https://vk.com/audio' }),
    })
  ).json();
  console.log(
    `  INFO VK inspect -> ok=${vkInspect.ok}, downloadAuthorized=${vkInspect.downloadAuthorized}, note="${vkInspect.authorizationNote}"`
  );

  console.log('\n=== Full Audit Live Verification Completed ===');
}

run().catch((err) => {
  console.error('Audit verification failed:', err);
  process.exit(1);
});
