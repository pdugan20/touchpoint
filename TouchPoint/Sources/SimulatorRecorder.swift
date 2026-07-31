import AVFoundation
import Cocoa
import ScreenCaptureKit

/// Records the booted iOS Simulator at native device resolution with the live
/// TouchPoint overlay, via ScreenCaptureKit. The capture filter includes only
/// the Simulator window and this app's overlay panel, cropped to the device
/// screen — whatever is on screen, including press animations, is what lands
/// in the file. A standalone CLI variant lives at tools/simrec.swift.
final class SimulatorRecorder: NSObject {
  private(set) var isRecording = false

  private var stream: SCStream?
  private var audioStream: SCStream?
  private var writer: AVAssetWriter?
  private var writerInput: AVAssetWriterInput?
  private var audioInput: AVAssetWriterInput?
  private var sessionStarted = false
  private var stopping = false
  private var outputURL: URL?
  private var native: NativeGeometry?
  private var displayFrame: CGRect = .zero
  private var simWindowID: CGWindowID = 0
  private var lastWindowFrame: CGRect = .zero
  private var config: SCStreamConfiguration?
  private var followTimer: DispatchSourceTimer?
  private let queue = DispatchQueue(label: "com.patrickdugan.touchpoint.recorder")

  // MARK: - Start

  func start(completion: @escaping (Error?) -> Void) {
    guard !isRecording else {
      completion(RecorderError.alreadyRecording)
      return
    }

    queue.async { [weak self] in
      guard let self else { return }
      do {
        try startOnQueue()
        DispatchQueue.main.async { completion(nil) }
      } catch {
        DispatchQueue.main.async { completion(error) }
      }
    }
  }

  private func startOnQueue() throws {
    let native = try SimulatorCapture.readNativeGeometry()
    let content = try SimulatorCapture.fetchShareableContent()

    guard
      let simWindow = content.windows
        .filter({
          $0.owningApplication?.bundleIdentifier == "com.apple.iphonesimulator"
            && $0.windowLayer == 0 && $0.isOnScreen
        })
        .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    else {
      throw RecorderError.noSimulatorWindow
    }

    let overlayWindows = content.windows.filter {
      $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
    }

    guard let screenRect = SimulatorCapture.deviceScreenRect(windowFrame: simWindow.frame, native: native) else {
      throw RecorderError.windowDoesNotLookLikeBareScreen
    }

    let windowCenter = CGPoint(x: simWindow.frame.midX, y: simWindow.frame.midY)
    guard let display = content.displays.first(where: { $0.frame.contains(windowCenter) }) else {
      throw RecorderError.noSimulatorWindow
    }

    self.native = native
    displayFrame = display.frame
    simWindowID = simWindow.windowID
    lastWindowFrame = simWindow.frame

    let filter = SCContentFilter(display: display, including: [simWindow] + overlayWindows)

    let config = SCStreamConfiguration()
    config.width = native.width
    config.height = native.height
    config.sourceRect = CGRect(
      x: screenRect.minX - display.frame.minX,
      y: screenRect.minY - display.frame.minY,
      width: screenRect.width,
      height: screenRect.height
    )
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.colorSpaceName = CGColorSpace.sRGB
    config.showsCursor = false
    config.queueDepth = 8
    config.captureResolution = .best
    self.config = config

    try setupWriter(native: native)

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    self.stream = stream

    try attachAudioStream(display: display)

    try startVideoCapture(stream)
    startAudioCapture()

    isRecording = true
    stopping = false
    startWindowFollower()
  }

  // MARK: - Stop

  func stop(completion: @escaping (Result<URL, Error>) -> Void) {
    queue.async { [weak self] in
      guard let self, isRecording, !stopping else { return }
      stopping = true
      followTimer?.cancel()
      followTimer = nil

      let semaphore = DispatchSemaphore(value: 0)
      stream?.stopCapture { _ in semaphore.signal() }
      semaphore.wait()
      stream = nil
      let audioSemaphore = DispatchSemaphore(value: 0)
      audioStream?.stopCapture { _ in audioSemaphore.signal() }
      audioSemaphore.wait()
      audioStream = nil

      guard let writer, let writerInput, let outputURL, sessionStarted else {
        cleanUp()
        DispatchQueue.main.async {
          completion(.failure(RecorderError.setupFailed("No frames were captured.")))
        }
        return
      }

      writerInput.markAsFinished()
      audioInput?.markAsFinished()
      let finishSemaphore = DispatchSemaphore(value: 0)
      writer.finishWriting { finishSemaphore.signal() }
      finishSemaphore.wait()

      let result: Result<URL, Error> = writer.status == .completed
        ? .success(outputURL)
        : .failure(RecorderError.setupFailed(writer.error?.localizedDescription ?? "Finalizing failed."))
      cleanUp()
      DispatchQueue.main.async { completion(result) }
    }
  }

  private func cleanUp() {
    isRecording = false
    sessionStarted = false
    writer = nil
    writerInput = nil
    audioInput = nil
    stream = nil
    audioStream = nil
    config = nil
  }

  /// Re-resolve the capture filter after the overlay panel is recreated
  /// (size changes rebuild the window, giving it a new window ID).
  func refreshContentFilter() {
    queue.async { [weak self] in
      guard let self, isRecording, !stopping, let stream, let config else { return }
      guard let content = try? SimulatorCapture.fetchShareableContent() else { return }

      let simWindows = content.windows.filter { $0.windowID == self.simWindowID }
      let overlayWindows = content.windows.filter {
        $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
      }
      guard
        let simWindow = simWindows.first,
        let display = content.displays.first(where: { $0.frame == self.displayFrame })
      else { return }

      let filter = SCContentFilter(display: display, including: [simWindow] + overlayWindows)
      stream.updateContentFilter(filter) { _ in }
      stream.updateConfiguration(config) { _ in }
    }
  }
}

// MARK: - Audio & window following

extension SimulatorRecorder {
  /// Simulator audio is not attributed to the Simulator's windows, so a
  /// window-filtered stream records silence. Capture audio on a second,
  /// display-wide stream (no video output attached) instead.
  private func attachAudioStream(display: SCDisplay) throws {
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

  private func startVideoCapture(_ stream: SCStream) throws {
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

  private func startAudioCapture() {
    let semaphore = DispatchSemaphore(value: 0)
    audioStream?.startCapture { error in
      if let error {
        NSLog("SimulatorRecorder audio capture unavailable: \(error.localizedDescription)")
      }
      semaphore.signal()
    }
    semaphore.wait()
  }

  /// The crop rect is fixed at capture start, so re-derive it whenever the
  /// Simulator window moves or resizes mid-recording.
  private func startWindowFollower() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(500))
    timer.setEventHandler { [weak self] in self?.refreshSourceRect() }
    timer.resume()
    followTimer = timer
  }

  private func refreshSourceRect() {
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

  private func setupWriter(native: NativeGeometry) throws {
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

// MARK: - SCStreamOutput

extension SimulatorRecorder: SCStreamOutput {
  func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard sampleBuffer.isValid, !stopping else { return }

    // Audio rides along once the session is anchored to the first video frame.
    if type == .audio {
      guard sessionStarted, let audioInput, audioInput.isReadyForMoreMediaData else { return }
      audioInput.append(sampleBuffer)
      return
    }

    guard type == .screen else { return }
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
      as? [[SCStreamFrameInfo: Any]],
      let statusRaw = attachments.first?[.status] as? Int,
      let status = SCFrameStatus(rawValue: statusRaw),
      status == .complete,
      let writer, let writerInput
    else {
      return
    }

    if !sessionStarted {
      writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
      sessionStarted = true
    }

    if writerInput.isReadyForMoreMediaData {
      writerInput.append(sampleBuffer)
    }
  }
}

// MARK: - SCStreamDelegate

extension SimulatorRecorder: SCStreamDelegate {
  func stream(_: SCStream, didStopWithError error: Error) {
    NSLog("SimulatorRecorder stream stopped: \(error.localizedDescription)")
  }
}
