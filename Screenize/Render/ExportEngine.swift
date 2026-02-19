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
            let totalFrames = Int(trimmedDuration * frameRate)

            // 2. Load and interpolate mouse data
            await MainActor.run { progress = .loadingMouseData }

            let rawResult = await MainActor.run {
                MouseDataConverter.loadAndConvert(from: project)
            }
            let rawMousePositions = rawResult.positions
            let clickEvents = rawResult.clicks

            let smoothedResult = await MainActor.run {
                MouseDataConverter.loadAndConvertWithInterpolation(
                    from: project,
                    frameRate: frameRate
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
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

            let videoSettings = createVideoSettings(
                size: outputSize,
                codec: project.renderSettings.codec,
                quality: project.renderSettings.quality
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

            // 7. Start the writer
            guard writer.startWriting() else {
                throw ExportEngineError.writerStartFailed(writer.error)
            }

            writer.startSession(atSourceTime: .zero)

            // 8. Process frames using requestMediaDataWhenReady for proper backpressure
            guard let evaluator = evaluator, let renderer = renderer else {
                throw ExportEngineError.writerFailed
            }

            var frameIndex = 0
            let exportQueue = DispatchQueue(label: "com.screenize.export", qos: .userInitiated)

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

                    // Process frames while writer is ready
                    while writerInput.isReadyForMoreMediaData {
                        // Check for cancellation
                        if self.isCancelled {
                            sequentialReader.stopReading()
                            writerInput.markAsFinished()
                            if !didResume {
                                didResume = true
                                continuation.resume(throwing: ExportEngineError.cancelled)
                            }
                            return
                        }

                        // Read next frame from GPU-resident sequential reader
                        guard let frame = sequentialReader.nextFrame() else {
                            // No more frames - finalize
                            writerInput.markAsFinished()
                            if !didResume {
                                didResume = true
                                continuation.resume()
                            }
                            return
                        }

                        // Evaluate timeline state at this time
                        let state = evaluator.evaluate(at: frame.time)

                        // Render to pixel buffer (Metal-backed GPU pipeline)
                        guard let pixelBuffer = renderer.renderToPixelBuffer(
                            sourceFrame: frame.image, state: state
                        ) else {
                            frameIndex += 1
                            continue
                        }

                        // Compute output PTS relative to trim start
                        let outputPTS = CMTime(
                            seconds: frame.time - trimStart,
                            preferredTimescale: 600
                        )

                        adaptor.append(pixelBuffer, withPresentationTime: outputPTS)
                        frameIndex += 1

                        // Update progress periodically
                        if frameIndex % 10 == 0 || frameIndex == totalFrames {
                            let currentFrame = frameIndex
                            Task { @MainActor [weak self] in
                                self?.progress = .processing(frame: currentFrame, total: totalFrames)
                                self?.statistics = ExportStatistics(
                                    totalFrames: totalFrames,
                                    processedFrames: currentFrame,
                                    startTime: startTime,
                                    currentTime: Date()
                                )
                            }
                        }
                    }
                }
            }

            print("[Export] Completed - \(frameIndex) frames")

            // 9. Finalizing
            await MainActor.run { progress = .encoding }
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
                    totalFrames: frameIndex,
                    processedFrames: frameIndex,
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

    // MARK: - Video Settings

    private func createVideoSettings(
        size: CGSize,
        codec: VideoCodec,
        quality: ExportQuality
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
            let profileLevel: String = codec == .hevc ? "HEVC_Main_AutoLevel" : AVVideoProfileLevelH264HighAutoLevel
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoProfileLevelKey: profileLevel
            ]
        case .proRes422, .proRes4444:
            // ProRes does not require bitrate settings
            break
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
