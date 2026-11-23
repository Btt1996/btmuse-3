# Btt Music 2.00 — Device Testing Checklist

> **STATUS: AWAITING DEVICE — NOTHING IN THIS DOCUMENT CLAIMS A RESULT.**
> Every check below is **untested**. No box is ticked, no result is recorded,
> no behaviour is asserted. This document is a plan for a pass that has not
> happened yet.

- **Device:** Ahmed's iPhone XS Max, iOS 18+
- **App:** Btt Music 2.00 (`com.ahmed.btmu`), sideloaded unsigned IPA
  (`btmu-2.00-unsigned.ipa`), built from `Btt1996/btmuse-3.0`,
  branch `seed/iosbtmus2-2.00`, head `544eabc2`
- **Scope:** the Flutter app under `flutter_app/` (the canonical app). The
  React/Capacitor app is reference/fallback and is **not** covered by this
  pass, except where a check explicitly says so.
- **The 282 automated Dart tests are NOT a substitute for this pass.** They
  run in CI on a Mac runner; they prove Dart math, service logic and test
  doubles. They have never played audio, touched a lock screen, paired
  AirPods, or imported a real file on a phone. Every audio, background,
  lock-screen, AirPods, import and feel claim in this app is unverified
  until the checks below pass on the XS Max.

## How to use this checklist

1. Work through the sections **in order**. Later sections assume earlier
   ones passed (e.g. the queue checks assume import already works).
2. For each check: follow the steps exactly, compare with the expected
   result, tick **Pass** or **Fail**. On a Fail, write the actual behaviour,
   the build commit, and the settings in force in the Notes column — do not
   leave a Fail blank, and do not waive it with "it works in the foreground".
3. Checks marked **(booster ON)** must be run a second time with the booster
   at 300% (limiter on, unless the check says otherwise). The booster-off
   run and the booster-on run are separate results.
4. A failed gate blocks the Phase 7 gate verdict. Record failures; do not
   re-run a failed check and tick Pass without noting the first failure.
5. Known limits listed in §0.4 are **not** failures — record what you see
   and move on. Anything not in §0.4 that differs from the expected result
   is a Fail.

## 0. Prerequisites — gather before starting

Tick each item as you confirm it; do not start §1 until all of §0 is ready.

| # | Prerequisite | Why it is needed | Ready |
|---|---|---|---|
| P-1 | Unsigned IPA `btmu-2.00-unsigned.ipa` installed on the XS Max via sideloading (AltStore / Sideloadly / TrollStore); note the exact build commit hash | Every check is meaningless without a known build | ☐ |
| P-2 | ≥ 10 real tracks with distinct artwork ready to import, including: one track ≥ 4 minutes; one loud, full-range track (EQ / booster audibility); one track with synced LRC lyrics available on LRCLIB; one track with plain-only lyrics; one track whose file you can delete after import (missing-file case) | Covers the long-track, EQ, lyrics and missing-file checks | ☐ |
| P-3 | A second device (or a speaker) that can play a real song out loud in the room, for X1 | X1 identifies a song played in the room, not from the phone itself | ☐ |
| P-4 | Telegram bot token (in iOS Keychain via the app's Telegram screen); a Telegram chat/channel the bot can read (bot must be admin or receive forwards) with at least one audio file, including one file already in the library (re-send skip check) | Telegram import checks | ☐ |
| P-5 | Spotify: a public playlist URL, and a Spotify username whose public playlists can be browsed. Server-side Spotify credentials are **not** Ahmed's to provide in the app — the backend supplies them; if the backend is not deployed, the Spotify checks that need the server are expected to fail honestly (see D-4xx notes) | Spotify metadata + user-playlist checks | ☐ |
| P-6 | SoundCloud: a track URL to look up (metadata-only path). No client ID is required in the app for lookup; keyword search is honestly unavailable (see §0.4) | SoundCloud checks | ☐ |
| P-7 | X2 backend URL (`X2_BACKEND_URL`) deployed and reachable, **or** an explicit decision recorded here that the backend is not deployed and the app is running in degraded mode (see `docs/x2-degraded-mode.md`) | X2 acquisition checks that need the server | ☐ |
| P-8 | Jamendo client ID entered in Settings (Keychain), if Jamendo checks are to run; otherwise record "no Jamendo ID" and expect the honest AuthorizationFailure | X2 Jamendo checks | ☐ |
| P-9 | YouTube bridge: `tools/ytdlp_server.py` running on a reachable host, bridge URL saved in the app — **or** record "no bridge" and run only the metadata-only YouTube checks | YouTube bridge checks | ☐ |
| P-10 | AirPods (charged, paired) + optionally wired headphones | AirPods checks (§18) | ☐ |
| P-11 | A known Wi-Fi network + mobile data, and the ability to toggle Airplane mode | Offline / interruption checks | ☐ |
| P-12 | One deliberately corrupted file (e.g. a `.mp3` that is actually a text file, and one truncated MP3), plus one non-audio file (e.g. a `.mp4` video) | Corrupted-file checks (§24) | ☐ |
| P-13 | A duplicate of a track already in the library (same file, and separately a different file of the same song) | Duplicate checks (§25) | ☐ |
| P-14 | A playlist file for import: one `btmu-playlist` v1 JSON export and one M3U file (make the JSON by exporting a playlist from the app first, §12) | Playlist import checks | ☐ |
| P-15 | A backup JSON exported from the app (§20) before any destructive check, so the library can be restored | Safety net for storage/backup checks | ☐ |

### 0.1 Build & settings record (fill in once, before §1)

| Field | Value |
|---|---|
| Build commit hash | |
| IPA file name / source | |
| iOS version on the XS Max | |
| Date of this pass | |
| EQ preset in force at start | |
| Booster % / limiter on-off / normalization on-off at start | |
| Crossfade enabled / seconds at start | |
| Shuffle / repeat state at start | |
| X2 backend deployed? (URL or "degraded mode") | |
| YouTube bridge running? (URL or "none") | |
| Jamendo client ID entered? (yes / no) | |

### 0.2 Conventions used in this checklist

- **Tap** = single tap. **Player** = fullscreen player; **mini-player** = the
  collapsed bar at the bottom.
- **"Already in library"** means the app shows that chip/label (or the
  equivalent), not that you guess it.
- **Booster OFF** = 100% (multiplier 1.0). **Booster ON** = 300%, limiter on,
  normalization on (defaults), unless a check says otherwise.
- **dB honesty:** at 300% the raw gain is +9.54 dB; with the default −1.5 dB
  normalization the net is **+8.04 dB** (UI shows "+8.0 dB"). The UI must
  state that 300% is gain, not 3× perceived loudness.

### 0.3 What "Pass" means

A check passes only if the **exact** expected result happens on the device.
"Seems fine", "probably works" and "worked in CI" are not passes. If you
cannot observe the expected result, mark Fail and say what you observed
instead.

### 0.4 Known limits — record, do not fail

These are documented limitations of the build at head `544eabc2`. If you see
exactly this behaviour, note it and move on; it is not a Fail.

- **K-1** Spotify user-playlist browse returns the **first 50 playlists
  only** (no pagination). A user with > 50 public playlists will not see
  the rest.
- **K-2** Jamendo `resolveUrl` supports **track pages only** (not artist /
  album / playlist pages).
- **K-3** Archive.org search is **not collection-scoped**.
- **K-4** X1: a chord sharing one sustained partial plus its 1.5× harmonic
  under identical FM can still false-positive. This is a documented engine
  limitation (`docs/x1-recall.md`); synthetic recall is not real-song recall.
- **K-5** Smart Remix measured BPM range is **65–171 BPM**; above-range
  tempos fold to half-time; no octave disambiguation. A track with no
  detectable tempo shows no tempo (BPM 0 = "no tempo"), not a bogus number.
- **K-6** Lyrics: LRC timestamps require two-digit minutes; a 4-fraction-digit
  timestamp can leave a stray `6]`; there is no cache TTL.
- **K-7** The SpotDL bridge is **quarantined by design** (legal review).
  Any SpotDL row/button must show "Unavailable — legal review" and do
  nothing. It must never download. That is the correct behaviour, not a bug.
- **K-8** Spotify metadata import is **metadata-only**: it never implies an
  audio download. "Find Authorized Source in X2" is the path to audio.
- **K-9** VK and SoundCloud **keyword search is honestly unavailable**
  (providers throw `AuthorizationFailure`; the UI says so before submit).
  URL lookup is the working path for both.
- **K-10** Retry on a download task restored from a previous session is
  **disabled** (no payload persisted for restored tasks). The button must be
  visibly disabled, not silently dead.
- **K-11** iOS cannot self-update: the update check can only point at a
  GitHub release; installing a new build means sideloading a new unsigned
  IPA. There is no in-app install button.
- **K-12** The React/Capacitor app is the fallback, not the shipped app;
  its update check reads the served `/api/version` manifest, not GitHub
  releases. Not tested here.

---

## 1. Startup & navigation

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-001 | Force-quit the app (if running). Tap the app icon on the Home Screen. | App launches to Home without a crash, a white/light flash, or a hang. First paint is dark. | ☐ Pass ☐ Fail |
| D-002 | On first launch after install (or after clearing data), read the Home screen header. | Header reads "Btmus by Taboubi Ahmed" with the version badge "2.00". The logo is the new BT gradient mark (bold "BT", violet→magenta→pink-red gradient, white play button inside the B, on black) — no Triforce anywhere. | ☐ Pass ☐ Fail |
| D-003 | Tap each bottom tab in order: Home → Library → Import → X2 → X1 → Playlists. | Each tab opens its screen; no blank screen, no crash, no stuck spinner. Tab state is kept when you return (e.g. scroll position / entered text is not lost). | ☐ Pass ☐ Fail |
| D-004 | From Home, open Search, then Settings, then Downloads (pushed routes). Go back from each. | Each opens and returns cleanly to where you came from. | ☐ Pass ☐ Fail |
| D-005 | Rotate the phone (if rotation is supported) and use the app one-handed on the XS Max (5.8", notch). | No clipped text, no content hidden under the notch or Home indicator; safe areas respected. | ☐ Pass ☐ Fail |
| D-006 | Leave the app on Home for 2 minutes without touching it. | No crash, no unexpected navigation, no spinner that never resolves. | ☐ Pass ☐ Fail |

## 2. Import — local files (Files)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-010 | Library tab → import a single MP3 from the Files app (Files picker). | File imports; track appears in Library with correct title/artist/album from its tags. | ☐ Pass ☐ Fail |
| D-011 | Import Center → batch-import 5 files at once (mix of mp3 / m4a / flac / wav). | All import with per-file progress; a summary/snackbar reports how many imported and how many were skipped (if any). | ☐ Pass ☐ Fail |
| D-012 | In the Files picker, try to pick a non-audio file (e.g. a PDF or image). | The picker refuses it, or the app rejects it with a clear error — it is never added as a track. | ☐ Pass ☐ Fail |
| D-013 | Import a file with embedded artwork. | Artwork shows in Library, in the player, and on the lock screen (§17). | ☐ Pass ☐ Fail |
| D-014 | Import a file with missing/empty tags. | Track still imports (title falls back to the file name or "Unknown"); no crash. | ☐ Pass ☐ Fail |
| D-015 | Import a file, then delete the source file from Files (outside the app). Open the app → Library → play that track. | App reports the file as missing (does not stall silently, does not pretend to play). Storage dashboard offers "Remove N missing entries" (see §19). | ☐ Pass ☐ Fail |

## 3. Import — Telegram

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-020 | Import tab → Telegram. Enter the bot token (Keychain). Tap verify/connect. | `getMe` verification succeeds; the bot identity is shown. A wrong token gives a clear error, not a hang. | ☐ Pass ☐ Fail |
| D-021 | Run a scan of the bot's chats for audio messages. | Scan lists audio files with names/sizes; a channel the bot cannot read shows the documented limitation (bot must be admin or receive forwards) instead of an empty list with no explanation. | ☐ Pass ☐ Fail |
| D-022 | Download one audio file from the scan, watching progress. Cancel a second download mid-way. | First download completes and the track appears in Library. The cancelled one stops cleanly and does not leave a partial track. | ☐ Pass ☐ Fail |
| D-023 | Download a file larger than the 20 MB Bot API limit (if available). | The file is flagged with a block icon / clear message instead of a download button that fails. | ☐ Pass ☐ Fail |
| D-024 | Re-send (or re-scan) an audio file that is already in the library. | The app skips the re-download and flags it "already in library" (via `file_unique_id` dedup) — no duplicate track is created. | ☐ Pass ☐ Fail |
| D-025 | Force-quit the app during a Telegram download, relaunch, open Downloads. | The interrupted task is shown honestly (failed/interrupted); no phantom "downloading forever" row. | ☐ Pass ☐ Fail |

## 4. Import — Spotify (metadata only)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-030 | Import Center → Spotify sheet. Paste a public Spotify playlist URL. Fetch it. | Playlist metadata loads (name, tracks with title/artist). If the backend is not deployed, the error says the server is unavailable — it never pretends the playlist is empty or private when the real cause is the server. | ☐ Pass ☐ Fail |
| D-031 | In the fetched playlist, look at the per-track flags. | Tracks already in your library show "Already in library" chips. Tracks not in the library do not. | ☐ Pass ☐ Fail |
| D-032 | Tap "Find Authorized Source in X2" on a metadata-only track. | The app hands the track to X2 search (§15) — it does not offer or imply a Spotify audio download. | ☐ Pass ☐ Fail |
| D-033 | Import the playlist's metadata into a local playlist (save). | A local playlist is created with the tracks that exist in the library, in the playlist's order; missing tracks are accounted for (listed as missing/skipped), never silently dropped. | ☐ Pass ☐ Fail |
| D-034 | Paste a private Spotify playlist URL, or a malformed URL. | A clear, honest error — not a crash, not a silent empty result. | ☐ Pass ☐ Fail |

## 5. Import — SoundCloud

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-040 | Import Center → SoundCloud sheet. Paste a SoundCloud track URL and look it up. | Track metadata resolves (title/artist, artwork if available). | ☐ Pass ☐ Fail |
| D-041 | In the SoundCloud sheet, try a keyword search (type an artist/track name, no URL). | The UI states before submit that keyword search is unavailable / needs a token (K-9) — it does not run a search that returns nothing with no explanation. | ☐ Pass ☐ Fail |
| D-042 | For a SoundCloud track whose creator enabled downloads, download it. For one that did not, attempt download. | Enabled: downloads and imports. Not enabled: a clear message that downloads are not enabled by the creator — never a fake download. | ☐ Pass ☐ Fail |
| D-043 | Look for any "SoundCloud Ready" badge or claim that SoundCloud audio download is generally available. | No such claim exists; copy says "SoundCloud Metadata Only" (or equivalent honest wording). | ☐ Pass ☐ Fail |

## 6. Import — X1 → X2 chain

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-050 | X1 tab → identify a real song played in the room from the second device (§14, D-140). On the result, tap "Find this song in X2". | X2 search opens with the identified track; authorized sources are offered; an unauthorized source is never offered as a download. | ☐ Pass ☐ Fail |
| D-051 | From the X2 result, acquire the track into the offline library. | Download shows progress, validates (MIME, duration, hash) and the track appears in Library, playable offline (§16). | ☐ Pass ☐ Fail |
| D-052 | Repeat D-050/D-051 for a track that has no authorized source. | The app says so honestly (no match / no authorized source) — it never falls back to an unauthorized download. | ☐ Pass ☐ Fail |

## 7. Import — YouTube bridge (metadata / self-hosted only)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-060 | Import Center → YouTube sheet. Paste a YouTube URL with NO bridge configured. | Metadata/search results show. "Import via my bridge" is not offered (or is visibly unavailable) until a bridge is configured. There is NO built-in "YouTube MP3" download button anywhere. | ☐ Pass ☐ Fail |
| D-061 | If a bridge is running (P-9): save its URL in the sheet, tap Test. | Health check passes and says so; a wrong/unreachable URL gives a clear error. | ☐ Pass ☐ Fail |
| D-062 | If a bridge is running: import a track via "Import via my bridge". | Track imports through the bridge and appears in Library; it appears in Downloads history. | ☐ Pass ☐ Fail |
| D-063 | If no bridge is running: confirm the YouTube sheet still works for metadata/search. | Metadata-only use works without a bridge; nothing claims a download happened. | ☐ Pass ☐ Fail |

## 8. Metadata & artwork

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-070 | Library → open a track's metadata editor. Change title, artist, album, genre. Save. | Changes persist after leaving and returning, and after an app restart. The track still plays. | ☐ Pass ☐ Fail |
| D-071 | Library → use search (title, artist, album). Switch the Tracks / Favorites / Artists / Albums segments. | Search filters correctly; each segment shows the right grouping. | ☐ Pass ☐ Fail |
| D-072 | Library → tap the favorite (heart) on a track, then open the Favorites segment. | Track appears in Favorites; unfavoriting removes it. Home Recently Played / favorites reflect the change. | ☐ Pass ☐ Fail |
| D-073 | Play tracks with and without embedded artwork; check Library list, mini-player, fullscreen player, lock screen. | Artwork shows where it exists; where it is missing a clean placeholder shows (no broken-image icon, no crash). | ☐ Pass ☐ Fail |
| D-074 | Library → delete a track (confirm if asked). | Track is gone from Library, playlists and queue; its file/storage is freed (check §19 totals move). | ☐ Pass ☐ Fail |

## 9. Playback

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-080 | Library → play a track. Use mini-player play/pause, then open the fullscreen player. | Audio starts promptly; mini-player and fullscreen player agree on track, position and state. | ☐ Pass ☐ Fail |
| D-081 | In the fullscreen player, tap Next / Previous repeatedly, including Previous within the first 4 seconds of a track and after 4 seconds. | Next advances; Previous restarts the track when > 4 s in, and goes to the previous track when ≤ 4 s in. Behaviour matches the lock-screen / AirPods Previous behaviour (§17/§18). | ☐ Pass ☐ Fail |
| D-082 | Play a track to its end with repeat OFF and a queue behind it. | Next track starts automatically with no gap/stutter beyond the crossfade setting. | ☐ Pass ☐ Fail |
| D-083 | Play the last track of the queue to its end with repeat OFF. | Playback stops; Now Playing clears (lock screen shows no stale track — see D-113). | ☐ Pass ☐ Fail |
| D-084 | Set repeat-all, play the last track to its end. | Playback wraps to track 1. | ☐ Pass ☐ Fail |
| D-085 | Set repeat-one, play a track to its end. | The same track restarts cleanly (no crossfade into itself, no hard skip to the next track). | ☐ Pass ☐ Fail |
| D-086 | Turn shuffle ON with a ≥ 10-track queue. Press Next 10 times. | Every track plays at most once before any repeats; no track repeats immediately. Previous steps back through the shuffled order (not the library order). | ☐ Pass ☐ Fail |
| D-087 | With repeat OFF, press Next on the last track. Press Previous on the first track (≤ 4 s in). | Neither wraps: Next on the last track stops playback; Previous on the first track does not jump to the last track. | ☐ Pass ☐ Fail |
| D-088 | Settings → Audio Settings. For EACH EQ preset — Balanced, Warm Bass, Vocal Clarity, Late Night, Studio Bright — play the same loud, full-range track. (Gate G-7.) | Each preset is audibly distinct from Balanced (bass weight / vocal presence / brightness as labelled). **Fail any preset that sounds identical to Balanced** (that was the pre-fix bug). | ☐ Pass ☐ Fail |
| D-089 | Switch EQ presets mid-track. | Applies without a dropout, restart, or crash. | ☐ Pass ☐ Fail |
| D-090 | Audio Settings: set the booster slider to 300%. Read the gain readout. | Readout shows the raw and net dB in the form "300% · +9.5 dB gain − 1.5 dB normalization = +8.0 dB net" (or the equivalent correct numbers for the settings in force) AND states that 300% is gain, not 3× perceived loudness. | ☐ Pass ☐ Fail |
| D-091 | Audio Settings: turn the limiter OFF at 300% (read the warning first). Play a loud track briefly. | A clipping-risk warning is visible before enabling; the difference is audible. **Turn the limiter back ON after this check** and record that you did. | ☐ Pass ☐ Fail |
| D-092 | Audio Settings: turn normalization OFF at 300% (net +9.5 dB). Play a loud track. | No audible hard clipping/distortion; the limiter audibly prevents hard clipping. Restore normalization ON after. | ☐ Pass ☐ Fail |
| D-093 | Crossfade: enable, set overlap 6 s. Play two tracks across the boundary. (Gate G-10.) | Last 6 s of the outgoing track audibly overlap the start of the next: no gap, no hard cut, no volume dip/pump at the midpoint. | ☐ Pass ☐ Fail |
| D-094 | Crossfade: set overlap 2 s, then 14 s, and play across a boundary each time. | 2 s: short clean overlap. 14 s: long overlap. Both clean. | ☐ Pass ☐ Fail |
| D-095 | Crossfade: disable it. Play across a track boundary. | Tracks end with a clean stop/start, no overlap. | ☐ Pass ☐ Fail |
| D-096 | Crossfade ON + shuffle ON: play across a boundary. | The crossfade target is the next track in shuffle order, not the sequential one. | ☐ Pass ☐ Fail |
| D-097 | Crossfade ON + repeat-all on the last track; then crossfade ON + repeat-one. | Repeat-all: overlaps into track 1. Repeat-one: no crossfade, clean restart. | ☐ Pass ☐ Fail |
| D-098 | Play a track at 1.5× / 0.5× speed (if the speed control is exposed). Force-quit and relaunch, play again. | Speed setting persists across restart (or, if it is not persisted by design, record that — do not guess). | ☐ Pass ☐ Fail |
| D-099 | Play a track, then open another app, then return. | Playback continued while away; position is correct on return. | ☐ Pass ☐ Fail |

## 10. Seek

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-100 | In the fullscreen player, drag the seek slider to the middle of a track ≥ 4 minutes. | Audio resumes promptly from the new position; displayed position matches what you hear. | ☐ Pass ☐ Fail |
| D-101 | Drag the seek slider to within 5 seconds of the end. | Track ends and the next track starts (no stall, no loop of the last seconds). | ☐ Pass ☐ Fail |
| D-102 | Drag the seek slider to 0:00. | Track restarts from the beginning. | ☐ Pass ☐ Fail |
| D-103 | Seek repeatedly and rapidly (5 seeks in a row). | No crash, no stuck "loading", position settles on the last seek. | ☐ Pass ☐ Fail |
| D-104 | Seek from the lock screen (D-174) and confirm the in-app position follows. | App and lock screen agree after the lock-screen seek. | ☐ Pass ☐ Fail |

## 11. Queue & Up Next (Gate G-8)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-110 | Play a track, open the fullscreen player, tap "Up Next". | Queued tracks are listed in order with the current track marked. | ☐ Pass ☐ Fail |
| D-111 | In Up Next: add a track to the queue; add a different track to play next. | Queue grows; the "play next" track is next in line. | ☐ Pass ☐ Fail |
| D-112 | In Up Next: remove a track (✕). Playback continues. | Track is gone from the queue; playback is unaffected. | ☐ Pass ☐ Fail |
| D-113 | In Up Next: drag-reorder two tracks. Let playback reach them. | They play in the new order. | ☐ Pass ☐ Fail |
| D-114 | In Up Next: remove the currently playing track. | Playback moves to the next track cleanly (no silence, no crash). | ☐ Pass ☐ Fail |
| D-115 | In Up Next: tap "Clear" and confirm. | Queue empties (with a confirm dialog); playback stops cleanly. | ☐ Pass ☐ Fail |
| D-116 | Build a queue of ≥ 5 tracks, play track 2, note track + position. Kill the app from the app switcher. Relaunch. | The queue is as left: same tracks, same order, same current track — NOT the whole library. Playback is paused at the saved position. | ☐ Pass ☐ Fail |
| D-117 | After D-116, press play, then Next. | Resumes from the saved position; Next plays the next track of the saved queue, not the next-newest library track. | ☐ Pass ☐ Fail |
| D-118 | Enable shuffle and repeat-all. Kill the app from the switcher. Relaunch. | Both are still enabled (they persist). | ☐ Pass ☐ Fail |
| D-119 | Queue a track whose file was deleted after import (P-2) in the middle of a queue. Play through it. | Player skips it and plays the next track. **Fail if playback stops silently.** | ☐ Pass ☐ Fail |

## 12. Playlists

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-120 | Playlists tab → create a playlist (name + description). Add 3 tracks from Library (add-to-playlist). Open the playlist. | Playlist shows the 3 tracks in the order added. | ☐ Pass ☐ Fail |
| D-121 | Playlist detail → Play all. | Plays the playlist in order from track 1. | ☐ Pass ☐ Fail |
| D-122 | Playlist detail → remove one track. | Track is removed. (Note: unlike the React app, Flutter detail remove has no confirmation dialog — record whether that is still true; it is a cosmetic note, not a Fail.) | ☐ Pass ☐ Fail |
| D-123 | Playlist detail → export the playlist as JSON, then as M3U. Open the exported files. | Both exports are valid; JSON is the `btmu-playlist` v1 format; every track is present. | ☐ Pass ☐ Fail |
| D-124 | Playlists tab → import the JSON export from D-123. | Import succeeds; the new playlist is named with an " (imported)" suffix (existing playlist never overwritten); a summary dialog accounts for every entry (added / duplicates / missing / skipped — no silent drops). | ☐ Pass ☐ Fail |
| D-125 | Import the M3U export from D-123 the same way. | Same accounting as D-124; order preserved. | ☐ Pass ☐ Fail |
| D-126 | Try importing a backup JSON document (from §20) as a playlist. | It is rejected with a clear error (backup v2 is not a playlist document) — never imported as a playlist. | ☐ Pass ☐ Fail |
| D-127 | Delete a playlist (confirm if asked). | Playlist is gone; the tracks themselves remain in the Library. | ☐ Pass ☐ Fail |
| D-128 | Smart Remix → build a mix, then "Save mix as playlist" (see §29 for the quality checks). Name it and save. | Playlist is created in the exact mix order shown on screen (order preserved via sequential insert). | ☐ Pass ☐ Fail |

## 13. Spotify — user-playlist browse (Phase 5)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-130 | Spotify sheet → Browse-user mode. Enter a Spotify username / user ID. | The user's public playlists list with cover art, owner name and track counts. If the backend is not deployed, the error says the server is unavailable (not "user not found"). | ☐ Pass ☐ Fail |
| D-131 | Tap one of the listed playlists. | Its track list opens; per-track "Already in library" chips show where applicable. | ☐ Pass ☐ Fail |
| D-132 | Enter a username that does not exist. | A clear "unknown user" (404-style) message — not an empty list, not a crash. | ☐ Pass ☐ Fail |
| D-133 | If the user has > 50 public playlists: scroll to the end of the list. | Only the first 50 are shown (K-1). Record this; do not fail it. | ☐ Pass ☐ Fail |

## 14. X1 — real song in the room (Phase 5 gate)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-140 | X1 tab. On the second device/speaker, play a real song that IS in the library (a track you imported). While it plays, tap Listen/Identify in the app (8 s capture). | The app identifies the correct song (title/artist match the song playing). Record the song and whether it matched. | ☐ Pass ☐ Fail |
| D-141 | Repeat D-140 with a real song that is NOT in the library. | The app reports no local match and offers open-catalog verification (MusicBrainz/Deezer/iTunes) with a 30 s preview — it does not invent a match. | ☐ Pass ☐ Fail |
| D-142 | Repeat D-140 with three different real songs (different genres/tempos, including one quiet passage). | Record match / no-match for each. At least note the recall you observe — this is the real-song recall measurement; synthetic recall numbers do not count here. | ☐ Pass ☐ Fail |
| D-143 | X1 tab → deny microphone permission when iOS asks (or revoke it in iOS Settings → Btmus → Microphone, then try again). | A distinct mic-denied state with the iOS Settings path — not a generic error, not a hang. Re-enable the permission and confirm identifying works again. | ☐ Pass ☐ Fail |
| D-144 | X1 tab → tap Listen with no music playing (silence / room noise only). | "No match" state — white noise / silence must not produce a match. | ☐ Pass ☐ Fail |
| D-145 | X1 tab → tap Listen, then lose network mid-capture (Airplane mode on before the catalog check). | A distinct network-failure / timeout state — not a false match, not a hang. | ☐ Pass ☐ Fail |
| D-146 | X1 tab → Rebuild index. Note the count shown. | Index rebuilds; the count matches the library size. (Known nit: the snackbar can show the stale count — record it if you see it; cosmetic, not a Fail unless the index itself is wrong.) | ☐ Pass ☐ Fail |
| D-147 | X1 result screen → "Find this song in X2". | Hands off to X2 search for that song (see §6/§15). | ☐ Pass ☐ Fail |

## 15. X2 — real acquisition from an authorized source (Phase 5 gate)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-150 | X2 tab → search for a track by keyword. | Results arrive from the providers within the timeout; per-provider errors are shown per provider (a failing provider does not blank the whole result list). | ☐ Pass ☐ Fail |
| D-151 | X2 tab → acquire a real track from an authorized source (Audius, Internet Archive, Jamendo, or direct URL from an authorized host) into the offline library. | Download shows progress, validates content-type/size/audio header, and the track appears in Library and plays offline (§16). Record the provider used. | ☐ Pass ☐ Fail |
| D-152 | X2 tab → try to acquire a track from an unauthorized source. | The app refuses with an `AuthorizationFailure`-style message — no download starts. | ☐ Pass ☐ Fail |
| D-153 | X2 tab → use the filters All / Authorized / Metadata. | Each filter shows the right subset; metadata-only results are clearly marked and hand off to X2 rather than pretending to be downloadable audio. | ☐ Pass ☐ Fail |
| D-154 | X2 tab → play a 30 s preview of a search result, then stop it. | Preview plays and stops cleanly; stopping a preview does not start the full track. | ☐ Pass ☐ Fail |
| D-155 | X2 tab → search with no network (Airplane mode). | Per-provider errors / honest offline state — not a hang, not fake results. | ☐ Pass ☐ Fail |
| D-156 | If a Jamendo client ID is entered (P-8): search Jamendo. If no ID: search Jamendo. | With ID: results return. Without ID: keyword search is honestly unavailable with a named AuthorizationFailure (K-9 pattern). | ☐ Pass ☐ Fail |
| D-157 | Downloads → open a completed X2 download's history entry. Retry a failed download (one that failed while the app was running). | Retry works for a same-session failure. For a task restored from a previous session, Retry is visibly disabled (K-10) — not silently dead. | ☐ Pass ☐ Fail |

## 16. Offline playback (Airplane mode)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-160 | With a library of imported tracks, turn on Airplane mode. Play a track from the Library. | Plays normally — no network needed for local audio. | ☐ Pass ☐ Fail |
| D-161 | In Airplane mode, play a full queue of 5 local tracks end to end. | All play; no track fails for network reasons. | ☐ Pass ☐ Fail |
| D-162 | In Airplane mode, open the Player → Lyrics tab for a track with synced lyrics. | Cached lyrics show (if previously fetched); if never fetched, the state says offline — it does not say "not catalogued". | ☐ Pass ☐ Fail |
| D-163 | In Airplane mode, try X2 search and Spotify fetch. | Honest offline errors; nothing fakes a result. Turn Airplane mode off and confirm both work again. | ☐ Pass ☐ Fail |
| D-164 | In Airplane mode, play a track whose artwork was never downloaded. | Track still plays; missing artwork shows a placeholder, no crash. | ☐ Pass ☐ Fail |

## 17. Background / lock-screen (Gates G-1, G-2, G-3, G-6)

Run §17 twice where marked: once booster OFF, once booster ON (300%).

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-170 | **(G-1, booster OFF)** Start a track in the app. Lock the phone mid-song. Leave it locked ≥ 2 minutes. | Audio keeps playing with the screen off the whole time — no stop, no stutter at lock. | ☐ Pass ☐ Fail |
| D-171 | **(G-1)** Unlock after D-170. | App shows the correct track and a position that advanced while locked. | ☐ Pass ☐ Fail |
| D-172 | **(G-1, booster ON)** Repeat D-170 + D-171 with the booster at 300% (limiter on). | Same as booster OFF: audio never stops, no stutter at lock/unlock. This is the test the 7627d41 incident demands. | ☐ Pass ☐ Fail |
| D-173 | **(G-2)** Lock the phone while playing. Read the lock screen. | Correct title, artist, album, artwork, elapsed time advancing, total duration. | ☐ Pass ☐ Fail |
| D-174 | **(G-2)** On the lock screen, tap play/pause; drag the lock-screen scrubber. | Play/pause works; the scrubber seeks and the position in the app follows (see D-104). | ☐ Pass ☐ Fail |
| D-175 | **(G-2)** Open Control Center while playing. | Same metadata and controls as the lock screen. | ☐ Pass ☐ Fail |
| D-176 | **(G-2)** Let the queue end with repeat OFF while the phone is locked. | Lock-screen metadata clears — no stale track (title/artwork) left showing. **Fail if a finished track lingers.** | ☐ Pass ☐ Fail |
| D-177 | **(G-3, booster OFF)** Queue 2+ tracks, lock the phone, let a track end. | Next track starts while still locked; lock screen updates to it (title/artwork/position reset). | ☐ Pass ☐ Fail |
| D-178 | **(G-3)** Repeat D-177 with repeat-all on the last track, then with repeat-one. | Repeat-all wraps to track 1 while locked; repeat-one restarts the same track while locked. | ☐ Pass ☐ Fail |
| D-179 | **(G-3, booster ON)** Repeat D-177 with the booster at 300%. | Next track starts while locked, no dropout, no silence, no crash. | ☐ Pass ☐ Fail |
| D-180 | **(G-3)** Queue a deleted-file track in the middle, phone locked. Play through it. | Player skips it and plays the next track. **Fail if playback stops silently.** | ☐ Pass ☐ Fail |
| D-181 | **(G-6, booster ON)** Booster 300%, limiter ON, normalization ON: lock mid-song, skip from the lock screen, let a track end while locked. | All pass (G-1 + G-3 conditions) with no dropout, no silence, no crash. | ☐ Pass ☐ Fail |
| D-182 | **(G-6)** App-switch test with booster ON: switch to another app for 1 minute, return. | Playback continued; position is correct. | ☐ Pass ☐ Fail |
| D-183 | **(G-6)** Booster 300%, limiter OFF (warning read first): lock mid-song and skip from the lock screen. | Works; note any audible difference vs limiter ON. **Turn the limiter back ON after.** | ☐ Pass ☐ Fail |

## 18. AirPods (Gates G-4, G-5)

Run §18 twice where marked: once booster OFF, once booster ON (300%).

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-190 | Connect AirPods. Play a track with the phone locked. Single-press an AirPod. | Toggles pause/play. | ☐ Pass ☐ Fail |
| D-191 | Double-press an AirPod (phone locked, playing). | Skips to the next track; lock screen and app agree on the new track. | ☐ Pass ☐ Fail |
| D-192 | Triple-press an AirPod (phone locked). | Goes to the previous track — or restarts the current track if > 4 s in. Record which behaviour the build has; it must match the in-app Previous button (D-081). | ☐ Pass ☐ Fail |
| D-193 | Repeat D-190–D-192 with the booster at 300%. | Same behaviour as booster OFF. | ☐ Pass ☐ Fail |
| D-194 | **(G-5)** AirPods connected, track playing: remove one AirPod / disconnect AirPods (or unplug wired headphones). | Playback **pauses** — it does not keep playing on the phone speaker, and the app does not crash. | ☐ Pass ☐ Fail |
| D-195 | Reconnect AirPods after D-194. | Playback stays paused until you press play (record the actual behaviour — after the interruption-resume decision this must match Ahmed's chosen policy). | ☐ Pass ☐ Fail |
| D-196 | **(G-5)** While playing, receive or make a phone call (or trigger Siri). | Playback pauses at call start. At call end, record whether it resumes or stays paused, and confirm it matches the documented policy. | ☐ Pass ☐ Fail |
| D-197 | While playing, trigger a short sound that should duck audio (notification / timer). | Record whether audio ducks and returns to full volume. (Observation — record, do not fail on it unless audio never returns.) | ☐ Pass ☐ Fail |
| D-198 | Play music through the phone speaker (no AirPods), then connect AirPods mid-track. | Audio moves to AirPods without stopping or restarting the track. | ☐ Pass ☐ Fail |

## 19. Storage & duplicates

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-200 | Settings → Storage dashboard. Read the totals. | Per-source usage is shown and the totals are consistent with the library size (no obviously wrong numbers). | ☐ Pass ☐ Fail |
| D-201 | Storage dashboard → Re-scan. | Scan completes; totals refresh. | ☐ Pass ☐ Fail |
| D-202 | Storage dashboard → duplicate scan (library contains the duplicate pair from P-13). | Duplicate group is found; the suggested keeper is the most-played copy. | ☐ Pass ☐ Fail |
| D-203 | Delete the duplicate via the dashboard's confirmed-only deletion. | Only the duplicate is deleted, after a confirmation; the keeper remains and plays. | ☐ Pass ☐ Fail |
| D-204 | Storage dashboard → "Remove N missing entries" (after D-015 / a deleted file exists). | Only confirmed removal happens; the missing entries are gone from the Library; no good tracks are removed. | ☐ Pass ☐ Fail |
| D-205 | Storage dashboard → run a cleanup action. | Cleanup is confirmed-only (nothing is deleted without a confirmation) and the freed space is reflected in the totals. | ☐ Pass ☐ Fail |

## 20. Backup / restore

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-210 | Settings → Backup → Export. Save the JSON. | Export succeeds; the file is a valid backup document (v2 format). | ☐ Pass ☐ Fail |
| D-211 | Settings → Backup → Restore → pick the export from D-210 → preview. | Preview shows what will be restored (tracks/playlists) BEFORE anything changes. | ☐ Pass ☐ Fail |
| D-212 | Confirm the restore from D-211. | Restore completes; existing library/playlists are **never overwritten** (restored items merge; nothing you had is lost). | ☐ Pass ☐ Fail |
| D-213 | Try restoring a file that is not a backup (e.g. a random JSON, or the playlist export from D-123). | Rejected with a clear error — never imported as a backup. | ☐ Pass ☐ Fail |
| D-214 | Restore a backup, then check the library. | Restored tracks that reference files not on this phone are flagged as missing (not silently broken, not claimed present). | ☐ Pass ☐ Fail |

## 21. Update check

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-220 | Settings → update-check card → Check for updates (online). | States one of: up-to-date / update available / no releases yet / error — honestly, matching the GitHub releases state. | ☐ Pass ☐ Fail |
| D-221 | If an update is shown as available: look for an install button. | There is NO fake install button. Copy says iOS cannot self-update and to sideload the new unsigned IPA; a "Copy Release Link" button is present. | ☐ Pass ☐ Fail |
| D-222 | Settings → update check in Airplane mode. | States offline (not "up-to-date", not an invented version). | ☐ Pass ☐ Fail |

## 22. Permissions

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-230 | Fresh install (or revoked permissions): open X1 and tap Listen. | iOS microphone permission prompt appears; denying gives the distinct mic-denied state with the Settings path (see D-143). | ☐ Pass ☐ Fail |
| D-231 | Import a local file via the Files picker on first use. | Files access works without a crash; no permission prompt is needed beyond the picker itself (or, if one appears, it is the system picker). | ☐ Pass ☐ Fail |
| D-232 | If the app requests notification permission, deny it, then trigger something that would notify (e.g. a download completing). | App works normally without notifications; no crash, no repeated re-prompting. | ☐ Pass ☐ Fail |
| D-233 | iOS Settings → Btmus → revoke microphone, then open X1. | Mic-denied state appears (not a crash, not a silent failure). Re-enable and confirm recovery. | ☐ Pass ☐ Fail |

## 23. Network interruption

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-240 | Start an X2 download, then turn on Airplane mode mid-download. | Download fails honestly with an error state; no partial track is added to the Library. | ☐ Pass ☐ Fail |
| D-241 | After D-240, turn Airplane mode off and retry the download. | Retry works (same-session failure) and the track imports. | ☐ Pass ☐ Fail |
| D-242 | Start a Telegram download, then switch from Wi-Fi to mobile data mid-download (or vice versa). | Download either completes or fails honestly — it does not hang forever or corrupt the file. | ☐ Pass ☐ Fail |
| D-243 | Open the Lyrics tab for a track with no cached lyrics, then turn on Airplane mode before lyrics load. | Lyrics show the offline state (not "not catalogued", not a hang). | ☐ Pass ☐ Fail |
| D-244 | With the network flapping (Wi-Fi off/on repeatedly), browse Library and play local tracks. | Local playback is unaffected by network state. | ☐ Pass ☐ Fail |

## 24. Corrupted files

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-250 | Import the deliberately corrupted file from P-12 (text file renamed `.mp3`). | Rejected with an error before copy/insert — never silently accepted as a track. | ☐ Pass ☐ Fail |
| D-251 | Import the truncated MP3 from P-12. | Rejected with an error (or, if it imports, it does not crash playback — record exactly what happens). | ☐ Pass ☐ Fail |
| D-252 | Import the non-audio `.mp4` video file from P-12 via the local importer. | Rejected with an error — a `video/*` payload is never accepted as audio. | ☐ Pass ☐ Fail |
| D-253 | If a corrupted file somehow got into the Library (via restore or an older build), tap it to play. | App reports an error / skips it — it does not hang, loop silence, or crash. | ☐ Pass ☐ Fail |

## 25. Duplicate imports

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-260 | Import the exact same file twice (same file, local import). | Second import is rejected as a duplicate (SHA-256) with a clear message; only one track exists in the Library. | ☐ Pass ☐ Fail |
| D-261 | Batch-import a folder containing a file that is already in the library plus new files. | Batch completes; the duplicate is skipped and reported in the snackbar; the new files import (the batch is not aborted by the duplicate). | ☐ Pass ☐ Fail |
| D-262 | Import a different file of the same song (different encoding/bitrate, same title/artist). | Record what happens: SHA-256 dedup will not catch a different file — note whether the app flags it as a possible duplicate (duplicate scan, §19) or imports it as a second track. (Observation — record, do not fail on it.) | ☐ Pass ☐ Fail |
| D-263 | Re-download a Telegram file already in the library (see D-024). | Skipped via `file_unique_id`, flagged "already in library". | ☐ Pass ☐ Fail |
| D-264 | Import a Spotify playlist containing tracks already in the library (see D-031). | Per-track "Already in library" chips; no duplicate tracks created. | ☐ Pass ☐ Fail |

## 26. Restarts

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-270 | Play a track, note track + position. Kill the app from the switcher. Relaunch. | Queue is as left (see D-116); playback is paused at the saved position; pressing play resumes from there. | ☐ Pass ☐ Fail |
| D-271 | Change settings (EQ preset, booster %, shuffle, repeat). Kill the app. Relaunch. | Settings persist (EQ, booster, shuffle, repeat — see also D-118). | ☐ Pass ☐ Fail |
| D-272 | Restart the iPhone itself. Launch the app. | App launches cleanly; library, playlists and queue state are intact. | ☐ Pass ☐ Fail |
| D-273 | After a restart, open Downloads. | Download history is intact; a task restored from a previous session shows Retry disabled (K-10), not a dead button. | ☐ Pass ☐ Fail |
| D-274 | After a restart, open the Lyrics tab for a track whose lyrics were cached before. | Cached lyrics load without network. | ☐ Pass ☐ Fail |

## 27. Lyrics (Phase 6 device items)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-280 | Play a track with synced LRC lyrics on LRCLIB. Open the Player → Lyrics tab. | Synced lyrics show with the active line highlighted; highlight timing follows the music (record any lag you notice — this is the timing check, and lag is a Fail only if the highlight is visibly wrong, e.g. a line early/late or stuck). | ☐ Pass ☐ Fail |
| D-281 | While synced lyrics play, watch auto-scroll. | The active line stays in view; scrolling feels smooth, not jumpy. Record how it feels — this is the auto-scroll feel check. | ☐ Pass ☐ Fail |
| D-282 | While synced lyrics play, tap a lyric line. | Playback seeks to that line's timestamp (tap-to-seek). | ☐ Pass ☐ Fail |
| D-283 | Skip to the next track quickly (before lyrics load), then to another. | Lyrics shown always belong to the currently playing track — never a stale track's lyrics. Scroll offset does not carry over to the next track. | ☐ Pass ☐ Fail |
| D-284 | Play a track with plain-only lyrics (no synced LRC). | Plain lyrics show WITHOUT a "(Synced)" label. | ☐ Pass ☐ Fail |
| D-285 | Play a track with no lyrics on LRCLIB. | Honest "not yet catalogued on LRCLIB" state — not a blank screen, not a wrong song's lyrics. | ☐ Pass ☐ Fail |
| D-286 | Play a track with cached lyrics, then turn on Airplane mode and replay it. | Cached lyrics show. (If never fetched, the state says offline — see D-162.) | ☐ Pass ☐ Fail |
| D-287 | In the Lyrics tab, tap Retry while offline, then go online and tap Retry again. | Offline retry falls back to stale cache (if any) and says so; online retry forces a fresh fetch. | ☐ Pass ☐ Fail |
| D-288 | Play a track whose title has a suffix like "(Official Audio)" / "(Official Lyric Video)". Open Lyrics. | Lyrics are found for the right song (title suffixes stripped for lookup) — not the wrong song, not "not catalogued" when the song is catalogued. | ☐ Pass ☐ Fail |

## 28. Smart Remix & measured audio (Phase 6 device items)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-290 | Smart Remix → pick a mix mode (smooth / party / chill / energy / random / arcMix). Play the generated mix. | Mix plays in the shown order. Record whether the sequence feels right for the mode (especially arcMix: warm-up → build → peak → cooldown). This is the audible Smart Remix quality check — note what you hear, good or bad. | ☐ Pass ☐ Fail |
| D-291 | Check the BPM shown for 3 real songs you know the tempo of (e.g. a ~90 BPM, a ~120 BPM and a ~140 BPM track). | Shown BPM is within ~2 BPM of the true tempo for percussive tracks. Record the numbers — this is the real-song BPM accuracy check. | ☐ Pass ☐ Fail |
| D-292 | Check the BPM shown for a non-percussive track (ambient / sustained pad / solo vocal). | No bogus tempo is shown (no tempo displayed, or an "estimated" mark — K-5). **Fail if a steady non-percussive track shows a confident-looking measured BPM.** | ☐ Pass ☐ Fail |
| D-293 | Smart Remix → build a mix, then "Save mix as playlist" (§12, D-128). Open the saved playlist. | Playlist order exactly matches the mix order shown on screen. | ☐ Pass ☐ Fail |
| D-294 | In Smart Remix, look at the plan/preview for a track whose BPM/energy is estimated (not measured). | Estimates are marked with `~` (or equivalent) — measured and estimated values are never presented identically. | ☐ Pass ☐ Fail |

## 29. Playback history

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-300 | Play 3 different tracks fully (or substantially). Home → Recently Played → "See all" (Playback History). | All 3 appear, most recent first, with "played X ago · played Nx" text. Tap one: it plays. | ☐ Pass ☐ Fail |
| D-301 | Play the same track twice. Check its history entry. | Play count increments (played 2x); only one entry for the track (not two rows). | ☐ Pass ☐ Fail |
| D-302 | Seek within a track, pause/resume, and play a track whose file is missing. Check history. | History records real plays only — resume/seek do not create extra records, and a missing file creates none. | ☐ Pass ☐ Fail |
| D-303 | Playback History → Clear (confirm). | History list empties, but play counts are kept (check: the duplicate-keeper suggestion in §19 still prefers the most-played copy). | ☐ Pass ☐ Fail |
| D-304 | After D-303, play a track again. | It reappears in history. | ☐ Pass ☐ Fail |

## 30. Design review (Phase 2 gate — on the XS Max)

| # | Steps | Expected result | Pass / Fail |
|---|---|---|---|
| D-310 | Open the fullscreen player from the Home tab. Swipe down on the player. | Player dismisses with a springy swipe-down gesture; the mini-player returns. | ☐ Pass ☐ Fail |
| D-311 | Open the fullscreen player from the Library tab (tap a track there). Swipe down. | Same swipe-down dismiss works from this tab too (both tabs — the Phase 2 gate requires both). | ☐ Pass ☐ Fail |
| D-312 | Open the fullscreen player; watch the artwork transition. Close it; watch it return. | Shared-element Hero morph: artwork grows into the player and shrinks back symmetrically — same easing/duration both ways, no jump. | ☐ Pass ☐ Fail |
| D-313 | Scroll the Library and Home lists; open screens; switch tabs. | Staggered list entrances, smooth page transitions, no jank in scrolling or player transitions. Haptic ticks on scrubber/controls where designed. | ☐ Pass ☐ Fail |
| D-314 | Read the whole app (Home header, player, Settings, About): brand, colours, typography. | Premium Apple Music-like look: rich dark theme with depth, BT-gradient accent system (violet `#6202E1` → magenta `#C4009B` → pink-red `#F70E42`), large typography, artwork-forward cards, generous spacing. Header reads "Btmus by Taboubi Ahmed". No Triforce, no black-and-white cheap look, no leftover cyan/gold/teal accents. | ☐ Pass ☐ Fail |
| D-315 | Force-quit, relaunch, watch the first paint. | No light frame / white flash on fresh load — first paint is dark. | ☐ Pass ☐ Fail |
| D-316 | Check safe areas on every main screen (notch, Home indicator, bottom nav). | No clipped text or controls, no content under the notch or Home indicator. | ☐ Pass ☐ Fail |
| D-317 | Check the app icon on the Home Screen and the splash screen. | Both show the new BT gradient mark (not the Triforce, not a placeholder). | ☐ Pass ☐ Fail |
| D-318 | Overall: use the app for 10 minutes of normal browsing/playing. | It feels like a finished, premium app — note anything that feels cheap, unfinished or inconsistent (that is a Fail with notes, even if no single check above caught it). | ☐ Pass ☐ Fail |

---

## Sign-off

| Field | Value |
|---|---|
| Tester | |
| Device / iOS version | |
| Build commit hash | |
| Date(s) of pass | |
| Checks passed (count) | / 196 |
| Checks failed (count) | |
| Checks not run (list) | |

**Failed checks** (copy the ID, the actual behaviour, and the settings in force):

| Check ID | What happened instead | Settings in force |
|---|---|---|
| | | |
| | | |
| | | |

**Notes / observations** (including the §0.4 known-limit sightings, the
observation-only checks D-197, D-262, and anything else worth recording):

-
-
-

> A failed gate blocks the Phase 7 gate verdict. A failure is not waived by
> "it works in the foreground", by a CI green run, or by re-running the check
> until it passes once. Record the first failure.
