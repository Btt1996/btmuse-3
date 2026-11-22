import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class Sha256Helper {
  static String hashBytes(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  static Future<String> hashFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
