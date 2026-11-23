import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../data/models/audio_settings.dart';
import '../../data/models/smart_remix_config.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../errors/app_failure.dart';
import '../storage/local_database.dart';
import '../storage/queue_repository.dart';
import '../storage/secure_credentials_store.dart';
import '../utilities/crossfade_trigger.dart';
import '../utilities/traversal_order.dart';
import '../utilities/volume_dsp_math.dart';
import 'ios_audio_bridge.dart';

// Phase 3 — BttAudioHandler is the single Dart-side writer of playback
// state: every `playbackState` / `mediaItem` / `queue` emission in the
// Flutter path goes through this class (via `_emitNativePlaybackState`,
// `_transformEvent`, `_publishQueue`). There is no second Dart writer.
// The native plugin is the single writer of MPNowPlayingInfoCenter on
// the Swift side (see its MARK "Now Playing (C-1: single writer)"); the
// duplicate `audio_service` Now Playing write cannot be disabled from
// Swift, so the Dart side neutralises it by value-identity instead — see
// [_toMediaItem]: both writers publish the same title / artist / album /
// artwork / duration / position / rate, so whichever write lands last
// shows the same thing. Device gate G-2 must prove the lock screen shows
// the plugin's artwork. No MPRemoteCommandCenter code is added here by
// design — audio_service owns lock-screen / Control Center commands.
class BttAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  AudioPlayer _primaryPlayer = AudioPlayer();
  AudioPlayer _crossfadePlayer = AudioPlayer();

  final LibraryRepository _libraryRepo;
  final SecureCredentialsStore _store;
  final QueueRepository _queueRepo;

  List<Track> _trackQueue = [];
  int _currentIndex = -1;

  /// Where the current queue came from (e.g. a playlist name), persisted
  /// with the queue so the UI can label it. Null for ad-hoc queues.
  String? _sourceLabel;

  bool _shuffle = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  /// Traversal order (Phase 3, S-1): sequential by default, a real
  /// Fisher–Yates shuffled order (current track first) when shuffle is
  /// on. Next/previous step through this order — never a random pick.
  /// Rebuilt when shuffle is toggled or the queue is edited; only the
  /// position moves when the current track advances.
  TraversalOrder _traversal = TraversalOrder.sequential(0, -1);

  AudioSettings _audioSettings = const AudioSettings();
  bool _isCrossfading = false;

  // Live native iOS playback state mirrored into audio_service streams.
  // `_nativePlaying` is adopted from the native snapshots
  // (`getNativePlaybackState` / `onNativePosition`), never assumed: W1's
  // `resumePlayback` refuses to claim playing after completion or with no
  // track loaded, so setting this to `true` unconditionally in `play()`
  // used to show "playing" over silence (C-4).
  bool _nativePlaying = false;
  Duration _nativePosition = Duration.zero;
  Duration _nativeDuration = Duration.zero;

  /// Honest processing state (Phase 3, C-1). Was a constant
  /// `AudioProcessingState.ready`; now it follows the native snapshots
  /// (`getNativePlaybackState` / `onNativePosition`, values "idle" /
  /// "completed" / "ready" — see [_processingStateFromNative]) and is set
  /// to `loading` while a `playFile`/`prepareFile` call is in flight.
  AudioProcessingState _processingState = AudioProcessingState.idle;

  Timer? _checkpointTimer;
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  final StreamController<Track?> _currentTrackController = StreamController<Track?>.broadcast();
  final StreamController<AudioSettings> _settingsController = StreamController<AudioSettings>.broadcast();

  /// The queue, in play order, for the UI ("Up Next"). Emitted on every
  /// queue mutation (add / remove / move / clear / replace) and on
  /// restore. The audio_service `queue` stream is fed the same list by
  /// [_publishQueue].
  final StreamController<List<Track>> _queueController = StreamController<List<Track>>.broadcast();
  Stream<List<Track>> get queueStream => _queueController.stream;

  /// Playback failures the UI can show (Phase 3, C-4): missing files,
  /// failed native play/resume/seek/crossfade, failed restores. Nothing
  /// in this handler fails silently any more — a failure is logged
  /// (debugPrint) AND emitted here.
  final StreamController<AppFailure> _playbackErrorController = StreamController<AppFailure>.broadcast();
  Stream<AppFailure> get playbackErrors => _playbackErrorController.stream;

  Stream<Track?> get currentTrackStream => _currentTrackController.stream;
  Stream<AudioSettings> get settingsStream => _settingsController.stream;
  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length) ? _trackQueue[_currentIndex] : null;
  List<Track> get currentTracks => List.unmodifiable(_trackQueue);
  AudioSettings get audioSettings => _audioSettings;
  bool get isShuffleEnabled => _shuffle;
  AudioServiceRepeatMode get repeatMode => _repeatMode;
  String? get queueSourceLabel => _sourceLabel;
  AudioProcessingState get processingState => _processingState;

  bool get _useNativeIosEngine => Platform.isIOS;

  // `queueRepository` is optional so existing call sites
  // (`main.dart`: `BttAudioHandler(libraryRepo, store)`) keep compiling;
  // it defaults to the app's LocalDatabase, matching LibraryRepository.
  BttAudioHandler(this._libraryRepo, this._store, {QueueRepository? queueRepository})
      : _queueRepo = queueRepository ?? QueueRepository(LocalDatabase.instance);

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await IosAudioBridge.configureAudioSession();

    _audioSettings = await _store.loadAudioSettings();
    await applyAudioSettings(_audioSettings);

    if (_useNativeIosEngine) {
      IosAudioBridge.setEventCallbacks(
        onPosition: (posSec, durSec, playing, processingState) {
          _nativePosition = Duration(milliseconds: (posSec * 1000).round());
          if (durSec > 0) {
            _nativeDuration = Duration(milliseconds: (durSec * 1000).round());
          }
          _nativePlaying = playing;
          _processingState = _processingStateFromNative(processingState);
          _emitNativePlaybackState();

          // S-3: crossfade fires whenever the user's crossfade setting is
          // on — it is no longer gated behind Smart Remix.
          if (shouldTriggerCrossfade(
            crossfadeEnabled: _audioSettings.crossfadeEnabled,
            isPlaying: playing,
            isCrossfading: _isCrossfading,
            remaining: _nativeDuration - _nativePosition,
            duration: _nativeDuration,
            crossfadeSeconds: _audioSettings.crossfadeSeconds,
            queueLength: _trackQueue.length,
          )) {
            unawaited(_triggerCrossfade());
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

    // C-2 — interruption policy, BY DESIGN, not a bug: after an
    // interruption ends (phone call, Siri, alarm) playback STAYS PAUSED
    // until the user presses play. There is deliberately no auto-resume
    // here and no native `interruptionNotification` /
    // `routeChangeNotification` observer in the plugin — the Dart
    // `audio_session` streams below are the only interruption path, so a
    // pause can never fire twice. Whether to auto-resume when the system
    // reports `shouldResume` is a decision for Ahmed, not something to
    // fix silently; if he chooses resume, add it here (and only here).
    // The `duck` branch only re-applies the effective volume when a
    // ducking interruption ends.
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

    await _restorePlaybackQueue();

    _checkpointTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final track = currentTrack;
      final isPlaying = _useNativeIosEngine ? _nativePlaying : _primaryPlayer.playing;
      final posMs = _useNativeIosEngine
          ? _nativePosition.inMilliseconds
          : _primaryPlayer.position.inMilliseconds;
      if (track != null && isPlaying) {
        _store.savePlaybackCheckpoint(track.id, posMs);
        unawaited(_savePositionBestEffort(posMs));
      }
    });
  }

  // --- Queue persistence (Q-1 / Q-2) -------------------------------------

  /// Restores the persisted queue (SQLite, v4) with its position, shuffle
  /// and repeat state. Entries whose track row or file is gone are dropped
  /// (count logged) instead of aborting the restore. If no queue is saved
  /// — or nothing in it survived — falls back to the pre-Phase-3
  /// single-track checkpoint behaviour (whole library as the queue).
  Future<void> _restorePlaybackQueue() async {
    try {
      final saved = await _queueRepo.loadQueue();
      if (saved != null && saved.trackIds.isNotEmpty) {
        final tracks = <Track>[];
        var dropped = 0;
        for (final id in saved.trackIds) {
          final track = await _libraryRepo.findById(id);
          if (track == null || !await File(track.localFilePath).exists()) {
            dropped++;
            continue;
          }
          tracks.add(track);
        }
        if (dropped > 0) {
          debugPrint(
            'BttAudioHandler: dropped $dropped saved queue entries '
            '(track deleted or file missing).',
          );
        }
        if (tracks.isNotEmpty) {
          _trackQueue = tracks;
          _currentIndex = saved.currentIndex.clamp(0, tracks.length - 1);
          _shuffle = saved.shuffle;
          _repeatMode = _repeatModeFromName(saved.repeatMode);
          _sourceLabel = saved.sourceLabel;
          _rebuildTraversal();
          final restorePos = Duration(milliseconds: saved.positionMs.clamp(0, 36000000));
          _nativePosition = restorePos;
          // Persist the pruned queue (dropped entries do not come back).
          _publishQueue(positionMs: saved.positionMs);
          final track = _trackQueue[_currentIndex];
          _currentTrackController.add(track);
          mediaItem.add(_toMediaItem(track));
          await _prepareCurrentTrackPaused(position: restorePos);
          return;
        }
        debugPrint(
          'BttAudioHandler: saved queue had no playable tracks; '
          'falling back to the legacy checkpoint.',
        );
      }
    } catch (e) {
      // C-4: a failed restore is reported, not swallowed — then the
      // legacy checkpoint is tried as a fallback.
      debugPrint('BttAudioHandler: queue restore failed ($e); '
          'trying legacy checkpoint.');
    }
    await _restoreLegacyCheckpoint();
  }

  /// Pre-Phase-3 behaviour, kept as the fallback when no queue is saved:
  /// restores one track + position from SharedPreferences and substitutes
  /// the whole library (newest-first) as the queue. Deliberately NOT
  /// persisted to SQLite — it is a fallback, not a queue the user built.
  Future<void> _restoreLegacyCheckpoint() async {
    try {
      final checkpoint = await _store.loadPlaybackCheckpoint();
      if (checkpoint.trackId == null) return;
      final allTracks = await _libraryRepo.getAllTracks();
      final idx = allTracks.indexWhere((t) => t.id == checkpoint.trackId);
      if (idx == -1) {
        debugPrint(
          'BttAudioHandler: legacy checkpoint track ${checkpoint.trackId} '
          'is no longer in the library.',
        );
        return;
      }

      final track = allTracks[idx];
      if (!await File(track.localFilePath).exists()) {
        debugPrint(
          'BttAudioHandler: legacy checkpoint file missing for '
          '"${track.title}".',
        );
        return;
      }

      _trackQueue = allTracks;
      _currentIndex = idx;
      _rebuildTraversal();
      queue.add(_trackQueue.map(_toMediaItem).toList());
      _queueController.add(List<Track>.unmodifiable(_trackQueue));
      _currentTrackController.add(track);
      mediaItem.add(_toMediaItem(track));

      final restorePos = Duration(milliseconds: checkpoint.positionMs.clamp(0, 36000000));
      await _prepareCurrentTrackPaused(position: restorePos);
    } catch (e) {
      // C-4: log the failure instead of swallowing it silently.
      debugPrint('BttAudioHandler: legacy checkpoint restore failed ($e).');
    }
  }

  /// Prepares the current track paused at [position] (restore path and
  /// removing-the-current-track path). Never auto-plays.
  Future<void> _prepareCurrentTrackPaused({Duration position = Duration.zero}) async {
    final track = currentTrack;
    if (track == null) return;
    if (_useNativeIosEngine) {
      _setProcessingState(AudioProcessingState.loading);
      _emitNativePlaybackState();
      final res = await IosAudioBridge.prepareFile(
        trackId: track.id,
        filePath: track.localFilePath,
        startPositionSeconds: position.inMilliseconds / 1000.0,
      );
      _nativePosition = position;
      _nativeDuration = Duration(
        milliseconds: ((res?.durationSeconds ?? track.durationSeconds.toDouble()) * 1000).round(),
      );
      _nativePlaying = false;
      if (res == null) {
        _reportPlaybackError(
          'Could not prepare "${track.title}".',
          code: 'prepare_failed',
          track: track,
        );
      }
      _setProcessingState(_processingStateFromNative(res?.processingState));
      _emitNativePlaybackState();
    } else {
      await _primaryPlayer.setAudioSource(AudioSource.file(track.localFilePath));
      await _primaryPlayer.seek(position);
    }
  }

  /// Publishes the queue to audio_service AND to [queueStream], then
  /// persists it (Q-1/Q-2: every mutation persists in one transaction).
  /// Pass `persist: false` when the caller is about to persist itself
  /// (e.g. `playTrackAtIndex` persists with position 0) — two concurrent
  /// unawaited writes could otherwise land out of order.
  void _publishQueue({int? positionMs, bool persist = true}) {
    queue.add(_trackQueue.map(_toMediaItem).toList());
    _queueController.add(List<Track>.unmodifiable(_trackQueue));
    if (persist) {
      unawaited(_persistQueue(positionMs: positionMs));
    }
  }

  /// Persists the full ordered queue + state in a single transaction.
  /// A persistence failure must never crash playback, but it is logged
  /// (C-4) instead of being swallowed silently.
  Future<void> _persistQueue({int? positionMs}) async {
    try {
      await _queueRepo.saveQueue(SavedQueue(
        trackIds: _trackQueue.map((t) => t.id).toList(),
        currentIndex: _currentIndex,
        positionMs: positionMs ?? _currentPositionMs(),
        shuffle: _shuffle,
        repeatMode: _repeatMode.name,
        sourceLabel: _sourceLabel,
      ));
    } catch (e) {
      debugPrint('BttAudioHandler: failed to persist queue ($e).');
    }
  }

  /// Cheap position-only write for the 5 s checkpoint timer.
  Future<void> _savePositionBestEffort(int positionMs) async {
    try {
      await _queueRepo.savePosition(positionMs);
    } catch (e) {
      debugPrint('BttAudioHandler: failed to persist queue position ($e).');
    }
  }

  int _currentPositionMs() => _useNativeIosEngine
      ? _nativePosition.inMilliseconds
      : _primaryPlayer.position.inMilliseconds;

  void _rebuildTraversal() {
    _traversal = _shuffle
        ? TraversalOrder.shuffled(_trackQueue.length, _currentIndex)
        : TraversalOrder.sequential(_trackQueue.length, _currentIndex);
  }

  /// Next queue index in traversal order, honouring repeat-all wrap.
  /// Returns null at the end of the queue when repeat is not all —
  /// that null is what makes repeat-none actually end the queue (S-2).
  /// Repeat-one never reaches this: completion restarts the current
  /// track instead, and a manual Next still advances.
  int? _nextIndexInTraversal() =>
      _traversal.next(wrap: _repeatMode == AudioServiceRepeatMode.all);

  int? _previousIndexInTraversal() =>
      _traversal.previous(wrap: _repeatMode == AudioServiceRepeatMode.all);

  static AudioServiceRepeatMode _repeatModeFromName(String raw) {
    return switch (raw) {
      'one' => AudioServiceRepeatMode.one,
      'all' => AudioServiceRepeatMode.all,
      _ => AudioServiceRepeatMode.none,
    };
  }

  /// Maps a native processing-state string onto [AudioProcessingState].
  /// The native side only ever sends "idle" / "completed" / "ready"
  /// (W1: there is no async loading window — file reads are synchronous
  /// on the method-call thread — so "loading"/"buffering" never arrive
  /// from a snapshot; Dart sets `loading` itself around play/prepare).
  static AudioProcessingState _processingStateFromNative(String? raw) {
    return switch (raw) {
      'idle' => AudioProcessingState.idle,
      'loading' => AudioProcessingState.loading,
      'buffering' => AudioProcessingState.buffering,
      'completed' => AudioProcessingState.completed,
      'ready' => AudioProcessingState.ready,
      _ => AudioProcessingState.ready,
    };
  }

  void _setProcessingState(AudioProcessingState state) {
    _processingState = state;
  }

  void _reportPlaybackError(String message, {String code = 'playback_error', Track? track}) {
    debugPrint('BttAudioHandler: $message');
    if (!_playbackErrorController.isClosed) {
      _playbackErrorController.add(AppFailure(message, code: code));
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
        // Only `seek` is advertised: `seekForward` / `seekBackward`
        // (±15 s) have no implementation anywhere in the handler, so
        // advertising them would offer a dead lock-screen button (C-1).
        systemActions: const {
          MediaAction.seek,
        },
        processingState: _processingState,
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
      if (shouldTriggerCrossfade(
        crossfadeEnabled: _audioSettings.crossfadeEnabled,
        isPlaying: player.playing,
        isCrossfading: _isCrossfading,
        remaining: player.duration == null ? Duration.zero : player.duration! - pos,
        duration: player.duration ?? Duration.zero,
        crossfadeSeconds: _audioSettings.crossfadeSeconds,
        queueLength: _trackQueue.length,
      )) {
        unawaited(_triggerCrossfade());
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
    final next = _nextIndexInTraversal();
    if (next != null) {
      await playTrackAtIndex(next);
    } else {
      // Queue ended (repeat-none; repeat-all already wrapped inside
      // `_nextIndexInTraversal`). Stops — see [_endQueue].
      await _endQueue();
    }
  }

  /// Repeat-none end of queue (S-2 / C-1): stop, do NOT wrap, and clear
  /// the lock-screen metadata. Only the native plugin can clear it, and
  /// only the handler knows the queue ended vs. advanced — hence the
  /// explicit `clearNowPlaying` call (W1 owns the channel method; the
  /// native side deliberately does NOT clear on every completion).
  /// The media item is also cleared so audio_service's own Now Playing
  /// write has nothing to republish; the current track stays selected so
  /// pressing play restarts it (see `play()`).
  Future<void> _endQueue() async {
    if (_useNativeIosEngine) {
      await IosAudioBridge.pausePlayback();
      await IosAudioBridge.clearNowPlaying();
      _nativePlaying = false;
    } else {
      await _primaryPlayer.pause();
    }
    mediaItem.add(null);
    _setProcessingState(AudioProcessingState.completed);
    _emitNativePlaybackState();
    unawaited(_persistQueue());
  }

  Future<void> setTrackQueueAndPlay(List<Track> tracks, {int initialIndex = 0, String? sourceLabel}) async {
    _trackQueue = List<Track>.from(tracks);
    _sourceLabel = sourceLabel;
    _rebuildTraversal();
    _publishQueue(persist: false);
    if (_trackQueue.isEmpty) {
      _currentIndex = -1;
      _currentTrackController.add(null);
      mediaItem.add(null);
      _publishQueue();
      return;
    }
    final safeIdx = initialIndex.clamp(0, _trackQueue.length - 1);
    await playTrackAtIndex(safeIdx);
  }

  // --- Queue mutation API (Q-2) -------------------------------------------
  //
  // Every method updates `_trackQueue`, re-publishes to audio_service +
  // `queueStream`, and persists the queue (Q-1). A queue edit rebuilds
  // the traversal order — sequential order is exact, and a shuffled
  // order is re-drawn with the current track first (S-1) — so an edit
  // can never leave a stale shuffle order behind. None of these methods
  // auto-plays, except removing the currently playing track, which moves
  // playback to the next track (documented below).

  Future<void> addToQueue(Track track) async {
    _trackQueue.add(track);
    _rebuildTraversal();
    _publishQueue();
  }

  /// Inserts [track] immediately after the current track, so it plays
  /// next. With an empty queue (or no current track) it is inserted at
  /// the front and nothing auto-plays.
  Future<void> addToQueueNext(Track track) async {
    final insertAt = _currentIndex >= 0 ? _currentIndex + 1 : 0;
    _trackQueue.insert(insertAt, track);
    _rebuildTraversal();
    _publishQueue();
  }

  /// Removes the track at [index]. Removing a track before the current
  /// one shifts `_currentIndex` down; removing the current track moves
  /// playback to the track that now sits at that position (the next
  /// track), or the last track if the removed one was the last — playing
  /// it only if playback was playing, otherwise just selecting it paused.
  /// Removing the last remaining track ends the queue (stops + clears
  /// Now Playing, as in [_endQueue]).
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _trackQueue.length) return;
    final wasCurrent = index == _currentIndex;
    final wasPlaying = _useNativeIosEngine ? _nativePlaying : _primaryPlayer.playing;
    _trackQueue.removeAt(index);
    if (_trackQueue.isEmpty) {
      _currentIndex = -1;
      _sourceLabel = null;
      _rebuildTraversal();
      await _stopPlaybackAndClearNowPlaying();
      _currentTrackController.add(null);
      mediaItem.add(null);
      _setProcessingState(AudioProcessingState.idle);
      _publishQueue();
      _emitNativePlaybackState();
      return;
    }
    if (wasCurrent) {
      final nextIdx = index < _trackQueue.length ? index : _trackQueue.length - 1;
      _currentIndex = nextIdx;
      _rebuildTraversal();
      if (wasPlaying) {
        _publishQueue(persist: false);
        await playTrackAtIndex(nextIdx);
      } else {
        _publishQueue();
        final track = _trackQueue[nextIdx];
        _currentTrackController.add(track);
        mediaItem.add(_toMediaItem(track));
        await _prepareCurrentTrackPaused();
      }
      return;
    }
    if (index < _currentIndex) _currentIndex--;
    _rebuildTraversal();
    _publishQueue();
  }

  /// Moves the track at [from] to [to]. `_currentIndex` follows the
  /// current track when it moves, and shifts when another track crosses
  /// over it, so the playing track never changes under a reorder.
  Future<void> moveQueueItem(int from, int to) async {
    if (from < 0 ||
        from >= _trackQueue.length ||
        to < 0 ||
        to >= _trackQueue.length ||
        from == to) {
      return;
    }
    final track = _trackQueue.removeAt(from);
    _trackQueue.insert(to, track);
    if (_currentIndex == from) {
      _currentIndex = to;
    } else if (from < _currentIndex && to >= _currentIndex) {
      _currentIndex--;
    } else if (from > _currentIndex && to <= _currentIndex) {
      _currentIndex++;
    }
    _rebuildTraversal();
    _publishQueue();
  }

  /// Empties the queue, stops playback, and clears the lock-screen
  /// metadata (C-1). The persisted queue is cleared too, so a relaunch
  /// after this falls back to the legacy checkpoint instead of
  /// resurrecting an explicitly cleared queue.
  Future<void> clearQueue() async {
    _trackQueue = [];
    _currentIndex = -1;
    _sourceLabel = null;
    _rebuildTraversal();
    await _stopPlaybackAndClearNowPlaying();
    _currentTrackController.add(null);
    mediaItem.add(null);
    _setProcessingState(AudioProcessingState.idle);
    _publishQueue();
    _emitNativePlaybackState();
  }

  /// Stops the engine and clears Now Playing. `stopPlayback` already
  /// clears Now Playing on the native side (W1); `clearNowPlaying` is
  /// called as well so the clear does not depend on that coupling.
  Future<void> _stopPlaybackAndClearNowPlaying() async {
    if (_useNativeIosEngine) {
      await IosAudioBridge.stopPlayback();
      await IosAudioBridge.clearNowPlaying();
      _nativePlaying = false;
      _nativePosition = Duration.zero;
      _nativeDuration = Duration.zero;
    } else {
      await _primaryPlayer.stop();
    }
  }

  Future<void> playTrackAtIndex(int index, {Set<int>? triedIndices}) async {
    if (index < 0 || index >= _trackQueue.length) return;
    _currentIndex = index;
    _traversal.moveTo(index);
    final track = _trackQueue[index];
    final file = File(track.localFilePath);
    if (!await file.exists()) {
      // C-4(a): a missing file never stalls the queue silently — report
      // it and move on to the next playable track in traversal order.
      _reportPlaybackError(
        'Skipped "${track.title}": audio file is missing.',
        code: 'missing_file',
        track: track,
      );
      await _playNextPlayableAfter(triedIndices: triedIndices ?? {index});
      return;
    }

    _currentTrackController.add(track);
    mediaItem.add(_toMediaItem(track));

    if (_useNativeIosEngine) {
      _setProcessingState(AudioProcessingState.loading);
      _emitNativePlaybackState();
      await IosAudioBridge.setPlaybackSpeed(_audioSettings.playbackSpeed);
      final res = await IosAudioBridge.playFile(
        trackId: track.id,
        filePath: track.localFilePath,
      );
      if (res == null) {
        // C-4(b): the native side did not start playback (a null result
        // is the bridge's failure signal). Do NOT claim "playing" — the
        // UI would show playing over silence. Report and move on.
        _nativePlaying = false;
        _setProcessingState(AudioProcessingState.ready);
        _emitNativePlaybackState();
        _reportPlaybackError(
          'Could not play "${track.title}".',
          code: 'native_play_failed',
          track: track,
        );
        await _playNextPlayableAfter(triedIndices: triedIndices ?? {index});
        return;
      }
      _nativePosition = Duration.zero;
      _nativeDuration = Duration(
        milliseconds: ((res.durationSeconds ?? track.durationSeconds.toDouble()) * 1000).round(),
      );
      _nativePlaying = res.playing;
      _setProcessingState(_processingStateFromNative(res.processingState));
      _emitNativePlaybackState();
    } else {
      await _primaryPlayer.setAudioSource(AudioSource.file(track.localFilePath));
      await _primaryPlayer.setSpeed(_audioSettings.playbackSpeed);
      _applyEffectiveVolume(_audioSettings);
      await _primaryPlayer.play();
    }

    unawaited(_libraryRepo.recordPlayback(track.id));
    unawaited(_store.savePlaybackCheckpoint(track.id, 0));
    unawaited(_persistQueue(positionMs: 0));

    await IosAudioBridge.updateNowPlayingNative(
      track: track,
      isPlaying: true,
      position: Duration.zero,
      duration: _useNativeIosEngine
          ? _nativeDuration
          : (_primaryPlayer.duration ?? Duration(seconds: track.durationSeconds)),
    );
  }

  /// Advances to the next playable track in traversal order after the
  /// failed track (the traversal position already sits on it — see
  /// `playTrackAtIndex`), skipping entries whose files are missing (each
  /// is reported). [triedIndices] is shared across the recursion through
  /// `playTrackAtIndex`, so a queue whose files are all missing ends the
  /// queue instead of looping forever (repeat-all wraps at most once
  /// through the un-tried entries). If no playable track remains, the
  /// queue ends ([_endQueue]).
  Future<void> _playNextPlayableAfter({required Set<int> triedIndices}) async {
    var candidate = _traversal.next(wrap: _repeatMode == AudioServiceRepeatMode.all);
    while (candidate != null && !triedIndices.contains(candidate)) {
      triedIndices.add(candidate);
      final track = _trackQueue[candidate];
      if (await File(track.localFilePath).exists()) {
        await playTrackAtIndex(candidate, triedIndices: triedIndices);
        return;
      }
      _reportPlaybackError(
        'Skipped "${track.title}": audio file is missing.',
        code: 'missing_file',
        track: track,
      );
      // Move past the skipped candidate so the next lookup continues
      // forward instead of returning it again.
      _traversal.moveTo(candidate);
      candidate = _traversal.next(wrap: _repeatMode == AudioServiceRepeatMode.all);
    }
    await _endQueue();
  }

  Future<void> _triggerCrossfade() async {
    if (_isCrossfading || _trackQueue.isEmpty) return;
    // No crossfade on repeat-one (Phase 3, S-2 decision): the track
    // restarts cleanly instead of fading into the next track and then
    // repeating the wrong one.
    if (_repeatMode == AudioServiceRepeatMode.one) return;
    // S-2/S-3: the crossfade target is the same "next track" `skipToNext`
    // would play — the next track in shuffle order when shuffling, the
    // first track on repeat-all — and none at the end of the queue with
    // repeat off.
    final nextIdx = _nextIndexInTraversal();
    if (nextIdx == null) return;

    final nextTrack = _trackQueue[nextIdx];
    if (!await File(nextTrack.localFilePath).exists()) {
      // Report it and let the normal completion path advance past it;
      // starting a crossfade into a missing file would fail natively.
      _reportPlaybackError(
        'Skipped "${nextTrack.title}": audio file is missing.',
        code: 'missing_file',
        track: nextTrack,
      );
      return;
    }

    _isCrossfading = true;
    try {
      if (_useNativeIosEngine) {
        final nextDur = await IosAudioBridge.startCrossfade(
          trackId: nextTrack.id,
          filePath: nextTrack.localFilePath,
          durationSeconds: _audioSettings.crossfadeSeconds,
        );
        if (nextDur == null) {
          // The native crossfade failed: do not advance — the normal
          // completion path will move on, and the failure is reported.
          _reportPlaybackError(
            'Crossfade into "${nextTrack.title}" failed.',
            code: 'native_crossfade_failed',
            track: nextTrack,
          );
          return;
        }
        _currentIndex = nextIdx;
        _traversal.moveTo(nextIdx);
        _nativePosition = Duration.zero;
        _nativeDuration = Duration(
          milliseconds: (nextDur * 1000).round(),
        );
        _nativePlaying = true;
        _currentTrackController.add(nextTrack);
        mediaItem.add(_toMediaItem(nextTrack));
        _emitNativePlaybackState();
        unawaited(_libraryRepo.recordPlayback(nextTrack.id));
        unawaited(_persistQueue(positionMs: 0));
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
      _traversal.moveTo(nextIdx);
      _currentTrackController.add(nextTrack);
      mediaItem.add(_toMediaItem(nextTrack));
      unawaited(_libraryRepo.recordPlayback(nextTrack.id));
      unawaited(_persistQueue(positionMs: 0));

      final steps = (_audioSettings.crossfadeSeconds * 10).clamp(10, 120);
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
    await _store.saveSmartRemixConfig(config);
  }

  double _computedSoftwareGain(AudioSettings settings) {
    final dsp = VolumeDspMath.evaluateGain(
      multiplier: settings.volumeMultiplier,
      limiterEnabled: settings.limiterEnabled,
      normalizationOffsetDb: VolumeDspMath.effectiveNormalizationOffsetDb(
        multiplier: settings.volumeMultiplier,
        normalizeVolume: settings.normalizeVolume,
      ),
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
      final resumed = await IosAudioBridge.resumePlayback();
      // C-4(e): `resumePlayback` refuses to claim playing after
      // completion or with no track loaded (W1) — it returns nil either
      // way and emits an `onNativePosition` snapshot with the truth. The
      // synchronous snapshot below is the source of truth; `_nativePlaying`
      // is adopted from it, never set to `true` unconditionally.
      final snapshot = await IosAudioBridge.getNativePlaybackState();
      if (snapshot != null) {
        _nativePlaying = snapshot.isPlaying;
        _nativePosition = snapshot.position;
        _nativeDuration = snapshot.duration;
        _setProcessingState(_processingStateFromNative(snapshot.processingState));
        if (!snapshot.isPlaying &&
            snapshot.processingState == 'idle' &&
            _trackQueue.isNotEmpty) {
          // Nothing is loaded natively — either play was pressed with a
          // queue but no current track yet (tracks added to an empty
          // queue), or a prepare failed at restore. (Re)start from the
          // current track, or the first track in traversal order when
          // none is selected; a file that still cannot be opened fails
          // loudly via `playTrackAtIndex` instead of stalling here.
          await playTrackAtIndex(currentTrack == null
              ? _traversal.order.first
              : _currentIndex);
        } else if (!snapshot.isPlaying &&
            snapshot.processingState == 'completed' &&
            currentTrack != null) {
          // The user pressed play on a finished track: restart it from
          // the top instead of showing "playing" over silence.
          await playTrackAtIndex(_currentIndex);
        }
      } else if (resumed) {
        _nativePlaying = true;
      } else {
        _nativePlaying = false;
        if (currentTrack != null) {
          _reportPlaybackError(
            'Playback could not resume.',
            code: 'native_resume_failed',
          );
        }
      }
      _emitNativePlaybackState();
    } else if (currentTrack == null && _trackQueue.isNotEmpty) {
      // Same no-current-track case as the native branch above.
      await playTrackAtIndex(_traversal.order.first);
    } else {
      await _primaryPlayer.play();
    }
    final track = currentTrack;
    if (track != null) {
      await IosAudioBridge.updateNowPlayingNative(
        track: track,
        isPlaying: _nativePlaying,
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
      final pausedOk = await IosAudioBridge.pausePlayback();
      // Adopt the native snapshot, mirroring `play()`: a failed pause
      // must not leave the UI claiming "paused" while audio still plays.
      final snapshot = await IosAudioBridge.getNativePlaybackState();
      if (snapshot != null) {
        _nativePlaying = snapshot.isPlaying;
        _nativePosition = snapshot.position;
        _nativeDuration = snapshot.duration;
        _setProcessingState(_processingStateFromNative(snapshot.processingState));
      } else if (pausedOk) {
        _nativePlaying = false;
      } else {
        // Keep the previous value: if the native pause failed, audio may
        // still be playing, and claiming "paused" would lie.
        _reportPlaybackError('Pause failed.', code: 'native_pause_failed');
      }
      _emitNativePlaybackState();
    } else {
      await _primaryPlayer.pause();
    }
    final track = currentTrack;
    if (track != null) {
      final pos = _useNativeIosEngine ? _nativePosition : _primaryPlayer.position;
      unawaited(_store.savePlaybackCheckpoint(track.id, pos.inMilliseconds));
      unawaited(_persistQueue(positionMs: pos.inMilliseconds));
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
      // Seeking to/past the end must not stall the queue: with W1's
      // native `seekTo` the track completes (fires `onNativeCompleted`),
      // and this Dart guard makes the same outcome deterministic even
      // against a Swift build without that fix — the track ends exactly
      // as a natural track-end would.
      if (_nativeDuration > Duration.zero && position >= _nativeDuration) {
        await _handleTrackCompletion();
        return;
      }
      final soughtOk = await IosAudioBridge.seekTo(position.inMilliseconds / 1000.0);
      if (!soughtOk) {
        _reportPlaybackError('Seek failed.', code: 'native_seek_failed');
      }
      final snapshot = await IosAudioBridge.getNativePlaybackState();
      if (snapshot != null) {
        _nativePlaying = snapshot.isPlaying;
        _nativePosition = snapshot.position;
        _nativeDuration = snapshot.duration;
        _setProcessingState(_processingStateFromNative(snapshot.processingState));
      } else {
        _nativePosition = position;
      }
      _emitNativePlaybackState();
      final track = currentTrack;
      if (track != null) {
        await IosAudioBridge.updateNowPlayingNative(
          track: track,
          isPlaying: _nativePlaying,
          position: _nativePosition,
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
    if (_currentIndex < 0) {
      // No current track yet (e.g. tracks were added to an empty queue):
      // start at the first track in traversal order.
      await playTrackAtIndex(_traversal.order.first);
      return;
    }
    final next = _nextIndexInTraversal();
    if (next == null) {
      // S-2: repeat-none ends the queue — no wrap to track 1.
      await _endQueue();
      return;
    }
    await playTrackAtIndex(next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_trackQueue.isEmpty) return;
    if (_currentIndex < 0) {
      await playTrackAtIndex(_traversal.order.first);
      return;
    }
    final posSec = _useNativeIosEngine ? _nativePosition.inSeconds : _primaryPlayer.position.inSeconds;
    if (posSec > 4) {
      await seek(Duration.zero);
      return;
    }
    final prev = _previousIndexInTraversal();
    if (prev == null) {
      // S-2: first track, repeat-none — no wrap to the last track.
      // Restart the current track instead.
      await seek(Duration.zero);
      return;
    }
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
    unawaited(_persistQueue());
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffle = shuffleMode != AudioServiceShuffleMode.none;
    // Enabling shuffle draws a new order with the current track first;
    // disabling restores the sequential order from the current track.
    _rebuildTraversal();
    if (_useNativeIosEngine) {
      _emitNativePlaybackState();
    } else {
      playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    }
    unawaited(_persistQueue());
  }

  /// C-1 (single Now Playing writer) — value-identity neutralisation.
  ///
  /// The native plugin is the writer of record for MPNowPlayingInfoCenter
  /// (it loads/fetches and caches artwork, and owns the clear). The
  /// `audio_service` package also writes the same InfoCenter from this
  /// media item + playback state, and there is no API — Dart or Swift —
  /// to disable the package's writes. So instead of publishing a
  /// deliberately incomplete media item (no artwork) and risking the
  /// package actively clearing the plugin's artwork on every state
  /// emission, this publishes the SAME values the plugin writes
  /// (title / artist / album / artwork / duration), so whichever write
  /// lands last shows the same thing. The duplicate is therefore
  /// invisible; only a device run (gate G-2) can prove the lock screen
  /// shows the plugin's artwork and no flicker.
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
      // See `_emitNativePlaybackState`: no seekForward / seekBackward —
      // no ±15 s behaviour is implemented anywhere.
      systemActions: const {
        MediaAction.seek,
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
    await _queueController.close();
    await _playbackErrorController.close();
    await IosAudioBridge.stopPlayback();
    await _primaryPlayer.dispose();
    await _crossfadePlayer.dispose();
  }
}
