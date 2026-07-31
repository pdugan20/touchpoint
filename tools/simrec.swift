#!/usr/bin/env swift

// simrec — record the booted iOS Simulator at native device resolution with the
// live TouchPoint cursor overlay, using ScreenCaptureKit.
//
// The capture filter includes exactly two windows: the Simulator and the
// TouchPoint overlay panel. Whatever you see on screen — including TouchPoint's
// press animations — is what lands in the file. No cursor sampling, no
// post-compositing.
//
// For a 1:1 native-pixel capture, put the Simulator in Pixel Accurate mode
// (Window → Pixel Accurate, Cmd+3) and turn off device bezels. simrec warns
// when the on-screen window is smaller than native.
//
// Usage: simrec [--force] [--prores] [--fps N] OUTPUT.mov
// Stop with Ctrl-C.

import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

// MARK: - Errors

enum SimrecError: LocalizedError {
  case badArguments
  case outputExists(String)
  case noBootedDisplay
  case shareableContentFailed(String)
  case noSimulatorWindow
  case windowDoesNotLookLikeBareScreen(CGRect)
  case noDisplayForWindow
  case writerFailed(String)
  case captureFailed(String)

  var errorDescription: String? {
    switch self {
    case .badArguments:
      return "Usage: simrec [--force] [--prores] [--fps N] OUTPUT.mov"
    case .outputExists(let path):
      return "Output already exists: \(path). Pass --force to replace it."
    case .noBootedDisplay:
      return "Could not read the booted Simulator's display geometry. Is a simulator booted?"
    case .shareableContentFailed(let message):
      return """
      Could not enumerate windows: \(message)
      If this is a permissions error, grant Screen Recording to your terminal in
      System Settings → Privacy & Security → Screen & System Audio Recording.
      """
    case .noSimulatorWindow:
      return "Could not find an on-screen Simulator window."
    case .windowDoesNotLookLikeBareScreen(let bounds):
      return """
      The Simulator window (\(Int(bounds.width))x\(Int(bounds.height))) does not look like a
      bezel-free device screen. Turn off Simulator → Window → Show Device Bezels and try again.
      """
    case .noDisplayForWindow:
      return "Could not match the Simulator window to a display."
    case .writerFailed(let message):
      return "Could not write the movie: \(message)"
    case .captureFailed(let message):
      return "Capture failed: \(message)"
    }
  }
}

// MARK: - Native device geometry

struct NativeGeometry {
  let width: Int
  let height: Int
  let scale: Double
}

func readNativeGeometry() throws -> NativeGeometry {
  let enumerate = Process()
  let output = Pipe()
  enumerate.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  enumerate.arguments = ["simctl", "io", "booted", "enumerate"]
  enumerate.standardOutput = output
  enumerate.standardError = FileHandle.nullDevice
  try enumerate.run()
  enumerate.waitUntilExit()

  let data = output.fileHandleForReading.readDataToEndOfFile()
  let description = String(decoding: data, as: UTF8.self)
  let pattern = #"(?s)Name:\s+LCD.*?Pixel Size:\s+\{(\d+),\s*(\d+)\}.*?Preferred UI Scale:\s+([0-9.]+)"#
  let regex = try NSRegularExpression(pattern: pattern)
  let range = NSRange(description.startIndex..., in: description)

  guard
    let match = regex.firstMatch(in: description, range: range),
    let widthRange = Range(match.range(at: 1), in: description),
    let heightRange = Range(match.range(at: 2), in: description),
    let scaleRange = Range(match.range(at: 3), in: description),
    let width = Int(description[widthRange]),
    let height = Int(description[heightRange]),
    let scale = Double(description[scaleRange])
  else {
    throw SimrecError.noBootedDisplay
  }

  return NativeGeometry(width: width, height: height, scale: scale)
}

// MARK: - Shareable content lookup

func fetchShareableContent() throws -> SCShareableContent {
  var result: Result<SCShareableContent, Error>?
  let semaphore = DispatchSemaphore(value: 0)
  SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
    if let content {
      result = .success(content)
    } else {
      result = .failure(error ?? SimrecError.shareableContentFailed("unknown error"))
    }
    semaphore.signal()
  }
  semaphore.wait()

  switch result! {
  case .success(let content):
    return content
  case .failure(let error):
    throw SimrecError.shareableContentFailed(error.localizedDescription)
  }
}

/// The device screen sub-rect of the Simulator window, in top-left-origin
/// screen points. The window is title-bar chrome on top plus the screen.
func deviceScreenRect(windowFrame: CGRect, native: NativeGeometry) throws -> CGRect {
  let expectedScreenHeight = windowFrame.width * CGFloat(native.height) / CGFloat(native.width)
  let chromeHeight = windowFrame.height - expectedScreenHeight
  guard expectedScreenHeight <= windowFrame.height + 2, chromeHeight >= 20, chromeHeight <= 100 else {
    throw SimrecError.windowDoesNotLookLikeBareScreen(windowFrame)
  }

  return CGRect(
    x: windowFrame.minX,
    y: windowFrame.maxY - expectedScreenHeight,
    width: windowFrame.width,
    height: expectedScreenHeight
  )
}

// MARK: - Recorder

final class Recorder: NSObject, SCStreamDelegate, SCStreamOutput {
  private let outputURL: URL
  private let useProRes: Bool
  private let fps: Int

  private var stream: SCStream?
  private var audioStream: SCStream?
  private var writer: AVAssetWriter?
  private var writerInput: AVAssetWriterInput?
  private var audioInput: AVAssetWriterInput?
  private var sessionStarted = false
  private var frameCount = 0
  private var droppedCount = 0
  private var stopping = false
  private let writeQueue = DispatchQueue(label: "simrec.write")
  private var signalSources: [DispatchSourceSignal] = []

  private var config: SCStreamConfiguration!
  private var native: NativeGeometry!
  private var displayFrame: CGRect = .zero
  private var simWindowID: CGWindowID = 0
  private var lastWindowFrame: CGRect = .zero
  private var followTimer: DispatchSourceTimer?

  init(outputURL: URL, useProRes: Bool, fps: Int) {
    self.outputURL = outputURL
    self.useProRes = useProRes
    self.fps = fps
  }

  func run() throws {
    let native = try readNativeGeometry()
    let content = try fetchShareableContent()

    let simWindows = content.windows.filter {
      $0.owningApplication?.bundleIdentifier == "com.apple.iphonesimulator"
        && $0.windowLayer == 0 && $0.isOnScreen
    }
    guard let simWindow = simWindows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    else {
      throw SimrecError.noSimulatorWindow
    }

    let touchPointWindows = content.windows.filter {
      guard let app = $0.owningApplication else { return false }
      return app.applicationName == "TouchPoint" || app.bundleIdentifier.contains("touchpoint")
    }
    if touchPointWindows.isEmpty {
      FileHandle.standardError.write(Data("""
      warning: no TouchPoint overlay window found — the touch cursor will not appear.
      Toggle it on with Cmd+Shift+T before recording.\n
      """.utf8))
    }

    let screenRect = try deviceScreenRect(windowFrame: simWindow.frame, native: native)

    let windowCenter = CGPoint(x: simWindow.frame.midX, y: simWindow.frame.midY)
    guard let display = content.displays.first(where: { $0.frame.contains(windowCenter) }) else {
      throw SimrecError.noDisplayForWindow
    }

    let backingScale = NSScreen.screens
      .first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID }?
      .backingScaleFactor ?? 2

    let onScreenPixels = screenRect.height * backingScale
    let coverage = onScreenPixels / CGFloat(native.height)
    if coverage < 0.98 {
      FileHandle.standardError.write(Data("""
      warning: the Simulator window covers \(Int(coverage * 100))% of native resolution on screen.
      The capture will be upscaled and soft. Use Simulator → Window → Pixel Accurate (Cmd+3)
      for a 1:1 native capture.\n
      """.utf8))
    }

    self.native = native
    displayFrame = display.frame
    simWindowID = simWindow.windowID
    lastWindowFrame = simWindow.frame

    let filter = SCContentFilter(display: display, including: [simWindow] + touchPointWindows)

    let config = SCStreamConfiguration()
    config.width = native.width
    config.height = native.height
    config.sourceRect = CGRect(
      x: screenRect.minX - display.frame.minX,
      y: screenRect.minY - display.frame.minY,
      width: screenRect.width,
      height: screenRect.height
    )
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))

    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.colorSpaceName = CGColorSpace.sRGB
    config.showsCursor = false
    config.queueDepth = 8
    config.captureResolution = .best
    self.config = config

    try setupWriter(width: native.width, height: native.height)

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writeQueue)

    self.stream = stream

    // Simulator audio is not attributed to the Simulator's windows, so a
    // window-filtered stream records silence. Capture audio on a second,
    // display-wide stream (no video output attached) instead.
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
    try audioStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writeQueue)
    self.audioStream = audioStream

    var startResult: Result<Void, Error>?
    let semaphore = DispatchSemaphore(value: 0)
    stream.startCapture { error in
      startResult = error.map { .failure($0) } ?? .success(())
      semaphore.signal()
    }
    semaphore.wait()
    if case .failure(let error) = startResult! {
      throw SimrecError.captureFailed(error.localizedDescription)
    }

    let audioSemaphore = DispatchSemaphore(value: 0)
    audioStream.startCapture { error in
      if let error {
        FileHandle.standardError.write(Data("warning: audio capture unavailable: \(error.localizedDescription)\n".utf8))
      }
      audioSemaphore.signal()
    }
    audioSemaphore.wait()

    installSignalHandlers()
    startWindowFollower()
    print("Recording \(native.width)x\(native.height) at up to \(fps) fps (\(useProRes ? "ProRes 4444" : "HEVC")).")
    print("Interact with the Simulator normally. Press Ctrl-C here to stop.")
    RunLoop.main.run()
  }

  /// The crop rect is fixed at capture start, so re-derive it whenever the
  /// Simulator window moves or resizes mid-recording.
  private func startWindowFollower() {
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "simrec.follow", qos: .utility))
    timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(500))
    timer.setEventHandler { [weak self] in self?.refreshSourceRect() }
    timer.resume()
    followTimer = timer
  }

  private func refreshSourceRect() {
    guard
      !stopping,
      let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], simWindowID) as? [[String: Any]],
      let bounds = info.first?[kCGWindowBounds as String] as? [String: CGFloat]
    else { return }

    let frame = CGRect(
      x: bounds["X"] ?? 0,
      y: bounds["Y"] ?? 0,
      width: bounds["Width"] ?? 0,
      height: bounds["Height"] ?? 0
    )
    guard frame.width > 0, !frame.equalTo(lastWindowFrame) else { return }
    guard let screenRect = try? deviceScreenRect(windowFrame: frame, native: native) else { return }

    lastWindowFrame = frame
    config.sourceRect = CGRect(
      x: screenRect.minX - displayFrame.minX,
      y: screenRect.minY - displayFrame.minY,
      width: screenRect.width,
      height: screenRect.height
    )
    stream?.updateConfiguration(config) { error in
      if let error {
        FileHandle.standardError.write(Data("warning: crop update failed: \(error.localizedDescription)\n".utf8))
      }
    }
    print("(window moved — crop retargeted, now \(Int(screenRect.width))x\(Int(screenRect.height)) pt on screen)")
  }

  private func setupWriter(width: Int, height: Int) throws {
    try? FileManager.default.removeItem(at: outputURL)
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    } catch {
      throw SimrecError.writerFailed(error.localizedDescription)
    }

    var settings: [String: Any] = [
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
    ]
    if useProRes {
      settings[AVVideoCodecKey] = AVVideoCodecType.proRes4444
    } else {
      settings[AVVideoCodecKey] = AVVideoCodecType.hevc
      settings[AVVideoCompressionPropertiesKey] = [
        AVVideoAverageBitRateKey: 40_000_000,
        AVVideoExpectedSourceFrameRateKey: fps,
      ]
    }

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = true
    guard writer.canAdd(input) else {
      throw SimrecError.writerFailed("writer rejected video input settings")
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
      throw SimrecError.writerFailed("writer rejected audio input settings")
    }
    writer.add(audio)
    audioInput = audio
    guard writer.startWriting() else {
      throw SimrecError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
    }

    self.writer = writer
    writerInput = input
  }

  // MARK: SCStreamOutput

  func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard sampleBuffer.isValid else { return }

    // Audio rides along once the session is anchored to the first video frame.
    if type == .audio {
      guard sessionStarted, !stopping, let audioInput, audioInput.isReadyForMoreMediaData else { return }
      audioInput.append(sampleBuffer)
      return
    }

    guard type == .screen else { return }
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
      as? [[SCStreamFrameInfo: Any]],
      let statusRaw = attachments.first?[.status] as? Int,
      let status = SCFrameStatus(rawValue: statusRaw),
      status == .complete
    else {
      return
    }

    guard let writer, let writerInput, !stopping else { return }

    if !sessionStarted {
      writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
      sessionStarted = true
    }

    if writerInput.isReadyForMoreMediaData {
      writerInput.append(sampleBuffer)
      frameCount += 1
    } else {
      droppedCount += 1
    }
  }

  // MARK: SCStreamDelegate

  func stream(_: SCStream, didStopWithError error: Error) {
    writeQueue.async { [weak self] in
      FileHandle.standardError.write(Data("stream stopped: \(error.localizedDescription)\n".utf8))
      self?.finish(exitCode: 1)
    }
  }

  // MARK: Stop

  private func installSignalHandlers() {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    for signalNumber in [SIGINT, SIGTERM] {
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: writeQueue)
      source.setEventHandler { [weak self] in self?.stopAndFinish() }
      source.resume()
      signalSources.append(source)
    }
  }

  private func stopAndFinish() {
    guard !stopping else { return }
    stopping = true
    followTimer?.cancel()
    followTimer = nil
    print("\nStopping…")

    let semaphore = DispatchSemaphore(value: 0)
    stream?.stopCapture { _ in semaphore.signal() }
    semaphore.wait()
    let audioSemaphore = DispatchSemaphore(value: 0)
    audioStream?.stopCapture { _ in audioSemaphore.signal() }
    audioSemaphore.wait()
    finish(exitCode: 0)
  }

  private func finish(exitCode: Int32) {
    guard let writer, let writerInput, sessionStarted else {
      FileHandle.standardError.write(Data("No frames were captured.\n".utf8))
      exit(1)
    }

    writerInput.markAsFinished()
    audioInput?.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting { semaphore.signal() }
    semaphore.wait()

    if writer.status == .completed {
      print("Wrote \(frameCount) frames (\(droppedCount) dropped) to: \(outputURL.path)")
      exit(exitCode)
    } else {
      FileHandle.standardError.write(
        Data("Finalizing failed: \(writer.error?.localizedDescription ?? "unknown")\n".utf8)
      )
      exit(1)
    }
  }
}

// MARK: - Entry

func parseArguments() throws -> (URL, Bool, Bool, Int) {
  var arguments = Array(CommandLine.arguments.dropFirst())
  let force = arguments.contains("--force")
  let prores = arguments.contains("--prores")
  arguments.removeAll { $0 == "--force" || $0 == "--prores" }

  var fps = 60
  if let index = arguments.firstIndex(of: "--fps") {
    guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0, value <= 120 else {
      throw SimrecError.badArguments
    }
    fps = value
    arguments.removeSubrange(index...(index + 1))
  }

  guard arguments.count == 1 else { throw SimrecError.badArguments }
  let path = NSString(string: arguments[0]).expandingTildeInPath
  return (URL(fileURLWithPath: path).standardizedFileURL, force, prores, fps)
}

do {
  let (outputURL, force, prores, fps) = try parseArguments()
  if !force, FileManager.default.fileExists(atPath: outputURL.path) {
    throw SimrecError.outputExists(outputURL.path)
  }
  try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  let recorder = Recorder(outputURL: outputURL, useProRes: prores, fps: fps)
  try recorder.run()
} catch {
  FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
  exit(1)
}
