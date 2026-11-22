import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../../data/models/audio_settings.dart';
import '../../data/models/smart_remix_config.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../storage/secure_credentials_store.dart';
import '../utilities/volume_dsp_math.dart';
import 'ios_audio_bridge.dart';

class BttAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  AudioPlayer _primaryPlayer = AudioPlayer();
  AudioPlayer _crossfadePlayer = AudioPlayer();

  final LibraryRepository _libraryRepo;
  final SecureCredentialsStore _store;

  List<Track> _trackQueue = [];
  int _currentIndex = -1;
  bool _shuffle = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  AudioSettings _audioSettings = const AudioSettings();
  SmartRemixConfig _remixConfig = const SmartRemixConfig();
  bool _isCrossfading = false;

  // Live native iOS playback state mirrored into audio_service streams
  bool _nativePlaying = false;
  Duration _nativePosition = Duration.zero;
  Duration _nativeDuration = Duration.zero;

  Timer? _checkpointTimer;
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  final StreamController<Track?> _currentTrackController = StreamController<Track?>.broadcast();
  final StreamController<AudioSettings> _settingsController = StreamController<AudioSettings>.broadcast();

  Stream<Track?> get currentTrackStream => _currentTrackController.stream;
  Stream<AudioSettings> get settingsStream => _settingsController.stream;
  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length) ? _trackQueue[_currentIndex] : null;
  List<Track> get currentTracks => List.unmodifiable(_trackQueue);
  AudioSettings get audioSettings => _audioSettings;
  bool get isShuffleEnabled => _shuffle;
  AudioServiceRepeatMode get repeatMode => _repeatMode;

  bool get _useNativeIosEngine => Platform.isIOS;

  BttAudioHandler(this._libraryRepo, this._store);

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await IosAudioBridge.configureAudioSession();

    _audioSettings = await _store.loadAudioSettings();
    _remixConfig = await _store.loadSmartRemixConfig();
    await applyAudioSettings(_audioSettings);

    if (_useNativeIosEngine) {
      IosAudioBridge.setEventCallbacks(
        onPosition: (posSec, durSec, playing) {
          _nativePosition = Duration(milliseconds: (posSec * 1000).round());
          if (durSec > 0) {
            _nativeDuration = Duration(milliseconds: (durSec * 1000).round());
          }
          _nativePlaying = playing;
          _emitNativePlaybackState();

          if (_remixConfig.enabled &&
              !_isCrossfading &&
              playing &&
              _nativeDuration.inSeconds > _remixConfig.crossfadeSeconds + 2 &&
              _trackQueue.length > 1) {
            final remaining = _nativeDuration - _nativePosition;
            if (remaining.inSeconds > 0 &&
                remaining.inSeconds <= _remixConfig.crossfadeSeconds) {
              unawaited(_triggerSmartCrossfade());
            }
          }
        },
        onCompleted: (_) {
          if (!_isCrossfading) {
            unawaited(_handleTrackCompletion());
          }
        },
      );
    } else {
      _attachPlayerListeners(_primaryPlayer);
    }

    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        pause();
      } else if (event.type == AudioInterruptionType.duck) {
        _applyEffectiveVolume(_audioSettings);
      }
    });

    session.becomingNoisyEventStream.listen((_) {
      pause();
    });

    await _restorePlaybackCheckpoint();

    _checkpointTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final track = currentTrack;
      final isPlaying = _useNativeIosEngine ? _nativePlaying : _primaryPlayer.playing;
      final posMs = _useNativeIosEngine
          ? _nativePosition.inMilliseconds
          : _primaryPlayer.position.inMilliseconds;
      if (track != null && isPlaying) {
        _store.savePlaybackCheckpoint(track.id, posMs);
      }
    });
  }

  Future<void> _restorePlaybackCheckpoint() async {
    try {
      final checkpoint = await _store.loadPlaybackCheckpoint();
      if (checkpoint.trackId == null) return;
      final allTracks = await _libraryRepo.getAllTracks();
      final idx = allTracks.indexWhere((t) => t.id == checkpoint.trackId);
      if (idx == -1) return;

      final track = allTracks[idx];
      if (!await File(track.localFilePath).exists()) return;

      _trackQueue = allTracks;
      _currentIndex = idx;
      queue.add(_trackQueue.map(_toMediaItem).toList());
      _currentTrackController.add(track);
      mediaItem.add(_toMediaItem(track));

      final restorePos = Duration(milliseconds: checkpoint.positionMs.clamp(0, 36000000));
      if (_useNativeIosEngine) {
        final dur = await IosAudioBridge.prepareFile(
          trackId: track.id,
          filePath: track.localFilePath,
          startPositionSeconds: restorePos.inMilliseconds / 1000.0,
        );
        _nativePosition = restorePos;
        _nativeDuration = Duration(seconds: dur?.round() ?? track.durationSeconds);
        _nativePlaying = false;
        _emitNativePlaybackState();
      } else {
        await _primaryPlayer.setAudioSource(AudioSource.file(track.localFilePath));
        await _primaryPlayer.seek(restorePos);
      }
    } catch (_) {
      // Safe non-fatal checkpoint recovery
    }
  }

  void _emitNativePlaybackState() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _nativePlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: AudioProcessingState.ready,
        playing: _nativePlaying,
        updatePosition: _nativePosition,
        bufferedPosition: _nativeDuration,
        speed: _audioSettings.playbackSpeed,
        queueIndex: _currentIndex >= 0 ? _currentIndex : 0,
        repeatMode: _repeatMode,
        shuffleMode: _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      ),
    );
  }

  void _attachPlayerListeners(AudioPlayer player) {
    _eventSub?.cancel();
    _posSub?.cancel();
    _stateSub?.cancel();

    _eventSub = player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event, player));
    });

    _posSub = player.positionStream.listen((pos) {
      if (_remixConfig.enabled &&
          !_isCrossfading &&
          player.playing &&
          player.duration != null &&
          _trackQueue.length > 1) {
        final remaining = player.duration! - pos;
        if (remaining.inSeconds > 0 &&
            remaining.inSeconds <= _remixConfig.crossfadeSeconds) {
          unawaited(_triggerSmartCrossfade());
        }
      }
    });

    _stateSub = player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && !_isCrossfading) {
        unawaited(_handleTrackCompletion());
      }
    });
  }

  Future<void> _handleTrackCompletion() async {
    if (_repeatMode == AudioServiceRepeatMode.one) {
      await seek(Duration.zero);
      await play();
      return;
    }
    if (_currentIndex + 1 < _trackQueue.length) {
      await skipToNext();
    } else if (_repeatMode == AudioServiceRepeatMode.all && _trackQueue.isNotEmpty) {
      await playTrackAtIndex(0);
    } else {
      await pause();
    }
  }

  Future<void> setTrackQueueAndPlay(List<Track> tracks, {int initialIndex = 0}) async {
    _trackQueue = List<Track>.from(tracks);
    queue.add(_trackQueue.map(_toMediaItem).toList());
    if (_trackQueue.isEmpty) {
      _currentIndex = -1;
      _currentTrackController.add(null);
      return;
    }
    final safeIdx = initialIndex.clamp(0, _trackQueue.length - 1);
    await playTrackAtIndex(safeIdx);
  }

  Future<void> playTrackAtIndex(int index) async {
    if (index < 0 || index >= _trackQueue.length) return;
    _currentIndex = index;
    final track = _trackQueue[index];
    final file = File(track.localFilePath);
    if (!await file.exists()) {
      return;
    }

    _currentTrackController.add(track);
    mediaItem.add(_toMediaItem(track));

    if (_useNativeIosEngine) {
      await IosAudioBridge.setPlaybackSpeed(_audioSettings.playbackSpeed);
      final durSec = await IosAudioBridge.playFile(
        trackId: track.id,
        filePath: track.localFilePath,
      );
      _nativePosition = Duration.zero;
      _nativeDuration = Duration(
        milliseconds: ((durSec ?? track.durationSeconds.toDouble()) * 1000).round(),
      );
      _nativePlaying = true;
      _emitNativePlaybackState();
    } else {
      await _primaryPlayer.setAudioSource(AudioSource.file(track.localFilePath));
      await _primaryPlayer.setSpeed(_audioSettings.playbackSpeed);
      _applyEffectiveVolume(_audioSettings);
      await _primaryPlayer.play();
    }

    unawaited(_libraryRepo.recordPlayback(track.id));
    unawaited(_store.savePlaybackCheckpoint(track.id, 0));

    await IosAudioBridge.updateNowPlayingNative(
      track: track,
      isPlaying: true,
      position: Duration.zero,
      duration: _useNativeIosEngine
          ? _nativeDuration
          : (_primaryPlayer.duration ?? Duration(seconds: track.durationSeconds)),
    );
  }

  Future<void> _triggerSmartCrossfade() async {
    if (_isCrossfading || _trackQueue.isEmpty) return;
    final nextIdx = _currentIndex + 1 < _trackQueue.length
        ? _currentIndex + 1
        : (_repeatMode == AudioServiceRepeatMode.all ? 0 : -1);
    if (nextIdx == -1) return;

    final nextTrack = _trackQueue[nextIdx];
    if (!await File(nextTrack.localFilePath).exists()) return;

    _isCrossfading = true;
    try {
      if (_useNativeIosEngine) {
        final nextDur = await IosAudioBridge.startCrossfade(
          trackId: nextTrack.id,
          filePath: nextTrack.localFilePath,
          durationSeconds: _remixConfig.crossfadeSeconds.toDouble(),
        );
        _currentIndex = nextIdx;
        _nativePosition = Duration.zero;
        _nativeDuration = Duration(
          milliseconds: ((nextDur ?? nextTrack.durationSeconds.toDouble()) * 1000).round(),
        );
        _nativePlaying = true;
        _currentTrackController.add(nextTrack);
        mediaItem.add(_toMediaItem(nextTrack));
        _emitNativePlaybackState();
        unawaited(_libraryRepo.recordPlayback(nextTrack.id));
        await IosAudioBridge.updateNowPlayingNative(
          track: nextTrack,
          isPlaying: true,
          position: Duration.zero,
          duration: _nativeDuration,
        );
        return;
      }

      final outgoing = _primaryPlayer;
      final incoming = _crossfadePlayer;

      await incoming.setAudioSource(AudioSource.file(nextTrack.localFilePath));
      await incoming.setVolume(0.0);
      await incoming.setSpeed(_audioSettings.playbackSpeed);
      await incoming.play();

      _currentIndex = nextIdx;
      _currentTrackController.add(nextTrack);
      mediaItem.add(_toMediaItem(nextTrack));
      unawaited(_libraryRepo.recordPlayback(nextTrack.id));

      final steps = (_remixConfig.crossfadeSeconds * 10).clamp(10, 120);
      final targetMult = _computedSoftwareGain(_audioSettings);

      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final (outGain, inGain) = VolumeDspMath.equalPowerCrossfade(t);
        await outgoing.setVolume((outGain * targetMult).clamp(0.0, 1.0));
        await incoming.setVolume((inGain * targetMult).clamp(0.0, 1.0));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      await outgoing.stop();
      _primaryPlayer = incoming;
      _crossfadePlayer = outgoing;
      _attachPlayerListeners(_primaryPlayer);
      playbackState.add(_transformEvent(_primaryPlayer.playbackEvent, _primaryPlayer));
    } finally {
      _isCrossfading = false;
    }
  }

  Future<void> applyAudioSettings(AudioSettings settings) async {
    _audioSettings = settings;
    _settingsController.add(settings);
    await _store.saveAudioSettings(settings);
    _applyEffectiveVolume(settings);
    if (_useNativeIosEngine) {
      await IosAudioBridge.setPlaybackSpeed(settings.playbackSpeed);
      await IosAudioBridge.applyAudioSettings(settings);
    } else {
      await _primaryPlayer.setSpeed(settings.playbackSpeed);
    }
  }

  Future<void> updateRemixConfig(SmartRemixConfig config) async {
    _remixConfig = config;
    await _store.saveSmartRemixConfig(config);
  }

  double _computedSoftwareGain(AudioSettings settings) {
    final dsp = VolumeDspMath.evaluateGain(
      multiplier: settings.volumeMultiplier,
      limiterEnabled: settings.limiterEnabled,
      normalizationOffsetDb: settings.normalizeVolume ? -1.5 : 0.0,
    );
    return dsp.linearOutput.clamp(0.0, 1.0);
  }

  void _applyEffectiveVolume(AudioSettings settings) {
    if (!Platform.isIOS) {
      unawaited(_primaryPlayer.setVolume(_computedSoftwareGain(settings)));
    }
  }

  @override
  Future<void> play() async {
    if (_useNativeIosEngine) {
      await IosAudioBridge.resumePlayback();
      _nativePlaying = true;
      _emitNativePlaybackState();
    } else {
      await _primaryPlayer.play();
    }
    final track = currentTrack;
    if (track != null) {
      await IosAudioBridge.updateNowPlayingNative(
        track: track,
        isPlaying: true,
        position: _useNativeIosEngine ? _nativePosition : _primaryPlayer.position,
        duration: _useNativeIosEngine
            ? _nativeDuration
            : (_primaryPlayer.duration ?? Duration(seconds: track.durationSeconds)),
      );
    }
  }

  @override
  Future<void> pause() async {
    if (_useNativeIosEngine) {
      await IosAudioBridge.pausePlayback();
      _nativePlaying = false;
      _emitNativePlaybackState();
    } else {
      await _primaryPlayer.pause();
    }
    final track = currentTrack;
    if (track != null) {
      final pos = _useNativeIosEngine ? _nativePosition : _primaryPlayer.position;
      unawaited(_store.savePlaybackCheckpoint(track.id, pos.inMilliseconds));
      await IosAudioBridge.updateNowPlayingNative(
        track: track,
        isPlaying: false,
        position: pos,
        duration: _useNativeIosEngine
            ? _nativeDuration
            : (_primaryPlayer.duration ?? Duration(seconds: track.durationSeconds)),
      );
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_useNativeIosEngine) {
      _nativePosition = position;
      await IosAudioBridge.seekTo(position.inMilliseconds / 1000.0);
      _emitNativePlaybackState();
      final track = currentTrack;
      if (track != null) {
        await IosAudioBridge.updateNowPlayingNative(
          track: track,
          isPlaying: _nativePlaying,
          position: position,
          duration: _nativeDuration,
        );
      }
      return;
    }
    await _primaryPlayer.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_trackQueue.isEmpty) return;
    if (_shuffle && _trackQueue.length > 1) {
      final candidates = List.generate(_trackQueue.length, (i) => i)..remove(_currentIndex);
      candidates.shuffle();
      await playTrackAtIndex(candidates.first);
      return;
    }
    final next = (_currentIndex + 1) % _trackQueue.length;
    await playTrackAtIndex(next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_trackQueue.isEmpty) return;
    final posSec = _useNativeIosEngine ? _nativePosition.inSeconds : _primaryPlayer.position.inSeconds;
    if (posSec > 4) {
      await seek(Duration.zero);
      return;
    }
    final prev = (_currentIndex - 1 + _trackQueue.length) % _trackQueue.length;
    await playTrackAtIndex(prev);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    if (_useNativeIosEngine) {
      _emitNativePlaybackState();
    } else {
      playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffle = shuffleMode != AudioServiceShuffleMode.none;
    if (_useNativeIosEngine) {
      _emitNativePlaybackState();
    } else {
      playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    }
  }

  MediaItem _toMediaItem(Track t) {
    Uri? artUri;
    if (t.artworkPath != null && t.artworkPath!.isNotEmpty) {
      artUri = Uri.file(t.artworkPath!);
    } else if (t.artworkUrl != null) {
      artUri = Uri.tryParse(t.artworkUrl!);
    }
    return MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: t.durationSeconds > 0 ? Duration(seconds: t.durationSeconds) : null,
      artUri: artUri,
    );
  }

  PlaybackState _transformEvent(PlaybackEvent event, AudioPlayer player) {
    return PlaybackState(
      controls: const [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: switch (player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: _currentIndex,
      repeatMode: _repeatMode,
      shuffleMode: _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }

  Future<void> dispose() async {
    _checkpointTimer?.cancel();
    await _eventSub?.cancel();
    await _posSub?.cancel();
    await _stateSub?.cancel();
    await _currentTrackController.close();
    await _settingsController.close();
    await IosAudioBridge.stopPlayback();
    await _primaryPlayer.dispose();
    await _crossfadePlayer.dispose();
  }
}
