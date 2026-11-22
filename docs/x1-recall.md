# X1 Recall — How It Is Measured, and What It Does Not Prove

## The headline, stated honestly

**Synthetic recall is not real-song recall.** The harness in
`flutter_app/test/x1_recall_benchmark_test.dart` proves the local
fingerprint matcher works end-to-end on clean tonal audio. It says nothing
about identifying a real song played in a room. That gate is still open and
can only be measured on-device (see "What still needs the device" below).

## How recall is measured

- **Signals:** 8 synthetic "tracks" synthesized in-memory as PCM — summed
  sine partials at distinct fundamentals (220–415 Hz) plus a 1.5× harmonic,
  with ±40 Hz FM at 1.5 Hz so the spectrum moves over time. 8 seconds each
  at 11,025 Hz mono, the same sample rate the mic path records at.
- **Index:** each track is fingerprinted once with
  `LocalFingerprintEngine.extractLandmarks` (Radix-2 FFT 1024, Hann window,
  5 log-frequency bands, anchor–target landmark hashing) into an 8-track
  index — the same code path the app uses against the SQLite index.
- **Clips:** 4-second slices are cut from the tracks and identified with
  `matchSampleAgainstIndex` using the **production defaults**
  (`minAlignedHits: 6`, `minAlignedFraction: 0.02`) — no test-only
  loosening. Recall = clips correctly identified / clips attempted.
- **Noise:** white noise is added at a stated SNR, where
  SNR = 20·log₁₀(rms(signal) / rms(noise)). Noise uses a fixed seed
  (Box–Muller Gaussian over `dart:math`), so the harness is deterministic.
- **Rejection:** an unrelated chord and pure white noise must return no
  match (`null`).

## Measured numbers

Measured with a faithful Python port of the engine (same FFT size, Hann
window, bands, 0.002 magnitude floor, hashing with dt 1–10 / max 5 pairs,
same offset-histogram match with the same floors) and the same synth, clip
offsets, and 8 tracks as the Dart harness. The port also reproduced the
existing engine test's rejection case (unrelated chord vs a single-track
index → null), which cross-checks the port against the Dart engine.

| Case | Measured | Gate in the Dart test |
|---|---|---|
| Clean 4 s clips, offset 1.0 s | **8/8** (worst match: 272 aligned hashes vs a required floor of 42) | 8/8 |
| Time-shifted 4 s clips, offset 2.0 s (~1 s shift) | **8/8** | ≥ 14/16 combined with the row below |
| Time-shifted 4 s clips, offset 1.37 s (fractional, mid-frame: the 512-sample hop is ~46 ms) | **8/8** | ≥ 14/16 combined with the row above |
| 4 s clips + white noise, SNR 10 dB | **8/8** (worst match: 190 aligned vs floor 42) | ≥ 7/8 |
| 4 s clips + white noise, SNR 0 dB | **8/8** (worst match: 71 aligned vs floor 42) | Not gated — headroom only |
| 3 s clips + white noise, SNR 10 dB | **8/8** | Not gated |
| 2 s clips + white noise, SNR 10 dB | **8/8** | Not gated |
| Rejection: unrelated chord [150, 275, 520, 1100], 3 s | **null** (no match) | Must be null |
| Rejection: pure white noise, 3 s | **null** (no match) | Must be null |

Every gate is set **below** the measured value, so ordinary floating-point
differences between the port's FFT and Dart's radix-2 FFT cannot flip the
gate. The Dart test itself is the regression gate: it **fails** if recall
drops below the documented threshold. If it ever fails on CI or a dev
machine, re-measure before touching the thresholds — do not lower them
silently.

Run it with:

```sh
cd flutter_app
flutter test test/x1_recall_benchmark_test.dart
```

Note: the Dart test was **not** executed while writing this change — the
authoring environment has no Dart/Flutter toolchain. The numbers above are
from the Python port; the first `flutter test` run is what promotes them
from "measured in simulation" to "measured in Dart".

## Landmark counts behind the "try a longer sample" hint

The screen shows a "try a longer sample (up to 8 s)" hint when a local
search finds no match and fewer than **100** landmarks were extracted.
Measured landmark counts for a tonal clip (same port):

| Clip | Landmarks |
|---|---|
| Silence, 3 s | 0 |
| Tonal, 0.25 s | ~75 |
| Tonal, 0.5 s | ~200 |
| Tonal, 1 s | ~475 |
| Tonal, 2 s | ~1,020 |
| Tonal, 3 s | ~1,545 |
| Tonal, 4 s | ~2,070 |
| Full track, 8 s | ~3,600–4,100 |

Below 100 landmarks the sample holds under ~0.3 s of usable tonal audio
(or near-silence), so a longer sample is the actionable fix — not a
different song. Real songs vary in landmark density, so the hint only fires
on a no-match with a genuinely thin sample.

## What this does NOT prove

- **Real songs.** Stationary FM chords are the easy case: stable partials,
  no vocals, no drums, no transients, no key changes, no intros that differ
  from the chorus. Real music is harder in every dimension.
- **Room acoustics.** No reverb, no speaker colouration, no distance
  attenuation, no mic noise floor, no codec artefacts, no background
  conversation or traffic.
- **Library scale.** 8 tracks is a toy index. False-positive pressure grows
  with index size (see the limitation below), and real libraries hold
  hundreds of tracks.
- **Clip alignment.** The harness cuts clips from the same PCM that was
  indexed. A mic recording is a re-performance through air, not a slice of
  the file.

## Known limitations found while measuring

- **Near-coincident sustained partials can false-positive.** A first
  rejection candidate, chord [180, 310, 590, 990], matched track_6: its
  310 Hz partial shares an FFT bin with track_6's 311.13 Hz fundamental for
  the whole 3 s clip (bin width is ~10.8 Hz, FM is identical), aligning
  30 hashes against the 25-hash floor (2% of ~1,236 sample landmarks).
  The 2% relative floor was tuned when the index held one or a few tracks;
  taking the max over 8 tracks inflates chance alignments. The harness
  uses a chord that clears every track's partials instead, but the
  underlying weakness is real and worth a follow-up: a louder floor, or a
  minimum absolute margin over the runner-up track, for larger libraries.
- **Time-reversal still matches.** A time-reversed 3 s clip of track_1
  matched track_1 with 320 aligned hashes. For stationary FM tones the
  hash set is largely time-symmetric; real music with transients should
  differ, but reversal is not a valid rejection case for this engine.

## What still needs the device

The plan-item-23 gate — **"X1 identifies a real song played in the room"**
— needs Ahmed's iPhone XS Max, and has not been measured:

1. Mic permission granted, app in foreground, song played from a speaker
   in the same room (not headphones, not the same device).
2. Several real songs across genres, each tried at least twice: once in a
   quiet room, once with ordinary background noise (conversation/TV).
3. Record, for each attempt: song, clip length, landmarks extracted,
   match or no-match, and confidence. A song counts as identified only if
   the local match is the correct track.
4. Also record the failure modes separately: mic denied, no match, wrong
   match — the screen now shows distinct states for each, so the device
   test can tell them apart.

Until that run exists, any claim about real-song recall is unmeasured.
