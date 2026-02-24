import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import Combine

/// Export engine
/// Timeline-based final video output with Metal-accelerated GPU pipeline
final class ExportEngine: ObservableObject {

    // MARK: - Published Properties

    /// Current progress state
    @MainActor @Published private(set) var progress: ExportProgress = .idle

    /// Statistics info
    @MainActor @Published private(set) var statistics: ExportStatistics?

    // MARK: - Properties

    /// Project
    private var project: ScreenizeProject?

    /// Export task
    private var exportTask: Task<URL, Error>?

    /// Cancellation flag
    private var isCancelled: Bool = false

    /// Frame evaluator
    private var evaluator: FrameEvaluator?

    /// Renderer
    private var renderer: Renderer?

    /// Audio mixer
    private let audioMixer = AudioMixer()

    // MARK: - Initialization

    init() {}

    // MARK: - Export

    /// Start export
    /// - Parameters:
    ///   - project: Project to export
    ///   - outputURL: Output file URL
    /// - Returns: URL of the completed file
    func export(project: ScreenizeProject, to outputURL: URL) async throws -> URL {
        // Throw if an export is already in progress
        let isInProgress = await MainActor.run { progress.isInProgress }
        guard !isInProgress else {
            throw ExportEngineError.alreadyExporting
        }

        // Reset stale state from any previous export
        await MainActor.run {
            progress = .idle
            statistics = nil
        }
        self.isCancelled = false

        switch project.renderSettings.exportFormat {
        case .video:
            return try await exportVideo(project: project, to: outputURL)
        case .gif:
            return try await exportGIF(project: project, to: outputURL)
        }
    }

    // MARK: - Video Export

    private func exportVideo(project: ScreenizeProject, to outputURL: URL) async throws -> URL {
        self.project = project
        self.isCancelled = false

        await MainActor.run { progress = .preparing }
        let startTime = Date()

        do {
            // 1. Load video metadata
            await MainActor.run { progress = .loadingVideo }
            let extractor = try await VideoFrameExtractor(url: project.media.videoURL)

            let naturalSize = extractor.videoSize
            let frameRate = extractor.frameRate

            // Calculate the trim range
            let trimStart = project.timeline.effectiveTrimStart
            let trimEnd = project.timeline.effectiveTrimEnd
            let trimmedDuration = project.timeline.trimmedDuration

            // 2. Load and interpolate mouse data
            await MainActor.run { progress = .loadingMouseData }

            let rawResult = await MainActor.run {
                MouseDataConverter.loadAndConvert(from: project)
            }
            let rawMousePositions = rawResult.positions
            let clickEvents = rawResult.clicks

            let springConfig = project.timeline.cursorTrackV2?.springConfig
            let smoothedResult = await MainActor.run {
                MouseDataConverter.loadAndConvertWithInterpolation(
                    from: project,
                    frameRate: frameRate,
                    springConfig: springConfig
                )
            }
            let smoothedMousePositions = smoothedResult.positions
            print("Export: Loaded mouse data - \(rawMousePositions.count) raw, \(smoothedMousePositions.count) smoothed positions, \(clickEvents.count) clicks")

            // 3. Determine output size
            let outputSize = project.renderSettings.outputResolution.size(sourceSize: naturalSize)

            // 4. Create the render pipeline (Metal-backed Evaluator + Renderer)
            let pipeline = RenderPipelineFactory.createExportPipeline(
                project: project,
                rawMousePositions: rawMousePositions,
                smoothedMousePositions: smoothedMousePositions,
                clickEvents: clickEvents,
                frameRate: frameRate,
                sourceSize: naturalSize,
                outputSize: outputSize
            )
            evaluator = pipeline.evaluator
            renderer = pipeline.renderer

            // 5. Create GPU-resident sequential frame reader
            let sequentialReader = try await SequentialFrameReader(url: project.media.videoURL)
            try sequentialReader.startReading(from: trimStart, to: trimEnd)

            // 6. Configure the video writer
            let outputFrameRate = project.renderSettings.outputFrameRate.value(sourceFrameRate: frameRate)

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            let writer = try AVAssetWriter(outputURL: outputURL, fileType: project.renderSettings.codec.avFileType)

            let videoSettings = createVideoSettings(
                size: outputSize,
                codec: project.renderSettings.codec,
                quality: project.renderSettings.quality,
                frameRate: outputFrameRate,
                colorSpace: project.renderSettings.outputColorSpace
            )

            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = false

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(outputSize.width),
                    kCVPixelBufferHeightKey as String: Int(outputSize.height),
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
                ]
            )

            writer.add(writerInput)

            // 6b. Configure audio writer input (if audio sources exist)
            let systemAudioURL = project.media.systemAudioURL
            let micAudioURL = project.media.micAudioURL
            let hasSystemAudio: Bool
            if let sysURL = systemAudioURL, project.renderSettings.includeSystemAudio {
                hasSystemAudio = await Self.hasAudioTrack(url: sysURL)
            } else {
                hasSystemAudio = false
            }
            let hasMicAudio: Bool
            if project.renderSettings.includeMicrophoneAudio, let micURL = micAudioURL {
                hasMicAudio = await Self.hasAudioTrack(url: micURL)
            } else {
                hasMicAudio = false
            }

            var audioWriterInput: AVAssetWriterInput?
            if hasSystemAudio || hasMicAudio {
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: AudioMixer.outputSettings)
                audioInput.expectsMediaDataInRealTime = false
                writer.add(audioInput)
                audioWriterInput = audioInput
            }

            // 7. Start the writer
            guard writer.startWriting() else {
                throw ExportEngineError.writerStartFailed(writer.error)
            }

            writer.startSession(atSourceTime: .zero)

            // 8. Process frames
            guard let evaluator = evaluator, let renderer = renderer else {
                throw ExportEngineError.writerFailed
            }

            let totalOutputFrames = Int(trimmedDuration * outputFrameRate)

            let exportColorSpace: CGColorSpace? = project.renderSettings.outputColorSpace == .auto
                ? nil
                : project.renderSettings.outputColorSpace.cgColorSpace

            let framesWritten = try await processFrames(
                writer: writer,
                reader: sequentialReader,
                writerInput: writerInput,
                adaptor: adaptor,
                evaluator: evaluator,
                renderer: renderer,
                trimStart: trimStart,
                outputFrameRate: outputFrameRate,
                totalOutputFrames: totalOutputFrames,
                startTime: startTime,
                colorSpace: exportColorSpace
            )

            print("[Export] Completed - \(framesWritten) frames")

            // 9. Write audio
            if let audioInput = audioWriterInput {
                await MainActor.run { progress = .encoding }

                let systemVolume = project.renderSettings.systemAudioVolume
                let micVolume = project.renderSettings.microphoneAudioVolume

                if hasSystemAudio && hasMicAudio, let sysURL = systemAudioURL, let micURL = micAudioURL {
                    try await audioMixer.mixAndWrite(
                        systemAudioURL: sysURL,
                        micAudioURL: micURL,
                        writerInput: audioInput,
                        trimStart: trimStart,
                        trimEnd: trimEnd,
                        systemVolume: systemVolume,
                        micVolume: micVolume
                    )
                } else if hasSystemAudio, let sysURL = systemAudioURL {
                    try await audioMixer.writePassthrough(
                        audioURL: sysURL,
                        writerInput: audioInput,
                        trimStart: trimStart,
                        trimEnd: trimEnd,
                        volume: systemVolume
                    )
                } else if hasMicAudio, let micURL = micAudioURL {
                    try await audioMixer.writePassthrough(
                        audioURL: micURL,
                        writerInput: audioInput,
                        trimStart: trimStart,
                        trimEnd: trimEnd,
                        volume: micVolume
                    )
                }
            }

            // 10. Finalizing
            await MainActor.run { progress = .finalizing }

            await writer.finishWriting()

            if writer.status == .failed {
                throw writer.error ?? ExportEngineError.writerFailed
            }

            // Handle cancellation during finalization
            if isCancelled {
                await MainActor.run { progress = .cancelled }
                throw ExportEngineError.cancelled
            }

            // Completed
            await MainActor.run {
                progress = .completed(outputURL)
                statistics = ExportStatistics(
                    totalFrames: framesWritten,
                    processedFrames: framesWritten,
                    startTime: startTime,
                    currentTime: Date()
                )
            }

            return outputURL

        } catch {
            if !isCancelled {
                await MainActor.run { progress = .failed(error.localizedDescription) }
            }
            throw error
        }
    }

    // MARK: - GIF Export

    private func exportGIF(project: ScreenizeProject, to outputURL: URL) async throws -> URL {
        self.project = project
        self.isCancelled = false

        await MainActor.run { progress = .preparing }
        let startTime = Date()

        do {
            // 1. Load video metadata
            await MainActor.run { progress = .loadingVideo }
            let extractor = try await VideoFrameExtractor(url: project.media.videoURL)

            let naturalSize = extractor.videoSize
            let frameRate = extractor.frameRate

            let trimStart = project.timeline.effectiveTrimStart
            let trimEnd = project.timeline.effectiveTrimEnd
            let trimmedDuration = project.timeline.trimmedDuration

            // 2. Load mouse data
            await MainActor.run { progress = .loadingMouseData }

            let rawResult = await MainActor.run {
                MouseDataConverter.loadAndConvert(from: project)
            }
            let gifSpringConfig = project.timeline.cursorTrackV2?.springConfig
            let smoothedResult = await MainActor.run {
                MouseDataConverter.loadAndConvertWithInterpolation(
                    from: project,
                    frameRate: frameRate,
                    springConfig: gifSpringConfig
                )
            }
            print("[GIF Export] Loaded mouse data - \(rawResult.positions.count) raw, \(smoothedResult.positions.count) smoothed positions")

            // 3. Determine GIF output size
            let gifSettings = project.renderSettings.gifSettings
            let outputSize = gifSettings.effectiveSize(sourceSize: naturalSize)

            // 4. Create render pipeline at GIF output resolution
            let pipeline = RenderPipelineFactory.createExportPipeline(
                project: project,
                rawMousePositions: rawResult.positions,
                smoothedMousePositions: smoothedResult.positions,
                clickEvents: rawResult.clicks,
                frameRate: frameRate,
                sourceSize: naturalSize,
                outputSize: outputSize
            )
            evaluator = pipeline.evaluator
            renderer = pipeline.renderer

            // 5. Create sequential reader
            let sequentialReader = try await SequentialFrameReader(url: project.media.videoURL)
            try sequentialReader.startReading(from: trimStart, to: trimEnd)

            // 6. Create GIF encoder
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            let gifFrameRate = Double(gifSettings.frameRate)
            let totalOutputFrames = Int(trimmedDuration * gifFrameRate)
            let gifEncoder = GIFEncoder(outputURL: outputURL, settings: gifSettings)
            try gifEncoder.beginWriting(estimatedFrameCount: totalOutputFrames)

            // 7. Process frames
            guard let evaluator = evaluator, let renderer = renderer else {
                throw ExportEngineError.writerFailed
            }

            let outputFrameInterval = 1.0 / gifFrameRate
            var outputFrameIndex = 0
            let gifCFRReader = CFRFrameReader(source: sequentialReader)

            while outputFrameIndex < totalOutputFrames {
                if isCancelled {
                    await MainActor.run { progress = .cancelled }
                    throw ExportEngineError.cancelled
                }

                let idealTime = trimStart + Double(outputFrameIndex) * outputFrameInterval

                guard let sourceFrame = gifCFRReader.frame(at: idealTime) else { break }

                let state = evaluator.evaluate(at: idealTime)

                if let cgImage = renderer.renderToCGImage(
                    sourceFrame: sourceFrame.image, state: state
                ) {
                    gifEncoder.addFrame(cgImage)
                }

                outputFrameIndex += 1

                if outputFrameIndex.isMultiple(of: 5) || outputFrameIndex == totalOutputFrames {
                    let current = outputFrameIndex
                    let total = totalOutputFrames
                    await MainActor.run {
                        progress = .processing(frame: current, total: total)
                        statistics = ExportStatistics(
                            totalFrames: total,
                            processedFrames: current,
                            startTime: startTime,
                            currentTime: Date()
                        )
                    }
                }
            }

            // 8. Finalize
            await MainActor.run { progress = .finalizing }
            try gifEncoder.finalize()

            let totalWritten = gifEncoder.framesWritten
            print("[GIF Export] Completed - \(totalWritten) frames")

            await MainActor.run {
                progress = .completed(outputURL)
                statistics = ExportStatistics(
                    totalFrames: totalWritten,
                    processedFrames: totalWritten,
                    startTime: startTime,
                    currentTime: Date()
                )
            }

            return outputURL

        } catch {
            if !isCancelled {
                await MainActor.run { progress = .failed(error.localizedDescription) }
            }
            throw error
        }
    }

    // MARK: - Cancel

    /// Cancel the export
    func cancel() {
        isCancelled = true
        exportTask?.cancel()
    }

    // MARK: - Reset

    /// Reset the state
    @MainActor
    func reset() {
        progress = .idle
        statistics = nil
        isCancelled = false
    }

    // MARK: - Frame Processing

    /// Process frames with frame-rate-aware sampling using requestMediaDataWhenReady
    /// - Returns: Number of frames written
    private func processFrames(
        writer: AVAssetWriter,
        reader: SequentialFrameReader,
        writerInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        evaluator: FrameEvaluator,
        renderer: Renderer,
        trimStart: TimeInterval,
        outputFrameRate: Double,
        totalOutputFrames: Int,
        startTime: Date,
        colorSpace: CGColorSpace? = nil
    ) async throws -> Int {
        let outputFrameInterval = 1.0 / outputFrameRate
        var outputFrameIndex = 0
        let exportQueue = DispatchQueue(label: "com.screenize.export", qos: .userInitiated)
        let cfrReader = CFRFrameReader(source: reader)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false

            writerInput.requestMediaDataWhenReady(on: exportQueue) { [weak self] in
                guard let self = self else {
                    if !didResume {
                        didResume = true
                        continuation.resume(throwing: ExportEngineError.writerFailed)
                    }
                    return
                }

                // Detect writer failure (prevents hang when writer silently fails)
                if writer.status == .failed {
                    writerInput.markAsFinished()
                    if !didResume {
                        didResume = true
                        continuation.resume(
                            throwing: writer.error ?? ExportEngineError.writerFailed
                        )
                    }
                    return
                }

                while writerInput.isReadyForMoreMediaData {
                    if self.isCancelled {
                        reader.stopReading()
                        writerInput.markAsFinished()
                        if !didResume {
                            didResume = true
                            continuation.resume(throwing: ExportEngineError.cancelled)
                        }
                        return
                    }

                    if outputFrameIndex >= totalOutputFrames {
                        writerInput.markAsFinished()
                        if !didResume {
                            didResume = true
                            continuation.resume()
                        }
                        return
                    }

                    let idealTime = trimStart + Double(outputFrameIndex) * outputFrameInterval

                    guard let sourceFrame = cfrReader.frame(at: idealTime) else {
                        writerInput.markAsFinished()
                        if !didResume {
                            didResume = true
                            continuation.resume()
                        }
                        return
                    }

                    let state = evaluator.evaluate(at: idealTime)

                    guard let pixelBuffer = renderer.renderToPixelBuffer(
                        sourceFrame: sourceFrame.image, state: state, outputColorSpace: colorSpace
                    ) else {
                        outputFrameIndex += 1
                        continue
                    }

                    let outputPTS = CMTime(
                        seconds: Double(outputFrameIndex) * outputFrameInterval,
                        preferredTimescale: 90_000
                    )

                    if !adaptor.append(pixelBuffer, withPresentationTime: outputPTS) {
                        writerInput.markAsFinished()
                        if !didResume {
                            didResume = true
                            continuation.resume(
                                throwing: writer.error ?? ExportEngineError.writerFailed
                            )
                        }
                        return
                    }
                    outputFrameIndex += 1

                    if outputFrameIndex.isMultiple(of: 10) || outputFrameIndex == totalOutputFrames {
                        let currentFrame = outputFrameIndex
                        let total = totalOutputFrames
                        Task { @MainActor [weak self] in
                            self?.progress = .processing(frame: currentFrame, total: total)
                            self?.statistics = ExportStatistics(
                                totalFrames: total,
                                processedFrames: currentFrame,
                                startTime: startTime,
                                currentTime: Date()
                            )
                        }
                    }
                }
            }
        }

        return outputFrameIndex
    }

    // MARK: - Audio Helpers

    /// Check if a URL contains an audio track
    private static func hasAudioTrack(url: URL) async -> Bool {
        let asset = AVAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return !tracks.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Video Settings

    private func createVideoSettings(
        size: CGSize,
        codec: VideoCodec,
        quality: ExportQuality,
        frameRate: Double,
        colorSpace: OutputColorSpace = .auto
    ) -> [String: Any] {
        let bitRate = quality.bitRate(for: size)

        var settings: [String: Any] = [
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCodecKey: codec.avCodecType
        ]

        // Compression settings per codec
        switch codec {
        case .h264, .hevc:
            let profileLevel: String = codec == .hevc
                ? "HEVC_Main_AutoLevel"
                : AVVideoProfileLevelH264HighAutoLevel
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: Int(frameRate),
                AVVideoProfileLevelKey: profileLevel
            ]
        case .proRes422, .proRes4444:
            // ProRes does not require bitrate settings
            break
        }

        // Color space metadata tagging (only when explicitly selected)
        if colorSpace != .auto {
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: colorSpace.avColorPrimaries,
                AVVideoTransferFunctionKey: colorSpace.avTransferFunction,
                AVVideoYCbCrMatrixKey: colorSpace.avYCbCrMatrix
            ]
        }

        return settings
    }
}

// MARK: - Errors

enum ExportEngineError: Error, LocalizedError {
    case alreadyExporting
    case noVideoTrack
    case readerStartFailed
    case writerStartFailed(Error?)
    case writerFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .alreadyExporting:
            return "An export is already in progress"
        case .noVideoTrack:
            return "Could not find a video track"
        case .readerStartFailed:
            return "Failed to start reading video"
        case .writerStartFailed(let underlyingError):
            if let error = underlyingError {
                return "Failed to start writing video: \(error.localizedDescription)"
            }
            return "Failed to start writing video"
        case .writerFailed:
            return "Failed to write video"
        case .cancelled:
            return "Export was cancelled"
        }
    }
}
