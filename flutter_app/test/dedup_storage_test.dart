import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/utilities/sha256_helper.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/library_repository.dart';

// Pure-logic tests only: hash stability, duplicate detection/grouping,
// keeper suggestion, and the duplicate result/failure contracts.
// No network, no sqflite, no device APIs — grouping and hashing are
// exercised without opening a database, so these run as plain unit tests.

Track _track({
  required String id,
  required String sha256,
  String title = 'Song',
  String artist = 'Artist',
  int fileSizeBytes = 1000,
  int playCount = 0,
  int addedAtMs = 1000,
  String sourceProvider = 'local_file',
}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    album: 'Single',
    durationSeconds: 180,
    localFilePath: '/tmp/btmu_audio/$id.mp3',
    format: 'MP3',
    fileSizeBytes: fileSizeBytes,
    sha256: sha256,
    sourceProvider: sourceProvider,
    addedAtMs: addedAtMs,
    playCount: playCount,
  );
}

void main() {
  group('Sha256Helper.hashBytes stability', () {
    test('same bytes always produce the same hash', () {
      final bytes = Uint8List.fromList(utf8.encode('btmu duplicate test audio'));
      expect(Sha256Helper.hashBytes(bytes), Sha256Helper.hashBytes(bytes));
    });

    test('empty input matches the known SHA-256 empty-string vector', () {
      expect(
        Sha256Helper.hashBytes(Uint8List(0)),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('"abc" matches the known SHA-256 test vector', () {
      expect(
        Sha256Helper.hashBytes(Uint8List.fromList(utf8.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('different bytes produce different hashes', () {
      final a = Sha256Helper.hashBytes(Uint8List.fromList([1, 2, 3, 4]));
      final b = Sha256Helper.hashBytes(Uint8List.fromList([1, 2, 3, 5]));
      expect(a, isNot(equals(b)));
      expect(a.length, 64);
    });

    test('hashFile agrees with hashBytes for the same content', () async {
      final dir = await Directory.systemTemp.createTemp('btmu_dedup_test');
      try {
        final file = File('${dir.path}/sample.mp3');
        final bytes = Uint8List.fromList(utf8.encode('fake audio bytes'));
        await file.writeAsBytes(bytes);
        expect(await Sha256Helper.hashFile(file), Sha256Helper.hashBytes(bytes));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('groupTracksBySha256 duplicate detection', () {
    test('groups tracks sharing a hash, ignores singletons', () {
      const hashA = 'a' * 64;
      const hashB = 'b' * 64;
      final groups = groupTracksBySha256([
        _track(id: '1', sha256: hashA),
        _track(id: '2', sha256: hashA),
        _track(id: '3', sha256: hashB),
      ]);
      expect(groups.length, 1);
      expect(groups.first.sha256, hashA);
      expect(groups.first.count, 2);
    });

    test('rows with an empty hash are never grouped as duplicates', () {
      final groups = groupTracksBySha256([
        _track(id: '1', sha256: ''),
        _track(id: '2', sha256: ''),
        _track(id: '3', sha256: ''),
      ]);
      expect(groups, isEmpty);
    });

    test('a remaster / re-encode (different hash) is not a duplicate', () {
      const hashA = 'a' * 64;
      const hashB = 'c' * 64;
      final groups = groupTracksBySha256([
        _track(id: '1', sha256: hashA, title: 'Song', artist: 'Artist'),
        _track(id: '2', sha256: hashB, title: 'Song', artist: 'Artist'),
      ]);
      expect(groups, isEmpty);
    });

    test('groups are ordered by reclaimable bytes, largest first', () {
      const hashSmall = 's' * 64;
      const hashBig = 'l' * 64;
      final groups = groupTracksBySha256([
        _track(id: '1', sha256: hashSmall, fileSizeBytes: 1000),
        _track(id: '2', sha256: hashSmall, fileSizeBytes: 1000),
        _track(id: '3', sha256: hashBig, fileSizeBytes: 9000),
        _track(id: '4', sha256: hashBig, fileSizeBytes: 9000),
        _track(id: '5', sha256: hashBig, fileSizeBytes: 9000),
      ]);
      expect(groups.length, 2);
      expect(groups.first.sha256, hashBig);
      expect(groups.first.reclaimableBytes, 18000);
      expect(groups.last.reclaimableBytes, 1000);
    });
  });

  group('DuplicateGroup space and keeper rules', () {
    test('reclaimableBytes is total minus the largest copy', () {
      const hash = 'd' * 64;
      final group = DuplicateGroup(sha256: hash, tracks: [
        _track(id: '1', sha256: hash, fileSizeBytes: 5000),
        _track(id: '2', sha256: hash, fileSizeBytes: 5000),
        _track(id: '3', sha256: hash, fileSizeBytes: 5000),
      ]);
      expect(group.totalBytes, 15000);
      expect(group.reclaimableBytes, 10000);
    });

    test('suggested keeper is most-played, newest breaks ties', () {
      const hash = 'e' * 64;
      final group = DuplicateGroup(sha256: hash, tracks: [
        _track(id: 'old-played', sha256: hash, playCount: 5, addedAtMs: 1000),
        _track(id: 'new-played', sha256: hash, playCount: 5, addedAtMs: 2000),
        _track(id: 'unplayed', sha256: hash, playCount: 0, addedAtMs: 3000),
      ]);
      expect(group.suggestedKeeper.id, 'new-played');

      final mostPlayed = DuplicateGroup(sha256: hash, tracks: [
        _track(id: 'a', sha256: hash, playCount: 1, addedAtMs: 9999),
        _track(id: 'b', sha256: hash, playCount: 9, addedAtMs: 1000),
      ]);
      expect(mostPlayed.suggestedKeeper.id, 'b');
    });
  });

  group('Duplicate result / failure contract', () {
    test('DuplicateTrackFailure names the existing track and is a ValidationFailure', () {
      const hash = 'f' * 64;
      final existing = _track(id: '1', sha256: hash, title: 'Skyline', artist: 'Btt');
      final failure = DuplicateTrackFailure(existing, hash);
      expect(failure, isA<ValidationFailure>());
      expect(failure.code, 'duplicate_track');
      expect(failure.existingTrack.id, '1');
      expect(failure.sha256, hash);
      expect(failure.message, contains('Already in library'));
      expect(failure.message, contains('Skyline'));
    });

    test('ImportResult distinguishes imported from duplicate', () {
      const hash = 'a' * 64;
      final existing = _track(id: '1', sha256: hash);
      final ImportResult dup = Duplicate(existing, hash);
      final ImportResult imported = Imported(_track(id: '2', sha256: 'b' * 64));

      expect(dup, isA<Duplicate>());
      expect(imported, isA<Imported>());
      final label = switch (dup) {
        Imported(:final track) => 'imported ${track.id}',
        Duplicate(:final existingTrack, :final sha256) =>
          'duplicate of ${existingTrack.id} ($sha256)',
      };
      expect(label, 'duplicate of 1 ($hash)');
    });
  });

  group('formatBytes', () {
    test('formats B / KB / MB boundaries', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(1536 * 1024), '1.5 MB');
    });
  });
}
