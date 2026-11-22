# Btt Music 2.00 — Open-Source Feasibility, Licenses & Zero-API-Key Architecture

## 1. Open-Source Research & Licensing Audit

| Component | Purpose | License | iOS Compatibility | Adopted Strategy in Btt Music 2.00 |
| --- | --- | --- | --- | --- |
| **Apple AVFoundation / Accelerate** | Native audio decoding & DSP | Apple SDK | Native iOS 18+ | `AudioEnginePlugin.swift` resamples imported MP3/M4A/FLAC/WAV to 11,025 Hz mono PCM with zero FFmpeg bloat. |
| **Apple ShazamKit (`SHCustomCatalog`)** | Custom on-device catalog | Apple SDK | Native (no Cloud cap needed) | Eligible offline add-on; primary X1 relies on pure Dart `LocalFingerprintEngine` for cross-testability. |
| **Chromaprint + AcoustID** | Audio fingerprinting | **LGPL 2.1** (lib) + Paid Key | Requires CMake + FFmpeg + API key | **Not mandated.** AcoustID requires registering an API key (`client=...`) and commercial fees for commercial apps. |
| **Olaf** | Constellation Peak Hashing | **AGPL-3.0** + Patents | Portable ANSI C / LMDB | **Algorithmic inspiration only; implemented cleanly from scratch** (`LocalFingerprintEngine`) avoiding AGPL-3.0 constraints. |
| **Audius Open Protocol** | Open music search & streams | **Apache 2.0** | REST HTTPS direct | **Adopted in X2.** Zero API key required for public search & full creator-permitted streams. |
| **Deezer Public / MusicBrainz / iTunes** | Track metadata & 30s previews | Public REST | REST HTTPS direct | **Adopted in X1 & X2.** Zero API keys required (MusicBrainz uses proper `User-Agent` + 1 req/s rate respect). |
| **`yt-dlp` (Python)** | YouTube stream extraction | **Unlicense** | Experimental (`PythonKit`, 50–100 MB, App Store rejections, PoToken breaks) | **Not bundled in iOS binary.** Official zero-key oEmbed metadata runs directly on-device; optional user self-hosted Piped/Invidious companion supported. |
| **VK Audio Retrieval** | VK music tracks | Proprietary platform | Unauthenticated `audio.get` deprecated; HLS/encrypted segments | **Isolated in `VkProvider` + optional user session cookie** (`remixsid`/`p`), never faking unavailable tracks. |

---

## 2. What Works Locally on iOS vs. What Requires Backend / Companion Deployment

### Works 100% Standalone on iOS (`flutter_app/`, zero backend or API keys needed)
- **Offline Library & SQLite Vault (`local_database.dart`):** Local file imports, metadata editing, playlists, play counts, and atomic file persistence in Application Documents.
- **Native Audio Engine (`AudioEnginePlugin.swift`):** Background audio playback, `MPNowPlayingInfoCenter` lock screen artwork & controls, AirPods remote commands, interruption handling, 100%–300% speaker boost with peak limiter, and Smart Remix equal-power crossfading.
- **X1 Identification:** Native `AVAudioFile` PCM resampling + pure-Dart FFT constellation landmark matching (`LocalFingerprintEngine`) + zero-key MusicBrainz, Deezer, and iTunes verification catalogs with 30s preview confirmation.
- **Telegram Bot Import (`telegram_screen.dart`):** Connects directly from iOS using the user's own bot token stored in iOS Keychain (`flutter_secure_storage`).
- **Direct X2 Acquisition:** Permissionless **Audius Open Audio Protocol** keyword search + full stream downloads, **Direct Audio URL** downloads, **Podcast/Music RSS** XML enclosure parsing, and official zero-key **YouTube / SoundCloud / Spotify oEmbed** URL inspection.
- **Direct Piped / Invidious Routing:** When `PIPED_API_URL` or `INVIDIOUS_API_URL` are supplied (at build time via `--dart-define` or at runtime in **Settings → X2 Backend & Multi-Provider Config**), iOS probes availability, enforces timeouts, and fails over across instances directly.

### Requires `X2_BACKEND_URL` (Deployed `server.ts` Companion)
- **`X2_BACKEND_URL` is NEVER invented or defaulted to `localhost`.** If omitted, Settings and X2 UI explicitly report it as **Not Configured**.
- Deploying `server.ts` enables:
  - Server-side fallback relay `/api/x2/youtube/search` & `/api/x2/health` aggregating `PIPED_API_URL` / `INVIDIOUS_API_URL`.
  - Server-side VK public page OpenGraph inspection (`/api/x2/url-inspect`).
  - CORS-free Web/PWA Telegram & audio stream proxy (`/api/telegram/*`, `/api/audio-proxy`).
  - No fake audio streams or simulated downloads are ever returned when any provider or backend is unconfigured or offline.
