class X1Identification {
  final String provider;
  final String title;
  final String artist;
  final String album;
  final String? releaseDate;
  final int durationSeconds;
  final String? artworkUrl;
  final String? previewUrl;
  final String? externalId;
  final String? matchedTrackId;
  final bool isLocalLibraryMatch;
  final double confidence;
  final double? detectedBpm;
  final double? dominantFrequencyHz;
  final int identifiedAtMs;

  const X1Identification({
    required this.provider,
    required this.title,
    required this.artist,
    required this.album,
    this.releaseDate,
    this.durationSeconds = 0,
    this.artworkUrl,
    this.previewUrl,
    this.externalId,
    this.matchedTrackId,
    this.isLocalLibraryMatch = false,
    required this.confidence,
    this.detectedBpm,
    this.dominantFrequencyHz,
    required this.identifiedAtMs,
  });

  String get x2SearchQuery => '$artist $title'.trim();

  factory X1Identification.fromBackendJson(
    Map<String, dynamic> json,
    String provider,
  ) {
    return X1Identification(
      provider: provider,
      title: (json['title'] as String?) ?? 'Unknown Title',
      artist: (json['artist'] as String?) ?? 'Unknown Artist',
      album: (json['album'] as String?) ?? 'Single',
      releaseDate: json['releaseDate'] as String?,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      artworkUrl: json['artworkUrl'] as String?,
      previewUrl: json['previewUrl'] as String?,
      externalId: json['externalId'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.80,
      identifiedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
