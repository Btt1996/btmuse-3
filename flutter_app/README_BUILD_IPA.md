# Btt Music 3.0 (`BTmu`) — iOS Build, Signing & Zero-Key Architecture Guide

- **Application Name:** Btt Music (`BTmu`)
- **Developer:** Ahmed Taboubi
- **Bundle Identifier:** `com.ahmed.btmu`
- **Target Platform:** iOS 18.0+ (Flutter 3.24+ / Dart 3.5+ / Swift 5)
- **Project Location:** `/flutter_app/`

---

## 1. Zero User-Configured API Keys

Btt Music 3.0 operates out of the box **without** requiring users to sign up for AudD, ACRCloud, YouTube Developer API, Spotify Developer API, SoundCloud API, or Jamendo keys:
- **X1 Identification:** Matches offline library songs via native Swift `AVAudioFile` PCM decoding + pure-Dart Spectral Constellation Landmark hashing (`LocalFingerprintEngine`), and queries zero-key MusicBrainz, Deezer, and iTunes public endpoints with playable 30s confirmation previews.
- **X2 Acquisition Priority:** VK public URL metadata + optional isolated user VK session, Telegram bot sync (token stored in iOS Keychain), YouTube zero-key oEmbed + optional self-hosted Piped/Invidious companion, SoundCloud public oEmbed, permissionless Audius Open Audio Protocol streams, Direct Audio streams, and Podcast/Music RSS XML enclosures.

---

## 2. Build Stage Matrix (Honest Status)

| Stage | Description | How to Produce | Can Run in Linux Sandbox? |
| --- | --- | --- | --- |
| **1. Dart Unit Tests & Analyze** | `flutter analyze`, `flutter test` | macOS CI / local Flutter SDK | **No** (Flutter/Dart SDK not installed in this Linux container) |
| **2. Debug iOS Build** | Simulator/dev build (`flutter run`) | macOS + Xcode 16+ + CocoaPods | **No** |
| **3. Release Build (No Codesign)** | `flutter build ios --release --no-codesign` | GitHub Actions `macos-latest` | **No** |
| **4. Unsigned IPA (`Payload/Runner.app`)** | Zipped `.ipa` for sideloading tools (AltStore/Sideloadly) | Produced automatically by `.github/workflows/flutter-ios-ipa.yml` | **No** |
| **5. Signed Installable IPA** | Ad-Hoc / Development / App Store signed `.ipa` | GitHub Actions with Apple Signing Secrets OR local Xcode Organizer | **No** |
| **6. Hardware iPhone Verification** | Lock-screen AirPods, Bluetooth disconnect, 300% speaker check | Physical iPhone on iOS 18+ | **No** (requires physical hardware) |

---

## 3. Producing an Installable Signed IPA via GitHub Actions

Add these **Repository Secrets** in GitHub (`Settings → Secrets and variables → Actions`):

1. `BUILD_CERTIFICATE_BASE64`: Base64 of your Apple Distribution or Development `.p12` certificate
2. `P12_PASSWORD`: Password for the `.p12` file
3. `PROVISIONING_PROFILE_BASE64`: Base64 of the `.mobileprovision` matching `com.ahmed.btmu`
4. `KEYCHAIN_PASSWORD`: Random temporary string for CI keychain
5. `APPLE_TEAM_ID`: Your 10-character Apple Developer Team ID

Trigger **Actions → Btt Music 3.0 iOS Build & IPA → Run workflow** to download `btmu-signed-ipa` (or `btmu-unsigned-ipa` when signing secrets are omitted).

### Optional X2 Environment Variables (Repository Variables)

None of these are mandatory, and no placeholder URL is invented if omitted:
- `X2_BACKEND_URL`: URL of your deployed Btt Music `server.ts` instance.
- `PIPED_API_URL`: Single Piped API origin or comma-separated failover list (e.g., `https://piped-1.example,https://piped-2.example`).
- `INVIDIOUS_API_URL`: Single Invidious API origin or comma-separated failover list.

All three can also be configured or tested live inside **Settings → X2 Backend & Multi-Provider Config** on iPhone.
