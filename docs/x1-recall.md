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
  (`minAlignedHits: 6`, `minAlignedFraction: 0.02`, plus the Phase 6
  runner-up margin: best track must beat the second-best by a gap of at
  least the relative floor and a ratio of at least 1.5 — see "Runner-up
  margin" below) — no test-only loosening. Recall = clips correctly
  identified / clips attempted.
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
| Rejection: near-coincident chord [180, 310, 590, 990], 3 s (Phase 6 margin) | **null** — best 30 vs runner-up 15, gap 15 < floor 25 | Must be null (`margin: near-coincident partial chord is rejected`) |
| Rejection: near-coincident chord [180, 310, 590, 990], 4 s (Phase 6 margin) | **null** — best 38 vs runner-up 19, gap 19 < floor 42 | Not gated — headroom only |

## Runner-up margin (Phase 6)

**The rule.** `matchSampleAgainstIndex` now tracks the best aligned-offset
count per candidate track, not just the global best, and accepts a match
only when the best track beats the runner-up by BOTH:

- an absolute gap of at least the relative floor
  (`ceil(sampleHashes * 0.02)`), AND
- a ratio of at least `minRunnerUpMarginRatio = 1.5`.

With a single candidate track there is no runner-up and the margin is
vacuous (the floor alone decides). A close second-best is treated as
ambiguous and returns no match rather than a possibly-wrong match.

**Why.** The 2% relative floor was tuned when the index held one or a few
tracks; taking the max over 8 tracks inflates chance alignments. The
documented Phase 5 case — chord [180, 310, 590, 990] matching track_6
with 30 aligned hashes against a 25-hash floor — cleared the floor while
track_2 aligned 15. The margin rejects it (gap 15 < floor 25).

**Measured (Python port of the engine, same method as the table above).**
True matches have enormous headroom over the margin; the rejection cases
fail it clearly:

| Case | Best | Runner-up | Gap vs floor | Ratio | Verdict |
|---|---|---|---|---|---|
| Clean 4 s clips, worst (track_6) | 272 | 7 | 265 vs 37 | 38.9 | Accept |
| Clean 4 s clips, best | 528 | 8 | 520 vs 39 | 66.0 | Accept |
| SNR 0 dB 4 s clips, worst (track_6) | 71 | 6 | 65 vs 42 | 11.8 | Accept |
| SNR 0 dB 4 s clips, best | 198 | 12 | 186 vs 42 | 16.5 | Accept |
| Near-coincident [180, 310, 590, 990], 3 s | 30 | 15 | 15 vs 25 | 2.0 | **Reject** |
| Near-coincident [180, 310, 590, 990], 4 s | 38 | 19 | 19 vs 42 | 2.0 | **Reject** |
| Unrelated [150, 275, 520, 1100], 3 s | 22 | 8 | 14 vs 25 | 2.8 | Reject (floor) |
| White noise, 3 s, seed 77 | 12 | 7 | 5 vs 31 | 1.7 | Reject (floor) |

**Tradeoff, stated plainly.** The margin trades recall for precision at
the ambiguous edge: a clip that genuinely matches a track but aligns
nearly as well on another track now returns no match instead of a guess.
That is the conservative direction — a missed identification is visible
("no match, try a longer sample") while a wrong identification is
silent. The cost is measurable on short, very noisy true clips, which
are NOT gated: 2 s clips at SNR 0 dB measure worst gap 23 vs floor 21
(track_6: best 28 vs runner-up 5) and gap 23 vs floor 21 (track_7: best
26 vs runner-up 3) — a 2-hash margin that could flip to no-match under
FFT floating-point differences between the port and Dart, or on real
audio. The gated 4 s cases have 23+ hashes of headroom (worst gap 65 vs
floor 42). If a future real-song test shows true 4 s matches landing
near the margin, re-measure before touching the constants — do not lower
them silently.

**What the margin does NOT fix.** While measuring, a stronger
near-coincidence was found: a chord sharing ONE sustained partial (plus
its 1.5× harmonic, under the same ±40 Hz FM) with a track still
false-positives confidently — [311, 500, 900, 1500] matches track_6 with
71 aligned hashes vs a 25 floor (gap 63, ratio 8.9), and
[220, 600, 900, 1500] matches track_1 with 49 vs 9. The shared
fundamental and its harmonic follow identical bin trajectories for the
whole clip, so the margin cannot separate them from a true match without
also killing true recall. This is a limitation of landmark hashing on
stationary tones with identical vibrato, not of the margin; real songs
rarely hold one sustained note with identical vibrato against another
song for 3 s, and real music has transients that break the symmetry —
but that is an assumption, not a measurement. The device gate (real
songs on Ahmed's iPhone XS Max) is the arbiter. See "Known limitations".

**Synthetic recall is not real-song recall.** The margin was tuned and
validated on the same synthetic chords as the rest of this harness. It
says nothing about real songs in a room, and it does not change the
device gate below.

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
from "measured in simulation" to "measured in Dart". The same applies to
the Phase 6 changes (runner-up margin, tempo-estimator gates, and the new
`smart_remix_telemetry_test.dart`): port-measured, Dart-unrun.

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

- **Near-coincident sustained partials can false-positive — partly
  fixed by the Phase 6 runner-up margin.** A first rejection candidate,
  chord [180, 310, 590, 990], matched track_6: its 310 Hz partial shares
  an FFT bin with track_6's 311.13 Hz fundamental for the whole 3 s clip
  (bin width is ~10.8 Hz, FM is identical), aligning 30 hashes against
  the 25-hash floor (2% of ~1,236 sample landmarks). The 2% relative
  floor was tuned when the index held one or a few tracks; taking the max
  over 8 tracks inflates chance alignments. The Phase 6 margin rejects
  this chord (best 30 vs runner-up 15, gap 15 < floor 25) — see "Runner-up
  margin" above — but it does NOT fix the stronger case: a chord sharing
  one sustained partial plus its 1.5× harmonic under identical FM still
  false-positives confidently ([311, 500, 900, 1500] → track_6, 71
  aligned vs floor 25; [220, 600, 900, 1500] → track_1, 49 vs 9),
  because the shared trajectories are identical for the whole clip. No
  margin separates those from true matches without also killing true
  recall; real songs are assumed harder to confuse this way, but that is
  unmeasured until the device gate.
- **Time-reversal still matches.** A time-reversed 3 s clip of track_1
  matched track_1 with 320 aligned hashes. For stationary FM tones the
  hash set is largely time-symmetric; real music with transients should
  differ, but reversal is not a valid rejection case for this engine.

## Tempo estimation (Phase 6, Smart Remix)

The same engine file owns Smart Remix telemetry
(`analyzeTelemetry` → `_estimateTempoBpm`), verified in Phase 6 with
the same Python-port method. The pre-Phase-6 estimator ran a raw
(non-mean-removed, un-normalised) autocorrelation over 25 ms mean-absolute
envelope frames and returned the argmax lag unconditionally — so a steady
440 Hz sine, white noise, and even silence all "measured" **171.4 BPM**
(lag 14, the first argmax on a flat correlation), and that value was
stored with `is_analysis_estimated = 0`. Phase 6 mean-removes the
envelope, normalises each lag by the overlap count, and returns 0 ("no
tempo") unless the envelope really modulates (CV ≥ 0.25) and the
autocorrelation peak is real (normalised peak ≥ 0.30). Port-measured:

| Signal (8 s, 11,025 Hz) | Old estimator | New estimator | Truth |
|---|---|---|---|
| Periodic bursts, 90 / 100 / 120 / 128 / 140 / 160 BPM | 88.9 / 100 / 120 / 126.3 / 141.2 / 160 | same | ±~2 BPM (40 fps quantisation) |
| Periodic bursts + noise, 120 BPM | 120 | 120 | 120 |
| Steady 440 Hz sine | **171.4** | **0 (no tempo)** | no beats |
| Steady white noise | **171.4** | **0** | no beats |
| Silence | **171.4** | **0** | no beats |
| FM chord, no beats | 64.9 | **0** | no beats |
| 60 BPM bursts (below the 65–171 range) | 64.9 | **0** | 60, out of range |
| 180 BPM bursts (above range) | 88.9 | 88.9 | 180, folds to half-time |

Remaining limits: the detector covers 65–171 BPM only; above-range tempi
fold to half-time (180 → 88.9) because there is no octave
disambiguation; 40 fps quantisation gives ±~2 BPM error. The React
estimator (`src/services/audioAnalysis.ts`) uses onset-flux plus octave
folding into 70–180 and is the model for a future fix. Energy is RMS
× 2.2 clamped to [0.1, 1.0] — monotonic, so ordering is preserved, but
the absolute score is not a calibrated loudness measure. Tests:
`flutter_app/test/smart_remix_telemetry_test.dart`. Real-song BPM
accuracy is unmeasured — same device gate as X1.

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
