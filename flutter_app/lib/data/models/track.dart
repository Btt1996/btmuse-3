class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? genre;
  final int durationSeconds;
  final String localFilePath;
  final String? artworkPath;
  final String? artworkUrl;
  final String format;
  final int fileSizeBytes;
  final String sha256;
  final String sourceProvider;
  final bool isFavorite;
  final int playCount;
  final int? lastPlayedAtMs;
  final int addedAtMs;
  final double? bpm;
  final double? energyScore;
  final bool isAnalysisEstimated;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.genre,
    required this.durationSeconds,
    required this.localFilePath,
    this.artworkPath,
    this.artworkUrl,
    required this.format,
    required this.fileSizeBytes,
    required this.sha256,
    required this.sourceProvider,
    this.isFavorite = false,
    this.playCount = 0,
    this.lastPlayedAtMs,
    required this.addedAtMs,
    this.bpm,
    this.energyScore,
    this.isAnalysisEstimated = true,
  });

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    String? genre,
    int? durationSeconds,
    String? localFilePath,
    String? artworkPath,
    String? artworkUrl,
    String? format,
    int? fileSizeBytes,
    String? sha256,
    String? sourceProvider,
    bool? isFavorite,
    int? playCount,
    int? lastPlayedAtMs,
    int? addedAtMs,
    double? bpm,
    double? energyScore,
    bool? isAnalysisEstimated,
  }) {
    return Track(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      localFilePath: localFilePath ?? this.localFilePath,
      artworkPath: artworkPath ?? this.artworkPath,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      format: format ?? this.format,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      sha256: sha256 ?? this.sha256,
      sourceProvider: sourceProvider ?? this.sourceProvider,
      isFavorite: isFavorite ?? this.isFavorite,
      playCount: playCount ?? this.playCount,
      lastPlayedAtMs: lastPlayedAtMs ?? this.lastPlayedAtMs,
      addedAtMs: addedAtMs ?? this.addedAtMs,
      bpm: bpm ?? this.bpm,
      energyScore: energyScore ?? this.energyScore,
      isAnalysisEstimated: isAnalysisEstimated ?? this.isAnalysisEstimated,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'genre': genre,
        'duration_seconds': durationSeconds,
        'local_file_path': localFilePath,
        'artwork_path': artworkPath,
        'artwork_url': artworkUrl,
        'format': format,
        'file_size_bytes': fileSizeBytes,
        'sha256': sha256,
        'source_provider': sourceProvider,
        'is_favorite': isFavorite ? 1 : 0,
        'play_count': playCount,
        'last_played_at_ms': lastPlayedAtMs,
        'added_at_ms': addedAtMs,
        'bpm': bpm,
        'energy_score': energyScore,
        'is_analysis_estimated': isAnalysisEstimated ? 1 : 0,
      };

  factory Track.fromMap(Map<String, dynamic> map) => Track(
        id: map['id'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        album: (map['album'] as String?) ?? 'Single',
        genre: map['genre'] as String?,
        durationSeconds: (map['duration_seconds'] as int?) ?? 0,
        localFilePath: map['local_file_path'] as String,
        artworkPath: map['artwork_path'] as String?,
        artworkUrl: map['artwork_url'] as String?,
        format: (map['format'] as String?) ?? 'mp3',
        fileSizeBytes: (map['file_size_bytes'] as int?) ?? 0,
        sha256: (map['sha256'] as String?) ?? '',
        sourceProvider: (map['source_provider'] as String?) ?? 'local',
        isFavorite: ((map['is_favorite'] as int?) ?? 0) == 1,
        playCount: (map['play_count'] as int?) ?? 0,
        lastPlayedAtMs: map['last_played_at_ms'] as int?,
        addedAtMs: (map['added_at_ms'] as int?) ?? 0,
        bpm: (map['bpm'] as num?)?.toDouble(),
        energyScore: (map['energy_score'] as num?)?.toDouble(),
        isAnalysisEstimated: ((map['is_analysis_estimated'] as int?) ?? 1) == 1,
      );
}
