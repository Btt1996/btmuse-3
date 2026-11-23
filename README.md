# Btt Music 2.00 — Btmus by Taboubi Ahmed

**Btt Music** (short name **btmu**) is an offline-first music player for iPhone.
Bundle identifier: `com.ahmed.btmu` · Target: iOS 18+ · Primary device: iPhone XS Max ·
Developer: Ahmed Taboubi · Target release: **2.00**.

> **Version of truth: 2.00 everywhere.** The Flutter app previously called itself
> "Btt Music 3.0" (`3.0.0+30`); that was an internal codename, now retired as a
> release label. The repository is named `btmuse-3.0` for historical reasons — the
> release it ships is **2.00**.

## What this repo is

Seeded from [`Btt1996/Iosbtmus2`](https://github.com/Btt1996/Iosbtmus2) `main`
@ `15f88213902680d82488208950658b2df48d0b6e` (2026-11-15, "feat: integrate X2
backend and implement SSRF guards"), preserving the lineage. The original
placeholder commit of this repo (`f61602a`, "Initial commit") is the root of
this branch's history and remains recoverable.

**Canonical app: `flutter_app/` (Flutter).** It is the 2.00 app: dark-only design,
native audio engine, Riverpod state management, `just_audio` + `audio_service`,
SQLite, microphone X1 identification, X2 acquisition from authorized sources,
Telegram sync, Smart Remix, 5-band native EQ, and a native 300% volume boost
(limiter-guarded, off by default).

**Reference / fallback: the React + Capacitor app** (`src/`, `ios/`, `server.ts`).
It is the previous generation's web app kept in this repo as a reference
implementation and a fallback web build — not a second app to ship. Lyrics
live in both paths now: the React `lyricsService.ts` + `LyricsView.tsx`
(LRCLIB) and the Flutter port (`flutter_app/lib/features/lyrics/`, same
LRCLIB two-strategy flow with a SQLite cache).

**Native reference (not in this repo):**
[`Btt1996/BttMusic`](https://github.com/Btt1996/BttMusic) — the parallel SwiftUI
+ SwiftData + AVFoundation rebuild. Borrow ideas and verified code from it
(AVAudioEngine graph, `BoosterTests`, Share Extension + `bttmu://` YouTube
bridge, unsigned-IPA CI verification, backup/restore design); do not merge it.

## Architecture

```
flutter_app/            Flutter app — the canonical 2.00 app
  lib/
    app/                app shell, providers, theme (dark-only, obsidian #05070B)
    core/               audio handler, iOS audio bridge, storage, networking
    data/               models + repositories (library, playlist, history)
    features/           home, library, player, playlists, search, settings,
                        import_center, telegram, x1, x2, smart_remix,
                        downloads, audio_settings, lyrics, storage, backup
  ios/Runner/           iOS shell — AudioEnginePlugin.swift (native AVAudioEngine:
                        5-band EQ, DynamicsProcessor boost + limiter, crossfade,
                        MPNowPlayingInfoCenter), Info.plist (UIBackgroundModes: audio)
  test/                 12 Dart unit tests
src/                    React 19 + TypeScript + Vite 8 + Capacitor 8 app (reference)
ios/                    Capacitor iOS shell + AudioBridgePlugin.swift
server.ts               Express proxy + X2 backend (Telegram, Spotify, SoundCloud,
                        iTunes, YouTube metadata; SSRF guards; rate limits)
server/                 X2 provider router
scripts/                icon generation, full-audit + X2 connectivity verification
.github/workflows/      flutter-ios-ipa.yml (analyze, test, unsigned IPA only;
                        no signed IPA is built — see Release sequencing)
```

## Features

| Feature | Status |
|---|---|
| Offline music library (import, metadata, artwork, search, sort, duplicates) | Implemented (Flutter + React) |
| Playback (play/pause, prev/next, seek, shuffle, repeat one/all, queue) | Implemented |
| Playlists (create/rename/delete, reorder, import/export) | Implemented |
| Native background audio, lock-screen + Control Center controls, AirPods | Implemented, **not yet verified on a physical iPhone** |
| Local file import (Files app, document browser, ID3 parsing, SHA-256 dedup) | Implemented |
| Telegram import (bot token in Keychain; bot must receive forwards or be admin) | Implemented |
| Spotify playlist import | Metadata only — the Spotify API returns no audio |
| SoundCloud import (search + oEmbed; downloads only where creators enabled them) | Implemented (Flutter + React) |
| X1 song identification (mic → local fingerprint + MusicBrainz/Deezer/iTunes) | Implemented (Flutter); no ShazamKit/ACRCloud/AudD keys needed |
| X2 audio acquisition (Audius, Internet Archive, Jamendo, direct URL, RSS, Piped/Invidious via backend) | Implemented; needs a deployed `server.ts` for the relay paths |
| Smart Remix (BPM/energy DSP, energy-arc sequences) | Implemented |
| Lyrics (synced LRC + cache) | Implemented (Flutter + React) |
| EQ (5-band, native) | Flutter only |
| 300% volume boost (native gain + limiter, +9.54 dB max, off by default) | Flutter only; **never** via Web Audio in the Capacitor path (it breaks iOS background audio — see commit `7627d41` in the lineage) |
| Swipe-down to dismiss the fullscreen player | **Not yet implemented** — Phase 2 work |
| Backup / restore | Implemented (Flutter; one-JSON export, preview before restore, never-overwrite, metadata-only flagging) |
| Storage dashboard (per-source usage, SHA-256 duplicate scan, confirmed-only cleanup) | Implemented (Flutter) |

## What this app does NOT do (honest scope)

- **No "YouTube MP3" download button.** YouTube's Terms of Service prohibit
  downloading; no YouTube API returns MP3s. YouTube is supported as
  search/metadata only, plus an optional **self-hosted bridge** (run yt-dlp on
  your own server; the app does nothing without one configured — see the
  `BttMusic` Share Extension + `bttmu://` pattern). `spotify_to_mp3` is not
  integrated: it chains an unauthorized Selenium scrape + yt-dlp download,
  is Windows-only, and has been untouched since 2022.
- **No fake identification results.** X1 reports a match only when the local
  fingerprint index or a public catalog confirms it.
- **No credentials in the repo.** Spotify client id/secret, SoundCloud/Jamendo
  client ids, Telegram bot token, and the X2 backend URL live in environment
  variables / the iOS Keychain, never in source. See `.env.example`.

## Build

### Flutter app (canonical)

```bash
cd flutter_app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

CI (`.github/workflows/flutter-ios-ipa.yml`, macOS runner) runs `flutter
analyze`, `flutter test`, verifies `PRODUCT_BUNDLE_IDENTIFIER =
com.ahmed.btmu`, and builds an **unsigned** IPA (`btmu-2.00-unsigned.ipa`) as
a check artifact. No signed IPA is built. It runs on pushes and pull
requests touching `flutter_app/**`.

## Release sequencing — DECISION (Ahmed, 2026-11-22)

**The final deliverable is a REGULAR UNSIGNED IPA. No Apple signing secrets
are needed and no signed IPA will be pursued.**

- CI checks (`flutter analyze`, `flutter test`) may run on PRs along the way —
  they are checks, not releases.
- Do NOT treat any early CI IPA artifact as the release, and do NOT push for a
  release build mid-way through the phases.
- The final unsigned IPA (`btmu-2.00-unsigned.ipa`) is built at the END, after
  all phases are complete and their gates pass.
- Install via sideloading (AltStore / Sideloadly / TrollStore).

### React / Capacitor reference app

```bash
npm install
npm run dev        # web dev server
npm run build      # production bundle -> dist/
npx cap sync ios   # regenerate ios/App/App/public/
```

`server.ts` needs a Node host (it is not a static site). Copy `.env.example`
to `.env` and fill in the backend URLs; never invent a backend URL.

## Testing — what is verified and what is not

- 12 Dart unit tests exist (`flutter_app/test/`). No test run has been recorded
  yet in this repo; CI runs them on every PR.
- `BttMusic` (SwiftUI) is the only sibling repo with any test evidence, and
  even there audio output was never verified on a device.
- **Nothing about background audio, lock-screen controls, AirPods, the 300%
  boost, or Files import is verified on a physical iPhone yet.** The required
  device pass (iPhone XS Max, iOS 18+): lock mid-song, skip from the lock
  screen, let a track end while locked, AirPods play/pause/next/previous,
  booster on and off. Do not mark these complete until that pass happens.

## Blockers (need Ahmed)

1. **Physical iPhone test** — the device pass above.
2. **Credentials** (all optional, all server-side or Keychain-only): Spotify
   developer app, SoundCloud client id, Jamendo client id, Telegram bot token.
3. **X2 backend deployment** (`X2_BACKEND_URL`) — a Node host for `server.ts`.
   Without it the Piped/Invidious relay and CORS-free proxy paths report
   "Not Configured".
4. **Logo check** — confirm the BT monogram mark (bold "BT" in
   violet→magenta→pink-red gradient, white play button inside the B, on
   black) is the artwork in `flutter_app/assets/images/app_logo.png`,
   `public/app-logo.png`, and the app icons before release.
   (Superseded 2026-11-22: the old Triforce mark is retired; the new BT
   monogram binaries must land at every logo path, including
   `public/app-logo.png` and the PWA icons.)

No Apple signing secrets are needed: the release is a regular unsigned IPA
(see Release sequencing above).

## Lineage

```
Bt-music-  (Oct 25, 2026)   genesis PWA snapshot
  └─ Btmus-3  (Oct 27–Nov 5)  shipped 1.8.0
       └─ iOS-btmus  (Nov 5)  + Capacitor 8 + iOS shell + audio bridge
            └─ Iosbtmus2  (Nov 7–15)  + flutter_app/ + X2 backend + SSRF guards
                 └─ btmuse-3.0  (Nov 22)  this repo — Btt Music 2.00

BttMusic (Nov 10–11) — parallel native SwiftUI rebuild (reference only)
```

Historical repos (`Btmus-3`, `iOS-btmus`, `Bt-music-`) are references; do not
build from them. `Btt1996/Btt-music` does not exist — do not reference that
URL. `BttMusic-X2` is an empty placeholder.

## Workflow

Work happens on development branches with pull requests into `main`. Never
force-push over `main`. Commits are logical groups with meaningful messages.
Every PR lists architecture decisions, features completed, tests performed,
known limitations, and build results.
