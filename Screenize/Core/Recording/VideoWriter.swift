import Foundation
import AVFoundation
import CoreMedia
import CoreImage

final class VideoWriter: @unchecked Sendable {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let outputURL: URL
    private let configuration: VideoWriterConfiguration

    private var isWriting = false
    private var sessionStartTime: CMTime?
    private var lastVideoTime: CMTime = .zero

    private let writerQueue = DispatchQueue(label: "com.screenize.videowriter", qos: .userInteractive)
    private let lock = NSLock()

    // Frame drop callback
    var onFrameDropped: (() -> Void)?

    init(outputURL: URL, configuration: VideoWriterConfiguration) throws {
        self.outputURL = outputURL
        self.configuration = configuration

        try setupAssetWriter()
    }

    private func setupAssetWriter() throws {
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: configuration.fileType)

        // Video input setup
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: configuration.videoBitRate,
            AVVideoMaxKeyFrameIntervalKey: configuration.keyFrameInterval,
            AVVideoExpectedSourceFrameRateKey: configuration.frameRate,
            AVVideoAllowFrameReorderingKey: false  // Reduce latency by disabling frame reordering
        ]

        // Add profile level if specified
        if let profileLevel = configuration.profileLevel {
            compressionProperties[AVVideoProfileLevelKey] = profileLevel
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: configuration.videoCodec,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        videoInput?.performsMultiPassEncodingIfSupported = false  // Real-time encoding

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: configuration.width,
            kCVPixelBufferHeightKey as String: configuration.height
        ]

        guard let videoInput = videoInput else {
            throw VideoWriterError.writerNotInitialized
        }

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if assetWriter?.canAdd(videoInput) == true {
            assetWriter?.add(videoInput)
        }

        // Audio input setup
        if configuration.includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: configuration.audioSampleRate,
                AVNumberOfChannelsKey: configuration.audioChannels,
                AVEncoderBitRateKey: configuration.audioBitRate
            ]

            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true

            if let audioInput = audioInput, assetWriter?.canAdd(audioInput) == true {
                assetWriter?.add(audioInput)
            }
        }
    }

    func startWriting() throws {
        guard let writer = assetWriter else {
            throw VideoWriterError.writerNotInitialized
        }

        guard writer.startWriting() else {
            throw VideoWriterError.failedToStart(writer.error)
        }

        isWriting = true
    }

    /// Add a video sample buffer synchronously, waiting for no frame loss
    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard isWriting, let videoInput = videoInput else {
            lock.unlock()
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Handle session start
        if sessionStartTime == nil {
            sessionStartTime = presentationTime
            assetWriter?.startSession(atSourceTime: presentationTime)
        }

        // Wait until isReadyForMoreMediaData is true (max 100ms)
        let maxWaitTime: TimeInterval = 0.1
        let startTime = Date()
        var waitCount = 0

        while !videoInput.isReadyForMoreMediaData {
            lock.unlock()

            // Check for timeout
            if Date().timeIntervalSince(startTime) > maxWaitTime {
                Log.recording.warning("Video sample wait timeout (\(waitCount) retries)")
                onFrameDropped?()
                return
            }

            // Retry after a short delay (100μs)
            usleep(100)
            waitCount += 1

            lock.lock()
            guard isWriting else {
                lock.unlock()
                return
            }
        }

        // Append the frame
        if !videoInput.append(sampleBuffer) {
            Log.recording.error("Failed to append video sample buffer")
            lock.unlock()
            onFrameDropped?()
            return
        }

        lastVideoTime = presentationTime
        lock.unlock()
    }

    /// Add pixel buffers synchronously, waiting without frame loss
    func appendVideoPixelBuffer(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        lock.lock()
        guard isWriting, let adaptor = pixelBufferAdaptor else {
            lock.unlock()
            return
        }

        // Handle session start
        if sessionStartTime == nil {
            sessionStartTime = presentationTime
            assetWriter?.startSession(atSourceTime: presentationTime)
        }

        let input = adaptor.assetWriterInput

        // Wait until isReadyForMoreMediaData is true (max 100ms)
        let maxWaitTime: TimeInterval = 0.1
        let startTime = Date()
        var waitCount = 0

        while !input.isReadyForMoreMediaData {
            lock.unlock()

            // Check for timeout
            if Date().timeIntervalSince(startTime) > maxWaitTime {
                Log.recording.warning("Frame wait timeout (\(waitCount) retries)")
                onFrameDropped?()
                return
            }

            // Retry after a short delay (100μs)
            usleep(100)
            waitCount += 1

            lock.lock()
            guard isWriting else {
                lock.unlock()
                return
            }
        }

        // Append the frame
        if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            Log.recording.error("Failed to append pixel buffer")
            lock.unlock()
            onFrameDropped?()
            return
        }

        lastVideoTime = presentationTime
        lock.unlock()
    }

    /// Append audio sample buffers synchronously, waiting without loss
    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard isWriting, let audioInput = audioInput, configuration.includeAudio else {
            lock.unlock()
            return
        }

        // Wait until isReadyForMoreMediaData is true (max 50ms)
        let maxWaitTime: TimeInterval = 0.05
        let startTime = Date()

        while !audioInput.isReadyForMoreMediaData {
            lock.unlock()

            if Date().timeIntervalSince(startTime) > maxWaitTime {
                Log.recording.warning("Audio sample wait timeout")
                return
            }

            usleep(100)

            lock.lock()
            guard isWriting else {
                lock.unlock()
                return
            }
        }

        if !audioInput.append(sampleBuffer) {
            Log.recording.error("Failed to append audio sample buffer")
        }

        lock.unlock()
    }

    func finishWriting() async throws -> URL {
        guard isWriting else {
            throw VideoWriterError.notWriting
        }

        isWriting = false

        return try await withCheckedThrowingContinuation { continuation in
            writerQueue.async { [weak self] in
                guard let self = self, let writer = self.assetWriter else {
                    continuation.resume(throwing: VideoWriterError.writerNotInitialized)
                    return
                }

                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()

                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: self.outputURL)
                    } else {
                        continuation.resume(throwing: VideoWriterError.failedToFinish(writer.error))
                    }
                }
            }
        }
    }

    func cancelWriting() {
        isWriting = false
        assetWriter?.cancelWriting()

        // Clean up file
        do {
            try FileManager.default.removeItem(at: outputURL)
        } catch {
            Log.recording.debug("Could not remove cancelled recording file: \(error.localizedDescription)")
        }
    }

    var currentDuration: TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return CMTimeGetSeconds(lastVideoTime - startTime)
    }

    /// Check whether VideoWriter is ready to accept more data
    var isReadyForMoreMediaData: Bool {
        return videoInput?.isReadyForMoreMediaData ?? false
    }

    /// Synchronously append pixel buffers (quality-first for export) - returns success
    @discardableResult
    func appendVideoPixelBufferSync(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> Bool {
        guard isWriting, let adaptor = pixelBufferAdaptor else { return false }

        // Handle session start
        if sessionStartTime == nil {
            sessionStartTime = presentationTime
            assetWriter?.startSession(atSourceTime: presentationTime)
        }

        // Ensure readiness
        guard adaptor.assetWriterInput.isReadyForMoreMediaData else {
            return false
        }

        // Attempt synchronous append
        let success = adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        if success {
            lastVideoTime = presentationTime
        }
        return success
    }
}

// MARK: - VideoWriterConfiguration

struct VideoWriterConfiguration {
    var width: Int
    var height: Int
    var frameRate: Int
    var videoBitRate: Int
    var keyFrameInterval: Int
    var videoCodec: AVVideoCodecType
    var profileLevel: String?  // nil = auto-select based on codec
    var fileType: AVFileType
    var includeAudio: Bool
    var audioSampleRate: Double
    var audioChannels: Int
    var audioBitRate: Int

    init(
        width: Int = 1920,
        height: Int = 1080,
        frameRate: Int = 60,
        videoBitRate: Int = 10_000_000,
        keyFrameInterval: Int = 60,
        videoCodec: AVVideoCodecType = .h264,
        profileLevel: String? = nil,  // Auto-select based on codec
        fileType: AVFileType = .mp4,
        includeAudio: Bool = true,
        audioSampleRate: Double = 48000,
        audioChannels: Int = 2,
        audioBitRate: Int = 128_000
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.videoBitRate = videoBitRate
        self.keyFrameInterval = keyFrameInterval
        self.videoCodec = videoCodec
        // Auto-select profile level based on codec if not specified
        if let profileLevel = profileLevel {
            self.profileLevel = profileLevel
        } else {
            self.profileLevel = Self.defaultProfileLevel(for: videoCodec)
        }
        self.fileType = fileType
        self.includeAudio = includeAudio
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.audioBitRate = audioBitRate
    }

    /// Returns the appropriate profile level for the given codec
    static func defaultProfileLevel(for codec: AVVideoCodecType) -> String {
        switch codec {
        case .hevc:
            return "HEVC_Main_AutoLevel"
        case .h264:
            return AVVideoProfileLevelH264HighAutoLevel
        default:
            return AVVideoProfileLevelH264HighAutoLevel
        }
    }

    static let highQuality = Self(
        videoBitRate: 20_000_000,
        videoCodec: .hevc
    )

    static let mediumQuality = Self(
        videoBitRate: 10_000_000
    )

    static let lowQuality = Self(
        frameRate: 30,
        videoBitRate: 5_000_000
    )

    static func forCaptureConfiguration(_ captureConfig: CaptureConfiguration, quality: ExportQuality = .high) -> Self {
        let bitRate: Int
        let codec: AVVideoCodecType

        switch quality {
        case .low:
            bitRate = 5_000_000
            codec = .h264
        case .medium:
            bitRate = 10_000_000
            codec = .h264
        case .high:
            bitRate = 20_000_000
            codec = .hevc
        case .original:
            bitRate = 50_000_000
            codec = .hevc
        }

        // Scale bitrate proportionally for higher frame rates (base rates are for 60fps)
        let frameRateScale = max(1.0, Double(captureConfig.frameRate) / 60.0)
        let scaledBitRate = Int(Double(bitRate) * frameRateScale)

        return Self(
            width: captureConfig.width,
            height: captureConfig.height,
            frameRate: captureConfig.frameRate,
            videoBitRate: scaledBitRate,
            keyFrameInterval: captureConfig.frameRate,  // Keyframe every second
            videoCodec: codec
        )
    }
}

// Note: ExportQuality is defined in Project/RenderSettings.swift

// MARK: - VideoWriterError

enum VideoWriterError: LocalizedError {
    case writerNotInitialized
    case failedToStart(Error?)
    case failedToFinish(Error?)
    case notWriting

    var errorDescription: String? {
        switch self {
        case .writerNotInitialized:
            return "Video writer not initialized"
        case .failedToStart(let error):
            return "Failed to start writing: \(error?.localizedDescription ?? "Unknown error")"
        case .failedToFinish(let error):
            return "Failed to finish writing: \(error?.localizedDescription ?? "Unknown error")"
        case .notWriting:
            return "Not currently writing"
        }
    }
}
