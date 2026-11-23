import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/features/settings/custom_font_service.dart';

Uint8List bytesWithMagic(List<int> magic) {
  // A plausible font file body: magic + 100 zero bytes (the validator
  // only checks the first 4 bytes, the extension and the size).
  return Uint8List.fromList([...magic, ...List.filled(100, 0)]);
}

void main() {
  group('CustomFontService.validateFontBytes', () {
    test('accepts a real TTF (0x00010000 magic)', () {
      expect(
        CustomFontService.validateFontBytes(
          bytesWithMagic([0x00, 0x01, 0x00, 0x00]),
          fileName: 'MyFont.ttf',
        ),
        isNull,
      );
    });

    test('accepts a TTF with the "true" magic', () {
      expect(
        CustomFontService.validateFontBytes(
          bytesWithMagic([0x74, 0x72, 0x75, 0x65]),
          fileName: 'MyFont.ttf',
        ),
        isNull,
      );
    });

    test('accepts a real OTF (OTTO magic)', () {
      expect(
        CustomFontService.validateFontBytes(
          bytesWithMagic([0x4F, 0x54, 0x54, 0x4F]),
          fileName: 'MyFont.otf',
        ),
        isNull,
      );
    });

    test('extension check is case-insensitive', () {
      expect(
        CustomFontService.validateFontBytes(
          bytesWithMagic([0x4F, 0x54, 0x54, 0x4F]),
          fileName: 'MyFont.OTF',
        ),
        isNull,
      );
    });

    test('rejects a PNG pretending to be a font', () {
      final reason = CustomFontService.validateFontBytes(
        bytesWithMagic([0x89, 0x50, 0x4E, 0x47]), // PNG magic
        fileName: 'not-a-font.ttf',
      );
      expect(reason, isNotNull);
      expect(reason, contains('not a real font'));
    });

    test('rejects a font collection (.ttc) with its own message', () {
      final reason = CustomFontService.validateFontBytes(
        bytesWithMagic([0x74, 0x74, 0x63, 0x66]), // 'ttcf'
        fileName: 'collection.ttc',
      );
      expect(reason, isNotNull);
      expect(reason, contains('.ttc'));
    });

    test('rejects a non-font extension', () {
      final reason = CustomFontService.validateFontBytes(
        bytesWithMagic([0x00, 0x01, 0x00, 0x00]),
        fileName: 'font.zip',
      );
      expect(reason, isNotNull);
      expect(reason, contains('.ttf'));
    });

    test('rejects an empty file', () {
      final reason = CustomFontService.validateFontBytes(
        Uint8List(0),
        fileName: 'empty.ttf',
      );
      expect(reason, isNotNull);
      expect(reason, contains('empty'));
    });

    test('rejects a file too short to be a font', () {
      final reason = CustomFontService.validateFontBytes(
        Uint8List.fromList([0x00, 0x01]),
        fileName: 'tiny.ttf',
      );
      expect(reason, isNotNull);
      expect(reason, contains('too short'));
    });

    test('rejects a file over the 20 MB cap', () {
      final reason = CustomFontService.validateFontBytes(
        Uint8List(CustomFontService.maxFontBytes + 1),
        fileName: 'huge.ttf',
      );
      expect(reason, isNotNull);
      expect(reason, contains('20 MB'));
    });
  });

  group('CustomFontService.sanitizeFileName', () {
    test('strips directory components', () {
      expect(
        CustomFontService.sanitizeFileName('../../etc/passwd.ttf'),
        'passwd.ttf',
      );
      expect(
        CustomFontService.sanitizeFileName('/tmp/My Font.ttf'),
        'My_Font.ttf',
      );
    });

    test('replaces unsafe characters with underscores', () {
      expect(
        CustomFontService.sanitizeFileName('my font!.ttf'),
        'my_font_.ttf',
      );
    });

    test('falls back to a safe name for empty / dot names', () {
      expect(CustomFontService.sanitizeFileName(''), 'custom-font.ttf');
      expect(CustomFontService.sanitizeFileName('..'), 'custom-font.ttf');
    });
  });
}
