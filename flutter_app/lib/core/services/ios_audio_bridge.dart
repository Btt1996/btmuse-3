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

/// Result of a native `playFile` / `prepareFile` call (W1, Phase 3).
/// The native side returns a map — `durationSeconds`, `playing`, and
/// `processingState` ("idle" / "completed" / "ready") — not just a
/// duration. A `null` result is the failure signal: the bridge returns
/// null when the channel throws or the method is unimplemented, and the
/// handler must then NOT claim playback started (C-4).
class NativePlayResult {
  final double? durationSeconds;
  final bool playing;
  final String processingState;

  const NativePlayResult({
    required this.durationSeconds,
    required this.playing,
    required this.processingState,
  });

  factory NativePlayResult.fromMap(Map<dynamic, dynamic> map) {
    return NativePlayResult(
      durationSeconds: (map['durationSeconds'] as num?)?.toDouble(),
      // Default `true` when the key is absent: a pre-W1 Swift build
      // returns only `durationSeconds` on success, and success meant
      // playing there. W1's build always sends the key.
      playing: (map['playing'] as bool?) ?? true,
      processingState: (map['processingState'] as String?) ?? 'ready',
    );
  }
}

/// Synchronous snapshot of the native playback state, from the
/// `getNativePlaybackState` channel method (W1, Phase 3, C-1). The
/// handler adopts `isPlaying` / `processingState` from this after
/// `resumePlayback` / `pausePlayback` / `seekTo`, because those methods
/// return nil whether they succeeded or refused — the snapshot is the
/// only source of truth.
class NativePlaybackState {
  final bool isPlaying;
  final String processingState;
  final Duration position;
  final Duration duration;
  final String? trackId;

  const NativePlaybackState({
    required this.isPlaying,
    required this.processingState,
    required this.position,
    required this.duration,
    this.trackId,
  });

  factory NativePlaybackState.fromMap(Map<dynamic, dynamic> map) {
    return NativePlaybackState(
      isPlaying: map['isPlaying'] == true,
      processingState: (map['processingState'] as String?) ?? 'ready',
      position: Duration(
        milliseconds: (((map['positionSeconds'] as num?)?.toDouble() ?? 0.0) * 1000).round(),
      ),
      duration: Duration(
        milliseconds: (((map['durationSeconds'] as num?)?.toDouble() ?? 0.0) * 1000).round(),
      ),
      trackId: map['trackId'] as String?,
    );
  }
}

class IosAudioBridge {
  static const MethodChannel _channel = MethodChannel('com.ahmed.btmu/audio_engine');
  static bool _handlerRegistered = false;
  static void Function(double positionSec, double durationSec, bool isPlaying, String processingState)? _onPosition;
  static void Function(String trackId)? _onCompleted;

  static void setEventCallbacks({
    required void Function(double positionSec, double durationSec, bool isPlaying, String processingState) onPosition,
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
        // W1 (C-1): the snapshot carries the honest processing state
        // ("idle" / "completed" / "ready"). Older Swift builds omit it;
        // default to "ready" so the handler keeps its previous behaviour
        // there instead of crashing on a missing key.
        final processingState = (args['processingState'] as String?) ?? 'ready';
        _onPosition?.call(pos, dur, playing, processingState);
      } else if (call.method == 'onNativeCompleted') {
        final trackId = (args['trackId'] as String?) ?? '';
        _onCompleted?.call(trackId);
      }
    });
  }

  /// Synchronous native state snapshot (W1, C-1). Returns null outside
  /// iOS, when the method is unimplemented, or when the channel throws.
  static Future<NativePlaybackState?> getNativePlaybackState() async {
    if (!Platform.isIOS) return null;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getNativePlaybackState');
      if (res == null) return null;
      return NativePlaybackState.fromMap(res);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
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

  static Future<NativePlayResult?> playFile({
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
      if (res == null) return null;
      return NativePlayResult.fromMap(res);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Native side not implemented (yet): treat exactly like a failure.
      return null;
    }
  }

  static Future<NativePlayResult?> prepareFile({
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
      if (res == null) return null;
      return NativePlayResult.fromMap(res);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Native side not implemented (yet): treat exactly like a failure.
      return null;
    }
  }

  /// Returns `true` when the native call succeeded. The handler relies on
  /// this (Phase 3, C-4): a failed resume must not leave the UI showing
  /// "playing" while silent. Previously these methods returned `void` and
  /// swallowed the failure, so the handler could not tell.
  static Future<bool> pausePlayback() async {
    if (!Platform.isIOS) return false;
    try {
      await _channel.invokeMethod<void>('pausePlayback');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> resumePlayback() async {
    if (!Platform.isIOS) return false;
    try {
      await _channel.invokeMethod<void>('resumePlayback');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> seekTo(double positionSeconds) async {
    if (!Platform.isIOS) return false;
    try {
      await _channel.invokeMethod<void>('seekTo', {'positionSeconds': positionSeconds});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
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
    } on MissingPluginException {
      return null;
    }
  }

  /// Clears the lock-screen / Control Center Now Playing info (Phase 3,
  /// C-1 + S-2: called when the queue ends or is cleared so a finished
  /// track's title/artwork does not linger). The channel method
  /// `clearNowPlaying` is owned by W1 on the native side
  /// (`AudioEnginePlugin` sets
  /// `MPNowPlayingInfoCenter.default().nowPlayingInfo = nil`); until that
  /// lands, an unimplemented method is caught here and this returns
  /// `false` instead of throwing, so the handler can call it
  /// unconditionally.
  static Future<bool> clearNowPlaying() async {
    if (!Platform.isIOS) return false;
    try {
      await _channel.invokeMethod<void>('clearNowPlaying');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
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
