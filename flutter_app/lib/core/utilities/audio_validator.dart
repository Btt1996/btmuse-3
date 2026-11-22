import 'dart:io';
import 'dart:typed_data';

enum AudioFormatType {
  mp3,
  m4a,
  aac,
  flac,
  wav,
  ogg,
  unknown,
}

class AudioValidationResult {
  final bool isValid;
  final AudioFormatType format;
  final String extension;
  final String? reason;

  const AudioValidationResult({
    required this.isValid,
    required this.format,
    required this.extension,
    this.reason,
  });
}

class AudioValidator {
  static const List<String> supportedExtensions = [
    'mp3',
    'm4a',
    'aac',
    'flac',
    'wav',
    'ogg',
  ];

  static AudioValidationResult inspectMagicBytes(
    Uint8List headerBytes, {
    String? fileName,
    bool allowExtensionFallback = false,
  }) {
    if (headerBytes.length < 4) {
      return const AudioValidationResult(
        isValid: false,
        format: AudioFormatType.unknown,
        extension: '',
        reason: 'File too small to be a valid audio file.',
      );
    }

    // Reject obvious HTML/XML/JSON/text error pages returned by broken servers
    final asciiHead = String.fromCharCodes(headerBytes.take(16)).trimLeft().toLowerCase();
    if (asciiHead.startsWith('<!doc') ||
        asciiHead.startsWith('<html') ||
        asciiHead.startsWith('<?xml') ||
        asciiHead.startsWith('{') ||
        asciiHead.startsWith('error:')) {
      return const AudioValidationResult(
        isValid: false,
        format: AudioFormatType.unknown,
        extension: '',
        reason: 'Payload is HTML, XML, or JSON rather than binary audio.',
      );
    }

    // MP3 with ID3v2 header or MPEG frame sync
    if (headerBytes[0] == 0x49 && headerBytes[1] == 0x44 && headerBytes[2] == 0x33) {
      return const AudioValidationResult(
        isValid: true,
        format: AudioFormatType.mp3,
        extension: 'mp3',
      );
    }
    if (headerBytes[0] == 0xFF && (headerBytes[1] & 0xE0) == 0xE0) {
      // Distinguish ADTS AAC vs MP3 frame sync using layer bits
      final layer = (headerBytes[1] >> 1) & 0x03;
      if (layer == 0) {
        return const AudioValidationResult(
          isValid: true,
          format: AudioFormatType.aac,
          extension: 'aac',
        );
      }
      return const AudioValidationResult(
        isValid: true,
        format: AudioFormatType.mp3,
        extension: 'mp3',
      );
    }

    // FLAC: "fLaC"
    if (headerBytes[0] == 0x66 &&
        headerBytes[1] == 0x4C &&
        headerBytes[2] == 0x61 &&
        headerBytes[3] == 0x43) {
      return const AudioValidationResult(
        isValid: true,
        format: AudioFormatType.flac,
        extension: 'flac',
      );
    }

    // WAV: "RIFF....WAVE"
    if (headerBytes.length >= 12 &&
        headerBytes[0] == 0x52 &&
        headerBytes[1] == 0x49 &&
        headerBytes[2] == 0x46 &&
        headerBytes[3] == 0x46 &&
        headerBytes[8] == 0x57 &&
        headerBytes[9] == 0x41 &&
        headerBytes[10] == 0x56 &&
        headerBytes[11] == 0x45) {
      return const AudioValidationResult(
        isValid: true,
        format: AudioFormatType.wav,
        extension: 'wav',
      );
    }

    // OGG: "OggS"
    if (headerBytes[0] == 0x4F &&
        headerBytes[1] == 0x67 &&
        headerBytes[2] == 0x67 &&
        headerBytes[3] == 0x53) {
      return const AudioValidationResult(
        isValid: true,
        format: AudioFormatType.ogg,
        extension: 'ogg',
      );
    }

    // M4A / MP4 ISO Base Media: "....ftyp"
    if (headerBytes.length >= 8 &&
        headerBytes[4] == 0x66 &&
        headerBytes[5] == 0x74 &&
        headerBytes[6] == 0x79 &&
        headerBytes[7] == 0x70) {
      return const AudioValidationResult(
        isValid: true,
        format: AudioFormatType.m4a,
        extension: 'm4a',
      );
    }

    if (allowExtensionFallback && fileName != null) {
      final dot = fileName.lastIndexOf('.');
      if (dot != -1) {
        final ext = fileName.substring(dot + 1).toLowerCase();
        if (supportedExtensions.contains(ext)) {
          return AudioValidationResult(
            isValid: true,
            format: _formatFromExt(ext),
            extension: ext,
          );
        }
      }
    }

    return const AudioValidationResult(
      isValid: false,
      format: AudioFormatType.unknown,
      extension: '',
      reason: 'Unrecognized or corrupted audio container header.',
    );
  }

  static Future<AudioValidationResult> inspectFile(
    File file, {
    int minBytes = 1024,
  }) async {
    if (!await file.exists()) {
      return const AudioValidationResult(
        isValid: false,
        format: AudioFormatType.unknown,
        extension: '',
        reason: 'Audio file does not exist.',
      );
    }
    final size = await file.length();
    if (size < minBytes) {
      return AudioValidationResult(
        isValid: false,
        format: AudioFormatType.unknown,
        extension: '',
        reason: 'Audio file is too small ($size bytes; minimum $minBytes bytes).',
      );
    }

    final raf = await file.open();
    try {
      final bytes = await raf.read(16);
      return inspectMagicBytes(bytes, fileName: file.path);
    } finally {
      await raf.close();
    }
  }

  static AudioFormatType _formatFromExt(String ext) {
    switch (ext) {
      case 'mp3':
        return AudioFormatType.mp3;
      case 'm4a':
        return AudioFormatType.m4a;
      case 'aac':
        return AudioFormatType.aac;
      case 'flac':
        return AudioFormatType.flac;
      case 'wav':
        return AudioFormatType.wav;
      case 'ogg':
        return AudioFormatType.ogg;
      default:
        return AudioFormatType.unknown;
    }
  }
}
