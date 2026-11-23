# X2 Degraded Mode — What Works With No Backend and No Credentials

Btt Music 2.00's X2 import layer is designed to degrade gracefully: the
app never invents a backend URL, a credential, or a result. When the
deployed companion backend (`X2_BACKEND_URL`) is absent and no provider
credentials are configured, the app still imports from every source that
is genuinely public. This document states exactly what works, what does
not, and what the UI says in each case.

No backend URL is invented anywhere in the app. An empty
`X2_BACKEND_URL` means "not configured", never a guessed default.

## Works with no backend and no credentials

| Source | How it works | What you get |
|---|---|---|
| Audius | Direct keyword search + URL resolve via the Audius Open Audio Protocol discovery nodes (`discoveryprovider.audius.co`), zero key | Full-length streams, artwork, creator-permitted downloads |
| Internet Archive | Keyword search via `advancedsearch.php` (audio items only) + `metadata/{id}`, then direct MP3 download from `archive.org/download/{id}/{file}` | Full-length public-library MP3s. Only files whose format is `MP3` / `VBR MP3` and whose item is public (`access-restricted-item` is not set) are offered; restricted or non-audio items are skipped silently |
| Direct audio URL | `HEAD` (or a 1 KB range `GET`) verifies the content type, then the file is imported | Any direct `audio/*` link the server serves |
| RSS / podcast feeds | Paste a feed URL (`.rss` / `.xml` / `/feed`, or any URL whose server answers `HEAD` with an XML/RSS content type). The Import Center lists every audio enclosure for batch selection | One result per audio `<enclosure>`, with duration when the feed declares `<itunes:duration>` / `<duration>` |
| YouTube URLs | Pasted `youtube.com` / `youtu.be` links resolve via the official zero-key YouTube oEmbed endpoint | Title / author / thumbnail metadata (metadata-only); the engine then searches the authorized providers for a downloadable match |
| SoundCloud URLs | Pasted `soundcloud.com` track links resolve via the official zero-key SoundCloud oEmbed endpoint | Title / author / thumbnail metadata (metadata-only by design) |
| Spotify track links | Single track links resolve via the official zero-key Spotify oEmbed endpoint | Title / artist metadata (metadata-only); the engine then searches the authorized providers for a downloadable match |
| Deezer | Zero-key public catalog search (`api.deezer.com/search`) | Metadata + artwork + verified 30-second preview streams (metadata-only) |
| Apple Catalog (iTunes) | Zero-key public search (`itunes.apple.com/search`) | Metadata + artwork (metadata-only) |
| X1 local matching | On-device fingerprint / metadata match against the local library | Finds tracks already owned, no network needed |
| VK URLs | Pasted public VK audio URLs are inspected via OpenGraph | Metadata (metadata-only); audio retrieval needs a user token or the backend |

Every download, from any source, still passes through the acquisition
engine's validation before import: authorization check, safe-URL check,
content-type check, completeness check, magic-bytes audio validation,
duration plausibility, and SHA-256 deduplication against the library.

## Needs configuration (and stays off until then)

| Source | Needs | UI report when missing |
|---|---|---|
| YouTube keyword search | `PIPED_API_URL`, `INVIDIOUS_API_URL`, or `X2_BACKEND_URL` (any one) | `youtube_not_configured`: "Not configured: Set PIPED_API_URL, INVIDIOUS_API_URL, or X2_BACKEND_URL in Settings to enable YouTube keyword search (pasting direct YouTube URLs works standalone via oEmbed)." |
| Spotify playlists / albums | Deployed backend (`X2_BACKEND_URL`); the server holds the Spotify credentials, the app never sees them | `spotify_playlist_needs_backend`: the playlist lookup fails naming `X2_BACKEND_URL` instead of inventing a backend |
| Spotify user playlists | Backend **plus** server-side Spotify credentials | Same backend error as above; the app cannot supply server credentials |
| Jamendo keyword search + track URLs | A Jamendo client ID (free, from devportal.jamendo.com), entered in Settings → "Jamendo client ID" | `jamendo_client_id_missing`: "Jamendo keyword search needs a client ID. Set the Jamendo client ID in Settings to enable it." The provider is not listed as searchable until the ID is saved |
| SoundCloud keyword search | Nothing can enable it — SoundCloud closed public API key registration | `soundcloud_search_restricted`: "SoundCloud closed public API key registrations for keyword search. Paste a SoundCloud track URL…" No Settings field exists for it, on purpose |
| VK keyword search | A VK user access token (via the Import Center VK sheet) | `vk_auth_required`: "VK permanently deprecated unauthenticated audio.search…" |
| Telegram sync | A Telegram bot token (Telegram screen) | Telegram features report the token as missing until one is entered |

## What changes when the backend IS deployed

With `X2_BACKEND_URL` set (and reachable), these paths unlock on top of
everything above:

- Spotify playlist / album tracklists (server-side Spotify credentials).
- YouTube keyword search as a third fallback after Piped and Invidious.
- Optional VK URL inspection through the backend.
- The backend health row in diagnostics reports "Connected (Nms)".

Nothing that already worked standalone changes: the backend is an
addition, never a replacement for the direct providers.

## Diagnostics (Settings → Test Connectivity)

`X2ConnectivityTester.runDiagnostics()` probes each source with a
5-second timeout and never reports success it did not observe:

| Row | Probe | "Not configured" wording |
|---|---|---|
| `X2_BACKEND_URL` | `GET {backend}/api/x2/health`, expects `{ok: true}` | "X2_BACKEND_URL is not configured. Optional companion features are offline." |
| Audius Direct (Zero-Key) | `GET discoveryprovider.audius.co/v1/tracks/search?query=ambient` | — (always attempted; failure is reported, not hidden) |
| Internet Archive (Zero-Key) | `GET archive.org/advancedsearch.php?q=mediatype:(audio)&rows=1&output=json` | — (always attempted; failure is reported, not hidden) |
| Jamendo | `GET api.jamendo.com/v3.0/tracks/?client_id=…&limit=1`, expects `headers.status == "success"` | "Jamendo client ID not configured — set the Jamendo client ID in Settings to enable Jamendo search." |
| Piped / Invidious | One probe per configured instance URL | "No Piped instances configured." / "No Invidious instances configured." |

## Principles (do not regress)

1. **Never invent a URL, key, or result.** An unconfigured source
   reports itself as unconfigured; a failed source reports the failure.
2. **Credentials live in the Keychain** (secure credentials store), never
   in code, never in chat, never in a frontend payload. The Jamendo
   client ID follows the same rule as the backend auth token.
3. **Public means public.** Archive.org results are downloadable only
   because they come from the public library search; restricted items
   are excluded at the provider, not at the UI.
4. **Metadata-only is a real state, not a failure.** YouTube,
   SoundCloud, Spotify, Deezer, and iTunes results are labelled as such
   and hand off to the authorized providers for acquisition.
