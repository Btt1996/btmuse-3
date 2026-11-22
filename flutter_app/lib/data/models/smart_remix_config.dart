enum SmartRemixMode {
  smoothMix,
  partyMix,
  chillMix,
  energyMix,
  randomSmartMix,
}

class SmartRemixConfig {
  final bool enabled;
  final SmartRemixMode mode;
  final int crossfadeSeconds;
  final bool beatMatchHint;

  const SmartRemixConfig({
    this.enabled = false,
    this.mode = SmartRemixMode.smoothMix,
    this.crossfadeSeconds = 6,
    this.beatMatchHint = true,
  });

  SmartRemixConfig copyWith({
    bool? enabled,
    SmartRemixMode? mode,
    int? crossfadeSeconds,
    bool? beatMatchHint,
  }) {
    return SmartRemixConfig(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      beatMatchHint: beatMatchHint ?? this.beatMatchHint,
    );
  }
}
