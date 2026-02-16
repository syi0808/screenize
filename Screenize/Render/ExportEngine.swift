import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import Combine

/// Export engine
/// Timeline-based final video output
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
            // 1. Load video
            await MainActor.run { progress = .loadingVideo }
            let extractor = try await VideoFrameExtractor(url: project.media.videoURL)

            let asset = AVAsset(url: project.media.videoURL)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw ExportEngineError.noVideoTrack
            }

            let naturalSize = extractor.videoSize
            let frameRate = extractor.frameRate

            // Calculate the trim range
            let trimStart = project.timeline.effectiveTrimStart
            let trimEnd = project.timeline.effectiveTrimEnd
            let trimmedDuration = project.timeline.trimmedDuration
            let totalFrames = Int(trimmedDuration * frameRate)

            // 2. Load and interpolate mouse data
            await MainActor.run { progress = .loadingMouseData }

            // Load raw mouse data
            let rawResult = await MainActor.run {
                MouseDataConverter.loadAndConvert(from: project)
            }
            let rawMousePositions = rawResult.positions
            let clickEvents = rawResult.clicks

            // Load smoothed mouse data (Catmull-Rom interpolated)
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

            // 4. Create the render pipeline (Evaluator + Renderer)
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

            // 6. Configure the video reader
            let reader = try AVAssetReader(asset: asset)

            // Set the trim range (read only the trimmed segment)
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: 600),
                end: CMTime(seconds: trimEnd, preferredTimescale: 600)
            )

            let readerOutputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
            readerOutput.alwaysCopiesSampleData = false
            reader.add(readerOutput)

            // 7. Configure the video writer
            // Remove existing file (AVAssetWriter does not overwrite)
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
                    kCVPixelBufferHeightKey as String: Int(outputSize.height)
                ]
            )

            writer.add(writerInput)

            // 8. Start the reader and writer
            guard reader.startReading() else {
                throw ExportEngineError.readerStartFailed
            }

            guard writer.startWriting() else {
                throw ExportEngineError.writerStartFailed(writer.error)
            }

            writer.startSession(atSourceTime: .zero)

            // 9. Frame processing loop
            var frameIndex = 0
            let ciContext = CIContext(options: [.useSoftwareRenderer: false])

            // Create pixel buffer pool
            var pixelBufferPool: CVPixelBufferPool?
            let poolAttrs: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
            let bufferAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, bufferAttrs as CFDictionary, &pixelBufferPool)

            // Trim start time (used for output presentation time)
            let trimStartTime = CMTime(seconds: trimStart, preferredTimescale: 600)

            while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                // Check for cancellation
                if isCancelled {
                    reader.cancelReading()
                    writer.cancelWriting()
                    await MainActor.run { progress = .cancelled }
                    throw ExportEngineError.cancelled
                }

                // Extract the source frame
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    frameIndex += 1
                    continue
                }

                let sourceFrame = CIImage(cvPixelBuffer: imageBuffer)

                // Presentation time
                let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let originalTime = CMTimeGetSeconds(sampleTime)

                // Evaluate the state
                guard let evaluator = evaluator else { continue }
                let state = evaluator.evaluate(at: originalTime)

                // Render the frame
                guard let renderer = renderer,
                      let rendered = renderer.render(sourceFrame: sourceFrame, state: state) else {
                    frameIndex += 1
                    continue
                }

                // Create a pixel buffer
                var outputPixelBuffer: CVPixelBuffer?
                if let pool = pixelBufferPool {
                    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputPixelBuffer)
                }

                guard let pixelBuffer = outputPixelBuffer else {
                    frameIndex += 1
                    continue
                }

                // Render the CIImage into the pixel buffer
                ciContext.render(
                    rendered,
                    to: pixelBuffer,
                    bounds: CGRect(origin: .zero, size: outputSize),
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )

                // Compute the output time (relative to the trim start)
                let outputPTS = CMTimeSubtract(sampleTime, trimStartTime)

                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }

                adaptor.append(pixelBuffer, withPresentationTime: outputPTS)

                // Update progress (refresh UI every 10 frames to reduce main-thread load)
                frameIndex += 1
                if frameIndex % 10 == 0 || frameIndex == totalFrames {
                    let currentFrame = frameIndex
                    await MainActor.run {
                        progress = .processing(frame: currentFrame, total: totalFrames)
                        statistics = ExportStatistics(
                            totalFrames: totalFrames,
                            processedFrames: currentFrame,
                            startTime: startTime,
                            currentTime: Date()
                        )
                    }
                }
            }

            print("📊 [Export] Completed - \(frameIndex) frames")

            // 10. Finalizing
            await MainActor.run { progress = .encoding }
            writerInput.markAsFinished()

            await MainActor.run { progress = .finalizing }

            await writer.finishWriting()

            if writer.status == .failed {
                throw writer.error ?? ExportEngineError.writerFailed
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
