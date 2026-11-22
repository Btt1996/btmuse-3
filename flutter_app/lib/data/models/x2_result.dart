class X2Result {
  final String id;
  final String providerId;
  final String providerLabel;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final String? artworkUrl;
  final String? audioUrl;
  final String? externalPageUrl;
  final String? format;
  final int? fileSizeBytes;
  final bool audioAvailable;
  final bool downloadAuthorized;
  final String? licenseName;
  final String authorizationNote;
  final double matchScore;

  const X2Result({
    required this.id,
    required this.providerId,
    required this.providerLabel,
    required this.title,
    required this.artist,
    required this.album,
    this.durationSeconds = 0,
    this.artworkUrl,
    this.audioUrl,
    this.externalPageUrl,
    this.format,
    this.fileSizeBytes,
    required this.audioAvailable,
    required this.downloadAuthorized,
    this.licenseName,
    required this.authorizationNote,
    this.matchScore = 0.0,
  });

  X2Result copyWith({
    double? matchScore,
    bool? audioAvailable,
    bool? downloadAuthorized,
    String? audioUrl,
    String? authorizationNote,
  }) {
    return X2Result(
      id: id,
      providerId: providerId,
      providerLabel: providerLabel,
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
      artworkUrl: artworkUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      externalPageUrl: externalPageUrl,
      format: format,
      fileSizeBytes: fileSizeBytes,
      audioAvailable: audioAvailable ?? this.audioAvailable,
      downloadAuthorized: downloadAuthorized ?? this.downloadAuthorized,
      licenseName: licenseName,
      authorizationNote: authorizationNote ?? this.authorizationNote,
      matchScore: matchScore ?? this.matchScore,
    );
  }
}
