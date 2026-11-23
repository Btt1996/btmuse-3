/// Pure crossfade trigger predicate (Phase 3, S-3).
///
/// Crossfade fires only when the user's crossfade setting is on — it is
/// no longer gated behind Smart Remix. The trigger window is the last
/// [crossfadeSeconds] of a track that is long enough to contain an
/// overlap (`duration > crossfadeSeconds + 2`), while a track is actually
/// playing, the queue has more than one track, and no crossfade is
/// already running. The position callback fires every 0.5 s, so the
/// window must be wider than the callback interval; with the 2 s slider
/// minimum the window is still 4× the interval.
///
/// Kept as a pure function (no audio, no platform) so the trigger
/// condition is unit-testable; the handler calls it from both the native
/// `onPosition` callback and the `just_audio` position listener.
/// The native equal-power law itself (`cos`/`sin`, 50 ms steps) lives in
/// `AudioEnginePlugin.startCrossfade` and its Dart mirror in
/// `VolumeDspMath.equalPowerCrossfade`; this predicate only decides *when*
/// to start it.
bool shouldTriggerCrossfade({
  required bool crossfadeEnabled,
  required bool isPlaying,
  required bool isCrossfading,
  required Duration remaining,
  required Duration duration,
  required double crossfadeSeconds,
  required int queueLength,
}) {
  if (!crossfadeEnabled || !isPlaying || isCrossfading) return false;
  if (queueLength <= 1) return false;
  if (duration.inMilliseconds <= (crossfadeSeconds + 2) * 1000) return false;
  final remainingSeconds = remaining.inMilliseconds / 1000.0;
  return remainingSeconds > 0 && remainingSeconds <= crossfadeSeconds;
}
