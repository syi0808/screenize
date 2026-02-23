import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// CFR (Constant Frame Rate) recording manager
/// Converts ScreenCaptureKit's VFR output to a fixed 60fps CFR recording
final class CFRRecordingManager: @unchecked Sendable {

    // MARK: - Properties

    /// Target frame rate (fixed at 60fps)
    private let targetFPS: Double = 60.0

    /// Base timestamp for audio rebasing (first audio sample's PTS)
    /// ScreenCaptureKit audio timestamps use the system media clock (since boot),
    /// while video uses synthetic timestamps starting from 0. We rebase audio to match.
    private var audioBaseTime: CMTime?

    /// Duration between frames (seconds)
    private var frameInterval: TimeInterval { 1.0 / targetFPS }

    /// Video writer
    private var videoWriter: VideoWriter?

    /// System audio sidecar writer
    private var systemAudioWriter: SystemAudioWriter?

    /// Recording status
    private var isRecording = false

    /// Last valid frame buffer
    private var lastValidPixelBuffer: CVPixelBuffer?

    /// Lock for the last frame
    private let frameLock = NSLock()

    /// Timer for writing frames
    private var frameTimer: DispatchSourceTimer?

    /// Queue for frame writing
    private let writerQueue = DispatchQueue(label: "com.screenize.cfr-writer", qos: .userInteractive)

    /// Current frame index
    private var frameIndex: Int64 = 0

    /// Recording start time
    private var recordingStartTime: Date?

    /// Output URL
    private var outputURL: URL?

    /// Capture configuration
    private var configuration: CaptureConfiguration?

    /// Pause state
    private var isPaused = false

    /// System audio output URL
    private var systemAudioURL: URL?

    /// Recording completion callback
    var onRecordingFinished: ((URL?) -> Void)?

    // MARK: - Initialization

    init() {}

    // MARK: - Recording Control

    /// Start CFR recording
    /// - Parameters:
    ///   - outputURL: Output file URL
    ///   - configuration: Capture configuration
    func startRecording(to outputURL: URL, configuration: CaptureConfiguration) throws {
        guard !isRecording else {
            throw CFRRecordingError.alreadyRecording
        }

        self.outputURL = outputURL
        self.configuration = configuration

        // Configure the VideoWriter (video only — system audio goes to sidecar)
        let writerConfig = VideoWriterConfiguration(
            width: configuration.width,
            height: configuration.height,
            frameRate: Int(targetFPS),
            videoBitRate: 20_000_000,  // 20Mbps for high quality
            keyFrameInterval: Int(targetFPS),  // Keyframe every second
            videoCodec: .hevc,
            fileType: .mov,
            includeAudio: false
        )

        videoWriter = try VideoWriter(outputURL: outputURL, configuration: writerConfig)
        try videoWriter?.startWriting()

        // Start system audio sidecar writer
        let sysAudioURL = Self.generateSystemAudioURL(for: outputURL)
        systemAudioWriter = SystemAudioWriter()
        try systemAudioWriter?.startWriting(to: sysAudioURL)
        self.systemAudioURL = sysAudioURL

        isRecording = true
        isPaused = false
        frameIndex = 0
        recordingStartTime = Date()
        lastValidPixelBuffer = nil
        audioBaseTime = nil

        // Start the frame writing timer
        startFrameTimer()

        print("🎬 [CFRRecordingManager] CFR recording started: \(Int(targetFPS))fps, \(configuration.width)x\(configuration.height)")
    }

    /// Stop recording
    func stopRecording() async -> CFRRecordingResult {
        guard isRecording else { return CFRRecordingResult(videoURL: nil, systemAudioURL: nil) }

        isRecording = false

        // Stop the timer
        stopFrameTimer()

        // Stop system audio writer
        let sysAudioURL = await systemAudioWriter?.stopWriting()
        self.systemAudioWriter = nil

        // Finish the video writer
        do {
            let url = try await videoWriter?.finishWriting()

            let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            print("🎬 [CFRRecordingManager] CFR recording ended: \(frameIndex) frames, \(String(format: "%.2f", duration))s")

            // Cleanup
            frameLock.lock()
            lastValidPixelBuffer = nil
            frameLock.unlock()

            videoWriter = nil
            outputURL = nil
            configuration = nil
            recordingStartTime = nil
            audioBaseTime = nil
            systemAudioURL = nil

            onRecordingFinished?(url)
            return CFRRecordingResult(videoURL: url, systemAudioURL: sysAudioURL)
        } catch {
            print("❌ [CFRRecordingManager] Failed to stop recording: \(error)")
            videoWriter?.cancelWriting()

            frameLock.lock()
            lastValidPixelBuffer = nil
            frameLock.unlock()

            videoWriter = nil
            systemAudioURL = nil

            onRecordingFinished?(nil)
            return CFRRecordingResult(videoURL: nil, systemAudioURL: sysAudioURL)
        }
    }

    /// Pause recording
    func pause() {
        isPaused = true
    }

    /// Resume recording
    func resume() {
        isPaused = false
    }

    // MARK: - Audio Handling

    /// Receive a system audio sample buffer from ScreenCaptureKit.
    /// Rebases timestamps so audio aligns with synthetic video timestamps.
    func receiveAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, !isPaused else { return }

        let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Capture the first audio PTS as our base for rebasing
        if audioBaseTime == nil {
            audioBaseTime = originalPTS
        }

        guard let base = audioBaseTime else { return }

        // Rebase: subtract the base time so audio starts near 0
        let rebasedPTS = originalPTS - base

        // Skip negative timestamps (can happen if samples arrive out of order)
        guard rebasedPTS.seconds >= 0 else { return }

        // Create a copy with the rebased timestamp
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: rebasedPTS,
            decodeTimeStamp: .invalid
        )

        var rebasedBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &rebasedBuffer
        )

        guard status == noErr, let buffer = rebasedBuffer else { return }

        systemAudioWriter?.appendSampleBuffer(buffer)
    }

    // MARK: - Frame Handling

    /// Counter for debug logging (first frame only)
    private var debugFrameCount: Int = 0

    /// Receive a new frame (invoked by SCStreamOutput)
    /// - Parameter sampleBuffer: Video sample buffer
    func receiveFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, !isPaused else { return }

        // Extract the pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // DEBUG: Log first frame info
        if debugFrameCount == 0 {
            let bufW = CVPixelBufferGetWidth(pixelBuffer)
            let bufH = CVPixelBufferGetHeight(pixelBuffer)
            print("🔍 [DEBUG] First frame pixel buffer: \(bufW)x\(bufH)")

            // Extract SCStreamFrameInfo from sample buffer attachments
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [NSDictionary],
               let dict = attachmentsArray.first {
                if let contentRectDict = dict[SCStreamFrameInfo.contentRect] as? NSDictionary,
                   let contentRect = CGRect(dictionaryRepresentation: contentRectDict) {
                    print("🔍 [DEBUG] contentRect: \(contentRect)")
                }
                if let contentScale = dict[SCStreamFrameInfo.contentScale] as? CGFloat {
                    print("🔍 [DEBUG] contentScale: \(contentScale)")
                }
                if let scaleFactor = dict[SCStreamFrameInfo.scaleFactor] as? CGFloat {
                    print("🔍 [DEBUG] scaleFactor: \(scaleFactor)")
                }
            }
        }
        debugFrameCount += 1

        // Copy the pixel buffer (source buffer is reused)
        guard let copiedBuffer = copyPixelBuffer(pixelBuffer) else { return }

        // Update the last frame
        frameLock.lock()
        lastValidPixelBuffer = copiedBuffer
        frameLock.unlock()
    }

    // MARK: - Timer

    /// Start the frame writing timer
    private func startFrameTimer() {
        let timer = DispatchSource.makeTimerSource(queue: writerQueue)

        // 60fps = 16.67ms intervals
        let intervalNs = UInt64(frameInterval * 1_000_000_000)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(intervalNs)), leeway: .microseconds(100))

        timer.setEventHandler { [weak self] in
            self?.writeNextFrame()
        }

        timer.resume()
        frameTimer = timer
    }

    /// Stop the frame writing timer
    private func stopFrameTimer() {
        frameTimer?.cancel()
        frameTimer = nil
    }

    /// Write the next frame
    private func writeNextFrame() {
        guard isRecording, !isPaused else { return }

        frameLock.lock()
        let pixelBuffer = lastValidPixelBuffer
        frameLock.unlock()

        guard let buffer = pixelBuffer else {
        // Skip if the first frame hasn't arrived yet
            return
        }

        // Calculate presentation time (fixed 60fps)
        let presentationTime = CMTime(value: frameIndex, timescale: CMTimeScale(targetFPS))

        // Append the frame to the writer
        videoWriter?.appendVideoPixelBuffer(buffer, presentationTime: presentationTime)

        frameIndex += 1
    }

    // MARK: - Utilities

    /// Copy a pixel buffer
    private func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let pixelFormat = CVPixelBufferGetPixelFormatType(source)

        var copy: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attrs as CFDictionary,
            &copy
        )

        guard status == kCVReturnSuccess, let destination = copy else {
            return nil
        }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(destination, [])
        }

        // Copy based on plane count
        let planeCount = CVPixelBufferGetPlaneCount(source)
        if planeCount == 0 {
            // Non-planar format
            if let srcBase = CVPixelBufferGetBaseAddress(source),
               let dstBase = CVPixelBufferGetBaseAddress(destination) {
                let srcBytesPerRow = CVPixelBufferGetBytesPerRow(source)
                let dstBytesPerRow = CVPixelBufferGetBytesPerRow(destination)
                let height = CVPixelBufferGetHeight(source)

                for row in 0..<height {
                    let srcRow = srcBase.advanced(by: row * srcBytesPerRow)
                    let dstRow = dstBase.advanced(by: row * dstBytesPerRow)
                    memcpy(dstRow, srcRow, min(srcBytesPerRow, dstBytesPerRow))
                }
            }
        } else {
            // Planar format
            for plane in 0..<planeCount {
                if let srcBase = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                   let dstBase = CVPixelBufferGetBaseAddressOfPlane(destination, plane) {
                    let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                    let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
                    let height = CVPixelBufferGetHeightOfPlane(source, plane)

                    for row in 0..<height {
                        let srcRow = srcBase.advanced(by: row * srcBytesPerRow)
                        let dstRow = dstBase.advanced(by: row * dstBytesPerRow)
                        memcpy(dstRow, srcRow, min(srcBytesPerRow, dstBytesPerRow))
                    }
                }
            }
        }

        return destination
    }

    // MARK: - Status

    /// Current recording duration
    var currentDuration: TimeInterval {
        guard isRecording, let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    /// Number of recorded frames
    var recordedFrameCount: Int64 {
        return frameIndex
    }

    // MARK: - Helpers

    /// Generate the system audio sidecar URL from the video output URL.
    private static func generateSystemAudioURL(for videoURL: URL) -> URL {
        let dir = videoURL.deletingLastPathComponent()
        let name = videoURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(name)_system.m4a")
    }
}

// MARK: - CFRRecordingResult

struct CFRRecordingResult {
    let videoURL: URL?
    let systemAudioURL: URL?
}

// MARK: - Errors

enum CFRRecordingError: LocalizedError {
    case alreadyRecording
    case notRecording
    case writerSetupFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Already recording"
        case .notRecording:
            return "Not currently recording"
        case .writerSetupFailed:
            return "Failed to configure the video writer"
        }
    }
}
