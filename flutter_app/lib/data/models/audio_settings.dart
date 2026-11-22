class AudioSettings {
  final double volumeMultiplier; // 1.0 = 100%, up to 3.0 = 300%
  final bool limiterEnabled;
  final bool normalizeVolume;
  final double playbackSpeed;
  final String eqPreset;

  const AudioSettings({
    this.volumeMultiplier = 1.0,
    this.limiterEnabled = true,
    this.normalizeVolume = true,
    this.playbackSpeed = 1.0,
    this.eqPreset = 'Balanced',
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
  }) {
    return AudioSettings(
      volumeMultiplier: volumeMultiplier ?? this.volumeMultiplier,
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
      normalizeVolume: normalizeVolume ?? this.normalizeVolume,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      eqPreset: eqPreset ?? this.eqPreset,
    );
  }
}
