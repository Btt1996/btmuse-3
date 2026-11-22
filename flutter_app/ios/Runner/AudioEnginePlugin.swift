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

    // 5-band EQ curve gains in dB
    let gains: [Float]
    switch eqPreset {
    case "Bass Boost":
      gains = [6.5, 4.0, 0.0, -1.0, 1.0]
    case "Vocal Clarity":
      gains = [-2.5, -1.0, 4.5, 4.0, 1.5]
    case "Treble Crisp":
      gains = [-1.0, 0.0, 1.5, 4.5, 6.0]
    case "Acoustic Warmth":
      gains = [3.5, 2.5, 1.0, 0.5, -1.5]
    default:
      gains = [0.0, 0.0, 0.0, 0.0, 0.0]
    }
    for i in 0..<min(gains.count, eqNode.bands.count) {
      eqNode.bands[i].gain = gains[i]
    }
    eqNode.bypass = (eqPreset == "Balanced")

    // Gain staging + DynamicsProcessor soft-knee ceiling (-1.0 dBFS)
    let normDb: Double = normalizeVolume ? -1.5 : 0.0
    let boostDb: Double
    if currentGainMultiplier <= 0.0001 {
      boostDb = -80.0
      engine.mainMixerNode.outputVolume = 0.0
    } else {
      boostDb = 20.0 * log10(currentGainMultiplier) + normDb
      engine.mainMixerNode.outputVolume = 1.0
    }

    let au = dynamicsNode.audioUnit
    let thresholdDb: Float = limiterEnabled ? -1.5 : 18.0
    AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, thresholdDb, 0)
    AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, limiterEnabled ? 2.5 : 40.0, 0)
    AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.002, 0)
    AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.05, 0)
    AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, Float(max(-40.0, min(12.0, boostDb))), 0)
    dynamicsNode.bypass = false

    result([
      "appliedMultiplier": currentGainMultiplier,
      "boostDb": boostDb,
      "limiterEnabled": limiterEnabled,
      "eqPreset": eqPreset
    ])
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
            self.stopPositionTimer()
            self.channel?.invokeMethod("onNativeCompleted", arguments: ["trackId": trackId ?? ""])
          }
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
        "playing": isPlayingState
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
    stopPositionTimer()
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
          self.stopPositionTimer()
          self.channel?.invokeMethod("onNativeCompleted", arguments: ["trackId": trackId ?? ""])
        }
      }
      if wasPlaying {
        node.play()
        isPlayingState = true
        startPositionTimer()
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
          self.stopPositionTimer()
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
      "isPlaying": isPlayingState
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
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      result(nil)
      return
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info

    if let artPath = args["artworkPath"] as? String,
       let image = UIImage(contentsOfFile: artPath) {
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      artworkCache.setObject(artwork, forKey: cacheKey)
      if activeTrackId == trackId {
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
          MPNowPlayingInfoCenter.default().nowPlayingInfo = current
        }
      }.resume()
    }

    result(nil)
  }
}
