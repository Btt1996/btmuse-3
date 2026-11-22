import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/data/models/download_task.dart';
import 'package:btmu/data/models/x2_result.dart';

// Phase 4, F10 — downloads retry-after-restart, DB-free evidence.
//
// The payload round-trip and the task-row round-trip are pure Dart and
// run here. The notifier wiring (`loadHistory` rehydration,
// `retryTask` falling back to the persisted row) needs sqflite +
// `HistoryRepository`, which have no host implementation under
// `flutter test`, so that wiring is verified by code inspection and
// by the CI run — see REPORT.md. What these tests pin down is the
// contract the wiring depends on: a payload survives JSON + SQLite
// map encoding, a pre-v5 row has no payload, and corrupt stored JSON
// never throws.

X2Result _result() {
  return const X2Result(
    id: 'audius_42',
    providerId: 'audius',
    providerLabel: 'Audius',
    title: 'Skyline',
    artist: 'Btt',
    album: 'Single',
    durationSeconds: 214,
    artworkUrl: 'https://cdn.example.org/cover.jpg',
    audioUrl: 'https://cdn.example.org/skyline.mp3',
    externalPageUrl: 'https://audius.co/btt/skyline',
    format: 'MP3',
    fileSizeBytes: 5120000,
    audioAvailable: true,
    downloadAuthorized: true,
    licenseName: 'CC-BY',
    authorizationNote: 'Authorized direct MP3 from Audius.',
    matchScore: 0.87,
  );
}

DownloadTask _task({String? payloadJson}) {
  return DownloadTask(
    id: 'task-1',
    title: 'Skyline',
    artist: 'Btt',
    providerId: 'audius',
    sourceUrl: 'https://cdn.example.org/skyline.mp3',
    artworkUrl: 'https://cdn.example.org/cover.jpg',
    stage: DownloadStage.failed,
    progress: 0.4,
    receivedBytes: 2048000,
    totalBytes: 5120000,
    errorMessage: 'Download failed.',
    payloadJson: payloadJson,
    createdAtMs: 1000,
    updatedAtMs: 2000,
  );
}

void main() {
  group('X2Result JSON round-trip (F10 payload)', () {
    test('toJson/fromJson preserves every field', () {
      final original = _result();
      final restored = X2Result.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.providerId, original.providerId);
      expect(restored.providerLabel, original.providerLabel);
      expect(restored.title, original.title);
      expect(restored.artist, original.artist);
      expect(restored.album, original.album);
      expect(restored.durationSeconds, original.durationSeconds);
      expect(restored.artworkUrl, original.artworkUrl);
      expect(restored.audioUrl, original.audioUrl);
      expect(restored.externalPageUrl, original.externalPageUrl);
      expect(restored.format, original.format);
      expect(restored.fileSizeBytes, original.fileSizeBytes);
      expect(restored.audioAvailable, original.audioAvailable);
      expect(restored.downloadAuthorized, original.downloadAuthorized);
      expect(restored.licenseName, original.licenseName);
      expect(restored.authorizationNote, original.authorizationNote);
      expect(restored.matchScore, original.matchScore);
    });

    test('toJson output is JSON-encodable (what the DB column stores)', () {
      final encoded = jsonEncode(_result().toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(X2Result.fromJson(decoded).title, 'Skyline');
    });

    test('fromJson with missing keys falls back to defaults, never throws', () {
      final restored = X2Result.fromJson({});
      expect(restored.id, '');
      expect(restored.title, '');
      expect(restored.durationSeconds, 0);
      expect(restored.audioAvailable, isFalse);
      expect(restored.downloadAuthorized, isFalse);
      expect(restored.authorizationNote, '');
      expect(restored.matchScore, 0.0);
      expect(restored.audioUrl, isNull);
    });

    test('fromJson with wrong-typed values ignores them, never throws', () {
      final restored = X2Result.fromJson({
        'id': 123,
        'durationSeconds': '214',
        'audioAvailable': 'yes',
        'matchScore': 'high',
        'fileSizeBytes': 5120000.5,
      });
      expect(restored.id, '');
      expect(restored.durationSeconds, 0);
      expect(restored.audioAvailable, isFalse);
      expect(restored.matchScore, 0.0);
      expect(restored.fileSizeBytes, 5120000);
    });

    test('fromJson keeps a page-only payload (no direct audio URL)', () {
      final restored = X2Result.fromJson({
        'id': 'vk_1',
        'providerId': 'vk',
        'providerLabel': 'VK Music',
        'title': 'VK Track',
        'artist': 'VK Artist',
        'album': 'VK Reference',
        'audioUrl': null,
        'externalPageUrl': 'https://vk.com/audio1',
        'audioAvailable': false,
        'downloadAuthorized': false,
        'authorizationNote': 'Metadata only.',
      });
      expect(restored.audioUrl, isNull);
      expect(restored.externalPageUrl, 'https://vk.com/audio1');
    });
  });

  group('DownloadTask payload persistence (schema v5)', () {
    test('toMap/fromMap round-trip preserves the payload', () {
      final task = _task(payloadJson: jsonEncode(_result().toJson()));
      final restored = DownloadTask.fromMap(task.toMap());
      expect(restored.payloadJson, task.payloadJson);
      final payload = restored.payload;
      expect(payload, isNotNull);
      expect(payload!.id, 'audius_42');
      expect(payload.title, 'Skyline');
      expect(payload.audioUrl, 'https://cdn.example.org/skyline.mp3');
      expect(payload.providerId, 'audius');
      expect(payload.matchScore, 0.87);
    });

    test('copyWith carries the payload across stage updates', () {
      final task = _task(payloadJson: jsonEncode(_result().toJson()));
      final updated = task.copyWith(
        stage: DownloadStage.completed,
        progress: 1.0,
        importedTrackId: 'track-9',
      );
      expect(updated.stage, DownloadStage.completed);
      expect(updated.payloadJson, task.payloadJson);
      expect(updated.payload!.title, 'Skyline');
    });

    test('pre-v5 row (no payload_json key) has no payload', () {
      final map = _task().toMap()..remove('payload_json');
      final restored = DownloadTask.fromMap(map);
      expect(restored.payloadJson, isNull);
      expect(restored.payload, isNull);
    });

    test('corrupt stored JSON decodes to null, never throws', () {
      expect(_task(payloadJson: '{not json').payload, isNull);
      expect(_task(payloadJson: '"just a string"').payload, isNull);
      expect(_task(payloadJson: '[1, 2, 3]').payload, isNull);
      expect(_task(payloadJson: '').payload, isNull);
    });

    test('stored JSON with no usable URL decodes to null', () {
      // A payload that names no audio URL and no page URL cannot be
      // retried; the getter reports "no payload" so Retry stays
      // disabled instead of queueing a doomed download.
      expect(
        _task(payloadJson: jsonEncode({'id': 1, 'title': 'Garbage'})).payload,
        isNull,
      );
      expect(
        _task(
          payloadJson: jsonEncode({
            'id': 'x',
            'title': 'Page only',
            'externalPageUrl': 'https://example.org/track',
          }),
        ).payload,
        isNotNull,
      );
    });
  });
}
