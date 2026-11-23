import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Custom font import (v3.0.5, item 9).
///
/// The user picks a `.ttf` / `.otf` file in Settings; the app validates
/// that it really is a font (magic bytes, not just the extension), copies
/// it into the app's private `btmu_fonts/` documents directory, and loads
/// it with [FontLoader] under the family name [familyName]. The theme then
/// uses that family for body + display text (see
/// `BttTheme.buildDarkTheme(customFontFamily:)`).
///
/// The font file never leaves the device, is never uploaded, and is never
/// committed — it lives in the app container next to the audio files.
/// Loading happens once at startup (`main.dart`); a bad file can never
/// break launch — a failed load just falls back to the built-in fonts.
class CustomFontService {
  /// Family name registered with the engine for the imported font.
  static const String familyName = 'BttCustom';

  static const String fontsDirName = 'btmu_fonts';

  /// Largest font file accepted (20 MB — far above any single font).
  static const int maxFontBytes = 20 * 1024 * 1024;

  /// Validates [bytes] as a real single font file.
  ///
  /// Returns null when the file is a valid `.ttf` / `.otf`, otherwise a
  /// plain-language reason the UI shows. Checks, in order: non-empty and
  /// under the size cap, a `.ttf`/`.otf` extension, and the magic bytes
  /// (TTF: `00 01 00 00` or ASCII `true`; OTF: ASCII `OTTO`). A `.ttc`
  /// collection is rejected by the magic check with its own message.
  static String? validateFontBytes(Uint8List bytes, {required String fileName}) {
    if (bytes.isEmpty) return 'That file is empty — pick a .ttf or .otf font file.';
    if (bytes.length > maxFontBytes) {
      return 'That font is over 20 MB — pick a smaller .ttf or .otf file.';
    }
    final ext = p.extension(fileName).toLowerCase();
    if (ext != '.ttf' && ext != '.otf') {
      return 'Only .ttf and .otf font files are supported (got "$ext").';
    }
    if (bytes.length < 4) {
      return 'That file is too short to be a font — pick a .ttf or .otf font file.';
    }
    final magic = bytes.sublist(0, 4);
    final isTtf = (magic[0] == 0x00 && magic[1] == 0x01 && magic[2] == 0x00 && magic[3] == 0x00) ||
        (magic[0] == 0x74 && magic[1] == 0x72 && magic[2] == 0x75 && magic[3] == 0x65); // 'true'
    final isOtf = magic[0] == 0x4F && magic[1] == 0x54 && magic[2] == 0x54 && magic[3] == 0x4F; // 'OTTO'
    final isTtc = magic[0] == 0x74 && magic[1] == 0x74 && magic[2] == 0x63 && magic[3] == 0x66; // 'ttcf'
    if (isTtc) {
      return 'Font collections (.ttc) are not supported — pick a single .ttf or .otf file.';
    }
    if (!isTtf && !isOtf) {
      return 'That file is not a real font (its first bytes do not match .ttf or .otf) — pick a font file.';
    }
    return null;
  }

  /// Private fonts directory inside the app container.
  static Future<Directory> fontsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, fontsDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Stores validated [bytes] under a sanitized [fileName] and returns the
  /// stored name. The caller must have run [validateFontBytes] first.
  static Future<String> installFont(Uint8List bytes, String fileName) async {
    final safe = sanitizeFileName(fileName);
    final dir = await fontsDirectory();
    final file = File(p.join(dir.path, safe));
    await file.writeAsBytes(bytes, flush: true);
    return safe;
  }

  /// Loads a previously installed font file into the engine. Returns
  /// [familyName] on success, null when the file is missing or fails to
  /// load (the caller falls back to the built-in fonts).
  static Future<String?> loadInstalledFont(String fileName) async {
    try {
      final dir = await fontsDirectory();
      final file = File(p.join(dir.path, p.basename(fileName)));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final problem = validateFontBytes(bytes, fileName: fileName);
      if (problem != null) return null;
      final loader = FontLoader(familyName);
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      return familyName;
    } catch (_) {
      return null;
    }
  }

  /// Deletes an installed font file (best-effort; a missing file is fine).
  static Future<void> removeInstalledFont(String fileName) async {
    try {
      final dir = await fontsDirectory();
      final file = File(p.join(dir.path, p.basename(fileName)));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Strips directory components and unsafe characters from a picked file
  /// name so it can never escape the fonts directory.
  static String sanitizeFileName(String fileName) {
    final base = p.basename(fileName).trim();
    final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'custom-font.ttf';
    return cleaned;
  }
}
