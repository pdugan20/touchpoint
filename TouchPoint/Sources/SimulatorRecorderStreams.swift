import AVFoundation
import Cocoa
import ScreenCaptureKit

// MARK: - Audio & window following

extension SimulatorRecorder {
  /// Simulator audio is not attributed to the Simulator's windows, so a
  /// window-filtered stream records silence. Capture audio on a second,
  /// display-wide stream (no video output attached) instead.
  func attachAudioStream(display: SCDisplay) throws {
    let audioConfig = SCStreamConfiguration()
    audioConfig.capturesAudio = true
    audioConfig.excludesCurrentProcessAudio = true
    audioConfig.sampleRate = 48000
    audioConfig.channelCount = 2
    audioConfig.width = 2
    audioConfig.height = 2
    audioConfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    let audioFilter = SCContentFilter(display: display, excludingWindows: [])
    let audioStream = SCStream(filter: audioFilter, configuration: audioConfig, delegate: self)
    try audioStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
    self.audioStream = audioStream
  }

  /// The stream delivers frames only when pixels change, so a static screen
  /// starves the video track. Re-append the last frame once per second of
  /// stillness (and once at stop) so the track always spans the take.
  func startHeartbeat() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 1, repeating: .seconds(1))
    timer.setEventHandler { [weak self] in self?.appendHeartbeatFrame(force: false) }
    timer.resume()
    heartbeatTimer = timer
  }

  func appendHeartbeatFrame(force: Bool) {
    guard
      sessionStarted,
      let sample = lastVideoSample,
      let writerInput, writerInput.isReadyForMoreMediaData
    else { return }
    let now = CMClockGetTime(CMClockGetHostTimeClock())
    let gap = CMTimeGetSeconds(CMTimeSubtract(now, lastVideoTime))
    guard force || gap > 1.05 else { return }

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: now,
      decodeTimeStamp: .invalid
    )
    var copy: CMSampleBuffer?
    CMSampleBufferCreateCopyWithNewTiming(
      allocator: kCFAllocatorDefault,
      sampleBuffer: sample,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timing,
      sampleBufferOut: &copy
    )
    if let copy {
      writerInput.append(copy)
      lastVideoTime = now
    }
  }

  func startVideoCapture(_ stream: SCStream) throws {
    var startError: Error?
    let semaphore = DispatchSemaphore(value: 0)
    stream.startCapture { error in
      startError = error
      semaphore.signal()
    }
    semaphore.wait()
    if let startError {
      throw RecorderError.setupFailed(startError.localizedDescription)
    }
  }

  func startAudioCapture() throws {
    var startError: Error?
    let semaphore = DispatchSemaphore(value: 0)
    audioStream?.startCapture { error in
      startError = error
      semaphore.signal()
    }
    semaphore.wait()
    // A silently-failed audio stream produces a take with a dead audio
    // track that nobody notices until review. Fail loudly instead.
    if let startError {
      throw RecorderError.setupFailed(
        "Audio capture failed to start: \(startError.localizedDescription) "
          + "Recording aborted so you don't get a silent take."
      )
    }
  }

  /// The crop rect is fixed at capture start, so re-derive it whenever the
  /// Simulator window moves or resizes mid-recording.
  func startWindowFollower() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(500))
    timer.setEventHandler { [weak self] in self?.refreshSourceRect() }
    timer.resume()
    followTimer = timer
  }

  func refreshSourceRect() {
    guard
      !stopping, let native, let config,
      let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], simWindowID) as? [[String: Any]],
      let bounds = info.first?[kCGWindowBounds as String] as? [String: CGFloat]
    else { return }

    let frame = CGRect(
      x: bounds["X"] ?? 0,
      y: bounds["Y"] ?? 0,
      width: bounds["Width"] ?? 0,
      height: bounds["Height"] ?? 0
    )
    guard
      frame.width > 0, !frame.equalTo(lastWindowFrame),
      let screenRect = SimulatorCapture.deviceScreenRect(windowFrame: frame, native: native)
    else { return }

    lastWindowFrame = frame
    config.sourceRect = CGRect(
      x: screenRect.minX - displayFrame.minX,
      y: screenRect.minY - displayFrame.minY,
      width: screenRect.width,
      height: screenRect.height
    )
    stream?.updateConfiguration(config) { _ in }
  }

  // MARK: - Writer

  func setupWriter(native: NativeGeometry) throws {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    let url = desktop.appendingPathComponent("Simulator Recording \(formatter.string(from: Date())).mov")

    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    } catch {
      throw RecorderError.setupFailed(error.localizedDescription)
    }

    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.hevc,
      AVVideoWidthKey: native.width,
      AVVideoHeightKey: native.height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 40_000_000,
        AVVideoExpectedSourceFrameRateKey: 60,
        // Keyframe every second and no frame reordering: raw takes are VFR,
        // and sparse keyframes make QuickTime scrubbing snap video seconds
        // behind the (exact) audio — which reads as broken A/V sync when
        // reviewing a take even though the file is correct.
        AVVideoMaxKeyFrameIntervalKey: 60,
        AVVideoAllowFrameReorderingKey: false,
      ],
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = true
    guard writer.canAdd(input) else {
      throw RecorderError.setupFailed("The writer rejected the video settings.")
    }
    writer.add(input)

    let audioSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 48000,
      AVNumberOfChannelsKey: 2,
      AVEncoderBitRateKey: 192_000,
    ]
    let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
    audio.expectsMediaDataInRealTime = true
    guard writer.canAdd(audio) else {
      throw RecorderError.setupFailed("The writer rejected the audio settings.")
    }
    writer.add(audio)
    audioInput = audio
    guard writer.startWriting() else {
      throw RecorderError.setupFailed(writer.error?.localizedDescription ?? "Could not start writing.")
    }

    self.writer = writer
    writerInput = input
    outputURL = url
  }
}
