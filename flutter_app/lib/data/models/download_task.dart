import 'dart:convert';

import 'x2_result.dart';

enum DownloadStage {
  waiting,
  searching,
  resolving,
  downloading,
  processing,
  importing,
  completed,
  failed,
  cancelled,
}

class DownloadTask {
  final String id;
  final String title;
  final String artist;
  final String providerId;
  final String sourceUrl;
  final String? artworkUrl;
  final DownloadStage stage;
  final double progress;
  final int receivedBytes;
  final int totalBytes;
  final String? errorMessage;
  final String? importedTrackId;

  /// The original [X2Result] this download was queued from, as a JSON
  /// string (Phase 4, F10 — schema v5 `payload_json`). Persisted so a
  /// failed task can be retried after an app restart, when the
  /// in-memory payload is gone. Null for tasks queued before payload
  /// persistence existed.
  final String? payloadJson;

  final int createdAtMs;
  final int updatedAtMs;

  const DownloadTask({
    required this.id,
    required this.title,
    required this.artist,
    required this.providerId,
    required this.sourceUrl,
    this.artworkUrl,
    required this.stage,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.importedTrackId,
    this.payloadJson,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  bool get isActive =>
      stage == DownloadStage.waiting ||
      stage == DownloadStage.searching ||
      stage == DownloadStage.resolving ||
      stage == DownloadStage.downloading ||
      stage == DownloadStage.processing ||
      stage == DownloadStage.importing;

  /// The original [X2Result] this download was queued from, decoded
  /// from [payloadJson]. Null when the task predates payload
  /// persistence (schema v5), when the stored JSON is corrupt or not
  /// an object, or when the decoded payload has no audio URL and no
  /// page URL to retry from — never throws, so a bad row can never
  /// crash the history screen or the retry path.
  X2Result? get payload {
    final raw = payloadJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final result = X2Result.fromJson(decoded);
      if ((result.audioUrl == null || result.audioUrl!.isEmpty) &&
          (result.externalPageUrl == null || result.externalPageUrl!.isEmpty)) {
        return null;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  DownloadTask copyWith({
    DownloadStage? stage,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? errorMessage,
    String? importedTrackId,
    int? updatedAtMs,
  }) {
    return DownloadTask(
      id: id,
      title: title,
      artist: artist,
      providerId: providerId,
      sourceUrl: sourceUrl,
      artworkUrl: artworkUrl,
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      importedTrackId: importedTrackId ?? this.importedTrackId,
      payloadJson: payloadJson,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'provider_id': providerId,
        'source_url': sourceUrl,
        'artwork_url': artworkUrl,
        'stage': stage.name,
        'progress': progress,
        'received_bytes': receivedBytes,
        'total_bytes': totalBytes,
        'error_message': errorMessage,
        'imported_track_id': importedTrackId,
        'payload_json': payloadJson,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs,
      };

  factory DownloadTask.fromMap(Map<String, dynamic> map) => DownloadTask(
        id: map['id'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        providerId: map['provider_id'] as String,
        sourceUrl: map['source_url'] as String,
        artworkUrl: map['artwork_url'] as String?,
        stage: DownloadStage.values.firstWhere(
          (e) => e.name == map['stage'],
          orElse: () => DownloadStage.failed,
        ),
        progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
        receivedBytes: (map['received_bytes'] as int?) ?? 0,
        totalBytes: (map['total_bytes'] as int?) ?? 0,
        errorMessage: map['error_message'] as String?,
        importedTrackId: map['imported_track_id'] as String?,
        // Absent on rows written before schema v5 (the column did not
        // exist yet) — those tasks simply have no retryable payload.
        payloadJson: map['payload_json'] as String?,
        createdAtMs: (map['created_at_ms'] as int?) ?? 0,
        updatedAtMs: (map['updated_at_ms'] as int?) ?? 0,
      );
}
