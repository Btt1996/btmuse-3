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
}
