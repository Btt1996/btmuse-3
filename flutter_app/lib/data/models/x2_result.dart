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
    String? providerId,
    String? providerLabel,
    double? matchScore,
    bool? audioAvailable,
    bool? downloadAuthorized,
    String? audioUrl,
    String? authorizationNote,
  }) {
    return X2Result(
      id: id,
      providerId: providerId ?? this.providerId,
      providerLabel: providerLabel ?? this.providerLabel,
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

  /// JSON round-trip for persisting a download payload (Phase 4, F10).
  /// Every field is a JSON-safe primitive (String / int / double /
  /// bool / null), so the payload serializes cleanly with no custom
  /// encoding. Keys mirror the field names.
  Map<String, dynamic> toJson() => {
        'id': id,
        'providerId': providerId,
        'providerLabel': providerLabel,
        'title': title,
        'artist': artist,
        'album': album,
        'durationSeconds': durationSeconds,
        'artworkUrl': artworkUrl,
        'audioUrl': audioUrl,
        'externalPageUrl': externalPageUrl,
        'format': format,
        'fileSizeBytes': fileSizeBytes,
        'audioAvailable': audioAvailable,
        'downloadAuthorized': downloadAuthorized,
        'licenseName': licenseName,
        'authorizationNote': authorizationNote,
        'matchScore': matchScore,
      };

  /// Defensive decode of [toJson] output. Missing keys fall back to the
  /// constructor defaults and wrong-typed values are ignored (never a
  /// throw), so a partially-corrupt stored payload still retries with
  /// best-effort data instead of crashing the retry path. Callers that
  /// need a usable payload should check `audioUrl` / `externalPageUrl`
  /// — see `DownloadTask.payload`, which does exactly that.
  factory X2Result.fromJson(Map<String, dynamic> json) {
    String s(String key, [String fallback = '']) {
      final v = json[key];
      return v is String ? v : fallback;
    }

    String? ns(String key) {
      final v = json[key];
      return v is String ? v : null;
    }

    int i(String key, [int fallback = 0]) {
      final v = json[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return fallback;
    }

    int? ni(String key) {
      final v = json[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    bool b(String key, [bool fallback = false]) {
      final v = json[key];
      return v is bool ? v : fallback;
    }

    double d(String key, [double fallback = 0.0]) {
      final v = json[key];
      return v is num ? v.toDouble() : fallback;
    }

    return X2Result(
      id: s('id'),
      providerId: s('providerId'),
      providerLabel: s('providerLabel'),
      title: s('title'),
      artist: s('artist'),
      album: s('album'),
      durationSeconds: i('durationSeconds'),
      artworkUrl: ns('artworkUrl'),
      audioUrl: ns('audioUrl'),
      externalPageUrl: ns('externalPageUrl'),
      format: ns('format'),
      fileSizeBytes: ni('fileSizeBytes'),
      audioAvailable: b('audioAvailable'),
      downloadAuthorized: b('downloadAuthorized'),
      licenseName: ns('licenseName'),
      authorizationNote: s('authorizationNote'),
      matchScore: d('matchScore'),
    );
  }
}
