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

  var stream: SCStream?
  var audioStream: SCStream?
  var writer: AVAssetWriter?
  var writerInput: AVAssetWriterInput?
  var audioInput: AVAssetWriterInput?
  var sessionStarted = false
  var stopping = false
  var outputURL: URL?
  var native: NativeGeometry?
  var displayFrame: CGRect = .zero
  var simWindowID: CGWindowID = 0
  var lastWindowFrame: CGRect = .zero
  var config: SCStreamConfiguration?
  var followTimer: DispatchSourceTimer?
  var heartbeatTimer: DispatchSourceTimer?
  var lastVideoSample: CMSampleBuffer?
  var lastVideoTime = CMTime.invalid
  let queue = DispatchQueue(label: "com.patrickdugan.touchpoint.recorder")

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
    try startAudioCapture()

    isRecording = true
    stopping = false
    startWindowFollower()
    startHeartbeat()
  }

  // MARK: - Stop

  func stop(completion: @escaping (Result<URL, Error>) -> Void) {
    queue.async { [weak self] in
      guard let self, isRecording, !stopping else { return }
      stopping = true
      followTimer?.cancel()
      followTimer = nil
      heartbeatTimer?.cancel()
      heartbeatTimer = nil
      // Close the video track at the stop moment so it spans the full take —
      // otherwise a still ending leaves the video shorter than the audio and
      // players render the gap as black.
      appendHeartbeatFrame(force: true)

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
    lastVideoSample = nil
    lastVideoTime = .invalid
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
      lastVideoSample = sampleBuffer
      lastVideoTime = sampleBuffer.presentationTimeStamp
    }
  }
}

// MARK: - SCStreamDelegate

extension SimulatorRecorder: SCStreamDelegate {
  func stream(_: SCStream, didStopWithError error: Error) {
    NSLog("SimulatorRecorder stream stopped: \(error.localizedDescription)")
  }
}
