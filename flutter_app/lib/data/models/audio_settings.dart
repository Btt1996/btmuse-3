class AudioSettings {
  final double volumeMultiplier; // 1.0 = 100%, up to 3.0 = 300%
  final bool limiterEnabled;
  final bool normalizeVolume;
  final double playbackSpeed;
  final String eqPreset;

  /// Standalone crossfade (Phase 3, S-3): applies whenever it is on,
  /// regardless of Smart Remix. Previously these fields lived on
  /// [SmartRemixConfig], which forced users to enable a sequencing feature
  /// just to get overlap between ordinary tracks. The native equal-power
  /// crossfade itself is unchanged; only the gate moved.
  final bool crossfadeEnabled;
  final double crossfadeSeconds; // overlap duration, seconds (was int 6)

  const AudioSettings({
    this.volumeMultiplier = 1.0,
    this.limiterEnabled = true,
    this.normalizeVolume = true,
    this.playbackSpeed = 1.0,
    this.eqPreset = 'Balanced',
    this.crossfadeEnabled = false,
    this.crossfadeSeconds = 6.0,
  });

  static const List<double> boostPresets = [1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
  static const List<String> eqPresets = [
    'Balanced',
    'Warm Bass',
    'Vocal Clarity',
    'Late Night',
    'Studio Bright',
  ];

  int get boostPercent => (volumeMultiplier * 100).round();

  bool get isExtremeBoost => volumeMultiplier > 1.5;

  AudioSettings copyWith({
    double? volumeMultiplier,
    bool? limiterEnabled,
    bool? normalizeVolume,
    double? playbackSpeed,
    String? eqPreset,
    bool? crossfadeEnabled,
    double? crossfadeSeconds,
  }) {
    return AudioSettings(
      volumeMultiplier: volumeMultiplier ?? this.volumeMultiplier,
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
      normalizeVolume: normalizeVolume ?? this.normalizeVolume,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      eqPreset: eqPreset ?? this.eqPreset,
      crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
    );
  }
}
