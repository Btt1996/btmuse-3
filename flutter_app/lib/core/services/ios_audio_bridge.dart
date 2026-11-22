import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:btmu/data/models/audio_settings.dart';
import 'package:btmu/data/models/track.dart';

class NativeAudioMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final int durationSeconds;
  final String? artworkPath;

  const NativeAudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.durationSeconds = 0,
    this.artworkPath,
  });
}

class IosAudioBridge {
  static const MethodChannel _channel = MethodChannel('com.ahmed.btmu/audio_engine');
  static bool _handlerRegistered = false;
  static void Function(double positionSec, double durationSec, bool isPlaying)? _onPosition;
  static void Function(String trackId)? _onCompleted;

  static void setEventCallbacks({
    required void Function(double positionSec, double durationSec, bool isPlaying) onPosition,
    required void Function(String trackId) onCompleted,
  }) {
    _onPosition = onPosition;
    _onCompleted = onCompleted;
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?) ?? const {};
      if (call.method == 'onNativePosition') {
        final pos = (args['positionSeconds'] as num?)?.toDouble() ?? 0.0;
        final dur = (args['durationSeconds'] as num?)?.toDouble() ?? 0.0;
        final playing = args['isPlaying'] == true;
        _onPosition?.call(pos, dur, playing);
      } else if (call.method == 'onNativeCompleted') {
        final trackId = (args['trackId'] as String?) ?? '';
        _onCompleted?.call(trackId);
      }
    });
  }

  static Future<void> configureAudioSession() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('configureSession');
    } on PlatformException {
      // Safe fallback if running outside iOS runtime
    }
  }

  static Future<void> applyAudioSettings(AudioSettings settings) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('applyAudioSettings', {
        'volumeMultiplier': settings.volumeMultiplier,
        'limiterEnabled': settings.limiterEnabled,
        'normalizeVolume': settings.normalizeVolume,
        'eqPreset': settings.eqPreset,
      });
    } on PlatformException {
      // Safe fallback
    }
  }

  static Future<void> setPlaybackSpeed(double speed) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('setPlaybackSpeed', {'speed': speed});
    } on PlatformException {}
  }

  static Future<double?> playFile({
    required String trackId,
    required String filePath,
    double startPositionSeconds = 0.0,
  }) async {
    if (!Platform.isIOS) return null;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('playFile', {
        'trackId': trackId,
        'filePath': filePath,
        'startPositionSeconds': startPositionSeconds,
      });
      return (res?['durationSeconds'] as num?)?.toDouble();
    } on PlatformException {
      return null;
    }
  }

  static Future<double?> prepareFile({
    required String trackId,
    required String filePath,
    double startPositionSeconds = 0.0,
  }) async {
    if (!Platform.isIOS) return null;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('prepareFile', {
        'trackId': trackId,
        'filePath': filePath,
        'startPositionSeconds': startPositionSeconds,
      });
      return (res?['durationSeconds'] as num?)?.toDouble();
    } on PlatformException {
      return null;
    }
  }

  static Future<void> pausePlayback() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('pausePlayback');
    } on PlatformException {}
  }

  static Future<void> resumePlayback() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('resumePlayback');
    } on PlatformException {}
  }

  static Future<void> seekTo(double positionSeconds) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('seekTo', {'positionSeconds': positionSeconds});
    } on PlatformException {}
  }

  static Future<void> stopPlayback() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('stopPlayback');
    } on PlatformException {}
  }

  static Future<double?> startCrossfade({
    required String trackId,
    required String filePath,
    required double durationSeconds,
  }) async {
    if (!Platform.isIOS) return null;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('startCrossfade', {
        'trackId': trackId,
        'filePath': filePath,
        'durationSeconds': durationSeconds,
      });
      return (res?['durationSeconds'] as num?)?.toDouble();
    } on PlatformException {
      return null;
    }
  }

  static Future<void> updateNowPlayingNative({
    required Track track,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('updateNowPlaying', {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'artworkUrl': track.artworkUrl,
        'artworkPath': track.artworkPath,
        'isPlaying': isPlaying,
        'positionSeconds': position.inMilliseconds / 1000.0,
        'durationSeconds': duration.inMilliseconds / 1000.0,
      });
    } on PlatformException {
      // Safe fallback
    }
  }

  /// Extracts ID3 / iTunes / Vorbis title, artist, album, duration, and embedded cover art on iOS.
  static Future<NativeAudioMetadata?> extractAudioMetadata({
    required String filePath,
    String? artworkDestPath,
  }) async {
    if (!Platform.isIOS) return null;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('extractAudioMetadata', {
        'filePath': filePath,
        'artworkDestPath': artworkDestPath,
      });
      if (res == null) return null;
      return NativeAudioMetadata(
        title: res['title'] as String?,
        artist: res['artist'] as String?,
        album: res['album'] as String?,
        durationSeconds: (res['durationSeconds'] as num?)?.toInt() ?? 0,
        artworkPath: res['artworkPath'] as String?,
      );
    } on PlatformException {
      return null;
    }
  }

  /// Uses native iOS AVAudioFile + AVAudioConverter to resample local MP3/M4A/FLAC/WAV
  /// into 11,025 Hz mono Float64 PCM samples without external FFmpeg binaries.
  static Future<List<double>> extractMonoPcm({
    required String filePath,
    int maxSeconds = 60,
    int targetSampleRate = 11025,
  }) async {
    if (!Platform.isIOS) return const [];
    try {
      final rawBytes = await _channel.invokeMethod<Uint8List>('extractMonoPcm', {
        'filePath': filePath,
        'maxSeconds': maxSeconds,
        'targetSampleRate': targetSampleRate,
      });
      if (rawBytes == null || rawBytes.isEmpty) return const [];
      final bd = ByteData.sublistView(rawBytes);
      final count = rawBytes.lengthInBytes ~/ 2;
      final samples = Float64List(count);
      for (var i = 0; i < count; i++) {
        samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
      }
      return samples;
    } on PlatformException {
      return const [];
    }
  }
}
