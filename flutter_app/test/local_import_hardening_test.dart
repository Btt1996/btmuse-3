import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/utilities/audio_validator.dart';
import 'package:btmu/core/utilities/sha256_helper.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/library_repository.dart';

// Phase 4, item 16 — local-file import hardening, DB-free evidence.
//
// `LibraryRepository.importFile` needs sqflite + the iOS audio bridge
// (MethodChannels with no host implementation under `flutter test`),
// so the import itself cannot run here. What CAN run here is every
// gate `importFile` funnels through, in order:
//   (a) `AudioValidator.inspectFile` — the first thing `importFile`
//       calls; an invalid result throws `ValidationFailure(reason)`
//       before anything is copied or inserted.
//   (b) `Sha256Helper.hashFile` — the dedup key `importFile` computes
//       before copying; identical bytes hash identically, so a second
//       import of the same file is the `Duplicate` /
//       `DuplicateTrackFailure` path, never a second row.
//   (c) missing-file rows are flagged by `getStorageStats`
//       (`missingFilesCount`) and cleaned up by
//       `deleteMissingFileEntries` — both need a database, so they are
//       verified by code inspection (see REPORT.md), not here.
//   (d) storage accounting: `importFile` stores
//       `fileSizeBytes = destFile.length()` and `getStorageStats`
//       sums `fileSizeBytes` per `source_provider` — verified by code
//       inspection (see REPORT.md).

Uint8List _padded(List<int> header, [int total = 2048]) {
  final bytes = Uint8List(total);
  bytes.setRange(0, header.length, header);
  return bytes;
}

Future<Directory> _tempDir() =>
    Directory.systemTemp.createTemp('btmu_local_import_test');

Track _track({required String id, required String sha256}) {
  return Track(
    id: id,
    title: 'Song',
    artist: 'Artist',
    album: 'Single',
    durationSeconds: 180,
    localFilePath: '/tmp/btmu_audio/$id.mp3',
    format: 'MP3',
    fileSizeBytes: 1000,
    sha256: sha256,
    sourceProvider: 'local_file',
    addedAtMs: 1000,
  );
}

void main() {
  group('import gate (a): corrupted / non-audio files are rejected', () {
    test('valid ID3 MP3 file passes validation', () async {
      final dir = await _tempDir();
      try {
        final file = File('${dir.path}/song.mp3');
        await file.writeAsBytes(_padded([0x49, 0x44, 0x33, 0x04]));
        final res = await AudioValidator.inspectFile(file);
        expect(res.isValid, isTrue);
        expect(res.extension, 'mp3');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('valid WAV and FLAC files pass validation', () async {
      final dir = await _tempDir();
      try {
        final wav = File('${dir.path}/song.wav');
        await wav.writeAsBytes(
          _padded([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]),
        );
        expect((await AudioValidator.inspectFile(wav)).extension, 'wav');

        final flac = File('${dir.path}/song.flac');
        await flac.writeAsBytes(_padded([0x66, 0x4C, 0x61, 0x43]));
        expect((await AudioValidator.inspectFile(flac)).extension, 'flac');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('random bytes with an .mp3 name are rejected, never imported', () async {
      final dir = await _tempDir();
      try {
        final file = File('${dir.path}/fake.mp3');
        final bytes = Uint8List(2048);
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = (i * 37 + 11) % 256;
        }
        await file.writeAsBytes(bytes);
        final res = await AudioValidator.inspectFile(file);
        expect(res.isValid, isFalse);
        expect(res.reason, contains('Unrecognized or corrupted'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('HTML error page disguised as .mp3 is rejected with a clear reason', () async {
      final dir = await _tempDir();
      try {
        final file = File('${dir.path}/error.mp3');
        final html = utf8.encode(
          '<!DOCTYPE html><html><body>403 Forbidden</body></html>',
        );
        final bytes = Uint8List(2048)..setRange(0, html.length, html);
        await file.writeAsBytes(bytes);
        final res = await AudioValidator.inspectFile(file);
        expect(res.isValid, isFalse);
        expect(res.reason, contains('HTML'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('JSON payload disguised as audio is rejected', () async {
      final dir = await _tempDir();
      try {
        final file = File('${dir.path}/data.mp3');
        final json = utf8.encode('{"error":"not found","code":404}');
        final bytes = Uint8List(2048)..setRange(0, json.length, json);
        await file.writeAsBytes(bytes);
        final res = await AudioValidator.inspectFile(file);
        expect(res.isValid, isFalse);
        expect(res.reason, contains('HTML, XML, or JSON'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('truncated RIFF header (no WAVE marker) is rejected', () async {
      final dir = await _tempDir();
      try {
        final file = File('${dir.path}/broken.wav');
        await file.writeAsBytes(
          _padded([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x00, 0x00, 0x00, 0x00]),
        );
        final res = await AudioValidator.inspectFile(file);
        expect(res.isValid, isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('tiny file with a valid header is rejected as too small', () async {
      final dir = await _tempDir();
      try {
        final file = File('${dir.path}/tiny.mp3');
        await file.writeAsBytes(Uint8List.fromList([0x49, 0x44, 0x33, 0x04, 0, 0]));
        final res = await AudioValidator.inspectFile(file);
        expect(res.isValid, isFalse);
        expect(res.reason, contains('too small'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('empty file is rejected as too small', () async {
      final dir = await _tempDir();
      try {
        final file = File('${dir.path}/empty.mp3');
        await file.writeAsBytes(Uint8List(0));
        final res = await AudioValidator.inspectFile(file);
        expect(res.isValid, isFalse);
        expect(res.reason, contains('too small'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('missing file is rejected as not existing', () async {
      final dir = await _tempDir();
      try {
        final res = await AudioValidator.inspectFile(File('${dir.path}/gone.mp3'));
        expect(res.isValid, isFalse);
        expect(res.reason, contains('does not exist'));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('import gate (b): duplicate detection by content hash', () {
    test('two files with identical bytes hash identically', () async {
      final dir = await _tempDir();
      try {
        final bytes = _padded([0x49, 0x44, 0x33, 0x04]);
        final first = File('${dir.path}/a.mp3')..writeAsBytesSync(bytes);
        final second = File('${dir.path}/b.mp3')..writeAsBytesSync(bytes);
        final hashA = await Sha256Helper.hashFile(first);
        final hashB = await Sha256Helper.hashFile(second);
        expect(hashA, hashB);
        expect(hashA.length, 64);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('one changed byte changes the hash — not a duplicate', () async {
      final dir = await _tempDir();
      try {
        final first = File('${dir.path}/a.mp3')
          ..writeAsBytesSync(_padded([0x49, 0x44, 0x33, 0x04]));
        final altered = Uint8List.fromList(_padded([0x49, 0x44, 0x33, 0x04]));
        altered[100] ^= 0xFF;
        final second = File('${dir.path}/b.mp3')..writeAsBytesSync(altered);
        expect(
          await Sha256Helper.hashFile(first),
          isNot(await Sha256Helper.hashFile(second)),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('identical hashes group as one duplicate pair', () {
      final bytes = _padded([0x49, 0x44, 0x33, 0x04]);
      final hash = Sha256Helper.hashBytes(bytes);
      final groups = groupTracksBySha256([
        _track(id: '1', sha256: hash),
        _track(id: '2', sha256: hash),
      ]);
      expect(groups.length, 1);
      expect(groups.first.count, 2);
      expect(groups.first.sha256, hash);
    });

    test('a duplicate is reported, not silently imported', () {
      const hash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final existing = _track(id: '1', sha256: hash);
      final ImportResult result = Duplicate(existing, hash);
      expect(result, isA<Duplicate>());
      final message = switch (result) {
        Imported(:final track) => 'imported ${track.id}',
        Duplicate(:final existingTrack, :final sha256) =>
          'duplicate of ${existingTrack.id} ($sha256)',
      };
      expect(message, 'duplicate of 1 ($hash)');
      // The legacy wrapper turns the same outcome into a thrown
      // DuplicateTrackFailure so batch callers can report the skip.
      final failure = DuplicateTrackFailure(existing, hash);
      expect(failure.message, contains('Already in library'));
    });
  });
}
