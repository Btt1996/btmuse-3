# Feature Inventory + Quarantine Audit — Btt Music 2.00

- Repo: `Btt1996/btmuse-3.0`, branch `seed/iosbtmus2-2.00`
- Canonical app: Flutter under `flutter_app/` — React/Capacitor under `src/` is reference/fallback.
- Audit date: 2026-11-22. Method: line-level read of every Flutter feature screen and every
  React screen/modal named below (plain viewing only; no build, test, or git command run).
  Repo-wide text search was used read-only to confirm `allorigins` / `spotdl` occurrences.
- Scope: Phase 0 item 5 — quarantine the SpotDL bridge UI until its legality is audited,
  remove the `allorigins.win` CORS-proxy fallback (server-side path only), and audit every
  screen for nonfunctional/stub controls.

## Summary counts

38 rows audited (18 Flutter + 20 React) — 35 at the Phase 1 audit, +3 new
Flutter rows in the Phase 6 update (F16 playback history, F17 update
checking, F18 storage/duplicates). F5 moved partial → implemented and
R20 moved missing → implemented in Phase 6; see the Phase 6 update
section at the end.

| Status | Flutter | React | Total |
|---|---|---|---|
| implemented | 15 | 13 | **28** |
| partial | 3 | 5 | **8** |
| missing | 0 | 0 | **0** |
| stub-or-dead (incl. quarantined-by-design) | 0 | 2 | **2** |

Definitions: **implemented** — the control does what its label promises, end to end as read.
**partial** — mostly works but has a dead path, misleading label, or an unverified sub-behavior.
**missing** — a named capability has no UI at all in that app. **stub** — a control that does
nothing, only shows a message, or (here) is intentionally disabled by quarantine.

## Flutter (canonical) — `flutter_app/lib/`

| # | Feature / screen | File(s) | Status | Evidence |
|---|---|---|---|---|
| F1 | App shell + bottom nav (6 tabs: Home, Library, Import, X2, X1, Playlists) | `lib/app/app.dart` | implemented | `AppShell` IndexedStack + `NavigationBar`; tab state via `currentTabIndexProvider`. Search/Settings/Downloads are pushed routes, not tabs — by design, not a gap. |
| F2 | Home | `features/home/home_screen.dart` | implemented | Engine cards navigate to X1/X2/Telegram/SmartRemix/Import; Recently Played + Recent Additions play via `audioHandler.setTrackQueueAndPlay`; favorite toggle invalidates library provider; empty state offers Import Center / Explore X2. Phase 6: Recently Played header now has a "See all" button opening the Playback History screen (`PlaybackHistoryScreen` via `BttPageRoute`). |
| F3 | Library + metadata editor | `features/library/library_screen.dart`, `metadata_editor_sheet.dart` | implemented | FilePicker import (mp3/m4a/aac/flac/wav/ogg) via `importFileIntoLibrary`; search filter; Tracks/Favorites/Artists/Albums segments; edit metadata (title/artist/album/genre, saved via repo), add-to-playlist, delete. Storage stats + duplicate count shown. |
| F4 | Import Center (+ VK / YouTube / SoundCloud / Direct-URL sheets) | `features/import_center/import_center_screen.dart` | **partial** | Local single + batch import implemented with progress + per-file failure reporting. YouTube sheet assigns `searchTracks` results; Direct-URL sheet verifies MIME/magic bytes and RSS enclosures. **STUB (2):** `_VkImportSheetState._runVkLookup` calls `await vk.searchTracks(input)` and **discards the return value** — keyword search with no token shows nothing. `_SoundCloudImportSheetState._lookup` does the same with `await sc.searchTracks(q)`. URL-resolve paths in both sheets do assign results and work. Fix (other worker / Flutter owner): assign the returned list to `_results`, or disable the keyword path with an honest label. Code NOT changed in this pass — Flutter files outside the inventory are out of scope for edits. |
| F5 | Player (MiniPlayer + FullScreenPlayer) | `features/player/mini_player.dart`, `full_screen_player.dart` | implemented | Play/pause, next/prev, seek slider, shuffle, repeat none/all/one, favorite toggle, Boost % + Smart Remix shortcuts all wired to the audio handler. **Phase 6 verified (was partial — lyrics gap now closed):** the Player/Lyrics tab shows synced LRC with active-line highlight, auto-scroll and tap-to-seek; plain-lyrics fallback; cache via `LyricsCacheStore` (SQLite `lyrics_cache`, tests inject an in-memory fake). 17 gaps closed in Phase 6: offline vs "not catalogued" are now distinct states (Dio `receiveTimeout`/`sendTimeout`/`unknown` = offline), retry forces a refresh (`forceRefresh`), search results are title-matched so the wrong song is not returned, plain-only lyrics no longer mislabelled "(Synced)", forced refresh while offline falls back to stale cache, fast track skips cannot show a stale track's lyrics (generation guard), scroll offset does not carry to the next track, scroll-resume dead end fixed, title regex now also strips "(Official Lyric Video)". Device check of highlight timing / auto-scroll feel / tap-to-seek still awaits Ahmed's iPhone XS Max. |
| F6 | Playlists + detail | `features/playlists/playlists_screen.dart`, `playlist_detail_screen.dart` | implemented | Create (name + description), delete, open detail, play-all, per-track remove. Note (not a stub): detail-screen remove has no confirmation dialog, unlike React which confirms deletes. **Phase 6: playlist import/export added** — own versioned format (`btmu-playlist` v1, distinct from backup v2; a test proves a backup document is rejected), JSON + M3U, SHA-256-first then `title\|artist` matching, `PlaylistImportResult` accounts for every entry (added/duplicates/missing/skipped — no silent drops), name collisions get a `" (imported)"` suffix, existing playlists never overwritten; export menu on the detail screen, import on the playlists screen, always-shown summary dialog. |
| F7 | Universal Search | `features/search/search_screen.dart` | implemented | Local library filter + online X2 search on submit; per-provider error box; 30s preview play/stop via `just_audio`; authorized download queues via download manager; metadata-only results hand off to X2 tab. |
| F8 | Settings | `features/settings/settings_screen.dart` | implemented | App identity card, Audio/Telegram/Downloads navigation, X2 backend + Piped + Invidious + auth-token fields persisted to the credentials store, Save + Test Connectivity with a live diagnostics card, storage footprint display. No SpotDL field exists in Flutter settings. Jamendo client-ID field added in Phase 5 (Keychain). **Phase 6: update-check card added** — checks GitHub releases via `UpdateService` (states: up-to-date / available / offline / error / no-releases; GitHub 404 honestly reported as "no releases yet"), honest copy "iOS cannot self-update — sideload the new unsigned IPA", Copy Release Link button; no fake install button (`url_launcher` is not a dependency). |
| F9 | Audio Settings (Extreme Boost) | `features/audio_settings/audio_settings_screen.dart` | implemented | 100–300% slider + presets, DSP gain/limiter readout via `VolumeDspMath`, soft-knee limiter + normalization switches, EQ preset chips — all applied through `handler.applyAudioSettings`. Clipping/hearing warnings shown conditionally. |
| F10 | Downloads + manager | `features/downloads/download_history_screen.dart`, `download_manager_provider.dart` | **partial** | Queue/cancel/clear-finished/progress/stage text all wired; acquisition validates content-type, size, and audio header before import. **STUB:** `retryTask` only retries when the payload is still in the in-memory `_queuedPayloads` map; a failed task restored from persisted history after an app restart has no payload, so **Retry silently does nothing**. Fix: persist the payload (or hide/disable Retry for restored tasks). Code NOT changed in this pass. |
| F11 | Smart Remix | `features/smart_remix/smart_remix_screen.dart`, `smart_remix_engine.dart` | implemented | **Phase 6 verified and fixed (old evidence was stale — the crossfade 2–14s and enable toggle were removed in Phase 3):** 6 mix modes — smooth, party, chill, energy, random, and **arcMix** (added Phase 6: the full warm-up → build → peak → cooldown Λ arc; ascending energies to the peak, then descending; persisted by name with a smoothMix fallback). **Save mix as playlist added** — name prompt (default `Smart Mix — <Mode>`), `createPlaylist` + sequentially-awaited `addTrackToPlaylist` (order preserved via `MAX(position)+1`), success/error snackbars. **Measured path verified:** `indexTrackAudio` (called on every import via `importFile`, plus `X1Service.indexAllLibraryTracks`) → `analyzeTelemetry` → `bpm`/`energy_score`/`is_analysis_estimated=0`; measured path requires bpm + energyScore present AND `!isAnalysisEstimated`, otherwise the disclosed genre/duration heuristic with "Est." (plan preview now prefixes `~` on estimates only). **Real defect fixed in Phase 6:** the old tempo estimator returned a bogus 171.4 BPM for steady sine/noise/silence and stored it as measured — now mean-removed, overlap-normalised autocorrelation with CV ≥ 0.25 and peak ≥ 0.30 gates returns 0 ("no tempo") for non-percussive audio; burst trains 90–160 BPM still accurate (±~2 BPM, port-measured). **Second defect fixed:** the WAV fallback decoded any sample rate as 11,025 Hz (4×-wrong tempo for 44.1 kHz WAVs) — now rate-guarded. Limits documented: 65–171 BPM range, above-range folds to half-time, no octave disambiguation; real-song BPM accuracy unmeasured — device gate. Launch plays the computed order. |
| F12 | Telegram Sync | `features/telegram/telegram_screen.dart`, `telegram_service.dart` | implemented | Bot token from iOS Keychain, `getMe` verification, audio-message scan, per-file download with progress + cancel, 20 MB Bot API limit flagged with a block icon instead of a dead download button. |
| F13 | X1 Recognition | `features/x1/x1_screen.dart`, `x1_service.dart`, `local_fingerprint_engine.dart` | implemented | Mic capture (8s auto-stop), local FFT constellation match against the indexed library, rebuild-index action with count, local-clip file pick, open-catalog verification (MusicBrainz/Deezer/iTunes) with 30s previews, "Find this song in X2" handoff. Minor nit (not a stub): the post-index snackbar reads `_indexedCount` before the refreshed count lands, so it can show the stale count. **Phase 6: engine internals now line-audited and hardened** — the matcher enforces a runner-up margin (best must beat the runner-up by gap ≥ relative floor AND ratio ≥ 1.5): the documented near-coincident chord [180,310,590,990] is now rejected, while the synthetic recall gates keep 23+ hashes of headroom on the worst gated case and white-noise rejection is preserved (noise best 12 vs floor 31). Tempo display hides the tempo when the estimator returns 0 (no-tempo) instead of showing "Tempo ~0 BPM". Open limitation, documented in `docs/x1-recall.md`: a chord sharing one sustained partial + its 1.5× harmonic under identical FM still false-positives (no margin can fix that without killing true recall). Synthetic recall is not real-song recall — device gate (real songs on Ahmed's iPhone XS Max) still open. |
| F14 | X2 Acquisition | `features/x2/x2_screen.dart`, `x2_search_engine.dart`, `x2_acquisition_engine.dart`, `providers/` (8), `clients/` | implemented | Parallel provider search with 9s timeout, per-provider errors, URL lookup with authorized-source handoff, filters (All/Authorized/Metadata), 30s previews, authorized-only download (throws `AuthorizationFailure` otherwise), content-type/size/audio-header validation, temp-file cleanup on failure. Providers: VK, YouTube, SoundCloud, Spotify-metadata, Audius, Deezer, iTunes-metadata, Direct URL. **No SpotDL anywhere in Flutter** (repo-wide search confirms zero hits). Flutter has no X2 benchmark modal; connectivity diagnostics live in Settings instead — accepted difference, not a gap. |
| F15 | App widgets / theme / providers | `lib/app/widgets/` (`btt_artwork`, `btt_logo_mark`, `track_tile`), `lib/app/theme/`, `lib/app/providers/app_providers.dart` | **partial** | Wired and rendered by every screen read (imports + usage verified); providers register all 8 X2 providers, download manager, X1/Telegram services. **Verification gap:** widget/theme sources were not line-read in this pass. |
| F16 | Playback history + Recently Played | `features/history/playback_history_screen.dart` (new, Phase 6), `features/home/home_screen.dart` | implemented | **Added in Phase 6.** Full history list ordered by `lastPlayedAtMs` desc, tap-to-play, "played X ago · played Nx", confirmed Clear that nulls only `last_played_at_ms` — play counts are kept because duplicate-keeper ranking depends on them (`LibraryRepository.clearPlaybackHistory()`). Verified `recordPlayback` fires on every real play path (`btt_audio_handler.dart:727` play start, `:824`/`:847` both crossfade paths) and never on resume/seek/missing files. Home's Recently Played section ("See all" → this screen) uses the same `lastPlayedAtMs != null` filter. |
| F17 | Update checking (GitHub releases) | `core/services/update_service.dart` (new, Phase 6), `features/settings/settings_screen.dart` | implemented | **Added in Phase 6.** `UpdateService` (Dio, no new dependency) `GET …/releases/latest` with numeric version compare; states up-to-date / available / offline / error / no-releases — GitHub 404 honestly reported as "no releases yet", never invented. Settings card only, honest copy "iOS cannot self-update — sideload the new unsigned IPA", Copy Release Link button; no fake install button. |
| F18 | Storage management + duplicate scanning | `features/settings/storage_dashboard.dart`, `data/repositories/library_repository.dart` | implemented | **Verified complete in Phase 6, no change needed.** Re-scan button, all delete/cleanup buttons wired, storage totals consistent, missing-file cleanup present (Phase 4 `deleteMissingFileEntries()` + confirmed-only "Remove N missing entries"). Duplicate scan with suggested keeper (most-played wins) and confirmed-only deletion. |

## React (reference/fallback) — `src/`

| # | Feature / screen | File(s) | Status | Evidence |
|---|---|---|---|---|
| R1 | Home + Onboarding | `components/screens/HomeScreen.tsx`, `OnboardingView.tsx` | implemented | Recently Played / Favorites / Recently Downloaded carousels, Smart Synchro run with live status, Smart Mix drawer, Import modal, library metrics, online/offline badge. Empty library shows Onboarding with 4 working actions (Telegram sync, file import, demo pack, DB restore). Fixed 2026-11-22 (premium redesign): Onboarding badge now reads v2.00; header brand is "Btmus by Taboubi Ahmed" with the BT monogram gradient accent. |
| R2 | Library | `components/screens/LibraryScreen.tsx` | implemented | Search (title/artist/album/file/key/BPM), filters (all/favorites/telegram/analyzed), 7 sort orders, multi-select batch analyze + delete, duplicates scan, per-track menu (queue, play next, add to playlist, info, delete with confirm). |
| R3 | Search (unified) | `components/screens/SearchScreen.tsx` | implemented | Unified search across YouTube/Spotify/SoundCloud/Telegram/local/Open-CC with source tabs + counts, Spotify playlist detection banner, preview playback, per-track download with progress state machine, history + Telegram Hub modals. Non-local "Add to Queue" honestly toasts "Download track first" instead of pretending to queue. |
| R4 | Playlists + detail | `components/screens/PlaylistsScreen.tsx`, `PlaylistDetailView.tsx` | implemented | Create, import, rename (inline), delete (confirmed), play-all, shuffle, reorder (up/down), remove track, Smart Mix optimize. |
| R5 | Sync & Import | `components/screens/SyncScreen.tsx` | implemented | 5 tabs: Spotify inspector entry, Telegram bot connect + scan + selective download, manual file import with source tag + auto-playlist, DB import/export (incl. Web Share fallback), privacy/iOS guide. Demo-pack generator creates clearly-labeled synthetic tone tracks. **Phase 6: "Browse a Spotify user's public playlists" section added** — input → `discoverUserPlaylists` (Phase 5 `/api/spotify/user` route) → list with cover art, owner, track counts → tap opens the existing Playlist Inspector via `initialUrl`; states: loading, not-found, private-or-empty, error/degraded with the server message verbatim; metadata-only copy. |
| R6 | Settings | `components/screens/SettingsScreen.tsx` | implemented | Update check/apply, 3 palette combos, volume booster + presets, Smart Mix config + library analysis, storage quota meter, duplicates scan, DB export/import, offline playback audit, clear-all-data (confirmed). The **"spotDL Evaluation" button now opens the quarantined modal** (honest unavailable notice) — see Quarantine decisions. **Phase 6:** update checks that fail now show an error banner (message + retry) instead of failing silently; a manifest with no `version` no longer silently reads as "latest". Note: the React update check queries the served `/api/version` manifest, not GitHub releases — switching is a coordinator decision (rate limits, what "update" means for a served PWA). |
| R7 | Full-screen player | `components/player/FullScreenPlayer.tsx` | implemented | Play/pause/next/prev, seek scrubber (mouse + touch), shuffle/repeat, favorite, add-to-playlist, queue, Smart Mix, lyrics toggle, circular volume dial, "Open in App" share/download fallback. |
| R8 | Mini player | `components/player/MiniPlayer.tsx` | implemented | Play/pause/next, progress line, booster + Smart Mix badges, opens full player on tap, hidden while full player is open. |
| R9 | Lyrics | `components/player/LyricsView.tsx` | implemented | LRCLIB synced lyrics with tap-to-seek + auto-scroll, plain-lyrics fallback, retry; honest "not yet catalogued on LRCLIB" empty state. **Phase 6 verified:** offline vs "not catalogued" are now distinct states (`LyricsFetchStatus` + `getLastLyricsFetchStatus()`), retry forces a refresh (`forceRefresh` param), search results are title-matched so the wrong song is not returned, plain-only lyrics no longer mislabelled "(Synced)", forced refresh while offline falls back to stale cache, scroll-offset carry-over to the next track fixed, footer tap-to-seek hint only for synced lyrics, mic icon contrast fixed on the gradient chip. |
| R10 | Playlist Import modal (X1/X2) | `components/import/PlaylistImportModal.tsx` | **partial** | 4-step wizard (URL → preview → live per-track pipeline → summary) with threshold slider, provider toggles, per-track retry + manual match confirm, Spotify credentials drawer. **Issues:** (a) **"SoundCloud Ready" badge is misleading** — the X2 import pipeline (`x2Engine`) has no SoundCloud adapter (Jamendo/Archive/FMA/Telegram/SpotDL/local only); (b) the spotDL row's "Configured / Needs Host" badge can still read a stale `localStorage` URL and its Architecture button now opens the quarantined notice — the flow is honestly dead-ended, but the row should be disabled/cleaned by the coordinator (file not rewritten here: reproducing the ~1,100-line modal verbatim risked transcription errors; the quarantine modal blocks the path). |
| R11 | Spotify Playlist Inspector | `components/import/SpotifyPlaylistReviewModal.tsx` | implemented | URL fetch via `x1Spotify`, per-track local-cache check, select/exclude, filters, individual + batch download via `x2Engine`, candidate inspector, playlist save with preserved order. |
| R12 | Telegram Discovery modal | `components/import/TelegramDiscoveryModal.tsx` | **partial** | Connect/verify/scan/download paths are implemented. **STUB (misleading demo data):** `PREVIEW_PUBLIC_CHANNELS` is a hardcoded fabricated catalog (e.g. "Neon Nights" by "CyberSound", "Clair de Lune") presented under "Discoverable Public Audio Samples". The rows are not real discoverable audio; their only action switches to the Connect tab. Fix: remove the fake catalog or label it explicitly as sample/demo data. This directly contradicts the "Zero Mocks" claim made by the X2 benchmark UI. |
| R13 | X2 Benchmark modal | `components/import/X2BenchmarkModal.tsx` | implemented | Runs `runX2Benchmark` (6 real tracks, live provider search, stream probe, blob validation) with per-track breakdown; copy quarantined — see Quarantine decisions. Pre-existing unused imports (`Download`, `RotateCcw`, `ExternalLink`, `CheckCircle2`) left as-is. |
| R14 | SpotDL info modal | `components/import/SpotDLInfoModal.tsx` | **stub** (quarantined by design) | Was a 3-tab modal with bridge-URL input + "Test & Save". Now renders an honest unavailable state with no input, no test, no save — see Quarantine decisions. |
| R15 | Player chrome + common modals | `player/QueueModal.tsx`, `SmartMixDrawer.tsx`, `VolumeControl.tsx`, `CircularVolumeDial.tsx`, `AddToPlaylistModal.tsx`, `BttPlaybackAnimation.tsx`, `navigation/BottomNav.tsx`, `common/{ConfirmModal,DuplicatesModal,MusicHistoryModal,PWAInstallModal,SplashScreen,Toast}.tsx`, `screens/TrackDetailModal.tsx` | **partial** | **Verification gap:** these files were not line-read in this pass; status rests on call sites only — every one is opened from a real handler with real props (e.g. `QueueModal`/`SmartMixDrawer` from `FullScreenPlayer`, `AddToPlaylistModal` from Library/Player, `DuplicatesModal` from Library/Settings, `MusicHistoryModal` from Search/Sync). No empty-handler or dead-button signal was found in the repo-wide grep for `TODO|FIXME|coming soon|not implemented` or empty callbacks (zero hits in `src/` + `flutter_app/lib/`). Close the gap by line-reading these before the gate, or explicitly accept for the reference app. **Phase 6:** `MusicHistoryModal` gained a `playback` filter tab + Play icon + play button for playback records, and `recordPlaybackHistory` — which had zero callers — is now called from `MusicContext.playTrack` after a track starts playing successfully (library tracks only; streaming previews are not recorded, so every playback record stays playable from history). |
| R16 | Spotify playlist resolution (X1) | `services/playlistImport/x1Spotify.ts` | **partial** | `parseSpotifyTarget` / `parseSpotifyPlaylistId` unchanged and correct. `fetchSpotifyPlaylist` now server-side only — `allorigins.win` fallback removed (see Quarantine decisions). Spotify metadata resolution is therefore unavailable when the server is down; the error now says so explicitly instead of silently proxying. |
| R17 | Spotify user/playlist discovery | `services/playlistImport/spotifyDiscoveryService.ts` | **partial** | `parseSpotifyUserId` unchanged. `discoverUserPlaylists` now server-side only — `allorigins.win` embed-scrape fallback removed; server failure now throws an explicit error instead of returning an empty playlist list with just a profile link. **Phase 6 corrections:** the old "canned presets" claim is wrong — `searchSpotifyPlaylists` returns `[]` + a warning, not static presets (comment fixed); `discoverUserPlaylists` now has a UI caller (SyncScreen "Browse a Spotify user's public playlists" section, Phase 6). Still partial: `searchSpotifyPlaylists` is a stub returning `[]` — that is placeholder data, not live search; flag for a later pass, not a gate blocker for the reference app. |
| R18 | SpotDL bridge | `services/playlistImport/spotdlBridge.ts` | **stub** (quarantined by design) | Was a live bridge: `GET {url}/health` + `POST {url}/api/match`. Now every public function is a no-op returning an explicit unavailable result — see Quarantine decisions. File kept (not deleted) so imports keep compiling. |
| R19 | X2 engine + benchmark service | `services/playlistImport/x2Engine.ts`, `x2Benchmark.ts` | implemented | Provider pipeline (local cache → SpotDL → Telegram → Jamendo → Archive → FMA) with confidence scoring, retry, per-track import + single-track resolve. **No code change needed:** with the quarantined bridge, `searchSpotDLBridge` returns `null`, so Step 2 records a `no_match` attempt and the pipeline continues. `x2Benchmark` inherits this automatically; its "requires self-hosted spotDL bridge" diagnostic note is now stale wording for commercial tracks (it still correctly reports 0 matches) — reword when the benchmark copy is next touched. `downloadAndValidateAudio` already falls back to the **server-side** `/api/audio-proxy` on direct-fetch CORS failure — that is the sanctioned server path, not a third-party proxy, and was left untouched. |
| R20 | Downloads history (React) | `services/historyService.ts`, `components/common/MusicHistoryModal.tsx` | implemented | **Phase 6 correction — was "missing" (stale since Phase 5):** React downloads history IS persisted — `recordDownloadHistory` (Phase 5, per-track X2 + bridge imports) + `MusicHistoryModal` render it, and Phase 6 added playback records (`recordPlaybackHistory`, now called from `MusicContext.playTrack`) with a `playback` filter tab and play buttons. The Phase 1 "reference-only" disposition is superseded by the implementation. |

## Quarantine decisions (code changes delivered with this audit)

All files are under `~/workspace/btmu-2.0/work/phase1/inventory-quarantine/`, mirroring
repo-relative paths. Complete file contents, not diffs. No new dependencies, no new URLs,
no invented credentials. `server.ts` untouched; the server-side Spotify/audio-proxy paths stay as-is.

1. **`src/services/playlistImport/spotdlBridge.ts`** — quarantined, file kept.
   - Header comment states the quarantine (Phase 0 item 5), the reason (spotDL is a
     Spotify→YouTube downloader concept; downloading from YouTube violates YouTube's ToS and
     ripping commercial tracks violates Spotify's ToS; Spotify streams are DRM-protected), and
     that re-enabling requires a legal audit.
   - `checkSpotDLBridgeStatus()` no longer fetches anything; always returns
     `{ isConfigured: false, isOnline: false, errorMessage: <explicit "unavailable — under legal review" message> }`.
   - `searchSpotDLBridge()` no longer fetches anything; always returns `null` (its existing
     "no match" signal), so the `x2Engine` SpotDL step records `no_match` and continues.
   - Exports, interface, and signatures unchanged, so all existing importers compile.
2. **`src/components/import/SpotDLInfoModal.tsx`** — quarantined UI, same props.
   - No URL input, no "Test & Save", no tabs, no bridge-status probe, no hosting instructions
     for running a spotDL server. Renders an honest "Unavailable — under legal review" state,
     the reason in plain language, and what still works (Telegram Hub, local files, Jamendo /
     Internet Archive / FMA open catalogs). Single Close/Done button only.
   - `bridgeUrl` / `onSaveBridgeUrl` props are retained so `SettingsScreen` and
     `PlaylistImportModal` compile unchanged; `onSaveBridgeUrl` is never invoked while quarantined.
3. **`src/components/import/X2BenchmarkModal.tsx`** — copy quarantine (one paragraph).
   - The limitations box no longer tells the user to "connect a self-hosted spotDL
     microservice in Settings". It now points only at the Telegram Audio Hub and importing
     audio they own, and states the spotDL bridge is unavailable while under legal review.
   - The benchmark itself is untouched; it runs through `searchAllX2Providers`, which now
     skips SpotDL via the quarantined bridge.
4. **`src/services/playlistImport/x1Spotify.ts`** — `allorigins.win` removed.
   - The entire client-side fallback block (fetch via
     `https://api.allorigins.win/raw?url=…open.spotify.com/embed/…`, `__NEXT_DATA__` scrape) is
     deleted. Resolution goes through `POST /api/spotify/playlist` only.
   - Server failure (HTTP error, empty/invalid payload, or network error) now throws an
     explicit "Spotify resolution server unavailable" error (server-provided `details`/`error`
     still surface when present). On native builds, where the server path was never attempted,
     it throws an explicit "requires the btmu server" error instead of the old misleading
     "ensure the playlist is Public" message. No third-party proxy is consulted anywhere.
5. **`src/services/playlistImport/spotifyDiscoveryService.ts`** — `allorigins.win` removed.
   - The embed-scrape fallback in `discoverUserPlaylists` (same `allorigins.win` pattern) is
     deleted. Server path (`/api/spotify/user`) only; any server failure throws an explicit
     "Spotify discovery server unavailable" error. Native builds throw an explicit
     server-required error. The previous silent fallback (return an empty playlist list with
     only a profile link) is gone.
   - Repo-wide search confirms these were the **only two** `allorigins.win` uses in `src/` and
     `flutter_app/lib/`, and no other third-party CORS proxy (`corsproxy`, `thingproxy`,
     `cors-anywhere`, `codetabs`, etc.) exists in either tree.
6. **Other stub-button decisions.**
   - Flutter VK/SoundCloud keyword search (F4) and Flutter download retry-after-restart (F10):
     **not modified** — Flutter files outside the inventory are out of scope for edits. Fixes
     are specified in the table above for the Flutter owner.
   - `PlaylistImportModal` spotDL row + Settings "spotDL Evaluation" button: **not modified**.
     Both open the quarantined modal, which now honestly explains unavailability, so neither is
     a dead control. Remaining cleanup (disable the row, drop the stale-`localStorage` "Configured"
     badge) is listed as a gate follow-up, not done here, to avoid rewriting the ~1,100-line modal.
   - No other stub/dead buttons were found: repo-wide grep for `TODO|FIXME|coming soon|not
     implemented` and for empty handlers returned zero hits in the audited trees (the only
     "not yet" hit is the honest LyricsView "not yet catalogued on LRCLIB" empty state).
   - Nothing was wired to invented behavior. The `TelegramDiscoveryModal` fake preview catalog
     (R12) and the `PlaylistImportModal` "SoundCloud Ready" badge (R10) were **not** silently
     fixed; they are recorded here as gate items for the owning worker/coordinator to disposition.

## Known follow-ups / things NOT changed

- Stale `localStorage` keys (`btt_spotdl_bridge_url`, used by `SettingsScreen` /
  `PlaylistImportModal` / `X2BenchmarkModal` settings) are not cleared by this change. With the
  quarantined bridge they can no longer cause a download, but `SettingsScreen` still passes
  `enableSpotDLBridge: !!spotDLBridgeUrl` into benchmark settings and `PlaylistImportModal`
  can still show a "Configured" badge from a stale value. Recommend a later pass that removes
  the key on load or drops the fields — coordinator decision, not taken unilaterally.
- `src/types/playlistImport.ts` still declares `AudioProviderType` including `'spotdl'` and
  `ImportSettings.enableSpotDLBridge` / `spotDLBridgeUrl` (default `false` / `''`). Left
  untouched: the quarantined bridge needs the type to keep compiling, and removing the
  settings fields is a schema decision for the coordinator. `x1Identification.ts` mentions
  spotDL only in a header comment ("Replaces legacy spotDL…") — comment only, no action.
- `x2Benchmark.ts` diagnostic copy still says commercial tracks "require self-hosted spotDL
  bridge or Telegram bot sync hub" and its summary notes repeat the point. Behavior is correct
  (0 matches, honest failure category); reword the copy when the benchmark text is next touched.
- `searchSpotifyPlaylists` canned presets (R17) and React's missing downloads-history screen
  (R20) are recorded, not fixed — both are reference-app-only concerns.

## Phase 1 gate verdict — NOT YET PASSING

The quarantine itself (this delivery) closes Phase 0 item 5's code requirements, but the gate
must stay closed until:

1. The five quarantined files in this delivery are merged (coordinator pushes).
2. F4 — Flutter VK + SoundCloud keyword search: assign results or disable with an honest label.
3. F10 — Flutter download retry after restart: persist the payload or disable Retry for
   restored tasks.
4. R12 — `TelegramDiscoveryModal` fabricated preview catalog: remove or explicitly label as demo.
5. R10 — `PlaylistImportModal`: correct the "SoundCloud Ready" badge; disable/clean the spotDL
   row and stale `localStorage` URL handling.
6. F5 — Flutter player lyrics gap: add a lyrics view or explicitly defer (lyrics worker owns).
7. R15 — line-read the remaining player/common components, or explicitly accept the
   call-site-only verification for the reference app.
8. R20 — React downloads history: add, or explicitly disposition as reference-only.

Cosmetic / non-blocking: X1 index snackbar stale count (F13),
`x2Benchmark.ts` spotDL wording, `PlaylistDetailScreen` (Flutter) remove-without-confirm.

## Coordinator dispositions (2026-11-22, added on review — not part of the audit itself)

- **Item 6 (F5, Flutter lyrics gap): RESOLVED.** The lyrics port landed on this
  branch as commit `eb73f2a` ("feat(flutter): port lyrics from React path") —
  LRCLIB service + synced view + Player/Lyrics tab in the fullscreen player.
- **Items 2–5 (F4, F10, R12, R10): FIXED in the follow-up gate-fix commit on
  this branch** (after the quarantine merge): F4 is honest copy in the VK /
  SoundCloud import sheets (keyword search needs a token / is unavailable —
  the providers throw an informative error that the UI already displayed; the
  sheets now say so before submit instead of only after); F10 adds
  `DownloadManagerNotifier.canRetry` and disables Retry for tasks restored
  from a previous session; R12 relabels the Telegram preview catalog as demo
  data; R10 corrects the "SoundCloud Ready" badge to "SoundCloud Metadata
  Only" and the spotDL row to a static "Unavailable — legal review" badge.
- **Item 7 (R15): ACCEPTED.** Call-site-only verification for the reference
  app's player/common modals is accepted for the reference app; the canonical
  Flutter player was line-read. No further action.
- **Item 8 (R20): DISPOSITIONED as reference-only.** React has no persisted
  downloads-history screen (session-scoped tasks only); Flutter has
  `DownloadHistoryScreen` backed by `HistoryRepository`. Acceptable: the React
  app is the fallback, not the shipped app. No code added.
- **Stale `btt_spotdl_bridge_url` key (see "Known follow-ups"):** left in place
  for a later pass — the quarantined modal/row no longer reads it for any
  decision or badge, so it cannot mislead or cause a download. Do not silently
  delete stored user data without that pass.
- **Gate verdict after these dispositions: PASSING for Phase 1**, subject to CI
  green on the branch (`flutter analyze` + `flutter test`) once the fixed
  workflow lands. The remaining non-gate items (R1 badge, F13 snackbar,
  `x2Benchmark.ts` copy, Flutter playlist-detail remove-without-confirm) are
  cosmetic and stay open as follow-ups.

## Phase 6 update (2026-11-22, coordinator — items 25–27)

Four workers (lyrics, smart-remix/X1-margin, Flutter features, React parity)
verified items 25–27 line-by-line; the coordinator integrated, added the
`arcMix` mode, the X1 tempo hide-when-0 fix, the Home "See all" wiring, the
`LibraryRepository.clearPlaybackHistory()` move, and the `MusicContext`
`recordPlaybackHistory` call, then rebuilt the web app. Row changes are
inline above (F2, F5, F6, F8, F11, F13, F16–F18 new, R5, R6, R9, R15, R17,
R20). Counts are now 38 rows: 28 implemented, 8 partial, 0 missing,
2 stub-or-dead (both quarantined-by-design SpotDL rows, R14/R18).

- **Item 25 (Lyrics): VERIFIED, gaps closed** — 17 gaps across Flutter +
  React (see F5/R9). Pre-existing quirks deliberately left unchanged (both
  apps): LRC timestamps require two-digit minutes; 4-fraction-digit
  timestamps leave a stray `6]`; no cache TTL.
- **Item 26 (Smart Remix): VERIFIED + FIXED** — measured BPM/energy path is
  real (`indexTrackAudio` → `analyzeTelemetry`); two real defects fixed (bogus
  171.4 BPM for steady signals stored as measured; WAV sample-rate fallback).
  Save-as-playlist added; `arcMix` (full Λ arc) added by the coordinator
  because no mode produced it. See F11.
- **Item 27 (history / playlists / update / storage / duplicates):
  IMPLEMENTED** — playback history (F16), playlist JSON/M3U import-export
  (F6), GitHub-releases update checking (F17), storage/duplicates verified
  complete (F18). React parity: `discoverUserPlaylists` wired to SyncScreen
  (R5/R17), playback records now recorded (R15/R20).
- **Phase 5 open items closed:** X1 false-positive margin implemented (F13);
  React `discoverUserPlaylists` has a UI caller (R5). Still open as known
  limits (not Phase 6 scope): `/api/spotify/user` returns first 50 playlists
  only (no pagination); Jamendo `resolveUrl` supports track pages only;
  Archive.org search not collection-scoped. Per-playlist export/import does
  not exist in React (whole-library DB export only) — needs a format decision;
  natural home `PlaylistDetailView.tsx`. React update check queries the served
  `/api/version` manifest, not GitHub releases — switching is a coordinator
  decision. Mid-loop save-as-playlist failure can leave a partial playlist;
  a transactional playlist insert is a follow-up. Server version drift
  flagged: `server.ts` hardcodes `version: '2.00'`, `buildDate: '2026-11-14'`
  vs `public/version.json` / `src/constants/version.ts` `2026-11-07`.
- **Tests:** 32 Dart test files, 282 `test()` calls (was 29/215) — counted
  with the same `grep -c "test("` method that produced the 215 figure at
  head `0f5a2f2c`. 3 new files (telemetry, update service, playlist
  export/import) + extensions to the lyrics / Smart Remix engine / X1
  recall benchmark suites. (Note: W2's "9 tests" and W3's "17 cases" in
  their reports undercount the files as written — 11 and 26 respectively
  by the same grep; the 282 total is the file-grounded count.) Authored,
  never run locally (no Dart SDK on this VM); CI is the gate. `tsc --noEmit`
  exit 0 on the integrated React tree; web app rebuilt (`bun run build`
  exit 0; BT gradient present, "Btmus by Taboubi Ahmed" in bundle,
  `createMediaElementSource` ×0 in live chunks, old cyan/gold ×0 in live
  chunks — hits remain only in superseded stale chunks).
- **Stale files: now 40** (39 hashed assets under `ios/App/App/public/assets/`
  unreferenced by the new `index.html`/`sw.js`, incl. the `aistudio/Paste_…`
  scratch image, + `ios/App/App/public/workbox-afac4cd2.js` at the public
  root — **correction:** the Phase 4/5 notes said this file was "not in the
  repo"; it IS tracked (seed commit `3ba652e`), at the public root rather
  than under `assets/`, and is unreferenced by the current `sw.js`, which
  uses `workbox-835c8c05`). Parent batch-deletes via the browser after CI
  green; do NOT delete one-by-one.
- **Device gates still open (awaiting Ahmed's iPhone XS Max — never
  claimed):** lyrics highlight timing / auto-scroll feel / tap-to-seek;
  real-song BPM accuracy; audible Smart Remix quality; save-as-playlist order
  on a real library; X1 real-song recall; playback-history behaviour on a
  real library.
- **Gate verdict for Phase 6: implementation DONE**, subject to CI green
  (`flutter analyze` + 282 tests + iOS build step) on the new head. No
  decorative buttons remain in the audited rows: the two remaining stub rows
  (R14/R18) are quarantined-by-design, not decorative. Next: Phase 7
  (build/test/release — unsigned IPA at the end only).
