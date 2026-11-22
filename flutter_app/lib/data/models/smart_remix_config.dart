enum SmartRemixMode {
  smoothMix,
  partyMix,
  chillMix,
  energyMix,
  randomSmartMix,
  // Phase 6: the full Λ arc — warm-up → build → peak → cooldown.
  // Appended last; the mode is persisted by name with a smoothMix
  // fallback (SecureCredentialsStore), so existing installs are safe.
  arcMix,
}

class SmartRemixConfig {
  final SmartRemixMode mode;

  /// Hint only: nothing in the handler or the native plugin reads it yet.
  /// The crossfade itself is a fixed-duration equal-power volume ramp,
  /// not tempo-aligned, so do not describe it as beat-matched anywhere.
  final bool beatMatchHint;

  // NOTE (Phase 3, S-3): crossfade moved to [AudioSettings]
  // (`crossfadeEnabled` / `crossfadeSeconds`). Smart Remix now owns
  // sequencing only. The old `crossfadeSeconds` field was removed here;
  // existing users are migrated once by
  // `SecureCredentialsStore.loadAudioSettings`, which reads the legacy
  // `btmu_remix_crossfade` / `btmu_remix_enabled` keys and copies them
  // into the new audio-settings keys on first launch after upgrade.
  //
  // NOTE (Phase 3, coordinator decision): the `enabled` flag was dropped
  // as vestigial. It used to mean "crossfade on" (the crossfade trigger
  // gated on it); after S-3 nothing reads it — sequencing is a one-shot
  // launch action (build a plan, play it), not a persistent mode — and
  // its only UI writer, the switch on the Smart Remix screen, was
  // removed by W3. The Launch button's `config.copyWith(enabled: true)`
  // call was removed at integration for the same reason.

  const SmartRemixConfig({
    this.mode = SmartRemixMode.smoothMix,
    this.beatMatchHint = true,
  });

  SmartRemixConfig copyWith({
    SmartRemixMode? mode,
    bool? beatMatchHint,
  }) {
    return SmartRemixConfig(
      mode: mode ?? this.mode,
      beatMatchHint: beatMatchHint ?? this.beatMatchHint,
    );
  }
}
