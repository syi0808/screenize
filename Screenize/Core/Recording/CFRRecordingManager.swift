import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

/// CFR (Constant Frame Rate) recording manager
/// Converts ScreenCaptureKit's VFR output to a fixed 60fps CFR recording
final class CFRRecordingManager: @unchecked Sendable {

    // MARK: - Properties

    /// Target frame rate (fixed at 60fps)
    private let targetFPS: Double = 60.0

    /// Duration between frames (seconds)
    private var frameInterval: TimeInterval { 1.0 / targetFPS }

    /// Video writer
    private var videoWriter: VideoWriter?

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

        // Configure the VideoWriter
        let writerConfig = VideoWriterConfiguration(
            width: configuration.width,
            height: configuration.height,
            frameRate: Int(targetFPS),
            videoBitRate: 20_000_000,  // 20Mbps for high quality
            keyFrameInterval: Int(targetFPS),  // Keyframe every second
            videoCodec: .hevc,
            fileType: .mov
        )

        videoWriter = try VideoWriter(outputURL: outputURL, configuration: writerConfig)
        try videoWriter?.startWriting()

        isRecording = true
        isPaused = false
        frameIndex = 0
        recordingStartTime = Date()
        lastValidPixelBuffer = nil

        // Start the frame writing timer
        startFrameTimer()

        print("🎬 [CFRRecordingManager] CFR recording started: \(Int(targetFPS))fps, \(configuration.width)x\(configuration.height)")
    }

    /// Stop recording
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        isRecording = false

        // Stop the timer
        stopFrameTimer()

        // Finish the writer
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

            onRecordingFinished?(url)
            return url
        } catch {
            print("❌ [CFRRecordingManager] Failed to stop recording: \(error)")
            videoWriter?.cancelWriting()

            frameLock.lock()
            lastValidPixelBuffer = nil
            frameLock.unlock()

            videoWriter = nil

            onRecordingFinished?(nil)
            return nil
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

            // Log sample buffer attachments
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[String: Any]] {
                print("🔍 [DEBUG] Frame attachments: \(attachments)")
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
