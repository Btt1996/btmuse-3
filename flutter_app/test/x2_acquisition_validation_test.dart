import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/data/models/download_task.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/features/x2/x2_acquisition_engine.dart';

// Phase 4, item 20: the X2 acquisition validation step, end to end.
// Every rejection below must throw (never silently drop), and the
// temporary download must be removed on every path, success or failure.
//
// The network is stubbed with Dio's HttpClientAdapter (same pattern as
// import_workflow_test.dart). The library is faked by subclassing
// LibraryRepository and overriding only importFileIntoLibrary — the real
// import (SQLite + native metadata) is covered by dedup_storage_test and
// the device gate, not here. getTemporaryDirectory is mocked to the
// system temp dir via the path_provider method channel.

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

Track _existingTrack() {
  return const Track(
    id: 'existing-1',
    title: 'Already Here',
    artist: 'Some Artist',
    album: 'Single',
    durationSeconds: 180,
    localFilePath: '/tmp/btmu_audio/existing-1.mp3',
    format: 'MP3',
    fileSizeBytes: 5000,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    sourceProvider: 'audius',
    addedAtMs: 1000,
  );
}

Track _importedTrack() {
  return const Track(
    id: 'imported-1',
    title: 'New Song',
    artist: 'New Artist',
    album: 'Single',
    durationSeconds: 180,
    localFilePath: '/tmp/btmu_audio/imported-1.mp3',
    format: 'MP3',
    fileSizeBytes: 5000,
    sha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    sourceProvider: 'audius',
    addedAtMs: 2000,
  );
}

/// Pretends the file being imported is already in the library.
class _DuplicateLibraryRepository extends LibraryRepository {
  _DuplicateLibraryRepository() : super(LocalDatabase.instance);

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
    throw DuplicateTrackFailure(_existingTrack(), _existingTrack().sha256);
  }
}

/// Pretends the import succeeds and returns a canned track.
class _SucceedingLibraryRepository extends LibraryRepository {
  _SucceedingLibraryRepository() : super(LocalDatabase.instance);

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
    return _importedTrack();
  }
}

Uint8List _mp3Bytes(int size) {
  final bytes = Uint8List(size);
  bytes[0] = 0x49; // 'I'
  bytes[1] = 0x44; // 'D'
  bytes[2] = 0x33; // '3'
  return bytes;
}

X2Result _result({
  required String audioUrl,
  int durationSeconds = 0,
  int? fileSizeBytes,
}) {
  return X2Result(
    id: 'test-1',
    providerId: 'audius',
    providerLabel: 'Audius',
    title: 'New Song',
    artist: 'New Artist',
    album: 'Single',
    durationSeconds: durationSeconds,
    audioUrl: audioUrl,
    format: 'mp3',
    fileSizeBytes: fileSizeBytes,
    audioAvailable: true,
    downloadAuthorized: true,
    authorizationNote: 'Test fixture.',
  );
}

X2AcquisitionEngine _engineWithBody(
  Uint8List body, {
  String contentType = 'audio/mpeg',
  required LibraryRepository repo,
}) {
  final dio = Dio();
  dio.httpClientAdapter = _StubAdapter((options) {
    return ResponseBody.fromBytes(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [contentType],
        Headers.contentLengthHeader: ['${body.length}'],
      },
    );
  });
  return X2AcquisitionEngine(ApiClient(customDio: dio), repo);
}

Set<String> _x2TempFiles() {
  return Directory.systemTemp
      .listSync()
      .where(
        (e) =>
            e is File &&
            e.path.split(Platform.pathSeparator).last.startsWith('x2_'),
      )
      .map((e) => e.path)
      .toSet();
}

void _noStages(
  DownloadStage stage,
  double progress,
  int received,
  int total,
) {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      },
    );
  });

  group('X2AcquisitionEngine validation (bad MIME / too small / duration)', () {
    test('rejects an HTML error page served as audio (bad MIME)', () async {
      final html = Uint8List.fromList(
        utf8.encode('<!DOCTYPE html><html>Error 403</html>'),
      );
      final engine = _engineWithBody(
        html,
        contentType: 'text/html',
        repo: _SucceedingLibraryRepository(),
      );

      expect(
        () => engine.acquireTrack(
          result: _result(audioUrl: 'https://cdn.example.org/track.mp3'),
          cancelToken: CancelToken(),
          onStageUpdate: _noStages,
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (e) => e.message,
            'message',
            contains('non-audio content'),
          ),
        ),
      );
    });

    test('rejects a video/mp4 payload even though ftyp looks like M4A', () async {
      final video = Uint8List(5000);
      video[4] = 0x66; // 'f'
      video[5] = 0x74; // 't'
      video[6] = 0x79; // 'y'
      video[7] = 0x70; // 'p'
      final engine = _engineWithBody(
        video,
        contentType: 'video/mp4',
        repo: _SucceedingLibraryRepository(),
      );

      expect(
        () => engine.acquireTrack(
          result: _result(audioUrl: 'https://cdn.example.org/track.mp4'),
          cancelToken: CancelToken(),
          onStageUpdate: _noStages,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects a too-small file that has a valid MP3 header', () async {
      final engine = _engineWithBody(
        _mp3Bytes(100),
        repo: _SucceedingLibraryRepository(),
      );

      expect(
        () => engine.acquireTrack(
          result: _result(
            audioUrl: 'https://cdn.example.org/track.mp3',
            fileSizeBytes: 100,
          ),
          cancelToken: CancelToken(),
          onStageUpdate: _noStages,
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (e) => e.message,
            'message',
            contains('too small'),
          ),
        ),
      );
    });

    test('rejects a file whose size is implausible for its declared duration',
        () async {
      final engine = _engineWithBody(
        _mp3Bytes(5000),
        repo: _SucceedingLibraryRepository(),
      );

      expect(
        () => engine.acquireTrack(
          result: _result(
            audioUrl: 'https://cdn.example.org/track.mp3',
            durationSeconds: 600,
            fileSizeBytes: 5000,
          ),
          cancelToken: CancelToken(),
          onStageUpdate: _noStages,
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (e) => e.message,
            'message',
            contains('declared duration'),
          ),
        ),
      );
    });

    test('rejects an unauthorized result before any download', () async {
      final engine = _engineWithBody(
        _mp3Bytes(5000),
        repo: _SucceedingLibraryRepository(),
      );
      const unauthorized = X2Result(
        id: 'yt-1',
        providerId: 'youtube',
        providerLabel: 'YouTube',
        title: 'Some Video',
        artist: 'Creator',
        album: 'YouTube Reference',
        audioAvailable: false,
        downloadAuthorized: false,
        authorizationNote: 'Metadata only.',
      );

      expect(
        () => engine.acquireTrack(
          result: unauthorized,
          cancelToken: CancelToken(),
          onStageUpdate: _noStages,
        ),
        throwsA(isA<AuthorizationFailure>()),
      );
    });
  });

  group('X2AcquisitionEngine duplicate + success paths', () {
    test('a duplicate is rejected with DuplicateTrackFailure and temp is cleaned',
        () async {
      final engine = _engineWithBody(
        _mp3Bytes(5000),
        repo: _DuplicateLibraryRepository(),
      );
      final before = _x2TempFiles();

      await expectLater(
        engine.acquireTrack(
          result: _result(
            audioUrl: 'https://cdn.example.org/track.mp3',
            fileSizeBytes: 5000,
          ),
          cancelToken: CancelToken(),
          onStageUpdate: _noStages,
        ),
        throwsA(
          isA<DuplicateTrackFailure>().having(
            (e) => e.existingTrack.title,
            'existingTrack.title',
            'Already Here',
          ),
        ),
      );
      expect(_x2TempFiles().difference(before), isEmpty);
    });

    test('a valid file imports and reports every stage in order', () async {
      final engine = _engineWithBody(
        _mp3Bytes(5000),
        repo: _SucceedingLibraryRepository(),
      );
      final stages = <DownloadStage>[];
      var finalProgress = 0.0;
      final before = _x2TempFiles();

      final track = await engine.acquireTrack(
        result: _result(
          audioUrl: 'https://cdn.example.org/track.mp3',
          fileSizeBytes: 5000,
        ),
        cancelToken: CancelToken(),
        onStageUpdate: (stage, progress, received, total) {
          stages.add(stage);
          finalProgress = progress;
        },
      );

      expect(track.id, 'imported-1');
      expect(stages.first, DownloadStage.resolving);
      expect(stages, contains(DownloadStage.downloading));
      expect(stages, contains(DownloadStage.processing));
      expect(stages, contains(DownloadStage.importing));
      expect(stages.last, DownloadStage.completed);
      expect(finalProgress, 1.0);
      expect(_x2TempFiles().difference(before), isEmpty);
    });
  });
}
