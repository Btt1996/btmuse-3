import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/features/telegram/telegram_service.dart';

typedef _StubHandler = ResponseBody Function(RequestOptions options);

class _StubAdapter implements HttpClientAdapter {
  final _StubHandler handler;
  _StubAdapter(this.handler);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }
}

Track _track({
  required String id,
  String title = 'Song',
  String artist = 'Artist',
  String sha256 = 'aabbcc',
  String? telegramFileUniqueId,
}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    album: 'Single',
    durationSeconds: 180,
    localFilePath: '/tmp/btmu_audio/$id.mp3',
    format: 'MP3',
    fileSizeBytes: 1000,
    sha256: sha256,
    sourceProvider: 'telegram',
    telegramFileUniqueId: telegramFileUniqueId,
    addedAtMs: 1000,
  );
}

/// Fake repository that answers `file_unique_id` lookups from memory and
/// never touches sqflite: the real repository needs a device database,
/// which unit tests do not have.
class _FakeLibraryRepository extends LibraryRepository {
  _FakeLibraryRepository() : super(LocalDatabase.instance);

  final Map<String, Track> byFileUniqueId = {};
  bool importCalled = false;

  @override
  Future<Track?> findByTelegramFileUniqueId(String fileUniqueId) async =>
      byFileUniqueId[fileUniqueId];

  @override
  Future<Track> importFileIntoLibrary({
    required File sourceFile,
    required String rawTitle,
    String? rawArtist,
    String? rawAlbum,
    String? artworkUrl,
    int durationSeconds = 0,
    required String sourceProvider,
    bool deleteSourceAfterCopy = false,
    String? telegramFileUniqueId,
  }) async {
    importCalled = true;
    throw UnimplementedError('import must not run in this test');
  }
}

Map<String, dynamic> _audioMsg({
  required String fileId,
  required String fileUniqueId,
  String title = 'Song A',
  String performer = 'Artist A',
}) {
  return {
    'message_id': 1,
    'date': 1700000000,
    'chat': {'id': 1, 'title': 'My Channel', 'type': 'channel'},
    'audio': {
      'file_id': fileId,
      'file_unique_id': fileUniqueId,
      'title': title,
      'performer': performer,
      'file_name': 'song_a.mp3',
      'duration': 200,
      'file_size': 5000000,
    },
  };
}

void main() {
  group('Telegram file_unique_id parsing', () {
    test('parses file_unique_id for audio, document, voice and channel_post', () async {
      var networkCalls = 0;
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter((options) {
        networkCalls++;
        final payload = {
          'ok': true,
          'result': [
            {
              'update_id': 1,
              'message': _audioMsg(fileId: 'fid-audio', fileUniqueId: 'vu-audio-1'),
            },
            {
              'update_id': 2,
              'message': {
                'message_id': 2,
                'date': 1700000100,
                'chat': {'id': 2, 'title': 'My Channel', 'type': 'channel'},
                'document': {
                  'file_id': 'fid-doc',
                  'file_unique_id': 'vu-doc-1',
                  'file_name': 'track.mp3',
                  'mime_type': 'audio/mpeg',
                  'file_size': 4000000,
                },
              },
            },
            {
              'update_id': 3,
              'message': {
                'message_id': 3,
                'date': 1700000200,
                'chat': {'id': 3, 'type': 'private'},
                'voice': {
                  'file_id': 'fid-voice',
                  'file_unique_id': 'vu-voice-1',
                  'duration': 30,
                  'file_size': 100000,
                },
              },
            },
            {
              'update_id': 4,
              'channel_post': {
                'message_id': 4,
                'date': 1700000300,
                'chat': {'id': 4, 'title': 'Announcements', 'type': 'channel'},
                'audio': {
                  'file_id': 'fid-chan',
                  'file_unique_id': 'vu-chan-1',
                  'title': 'Chan Song',
                  'performer': 'Chan Artist',
                  'file_name': 'chan.mp3',
                  'duration': 120,
                  'file_size': 3000000,
                },
              },
            },
            // Same file_id as update 1: deduped within the fetch.
            {
              'update_id': 5,
              'message': _audioMsg(fileId: 'fid-audio', fileUniqueId: 'vu-audio-1'),
            },
            // No audio payload: skipped.
            {
              'update_id': 6,
              'message': {
                'message_id': 6,
                'date': 1700000400,
                'chat': {'id': 6, 'type': 'private'},
                'text': 'hello',
              },
            },
          ],
        };
        return ResponseBody.fromString(
          jsonEncode(payload),
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      });

      final service = TelegramService(ApiClient(customDio: dio), _FakeLibraryRepository());
      final entries = await service.fetchAccessibleAudioMessages('TOKEN');
      expect(networkCalls, 1);
      // Reversed update order, duplicates and non-audio messages removed.
      expect(entries.length, 4);
      expect(entries.map((e) => e.fileUniqueId).toList(), [
        'vu-chan-1',
        'vu-voice-1',
        'vu-doc-1',
        'vu-audio-1',
      ]);
      expect(entries.first.title, 'Chan Song');
      expect(entries[1].title, 'Voice Note 1700000200');
      expect(entries[2].title, 'track');
      expect(entries.last.title, 'Song A');
      expect(entries.every((e) => !e.alreadyInLibrary), isTrue);
    });

    test('flags entries whose file_unique_id is already in the library', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter((_) {
        return ResponseBody.fromString(
          jsonEncode({
            'ok': true,
            'result': [
              {
                'update_id': 1,
                'message': _audioMsg(fileId: 'fid-audio', fileUniqueId: 'vu-audio-1'),
              },
              {
                'update_id': 2,
                'message': {
                  'message_id': 2,
                  'date': 1700000100,
                  'chat': {'id': 2, 'title': 'My Channel', 'type': 'channel'},
                  'document': {
                    'file_id': 'fid-doc',
                    'file_unique_id': 'vu-doc-1',
                    'file_name': 'track.mp3',
                    'mime_type': 'audio/mpeg',
                    'file_size': 4000000,
                  },
                },
              },
            ],
          }),
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      });

      final repo = _FakeLibraryRepository();
      repo.byFileUniqueId['vu-doc-1'] = _track(
        id: 't-doc',
        title: 'track',
        telegramFileUniqueId: 'vu-doc-1',
      );
      final service = TelegramService(ApiClient(customDio: dio), repo);
      final entries = await service.fetchAccessibleAudioMessages('TOKEN');
      expect(entries.length, 2);
      expect(entries[0].fileUniqueId, 'vu-doc-1');
      expect(entries[0].alreadyInLibrary, isTrue);
      expect(entries[1].alreadyInLibrary, isFalse);
    });
  });

  group('Telegram pre-download duplicate check', () {
    test('skips download and throws DuplicateTrackFailure when already imported', () async {
      var networkCalls = 0;
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter((_) {
        networkCalls++;
        throw StateError('download must not start for a duplicate');
      });

      final existing = _track(
        id: 't-existing',
        title: 'Song A',
        artist: 'Artist A',
        sha256: 'deadbeef',
        telegramFileUniqueId: 'vu-audio-1',
      );
      final repo = _FakeLibraryRepository();
      repo.byFileUniqueId['vu-audio-1'] = existing;

      final service = TelegramService(ApiClient(customDio: dio), repo);
      final entry = TelegramAudioEntry(
        fileId: 'fid-audio',
        fileUniqueId: 'vu-audio-1',
        title: 'Song A',
        performer: 'Artist A',
        fileName: 'song_a.mp3',
        durationSeconds: 200,
        fileSizeBytes: 5000000,
        chatTitle: 'My Channel',
        messageDateEpoch: 1700000000,
      );

      DuplicateTrackFailure? caught;
      try {
        await service.downloadAndImportAudio(
          botToken: 'TOKEN',
          entry: entry,
          onProgress: (_, __, ___) {},
        );
        fail('expected DuplicateTrackFailure');
      } on DuplicateTrackFailure catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught.message, contains('Already in library'));
      expect(caught.existingTrack.id, 't-existing');
      expect(networkCalls, 0);
      expect(repo.importCalled, isFalse);
    });

    test('still rejects over-limit files before any network when not a duplicate', () async {
      var networkCalls = 0;
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter((_) {
        networkCalls++;
        throw StateError('over-limit check must precede the network');
      });

      final service = TelegramService(ApiClient(customDio: dio), _FakeLibraryRepository());
      final entry = TelegramAudioEntry(
        fileId: 'fid-big',
        fileUniqueId: 'vu-big-1',
        title: 'Big',
        performer: 'Artist',
        fileName: 'big.mp3',
        durationSeconds: 600,
        fileSizeBytes: 21 * 1024 * 1024,
        chatTitle: 'My Channel',
        messageDateEpoch: 1700000000,
      );

      expect(
        () => service.downloadAndImportAudio(
          botToken: 'TOKEN',
          entry: entry,
          onProgress: (_, __, ___) {},
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (e) => e.message,
            'message',
            contains('20 MB'),
          ),
        ),
      );
      expect(networkCalls, 0);
    });

    test('copyWith preserves file_unique_id and flips alreadyInLibrary', () {
      const entry = TelegramAudioEntry(
        fileId: 'fid-audio',
        fileUniqueId: 'vu-audio-1',
        title: 'Song A',
        performer: 'Artist A',
        fileName: 'song_a.mp3',
        durationSeconds: 200,
        fileSizeBytes: 5000000,
        chatTitle: 'My Channel',
        messageDateEpoch: 1700000000,
      );
      final marked = entry.copyWith(alreadyInLibrary: true);
      expect(marked.fileUniqueId, 'vu-audio-1');
      expect(marked.alreadyInLibrary, isTrue);
      expect(marked.title, 'Song A');
    });
  });
}
