import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/utilities/audio_validator.dart';

void main() {
  test('AudioValidator accepts ID3 MP3, FLAC, and WAV headers', () {
    final mp3 = Uint8List.fromList([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00]);
    final flac = Uint8List.fromList([0x66, 0x4C, 0x61, 0x43, 0x00, 0x00, 0x00, 0x22]);
    final wav = Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45,
    ]);

    expect(AudioValidator.inspectMagicBytes(mp3).format, AudioFormatType.mp3);
    expect(AudioValidator.inspectMagicBytes(flac).format, AudioFormatType.flac);
    expect(AudioValidator.inspectMagicBytes(wav).format, AudioFormatType.wav);
  });

  test('AudioValidator rejects HTML error pages masquerading as MP3', () {
    final html = Uint8List.fromList('<!DOCTYPE html><html>404</html>'.codeUnits);
    final res = AudioValidator.inspectMagicBytes(html, fileName: 'fake.mp3');

    expect(res.isValid, isFalse);
  });

  test('AudioValidator.inspectFile rejects an empty file', () async {
    final dir = await Directory.systemTemp.createTemp('btmu_validator_test');
    try {
      final file = File('${dir.path}/empty.mp3');
      await file.writeAsBytes(Uint8List(0));
      final res = await AudioValidator.inspectFile(file, minBytes: 4096);
      expect(res.isValid, isFalse);
      expect(res.reason, contains('too small'));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('AudioValidator.inspectFile rejects a valid header below minBytes', () async {
    final dir = await Directory.systemTemp.createTemp('btmu_validator_test');
    try {
      // A real ID3 header, but only 100 bytes: too small to be a track.
      final bytes = Uint8List(100);
      bytes[0] = 0x49;
      bytes[1] = 0x44;
      bytes[2] = 0x33;
      final file = File('${dir.path}/tiny.mp3');
      await file.writeAsBytes(bytes);
      final res = await AudioValidator.inspectFile(file, minBytes: 4096);
      expect(res.isValid, isFalse);
      expect(res.reason, contains('too small'));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('AudioValidator.inspectFile rejects a file that does not exist', () async {
    final res = await AudioValidator.inspectFile(
      File('/tmp/btmu-definitely-not-here-2-00.mp3'),
      minBytes: 4096,
    );
    expect(res.isValid, isFalse);
    expect(res.reason, contains('does not exist'));
  });
}
