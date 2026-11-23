# Siri — Btmus 3.0.5 (batch 2, item 13)

## What was added

- `ios/Runner/SiriIntents.swift` — App Intents in the Runner target:
  - "Play some Btmus" / "Btmus me" / "Play Btmus" → plays the library.
  - "Shuffle Btmus" → shuffle-plays the library.
  - "Play \<playlist\> on Btmus" → plays that playlist by name.
- The intents open the app through `bttmu://siri/play`,
  `bttmu://siri/shuffle`, `bttmu://siri/playlist?name=…`; the Dart
  side (`DeepLinkBootstrap`) starts playback. An intent cannot reach
  the Flutter audio engine directly, so opening the app is the honest
  bridge — Siri opens Btt Music and playback starts there.
- The `bttmu` URL scheme lives in `ios/Runner/Info.plist`
  (`CFBundleURLTypes`); it needs no entitlement.

## Deep links handled by the app (`lib/core/deep_link.dart`)

| Link | Action |
| --- | --- |
| `bttmu://siri/play` | Play the library |
| `bttmu://siri/shuffle` | Shuffle-play the library |
| `bttmu://siri/playlist?name=…` | Play that playlist (unknown name: nothing plays, no fake) |

## Notes

- Siri shortcuts are compiled into the app and work on a sideloaded
  build, but Siri learns the phrases from use; the shortcuts appear
  in Settings → Siri once the app has been installed and opened.
- The Share Extension / Open In feature (batch 2, item 7) was
  **removed on 2026-11-23** at Ahmed's decision, for speed: the
  extension target, its sources, the audio document types ("Open In"),
  the App Group, the `bttmu://share` / `bttmu://youtube-import`
  deep-link shapes, the `file://` import branch, and the
  `drainShareInbox` bridge were all taken out. If the feature is ever
  wanted back, it has to be re-added as a whole — the pieces above
  were removed together, deliberately.
