import AudioToolbox
import AVFoundation
import Flutter
import MediaPlayer
import UIKit

final class AudioEnginePlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?

  private let artworkCache: NSCache<NSString, MPMediaItemArtwork> = {
    let cache = NSCache<NSString, MPMediaItemArtwork>()
    cache.countLimit = 40
    cache.totalCostLimit = 24 * 1024 * 1024
    return cache
  }()

  // Real CoreAudio AVAudioEngine DSP Graph
  private let engine = AVAudioEngine()
  private let playerA = AVAudioPlayerNode()
  private let playerB = AVAudioPlayerNode()
  private let deckMixer = AVAudioMixerNode()
  private let timePitch = AVAudioUnitTimePitch()
  private let eqNode = AVAudioUnitEQ(numberOfBands: 5)
  private let dynamicsNode = AVAudioUnitEffect(
    audioComponentDescription: AudioComponentDescription(
      componentType: kAudioUnitType_Effect,
      componentSubType: kAudioUnitSubType_DynamicsProcessor,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0,
      componentFlagsMask: 0
    )
  )

  private var graphConfigured = false
  private var useDeckAAsPrimary = true
  private var primaryFile: AVAudioFile?
  private var crossfadeFile: AVAudioFile?
  private var activeFileStartFrame: AVAudioFramePosition = 0
  private var activeTrackDurationSec: Double = 0.0
  private var activeTrackId: String?
  private var isPlayingState = false
  private var playbackGeneration = 0

  private var positionTimer: Timer?
  private var crossfadeTimer: Timer?
  private var isCrossfading = false

  private var currentGainMultiplier: Double = 1.0
  private var limiterEnabled: Bool = true
  private var normalizeVolume: Bool = true
  private var eqPreset: String = "Balanced"
  /// True once the loaded track has played to completion (and no new track,
  /// seek, or crossfade has superseded it). Used for the honest processing
  /// state: a finished track is "completed", not "ready".
  private var didCompleteCurrentTrack = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "com.ahmed.btmu/audio_engine",
      binaryMessenger: registrar.messenger()
    )
    let instance = AudioEnginePlugin()
    instance.channel = methodChannel
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "configureSession":
      configureSession(result: result)
    case "applyAudioSettings":
      applyAudioSettings(args: args, result: result)
    case "setPlaybackSpeed":
      let speed = Float(max(0.5, min(2.0, (args["speed"] as? Double) ?? 1.0)))
      ensureEngineGraph()
      timePitch.rate = speed
      result(nil)
    case "playFile":
      playFile(args: args, result: result)
    case "prepareFile":
      prepareFile(args: args, result: result)
    case "pausePlayback":
      pausePlayback(result: result)
    case "resumePlayback":
      resumePlayback(result: result)
    case "seekTo":
      seekTo(args: args, result: result)
    case "stopPlayback":
      stopPlayback(result: result)
    case "startCrossfade":
      startCrossfade(args: args, result: result)
    case "updateNowPlaying":
      updateNowPlaying(args: args, result: result)
    case "clearNowPlaying":
      clearNowPlaying()
      result(nil)
    case "getNativePlaybackState":
      getNativePlaybackState(result: result)
    case "extractMonoPcm":
      extractMonoPcm(args: args, result: result)
    case "extractAudioMetadata":
      extractAudioMetadata(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func ensureEngineGraph() {
    if graphConfigured { return }
    engine.attach(playerA)
    engine.attach(playerB)
    engine.attach(deckMixer)
    engine.attach(timePitch)
    engine.attach(eqNode)
    engine.attach(dynamicsNode)

    let format = engine.outputNode.outputFormat(forBus: 0)
    let stereoFormat = AVAudioFormat(
      standardFormatWithSampleRate: format.sampleRate > 0 ? format.sampleRate : 44100,
      channels: 2
    )

    engine.connect(playerA, to: deckMixer, format: stereoFormat)
    engine.connect(playerB, to: deckMixer, format: stereoFormat)
    engine.connect(deckMixer, to: timePitch, format: stereoFormat)
    engine.connect(timePitch, to: eqNode, format: stereoFormat)
    engine.connect(eqNode, to: dynamicsNode, format: stereoFormat)
    engine.connect(dynamicsNode, to: engine.mainMixerNode, format: stereoFormat)

    configureEqFrequencies()
    graphConfigured = true
  }

  private func ensurePlayerConnectionFormat(_ node: AVAudioPlayerNode, fileFormat: AVAudioFormat) {
    let wasRunning = engine.isRunning
    node.stop()
    engine.disconnectNodeOutput(node)
    engine.connect(node, to: deckMixer, format: fileFormat)
    if !wasRunning {
      engine.prepare()
    }
  }

  private func configureEqFrequencies() {
    let freqs: [Float] = [60, 230, 910, 3600, 14000]
    let types: [AVAudioUnitEQFilterType] = [
      .lowShelf,
      .parametric,
      .parametric,
      .parametric,
      .highShelf,
    ]
    for i in 0..<min(freqs.count, eqNode.bands.count) {
      let band = eqNode.bands[i]
      band.filterType = types[i]
      band.frequency = freqs[i]
      band.bandwidth = 1.0
      band.gain = 0.0
      band.bypass = false
    }
  }

  private func startEngineIfNeeded() throws {
    ensureEngineGraph()
    if !engine.isRunning {
      engine.prepare()
      try engine.start()
    }
  }

  private func activePlayer() -> AVAudioPlayerNode {
    useDeckAAsPrimary ? playerA : playerB
  }

  private func secondaryPlayer() -> AVAudioPlayerNode {
    useDeckAAsPrimary ? playerB : playerA
  }

  private func configureSession(result: @escaping FlutterResult) {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
      try session.setActive(true)
      ensureEngineGraph()
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "AUDIO_SESSION_ERROR",
          message: "Failed to configure AVAudioSession: \(error.localizedDescription)",
          details: nil
        )
      )
    }
  }

  private func applyAudioSettings(args: [String: Any], result: @escaping FlutterResult) {
    ensureEngineGraph()
    currentGainMultiplier = max(0.0, min(3.0, (args["volumeMultiplier"] as? Double) ?? 1.0))
    limiterEnabled = (args["limiterEnabled"] as? Bool) ?? true
    normalizeVolume = (args["normalizeVolume"] as? Bool) ?? true
    eqPreset = (args["eqPreset"] as? String) ?? "Balanced"

    // 5-band EQ curve gains in dB, bands at 60 / 230 / 910 / 3600 / 14000 Hz
    // (lowShelf, parametric, parametric, parametric, highShelf).
    //
    // CANONICAL PRESET CONTRACT (Phase 3, E-1): these case labels must match
    // AudioSettings.eqPresets in flutter_app/lib/data/models/audio_settings.dart
    // exactly — Balanced, Warm Bass, Vocal Clarity, Late Night, Studio Bright.
    // Every preset except Balanced maps to a distinct, non-flat curve; no
    // canonical preset may fall through to the default (all-zero) gains.
    // The default case below is defensive only, for a stale persisted string.
    // Legacy Swift-only names are retired, not renamed silently:
    //   "Bass Boost" curve lives on as "Warm Bass",
    //   "Treble Crisp" curve lives on as "Studio Bright",
    //   "Acoustic Warmth" has no Dart preset and is dropped.
    // See flutter_app/test/audio_settings_eq_test.dart, which asserts this
    // table (names + gains) against the Dart list.
    let gains: [Float]
    switch eqPreset {
    case "Balanced":
      gains = [0.0, 0.0, 0.0, 0.0, 0.0]
    case "Warm Bass":
      // Former "Bass Boost" curve, unchanged.
      gains = [6.5, 4.0, 0.0, -1.0, 1.0]
    case "Vocal Clarity":
      gains = [-2.5, -1.0, 4.5, 4.0, 1.5]
    case "Late Night":
      // NEW curve, gentle low/high roll-off for quiet late-night listening:
      //   60 Hz   -1.5 dB — sub-bass trimmed so playback does not boom
      //                    through walls / disturb others at night.
      //   230 Hz   0.0 dB — low mids left alone.
      //   910 Hz  +1.0 dB — mids kept slightly forward so vocals stay
      //                    intelligible at low volume.
      //   3600 Hz -1.0 dB — presence tamed, less harshness.
      //   14000 Hz -3.5 dB — highs rolled off, less hiss / shrillness.
      // Deliberately NOT a loudness-compensation lift: at night the goal is
      // restraint at both ends of the spectrum, not more bass.
      gains = [-1.5, 0.0, 1.0, -1.0, -3.5]
    case "Studio Bright":
      // Former "Treble Crisp" curve, unchanged.
      gains = [-1.0, 0.0, 1.5, 4.5, 6.0]
    default:
      gains = [0.0, 0.0, 0.0, 0.0, 0.0]
    }
    for i in 0..<min(gains.count, eqNode.bands.count) {
      eqNode.bands[i].gain = gains[i]
    }
    eqNode.bypass = (eqPreset == "Balanced")

    // Gain staging + DynamicsProcessor soft-knee ceiling (-1.0 dBFS).
    //
    // E-2 — the two numbers, stated plainly (both are returned below so the
    // Dart UI can show them instead of quoting only one):
    //   raw gain      = 20 * log10(multiplier)            (normalization off)
    //   effective gain = raw gain + normalization (-1.5 dB when on, the default)
    // At 300% (multiplier 3.0): raw = +9.54 dB, effective = +8.04 dB with the
    // default normalization. 300% is +9.5 dB of digital gain, not 3x perceived
    // loudness. The DynamicsProcessor OverallGain parameter receives the
    // effective gain clamped to [-40, +12] dB.
    // Limiter behaviour is UNCHANGED: limiter stays on by default and can only
    // be switched off explicitly by the user in the UI (limiterEnabled == false
    // neuters it via threshold 18 dB / headroom 40 dB; the node itself is never
    // bypassed).
    let (rawBoostDb, normDb, boostDb, overallGainDb) = currentGainValues()
    if currentGainMultiplier <= 0.0001 {
      engine.mainMixerNode.outputVolume = 0.0
    } else {
      engine.mainMixerNode.outputVolume = 1.0
    }

    let au = dynamicsNode.audioUnit
    let thresholdDb: Float = limiterEnabled ? -1.5 : 18.0
    AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, thresholdDb, 0)
    AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, limiterEnabled ? 2.5 : 40.0, 0)
    AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.002, 0)
    AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.05, 0)
    AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, Float(overallGainDb), 0)
    dynamicsNode.bypass = false

    result([
      "appliedMultiplier": currentGainMultiplier,
      "boostDb": boostDb,
      "rawBoostDb": rawBoostDb,
      "normalizationDb": normDb,
      "overallGainDb": overallGainDb,
      "limiterEnabled": limiterEnabled,
      "eqPreset": eqPreset
    ])
  }

  /// Gain values for the current multiplier / normalization settings.
  /// - rawBoostDb: 20 * log10(multiplier), before normalization (-80 dB when muted).
  /// - normDb: -1.5 dB when normalization is on AND the booster is off
  ///   (multiplier <= 1.0). When the user explicitly boosts above 100%,
  ///   the pad no longer subtracts from the boost: 300% delivers its
  ///   full +9.54 dB of digital gain. Normalization is a loudness-
  ///   balancing pad for normal playback, not a tax on an explicit boost
  ///   (v3.0.5 — the user reported 300% feeling small, and the audit
  ///   found the net was +8.04 dB, not +9.54 dB).
  /// - boostDb: raw + norm (the effective gain the user hears).
  /// - overallGainDb: boostDb clamped to [-40, +12] dB — exactly the value
  ///   written to the DynamicsProcessor OverallGain parameter. The limiter
  ///   stays engaged throughout; this change removes the pad, it does not
  ///   touch the limiter curve.
  private func currentGainValues() -> (rawDb: Double, normDb: Double, effectiveDb: Double, overallDb: Double) {
    let normDb: Double = (normalizeVolume && currentGainMultiplier <= 1.0) ? -1.5 : 0.0
    // Muted (multiplier ~0): -80 dB flat, as before — normalization is not
    // stacked on top of the mute floor.
    if currentGainMultiplier <= 0.0001 {
      return (-80.0, normDb, -80.0, -40.0)
    }
    let rawDb: Double = 20.0 * log10(currentGainMultiplier)
    let effectiveDb = rawDb + normDb
    let overallDb = max(-40.0, min(12.0, effectiveDb))
    return (rawDb, normDb, effectiveDb, overallDb)
  }

  private func prepareFile(args: [String: Any], result: @escaping FlutterResult) {
    loadAndSchedule(args: args, autoPlay: false, result: result)
  }

  private func playFile(args: [String: Any], result: @escaping FlutterResult) {
    loadAndSchedule(args: args, autoPlay: true, result: result)
  }

  private func loadAndSchedule(args: [String: Any], autoPlay: Bool, result: @escaping FlutterResult) {
    guard let filePath = args["filePath"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing filePath", details: nil))
      return
    }
    let startPosSec = max(0.0, (args["startPositionSeconds"] as? Double) ?? 0.0)
    let trackId = args["trackId"] as? String

    do {
      crossfadeTimer?.invalidate()
      isCrossfading = false
      try startEngineIfNeeded()

      let fileUrl = URL(fileURLWithPath: filePath)
      let file = try AVAudioFile(forReading: fileUrl)
      let sr = file.processingFormat.sampleRate
      let totalFrames = file.length
      let startFrame = min(totalFrames, AVAudioFramePosition(startPosSec * sr))
      let remainingFrames = AVAudioFrameCount(max(0, totalFrames - startFrame))

      playbackGeneration += 1
      let gen = playbackGeneration
      didCompleteCurrentTrack = false

      playerA.stop()
      playerB.stop()
      useDeckAAsPrimary = true
      primaryFile = file
      crossfadeFile = nil
      activeFileStartFrame = startFrame
      activeTrackDurationSec = sr > 0 ? Double(totalFrames) / sr : 0.0
      activeTrackId = trackId

      let node = activePlayer()
      ensurePlayerConnectionFormat(node, fileFormat: file.processingFormat)
      if !engine.isRunning {
        engine.prepare()
        try engine.start()
      }
      node.volume = 1.0

      if remainingFrames > 0 {
        node.scheduleSegment(
          file,
          startingFrame: startFrame,
          frameCount: remainingFrames,
          at: nil,
          completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
          DispatchQueue.main.async {
            guard let self = self,
                  self.playbackGeneration == gen,
                  !self.isCrossfading else { return }
            self.isPlayingState = false
            self.didCompleteCurrentTrack = true
            self.stopPositionTimer()
            self.emitPositionSnapshot()
            self.channel?.invokeMethod("onNativeCompleted", arguments: ["trackId": trackId ?? ""])
          }
        }
      } else {
        // Nothing left to play (started at/past the end): complete the track
        // instead of stalling the queue with no callback. Dart's
        // _handleTrackCompletion decides next / repeat / queue-end from here.
        didCompleteCurrentTrack = true
        isPlayingState = false
        stopPositionTimer()
        emitPositionSnapshot()
        let completedTrackId = trackId
        DispatchQueue.main.async { [weak self] in
          self?.channel?.invokeMethod("onNativeCompleted", arguments: ["trackId": completedTrackId ?? ""])
        }
      }

      if autoPlay && remainingFrames > 0 {
        node.play()
        isPlayingState = true
        startPositionTimer()
      } else {
        isPlayingState = false
        stopPositionTimer()
      }

      result([
        "durationSeconds": activeTrackDurationSec,
        "playing": isPlayingState,
        "processingState": nativeProcessingState()
      ])
    } catch {
      result(
        FlutterError(
          code: "PLAYBACK_ERROR",
          message: "Failed to open/play audio file: \(error.localizedDescription)",
          details: nil
        )
      )
    }
  }

  private func pausePlayback(result: @escaping FlutterResult) {
    activePlayer().pause()
    isPlayingState = false
    stopPositionTimer()
    emitPositionSnapshot()
    result(nil)
  }

  private func resumePlayback(result: @escaping FlutterResult) {
    do {
      try startEngineIfNeeded()
      // A completed track has no scheduled segment left: replaying it needs
      // a seek(0) / playFile, not a bare play(). Claiming "playing" here
      // would show a playing UI over silence (the C-4 failure pattern).
      if didCompleteCurrentTrack || primaryFile == nil {
        isPlayingState = false
        stopPositionTimer()
        emitPositionSnapshot()
        result(nil)
        return
      }
      activePlayer().play()
      isPlayingState = true
      startPositionTimer()
      emitPositionSnapshot()
      result(nil)
    } catch {
      result(FlutterError(code: "RESUME_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private func stopPlayback(result: @escaping FlutterResult) {
    crossfadeTimer?.invalidate()
    isCrossfading = false
    playbackGeneration += 1
    playerA.stop()
    playerB.stop()
    isPlayingState = false
    didCompleteCurrentTrack = false
    primaryFile = nil
    crossfadeFile = nil
    activeTrackDurationSec = 0.0
    stopPositionTimer()
    // C-1: stopping clears the lock-screen metadata — a stopped player must
    // not leave a stale track on the lock screen. Queue-end clearing is the
    // Dart side's job (only the handler knows the queue ended vs. advanced):
    // BttAudioHandler must call the "clearNowPlaying" channel method when
    // _handleTrackCompletion reaches the end of the queue with repeat off.
    clearNowPlaying()
    result(nil)
  }

  private func seekTo(args: [String: Any], result: @escaping FlutterResult) {
    guard let file = primaryFile else {
      result(nil)
      return
    }
    let positionSeconds = max(0.0, (args["positionSeconds"] as? Double) ?? 0.0)
    let wasPlaying = isPlayingState
    let sr = file.processingFormat.sampleRate
    let totalFrames = file.length
    let targetFrame = min(totalFrames, AVAudioFramePosition(positionSeconds * sr))
    let remaining = AVAudioFrameCount(max(0, totalFrames - targetFrame))

    playbackGeneration += 1
    let gen = playbackGeneration
    let trackId = activeTrackId
    didCompleteCurrentTrack = false

    let node = activePlayer()
    node.stop()
    activeFileStartFrame = targetFrame

    if remaining > 0 {
      node.scheduleSegment(
        file,
        startingFrame: targetFrame,
        frameCount: remaining,
        at: nil,
        completionCallbackType: .dataPlayedBack
      ) { [weak self] _ in
        DispatchQueue.main.async {
          guard let self = self,
                self.playbackGeneration == gen,
                !self.isCrossfading else { return }
          self.isPlayingState = false
          self.didCompleteCurrentTrack = true
          self.stopPositionTimer()
          self.emitPositionSnapshot()
          self.channel?.invokeMethod("onNativeCompleted", arguments: ["trackId": trackId ?? ""])
        }
      }
      if wasPlaying {
        node.play()
        isPlayingState = true
        startPositionTimer()
      }
    } else {
      // Seeked to/past the end: complete the track instead of stalling.
      // No segment is scheduled and nothing plays; firing onNativeCompleted
      // lets Dart advance the queue (or end it) exactly as a natural
      // track-end would. Dispatched async so this seekTo call returns first.
      isPlayingState = false
      didCompleteCurrentTrack = true
      stopPositionTimer()
      let completedTrackId = trackId
      DispatchQueue.main.async { [weak self] in
        self?.channel?.invokeMethod("onNativeCompleted", arguments: ["trackId": completedTrackId ?? ""])
      }
    }
    emitPositionSnapshot()
    result(nil)
  }

  private func startCrossfade(args: [String: Any], result: @escaping FlutterResult) {
    guard let filePath = args["filePath"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing filePath", details: nil))
      return
    }
    let durationSec = max(1.0, min(15.0, (args["durationSeconds"] as? Double) ?? 6.0))
    let nextTrackId = args["trackId"] as? String

    do {
      try startEngineIfNeeded()
      crossfadeTimer?.invalidate()

      let nextFile = try AVAudioFile(forReading: URL(fileURLWithPath: filePath))
      let outgoing = activePlayer()
      let incoming = secondaryPlayer()

      incoming.stop()
      ensurePlayerConnectionFormat(incoming, fileFormat: nextFile.processingFormat)
      if !engine.isRunning {
        engine.prepare()
        try engine.start()
      }
      incoming.volume = 0.0

      playbackGeneration += 1
      let gen = playbackGeneration

      let sr = nextFile.processingFormat.sampleRate
      let nextDuration = sr > 0 ? Double(nextFile.length) / sr : 0.0

      crossfadeFile = nextFile
      isCrossfading = true

      incoming.scheduleSegment(
        nextFile,
        startingFrame: 0,
        frameCount: AVAudioFrameCount(nextFile.length),
        at: nil,
        completionCallbackType: .dataPlayedBack
      ) { [weak self] _ in
        DispatchQueue.main.async {
          guard let self = self,
                self.playbackGeneration == gen,
                !self.isCrossfading else { return }
          self.isPlayingState = false
          self.didCompleteCurrentTrack = true
          self.stopPositionTimer()
          self.emitPositionSnapshot()
          self.channel?.invokeMethod("onNativeCompleted", arguments: ["trackId": nextTrackId ?? ""])
        }
      }
      incoming.play()

      let totalSteps = Int(durationSec * 20.0) // 50ms steps
      var step = 0
      crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
        guard let self = self else {
          timer.invalidate()
          return
        }
        step += 1
        let t = min(1.0, Double(step) / Double(max(1, totalSteps)))
        // Equal-power sinusoidal crossfade
        outgoing.volume = Float(cos(t * Double.pi * 0.5))
        incoming.volume = Float(sin(t * Double.pi * 0.5))

        if t >= 1.0 {
          timer.invalidate()
          outgoing.stop()
          incoming.volume = 1.0
          self.useDeckAAsPrimary.toggle()
          self.primaryFile = nextFile
          self.crossfadeFile = nil
          self.activeFileStartFrame = 0
          self.activeTrackDurationSec = nextDuration
          self.activeTrackId = nextTrackId
          self.isCrossfading = false
          self.didCompleteCurrentTrack = false
          self.isPlayingState = true
          self.startPositionTimer()
        }
      }
      result(["durationSeconds": nextDuration])
    } catch {
      isCrossfading = false
      result(FlutterError(code: "CROSSFADE_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private func currentElapsedSeconds() -> Double {
    guard let file = primaryFile else { return 0.0 }
    let node = activePlayer()
    guard let nodeTime = node.lastRenderTime,
          let playerTime = node.playerTime(forNodeTime: nodeTime) else {
      let sr = file.processingFormat.sampleRate
      return sr > 0 ? Double(activeFileStartFrame) / sr : 0.0
    }
    let sr = file.processingFormat.sampleRate
    guard sr > 0 else { return 0.0 }
    let currentFrame = Double(activeFileStartFrame) + Double(playerTime.sampleTime)
    return max(0.0, min(activeTrackDurationSec, currentFrame / sr))
  }

  private func startPositionTimer() {
    positionTimer?.invalidate()
    positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.emitPositionSnapshot()
    }
  }

  private func stopPositionTimer() {
    positionTimer?.invalidate()
    positionTimer = nil
  }

  private func emitPositionSnapshot() {
    channel?.invokeMethod("onNativePosition", arguments: [
      "positionSeconds": currentElapsedSeconds(),
      "durationSeconds": activeTrackDurationSec,
      "isPlaying": isPlayingState,
      // C-1: honest processing state for the Dart side — do NOT report
      // "ready" when idle (no track / stopped) or completed (track ended).
      // BttAudioHandler._emitNativePlaybackState must map this onto
      // AudioProcessingState instead of its current constant
      // AudioProcessingState.ready (see the getNativePlaybackState docs).
      "processingState": nativeProcessingState()
    ])
  }

  /// Honest native processing state, in audio_service terms.
  /// - "idle": no track loaded (fresh start, or after stopPlayback).
  /// - "completed": the loaded track played to the end (natural completion,
  ///   seek-to-end, or playFile started at/past the end).
  /// - "ready": a track is loaded and paused or playing.
  /// There is no async "loading" window to report: loadAndSchedule reads the
  /// file synchronously on the method-call thread, so between the Dart call
  /// and its result the state is transiently "loading" only inside that call.
  private func nativeProcessingState() -> String {
    if primaryFile == nil { return "idle" }
    if didCompleteCurrentTrack { return "completed" }
    return "ready"
  }

  /// Synchronous snapshot of the native playback state for the Dart side.
  /// Dart (BttAudioHandler / IosAudioBridge) should call this when it needs
  /// the state outside the 0.5 s position ticks — e.g. right after
  /// playFile/prepareFile — and must use "processingState" here instead of
  /// hard-coding AudioProcessingState.ready.
  private func getNativePlaybackState(result: @escaping FlutterResult) {
    let (_, _, boostDb, overallGainDb) = currentGainValues()
    result([
      "processingState": nativeProcessingState(),
      "isPlaying": isPlayingState,
      "positionSeconds": currentElapsedSeconds(),
      "durationSeconds": activeTrackDurationSec,
      "trackId": activeTrackId as Any,
      "eqPreset": eqPreset,
      "boostDb": boostDb,
      "overallGainDb": overallGainDb,
      "limiterEnabled": limiterEnabled
    ])
  }

  /// Extracts native ID3 / iTunes / Vorbis metadata, exact duration, and embedded cover art using AVURLAsset.
  private func extractAudioMetadata(args: [String: Any], result: @escaping FlutterResult) {
    guard let filePath = args["filePath"] as? String else {
      result(nil)
      return
    }
    let artworkDestPath = args["artworkDestPath"] as? String

    DispatchQueue.global(qos: .userInitiated).async {
      let url = URL(fileURLWithPath: filePath)
      let asset = AVURLAsset(url: url)
      let durationSec = CMTimeGetSeconds(asset.duration)
      let safeDuration = durationSec.isFinite && durationSec > 0 ? Int(durationSec.rounded()) : 0

      var title: String?
      var artist: String?
      var album: String?
      var savedArtworkPath: String?

      for item in asset.commonMetadata {
        guard let key = item.commonKey else { continue }
        switch key {
        case .commonKeyTitle:
          if let val = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
            title = val
          }
        case .commonKeyArtist:
          if let val = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
            artist = val
          }
        case .commonKeyAlbumName:
          if let val = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
            album = val
          }
        case .commonKeyArtwork:
          if savedArtworkPath == nil,
             let dest = artworkDestPath,
             let data = item.dataValue,
             !data.isEmpty {
            let destUrl = URL(fileURLWithPath: dest)
            if (try? data.write(to: destUrl, options: .atomic)) != nil {
              savedArtworkPath = dest
            }
          }
        default:
          break
        }
      }

      DispatchQueue.main.async {
        result([
          "title": title as Any,
          "artist": artist as Any,
          "album": album as Any,
          "durationSeconds": safeDuration,
          "artworkPath": savedArtworkPath as Any
        ])
      }
    }
  }

  /// Native iOS AVFoundation PCM decoder (zero external binaries / FFmpeg required).
  /// Converts MP3, M4A, AAC, FLAC, or WAV into 16-bit mono PCM at 11,025 Hz for local X1 fingerprinting.
  private func extractMonoPcm(args: [String: Any], result: @escaping FlutterResult) {
    guard let filePath = args["filePath"] as? String else {
      result(nil)
      return
    }
    let maxSeconds = (args["maxSeconds"] as? Int) ?? 60
    let targetSampleRate = Double((args["targetSampleRate"] as? Int) ?? 11025)

    DispatchQueue.global(qos: .userInitiated).async {
      let url = URL(fileURLWithPath: filePath)
      guard let audioFile = try? AVAudioFile(forReading: url),
            let outputFormat = AVAudioFormat(
              commonFormat: .pcmFormatInt16,
              sampleRate: targetSampleRate,
              channels: 1,
              interleaved: true
            ),
            let converter = AVAudioConverter(from: audioFile.processingFormat, to: outputFormat) else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      let maxOutputFrames = AVAudioFrameCount(maxSeconds) * AVAudioFrameCount(targetSampleRate)
      let chunkFrames: AVAudioFrameCount = 8192
      guard let inBuffer = AVAudioPCMBuffer(
        pcmFormat: audioFile.processingFormat,
        frameCapacity: chunkFrames
      ),
      let outBuffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: maxOutputFrames
      ) else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      var pcmData = Data()
      var totalFramesConverted: AVAudioFrameCount = 0

      while totalFramesConverted < maxOutputFrames {
        var reachedEnd = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
          do {
            try audioFile.read(into: inBuffer, frameCount: chunkFrames)
            if inBuffer.frameLength == 0 {
              reachedEnd = true
              outStatus.pointee = .endOfStream
              return nil
            }
            outStatus.pointee = .haveData
            return inBuffer
          } catch {
            reachedEnd = true
            outStatus.pointee = .endOfStream
            return nil
          }
        }

        var convError: NSError?
        outBuffer.frameLength = 0
        let remaining = maxOutputFrames - totalFramesConverted
        let status = converter.convert(to: outBuffer, error: &convError, withInputFrom: inputBlock)

        if let int16Ptr = outBuffer.int16ChannelData?[0], outBuffer.frameLength > 0 {
          let takeFrames = min(outBuffer.frameLength, remaining)
          pcmData.append(Data(bytes: int16Ptr, count: Int(takeFrames) * 2))
          totalFramesConverted += takeFrames
        }

        if reachedEnd || status == .endOfStream || status == .error || convError != nil {
          break
        }
      }

      DispatchQueue.main.async {
        result(FlutterStandardTypedData(bytes: pcmData))
      }
    }
  }

  // MARK: - Now Playing (C-1: single writer)
  //
  // OWNERSHIP: this plugin is the single native writer of
  // MPNowPlayingInfoCenter. Every write in this file goes through
  // setNowPlayingInfo(_:) and every clear through clearNowPlaying() — no
  // other method in this file touches nowPlayingInfo directly.
  // KNOWN DUPLICATE (Dart side, not fixable from Swift): audio_service also
  // writes the same InfoCenter from the MediaItem (BttAudioHandler._toMediaItem)
  // and PlaybackState (_emitNativePlaybackState). The handler worker must
  // neutralise that duplicate (e.g. publish the media item without artwork
  // and let this plugin own the info, or vice versa) and prove the result on
  // device (gate G-2); this plugin cannot disable the package's writes.
  // No MPRemoteCommandCenter code is added here by design — audio_service
  // owns lock-screen / Control Center commands (brief decision).

  /// The only place in this file that assigns nowPlayingInfo (apart from
  /// clearNowPlaying, which assigns nil). Pass nil to clear.
  private func setNowPlayingInfo(_ info: [String: Any]?) {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  /// Clears lock-screen / Control Center metadata. Called by stopPlayback
  /// and exposed as the "clearNowPlaying" channel method so Dart can call it
  /// on queue-end (only the handler knows the queue ended vs. advanced to
  /// the next track). Also clears activeTrackId so an in-flight artwork
  /// fetch for the old track cannot repopulate the info afterwards.
  private func clearNowPlaying() {
    activeTrackId = nil
    setNowPlayingInfo(nil)
  }

  private func updateNowPlaying(args: [String: Any], result: @escaping FlutterResult) {
    guard let trackId = args["id"] as? String else {
      result(nil)
      return
    }
    activeTrackId = trackId

    let title = (args["title"] as? String) ?? "Btt Music"
    let artist = (args["artist"] as? String) ?? "Unknown Artist"
    let album = (args["album"] as? String) ?? "Btt Music"
    let isPlaying = (args["isPlaying"] as? Bool) ?? false
    let position = (args["positionSeconds"] as? Double) ?? 0.0
    let duration = (args["durationSeconds"] as? Double) ?? 0.0

    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = title
    info[MPMediaItemPropertyArtist] = artist
    info[MPMediaItemPropertyAlbumTitle] = album
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    let cacheKey = trackId as NSString
    if let cachedArtwork = artworkCache.object(forKey: cacheKey) {
      info[MPMediaItemPropertyArtwork] = cachedArtwork
      setNowPlayingInfo(info)
      result(nil)
      return
    }

    setNowPlayingInfo(info)

    if let artPath = args["artworkPath"] as? String,
       let image = UIImage(contentsOfFile: artPath) {
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      artworkCache.setObject(artwork, forKey: cacheKey)
      if activeTrackId == trackId {
        info[MPMediaItemPropertyArtwork] = artwork
        setNowPlayingInfo(info)
      }
      result(nil)
      return
    }

    if let artUrlString = args["artworkUrl"] as? String,
       let artUrl = URL(string: artUrlString),
       artUrl.scheme == "https" {
      URLSession.shared.dataTask(with: artUrl) { [weak self] data, _, _ in
        guard let self = self,
              let data = data,
              let image = UIImage(data: data) else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.artworkCache.setObject(artwork, forKey: cacheKey)
        DispatchQueue.main.async {
          guard self.activeTrackId == trackId else { return }
          var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
          current[MPMediaItemPropertyArtwork] = artwork
          self.setNowPlayingInfo(current)
        }
      }.resume()
    }

    result(nil)
  }
}
