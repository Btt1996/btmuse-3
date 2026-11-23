# Share Extension & Siri — Btmus 3.0.5 (batch 2)

## What was added

### Share Extension (item 7 — Share-to / Open In)
- **Target** `ShareExtension` (`ios/ShareExtension/`, bundle
  `com.ahmed.btmu.ShareExtension`), embedded in the Runner app via the
  "Embed App Extensions" build phase. Sources:
  - `ShareViewController.swift` — hosts the SwiftUI view.
  - `ShareExtensionView.swift` — the handoff screen.
  - `Info.plist` — activation rule: one web URL, one text item, or one
    file (audio files arrive as file URLs).
  - `ShareExtension.entitlements` — App Group `group.com.ahmed.btmu`.
- **URLs / link text** are forwarded to Btt Music through the
  `bttmu://share?url=…` deep link (same pattern as the BttMusic
  SwiftUI app's extension). If iOS refuses the open from the
  extension — it sometimes does — the link is also copied to the
  pasteboard, and the screen says so.
- **Audio files** are copied into the App Group inbox
  (`<group>/ShareInbox/`). Btt Music drains that inbox on launch and
  on resume (`DeepLinkBootstrap`) and imports the files. The screen
  tells the user to open the app to finish.
- **Runner side**: `ios/Runner/Info.plist` gains the `bttmu` URL scheme
  (`CFBundleURLTypes`) and audio document types
  (`CFBundleDocumentTypes`: public.audio, mp3, m4a, aiff, wav,
  mpeg-4-audio), so the app also appears for "Open In" on audio files.
  `AppDelegate.swift` owns the `btmu/native_bridge` method channel:
  cold-launch link, live `onLink` forwarding, `openExternalUrl`, and
  `drainShareInbox`.

### Siri (item 13)
- `ios/Runner/SiriIntents.swift` — App Intents in the Runner target:
  - "Play some Btmus" / "Btmus me" / "Play Btmus" → plays the library.
  - "Shuffle Btmus" → shuffle-plays the library.
  - "Play \<playlist\> on Btmus" → plays that playlist by name.
- The intents open the app through `bttmu://siri/play`,
  `bttmu://siri/shuffle`, `bttmu://siri/playlist?name=…`; the Dart
  side (`DeepLinkBootstrap`) starts playback. An intent cannot reach
  the Flutter audio engine directly, so opening the app is the honest
  bridge — Siri opens Btt Music and playback starts there.

### Deep links handled by the app (`lib/core/deep_link.dart`)
| Link | Action |
| --- | --- |
| `bttmu://share?url=…` | Open X2 with the URL as the search query |
| `bttmu://youtube-import?url=…` | Same (legacy bridge URL) |
| `bttmu://siri/play` | Play the library |
| `bttmu://siri/shuffle` | Shuffle-play the library |
| `bttmu://siri/playlist?name=…` | Play that playlist (unknown name: nothing plays, no fake) |
| `file://…` (audio) | Import the file (`open-in` / `share-extension` source) |

## The App Group caveat — read this before sideloading

The audio-file handoff needs the App Group `group.com.ahmed.btmu`
provisioned. That requires a paid Apple Developer account; **the
unsigned build does not have it**. The code degrades gracefully
instead of pretending:

- **URL sharing works on the unsigned build** — the `bttmu://`
  scheme needs no entitlement, so sharing a link from Safari or
  another app hands it to Btt Music today.
- **Audio-file sharing on the unsigned build** shows an honest
  message in the extension ("Audio sharing needs the Btt Music App
  Group, which this unsigned build doesn't have. Save the file to
  Files and use Import from iPhone Files in Btt Music instead.") and
  does nothing else. `drainShareInbox` returns an empty list when the
  group container is unavailable.
- **With a paid account**, the group is already declared in both
  entitlements files; enable the App Groups capability for the Runner
  and ShareExtension targets with `group.com.ahmed.btmu` and the
  audio-file handoff works with no code change.

The same applies to Siri shortcuts: they are compiled into the app
and work on a sideloaded build, but Siri learns the phrases from use;
the shortcuts appear in Settings → Siri once the app has been
installed and opened.
