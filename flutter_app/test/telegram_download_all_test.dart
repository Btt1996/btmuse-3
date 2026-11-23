import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/features/telegram/telegram_service.dart';

TelegramAudioEntry _entry({
  required String fileId,
  int fileSizeBytes = 1024 * 1024,
  bool alreadyInLibrary = false,
}) {
  return TelegramAudioEntry(
    fileId: fileId,
    fileUniqueId: 'vu-$fileId',
    title: 'Track $fileId',
    performer: 'Artist',
    fileName: '$fileId.mp3',
    durationSeconds: 180,
    fileSizeBytes: fileSizeBytes,
    chatTitle: 'Chat',
    messageDateEpoch: 1000,
    alreadyInLibrary: alreadyInLibrary,
  );
}

void main() {
  group('isDownloadableTelegramEntry', () {
    test('fresh in-limit entries are downloadable', () {
      expect(isDownloadableTelegramEntry(_entry(fileId: 'a')), isTrue);
    });

    test('already-in-library entries are not downloadable', () {
      expect(
        isDownloadableTelegramEntry(
          _entry(fileId: 'a', alreadyInLibrary: true),
        ),
        isFalse,
      );
    });

    test('entries over the 20 MB Bot API limit are not downloadable', () {
      expect(
        isDownloadableTelegramEntry(
          _entry(fileId: 'a', fileSizeBytes: 21 * 1024 * 1024),
        ),
        isFalse,
      );
      expect(
        isDownloadableTelegramEntry(
          _entry(fileId: 'a', fileSizeBytes: 20 * 1024 * 1024),
        ),
        isTrue,
      );
    });
  });

  group('summarizeTelegramBatch', () {
    test('counts each outcome class', () {
      final summary = summarizeTelegramBatch([
        TelegramBatchOutcome.imported,
        TelegramBatchOutcome.imported,
        TelegramBatchOutcome.alreadyInLibrary,
        TelegramBatchOutcome.failed,
      ]);
      expect(summary.imported, 2);
      expect(summary.alreadyInLibrary, 1);
      expect(summary.failed, 1);
    });

    test('empty batch summarizes to zeros', () {
      final summary = summarizeTelegramBatch([]);
      expect(summary.imported, 0);
      expect(summary.alreadyInLibrary, 0);
      expect(summary.failed, 0);
    });
  });

  group('parseTelegramAudioEntries', () {
    test('audio, document and voice messages parse; non-audio skipped', () {
      final entries = parseTelegramAudioEntries([
        {
          'update_id': 1,
          'message': {
            'date': 100,
            'chat': {'title': 'Chat'},
            'audio': {
              'file_id': 'f-audio',
              'file_unique_id': 'vu-audio',
              'title': 'Song A',
              'performer': 'Singer',
              'duration': 200,
              'file_size': 3000000,
            },
          },
        },
        {
          'update_id': 2,
          'message': {
            'date': 101,
            'chat': {'title': 'Chat'},
            'document': {
              'file_id': 'f-doc',
              'file_unique_id': 'vu-doc',
              'file_name': 'track.mp3',
              'mime_type': 'audio/mpeg',
              'file_size': 4000000,
            },
          },
        },
        {
          'update_id': 3,
          'message': {
            'date': 102,
            'chat': {'title': 'Chat'},
            'document': {
              'file_id': 'f-pdf',
              'file_unique_id': 'vu-pdf',
              'file_name': 'notes.pdf',
              'mime_type': 'application/pdf',
              'file_size': 1000,
            },
          },
        },
        {
          'update_id': 4,
          'message': {
            'date': 103,
            'chat': {'title': 'Chat'},
            'voice': {
              'file_id': 'f-voice',
              'file_unique_id': 'vu-voice',
              'duration': 12,
              'file_size': 50000,
            },
          },
        },
      ]);
      // Newest first.
      expect(entries.map((e) => e.fileId).toList(), [
        'f-voice',
        'f-doc',
        'f-audio',
      ]);
      expect(entries[1].title, 'track');
      expect(entries[2].title, 'Song A');
    });

    test('a file posted twice appears once (first occurrence)', () {
      final entries = parseTelegramAudioEntries([
        {
          'update_id': 1,
          'message': {
            'date': 100,
            'chat': {'title': 'Chat'},
            'audio': {
              'file_id': 'f-dup',
              'file_unique_id': 'vu-dup',
              'title': 'Song',
              'duration': 180,
              'file_size': 1000,
            },
          },
        },
        {
          'update_id': 2,
          'message': {
            'date': 200,
            'chat': {'title': 'Chat'},
            'audio': {
              'file_id': 'f-dup',
              'file_unique_id': 'vu-dup',
              'title': 'Song',
              'duration': 180,
              'file_size': 1000,
            },
          },
        },
      ]);
      expect(entries.length, 1);
      expect(entries.first.messageDateEpoch, 100);
    });
  });
}
