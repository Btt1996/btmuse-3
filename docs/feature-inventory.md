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

35 rows audited (15 Flutter + 20 React).

| Status | Flutter | React | Total |
|---|---|---|---|
| implemented | 11 | 12 | **23** |
| partial | 4 | 5 | **9** |
| missing | 0 | 1 | **1** |
| stub-or-dead (incl. quarantined-by-design) | 0 | 2 | **2** |

Definitions: **implemented** — the control does what its label promises, end to end as read.
**partial** — mostly works but has a dead path, misleading label, or an unverified sub-behavior.
**missing** — a named capability has no UI at all in that app. **stub** — a control that does
nothing, only shows a message, or (here) is intentionally disabled by quarantine.

## Flutter (canonical) — `flutter_app/lib/`

| # | Feature / screen | File(s) | Status | Evidence |
|---|---|---|---|---|
| F1 | App shell + bottom nav (6 tabs: Home, Library, Import, X2, X1, Playlists) | `lib/app/app.dart` | implemented | `AppShell` IndexedStack + `NavigationBar`; tab state via `currentTabIndexProvider`. Search/Settings/Downloads are pushed routes, not tabs — by design, not a gap. |
| F2 | Home | `features/home/home_screen.dart` | implemented | Engine cards navigate to X1/X2/Telegram/SmartRemix/Import; Recently Played + Recent Additions play via `audioHandler.setTrackQueueAndPlay`; favorite toggle invalidates library provider; empty state offers Import Center / Explore X2. |
| F3 | Library + metadata editor | `features/library/library_screen.dart`, `metadata_editor_sheet.dart` | implemented | FilePicker import (mp3/m4a/aac/flac/wav/ogg) via `importFileIntoLibrary`; search filter; Tracks/Favorites/Artists/Albums segments; edit metadata (title/artist/album/genre, saved via repo), add-to-playlist, delete. Storage stats + duplicate count shown. |
| F4 | Import Center (+ VK / YouTube / SoundCloud / Direct-URL sheets) | `features/import_center/import_center_screen.dart` | **partial** | Local single + batch import implemented with progress + per-file failure reporting. YouTube sheet assigns `searchTracks` results; Direct-URL sheet verifies MIME/magic bytes and RSS enclosures. **STUB (2):** `_VkImportSheetState._runVkLookup` calls `await vk.searchTracks(input)` and **discards the return value** — keyword search with no token shows nothing. `_SoundCloudImportSheetState._lookup` does the same with `await sc.searchTracks(q)`. URL-resolve paths in both sheets do assign results and work. Fix (other worker / Flutter owner): assign the returned list to `_results`, or disable the keyword path with an honest label. Code NOT changed in this pass — Flutter files outside the inventory are out of scope for edits. |
| F5 | Player (MiniPlayer + FullScreenPlayer) | `features/player/mini_player.dart`, `full_screen_player.dart` | **partial** | Play/pause, next/prev, seek slider, shuffle, repeat none/all/one, favorite toggle, Boost % + Smart Remix shortcuts all wired to the audio handler. **Missing sub-item:** there is **no lyrics UI in the Flutter player** (React has `LyricsView`). Lyrics are owned by another worker — disposition needed: add or explicitly defer. |
| F6 | Playlists + detail | `features/playlists/playlists_screen.dart`, `playlist_detail_screen.dart` | implemented | Create (name + description), delete, open detail, play-all, per-track remove. Note (not a stub): detail-screen remove has no confirmation dialog, unlike React which confirms deletes. |
| F7 | Universal Search | `features/search/search_screen.dart` | implemented | Local library filter + online X2 search on submit; per-provider error box; 30s preview play/stop via `just_audio`; authorized download queues via download manager; metadata-only results hand off to X2 tab. |
| F8 | Settings | `features/settings/settings_screen.dart` | implemented | App identity card, Audio/Telegram/Downloads navigation, X2 backend + Piped + Invidious + auth-token fields persisted to the credentials store, Save + Test Connectivity with a live diagnostics card, storage footprint display. No SpotDL field exists in Flutter settings. |
| F9 | Audio Settings (Extreme Boost) | `features/audio_settings/audio_settings_screen.dart` | implemented | 100–300% slider + presets, DSP gain/limiter readout via `VolumeDspMath`, soft-knee limiter + normalization switches, EQ preset chips — all applied through `handler.applyAudioSettings`. Clipping/hearing warnings shown conditionally. |
| F10 | Downloads + manager | `features/downloads/download_history_screen.dart`, `download_manager_provider.dart` | **partial** | Queue/cancel/clear-finished/progress/stage text all wired; acquisition validates content-type, size, and audio header before import. **STUB:** `retryTask` only retries when the payload is still in the in-memory `_queuedPayloads` map; a failed task restored from persisted history after an app restart has no payload, so **Retry silently does nothing**. Fix: persist the payload (or hide/disable Retry for restored tasks). Code NOT changed in this pass. |
| F11 | Smart Remix | `features/smart_remix/smart_remix_screen.dart`, `smart_remix_engine.dart` | implemented | 5 mix modes, crossfade 2–14s, enable toggle, launch plays the computed order; plan preview labels BPM as "Est." vs "Measured" (heuristic fallback is disclosed, not hidden). Note: actual crossfade application lives in `BttAudioHandler.updateRemixConfig`, not line-audited here (player worker owns it). |
| F12 | Telegram Sync | `features/telegram/telegram_screen.dart`, `telegram_service.dart` | implemented | Bot token from iOS Keychain, `getMe` verification, audio-message scan, per-file download with progress + cancel, 20 MB Bot API limit flagged with a block icon instead of a dead download button. |
| F13 | X1 Recognition | `features/x1/x1_screen.dart`, `x1_service.dart`, `local_fingerprint_engine.dart` | implemented | Mic capture (8s auto-stop), local FFT constellation match against the indexed library, rebuild-index action with count, local-clip file pick, open-catalog verification (MusicBrainz/Deezer/iTunes) with 30s previews, "Find this song in X2" handoff. Minor nit (not a stub): the post-index snackbar reads `_indexedCount` before the refreshed count lands, so it can show the stale count. Engine internals were not line-audited in this pass. |
| F14 | X2 Acquisition | `features/x2/x2_screen.dart`, `x2_search_engine.dart`, `x2_acquisition_engine.dart`, `providers/` (8), `clients/` | implemented | Parallel provider search with 9s timeout, per-provider errors, URL lookup with authorized-source handoff, filters (All/Authorized/Metadata), 30s previews, authorized-only download (throws `AuthorizationFailure` otherwise), content-type/size/audio-header validation, temp-file cleanup on failure. Providers: VK, YouTube, SoundCloud, Spotify-metadata, Audius, Deezer, iTunes-metadata, Direct URL. **No SpotDL anywhere in Flutter** (repo-wide search confirms zero hits). Flutter has no X2 benchmark modal; connectivity diagnostics live in Settings instead — accepted difference, not a gap. |
| F15 | App widgets / theme / providers | `lib/app/widgets/` (`btt_artwork`, `btt_logo_mark`, `track_tile`), `lib/app/theme/`, `lib/app/providers/app_providers.dart` | **partial** | Wired and rendered by every screen read (imports + usage verified); providers register all 8 X2 providers, download manager, X1/Telegram services. **Verification gap:** widget/theme sources were not line-read in this pass. |

## React (reference/fallback) — `src/`

| # | Feature / screen | File(s) | Status | Evidence |
|---|---|---|---|---|
| R1 | Home + Onboarding | `components/screens/HomeScreen.tsx`, `OnboardingView.tsx` | implemented | Recently Played / Favorites / Recently Downloaded carousels, Smart Synchro run with live status, Smart Mix drawer, Import modal, library metrics, online/offline badge. Empty library shows Onboarding with 4 working actions (Telegram sync, file import, demo pack, DB restore). Fixed 2026-11-22 (premium redesign): Onboarding badge now reads v2.00; header brand is "Btmus by Taboubi Ahmed" with the BT monogram gradient accent. |
| R2 | Library | `components/screens/LibraryScreen.tsx` | implemented | Search (title/artist/album/file/key/BPM), filters (all/favorites/telegram/analyzed), 7 sort orders, multi-select batch analyze + delete, duplicates scan, per-track menu (queue, play next, add to playlist, info, delete with confirm). |
| R3 | Search (unified) | `components/screens/SearchScreen.tsx` | implemented | Unified search across YouTube/Spotify/SoundCloud/Telegram/local/Open-CC with source tabs + counts, Spotify playlist detection banner, preview playback, per-track download with progress state machine, history + Telegram Hub modals. Non-local "Add to Queue" honestly toasts "Download track first" instead of pretending to queue. |
| R4 | Playlists + detail | `components/screens/PlaylistsScreen.tsx`, `PlaylistDetailView.tsx` | implemented | Create, import, rename (inline), delete (confirmed), play-all, shuffle, reorder (up/down), remove track, Smart Mix optimize. |
| R5 | Sync & Import | `components/screens/SyncScreen.tsx` | implemented | 5 tabs: Spotify inspector entry, Telegram bot connect + scan + selective download, manual file import with source tag + auto-playlist, DB import/export (incl. Web Share fallback), privacy/iOS guide. Demo-pack generator creates clearly-labeled synthetic tone tracks. |
| R6 | Settings | `components/screens/SettingsScreen.tsx` | implemented | Update check/apply, 3 palette combos, volume booster + presets, Smart Mix config + library analysis, storage quota meter, duplicates scan, DB export/import, offline playback audit, clear-all-data (confirmed). The **"spotDL Evaluation" button now opens the quarantined modal** (honest unavailable notice) — see Quarantine decisions. |
| R7 | Full-screen player | `components/player/FullScreenPlayer.tsx` | implemented | Play/pause/next/prev, seek scrubber (mouse + touch), shuffle/repeat, favorite, add-to-playlist, queue, Smart Mix, lyrics toggle, circular volume dial, "Open in App" share/download fallback. |
| R8 | Mini player | `components/player/MiniPlayer.tsx` | implemented | Play/pause/next, progress line, booster + Smart Mix badges, opens full player on tap, hidden while full player is open. |
| R9 | Lyrics | `components/player/LyricsView.tsx` | implemented | LRCLIB synced lyrics with tap-to-seek + auto-scroll, plain-lyrics fallback, retry; honest "not yet catalogued on LRCLIB" empty state. (Lyrics owned by another worker — not touched.) |
| R10 | Playlist Import modal (X1/X2) | `components/import/PlaylistImportModal.tsx` | **partial** | 4-step wizard (URL → preview → live per-track pipeline → summary) with threshold slider, provider toggles, per-track retry + manual match confirm, Spotify credentials drawer. **Issues:** (a) **"SoundCloud Ready" badge is misleading** — the X2 import pipeline (`x2Engine`) has no SoundCloud adapter (Jamendo/Archive/FMA/Telegram/SpotDL/local only); (b) the spotDL row's "Configured / Needs Host" badge can still read a stale `localStorage` URL and its Architecture button now opens the quarantined notice — the flow is honestly dead-ended, but the row should be disabled/cleaned by the coordinator (file not rewritten here: reproducing the ~1,100-line modal verbatim risked transcription errors; the quarantine modal blocks the path). |
| R11 | Spotify Playlist Inspector | `components/import/SpotifyPlaylistReviewModal.tsx` | implemented | URL fetch via `x1Spotify`, per-track local-cache check, select/exclude, filters, individual + batch download via `x2Engine`, candidate inspector, playlist save with preserved order. |
| R12 | Telegram Discovery modal | `components/import/TelegramDiscoveryModal.tsx` | **partial** | Connect/verify/scan/download paths are implemented. **STUB (misleading demo data):** `PREVIEW_PUBLIC_CHANNELS` is a hardcoded fabricated catalog (e.g. "Neon Nights" by "CyberSound", "Clair de Lune") presented under "Discoverable Public Audio Samples". The rows are not real discoverable audio; their only action switches to the Connect tab. Fix: remove the fake catalog or label it explicitly as sample/demo data. This directly contradicts the "Zero Mocks" claim made by the X2 benchmark UI. |
| R13 | X2 Benchmark modal | `components/import/X2BenchmarkModal.tsx` | implemented | Runs `runX2Benchmark` (6 real tracks, live provider search, stream probe, blob validation) with per-track breakdown; copy quarantined — see Quarantine decisions. Pre-existing unused imports (`Download`, `RotateCcw`, `ExternalLink`, `CheckCircle2`) left as-is. |
| R14 | SpotDL info modal | `components/import/SpotDLInfoModal.tsx` | **stub** (quarantined by design) | Was a 3-tab modal with bridge-URL input + "Test & Save". Now renders an honest unavailable state with no input, no test, no save — see Quarantine decisions. |
| R15 | Player chrome + common modals | `player/QueueModal.tsx`, `SmartMixDrawer.tsx`, `VolumeControl.tsx`, `CircularVolumeDial.tsx`, `AddToPlaylistModal.tsx`, `BttPlaybackAnimation.tsx`, `navigation/BottomNav.tsx`, `common/{ConfirmModal,DuplicatesModal,MusicHistoryModal,PWAInstallModal,SplashScreen,Toast}.tsx`, `screens/TrackDetailModal.tsx` | **partial** | **Verification gap:** these files were not line-read in this pass; status rests on call sites only — every one is opened from a real handler with real props (e.g. `QueueModal`/`SmartMixDrawer` from `FullScreenPlayer`, `AddToPlaylistModal` from Library/Player, `DuplicatesModal` from Library/Settings, `MusicHistoryModal` from Search/Sync). No empty-handler or dead-button signal was found in the repo-wide grep for `TODO|FIXME|coming soon|not implemented` or empty callbacks (zero hits in `src/` + `flutter_app/lib/`). Close the gap by line-reading these before the gate, or explicitly accept for the reference app. |
| R16 | Spotify playlist resolution (X1) | `services/playlistImport/x1Spotify.ts` | **partial** | `parseSpotifyTarget` / `parseSpotifyPlaylistId` unchanged and correct. `fetchSpotifyPlaylist` now server-side only — `allorigins.win` fallback removed (see Quarantine decisions). Spotify metadata resolution is therefore unavailable when the server is down; the error now says so explicitly instead of silently proxying. |
| R17 | Spotify user/playlist discovery | `services/playlistImport/spotifyDiscoveryService.ts` | **partial** | `parseSpotifyUserId` unchanged. `discoverUserPlaylists` now server-side only — `allorigins.win` embed-scrape fallback removed; server failure now throws an explicit error instead of returning an empty playlist list with just a profile link. `searchSpotifyPlaylists` unchanged: returns **static canned presets** (Chill Hits, Today's Top Hits, lofi beats, Beast Mode) for chill/lofi/workout keywords and `[]` otherwise — that is placeholder data, not live search; flag for a later pass, not a gate blocker for the reference app. |
| R18 | SpotDL bridge | `services/playlistImport/spotdlBridge.ts` | **stub** (quarantined by design) | Was a live bridge: `GET {url}/health` + `POST {url}/api/match`. Now every public function is a no-op returning an explicit unavailable result — see Quarantine decisions. File kept (not deleted) so imports keep compiling. |
| R19 | X2 engine + benchmark service | `services/playlistImport/x2Engine.ts`, `x2Benchmark.ts` | implemented | Provider pipeline (local cache → SpotDL → Telegram → Jamendo → Archive → FMA) with confidence scoring, retry, per-track import + single-track resolve. **No code change needed:** with the quarantined bridge, `searchSpotDLBridge` returns `null`, so Step 2 records a `no_match` attempt and the pipeline continues. `x2Benchmark` inherits this automatically; its "requires self-hosted spotDL bridge" diagnostic note is now stale wording for commercial tracks (it still correctly reports 0 matches) — reword when the benchmark copy is next touched. `downloadAndValidateAudio` already falls back to the **server-side** `/api/audio-proxy` on direct-fetch CORS failure — that is the sanctioned server path, not a third-party proxy, and was left untouched. |
| R20 | Downloads history (React) | — (no file) | **missing** | React has no persisted downloads/history screen: `SyncScreen` keeps `downloadTasks` in component state only (session-scoped). Flutter has `DownloadHistoryScreen` backed by `HistoryRepository`. Acceptable for the reference app only if explicitly dispositioned; otherwise add or defer. |

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
