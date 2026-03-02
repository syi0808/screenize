import Foundation
import AVFoundation
import CoreImage
import CoreVideo

// MARK: - Video Export

extension ExportEngine {

    /// Context holding all writer-related objects for a video export session.
    struct WriterContext {
        let writer: AVAssetWriter
        let writerInput: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let audioWriterInput: AVAssetWriterInput?
        let hasSystemAudio: Bool
        let hasMicAudio: Bool
    }

    func exportVideo(project: ScreenizeProject, to outputURL: URL) async throws -> URL {
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
            Log.export.info("Export: Loaded mouse data - \(rawMousePositions.count) raw, \(smoothedMousePositions.count) smoothed positions, \(clickEvents.count) clicks")

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
            let writerCtx = try await configureWriter(
                project: project, outputURL: outputURL,
                outputSize: outputSize, sourceFrameRate: frameRate
            )

            // 7. Process frames
            guard let evaluator = evaluator, let renderer = renderer else {
                throw ExportEngineError.writerFailed
            }

            let totalOutputFrames = Int(trimmedDuration * outputFrameRate)

            let exportColorSpace: CGColorSpace? = project.renderSettings.outputColorSpace == .auto
                ? nil
                : project.renderSettings.outputColorSpace.cgColorSpace

            let framesWritten = try await processFrames(
                writer: writerCtx.writer,
                reader: sequentialReader,
                writerInput: writerCtx.writerInput,
                adaptor: writerCtx.adaptor,
                evaluator: evaluator,
                renderer: renderer,
                trimStart: trimStart,
                outputFrameRate: outputFrameRate,
                totalOutputFrames: totalOutputFrames,
                startTime: startTime,
                colorSpace: exportColorSpace
            )

            Log.export.info("Export completed - \(framesWritten) frames")

            // 8. Write audio
            if let audioInput = writerCtx.audioWriterInput {
                try await writeAudio(
                    project: project, audioInput: audioInput,
                    hasSystemAudio: writerCtx.hasSystemAudio,
                    hasMicAudio: writerCtx.hasMicAudio,
                    trimStart: trimStart, trimEnd: trimEnd
                )
            }

            // 9. Finalize
            await MainActor.run { progress = .finalizing }

            await writerCtx.writer.finishWriting()

            if writerCtx.writer.status == .failed {
                throw writerCtx.writer.error ?? ExportEngineError.writerFailed
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

    // MARK: - Writer Configuration

    func configureWriter(
        project: ScreenizeProject,
        outputURL: URL,
        outputSize: CGSize,
        sourceFrameRate: Double
    ) async throws -> WriterContext {
        let outputFrameRate = project.renderSettings.outputFrameRate.value(sourceFrameRate: sourceFrameRate)

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

        // Detect audio tracks
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

        guard writer.startWriting() else {
            throw ExportEngineError.writerStartFailed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        return WriterContext(
            writer: writer, writerInput: writerInput, adaptor: adaptor,
            audioWriterInput: audioWriterInput,
            hasSystemAudio: hasSystemAudio, hasMicAudio: hasMicAudio
        )
    }

    // MARK: - Audio Writing

    func writeAudio(
        project: ScreenizeProject,
        audioInput: AVAssetWriterInput,
        hasSystemAudio: Bool,
        hasMicAudio: Bool,
        trimStart: TimeInterval,
        trimEnd: TimeInterval
    ) async throws {
        await MainActor.run { progress = .encoding }

        let systemAudioURL = project.media.systemAudioURL
        let micAudioURL = project.media.micAudioURL
        let systemVolume = project.renderSettings.systemAudioVolume
        let micVolume = project.renderSettings.microphoneAudioVolume

        if hasSystemAudio && hasMicAudio, let sysURL = systemAudioURL, let micURL = micAudioURL {
            try await audioMixer.mixAndWrite(
                systemAudioURL: sysURL, micAudioURL: micURL,
                writerInput: audioInput,
                trimStart: trimStart, trimEnd: trimEnd,
                systemVolume: systemVolume, micVolume: micVolume
            )
        } else if hasSystemAudio, let sysURL = systemAudioURL {
            try await audioMixer.writePassthrough(
                audioURL: sysURL, writerInput: audioInput,
                trimStart: trimStart, trimEnd: trimEnd, volume: systemVolume
            )
        } else if hasMicAudio, let micURL = micAudioURL {
            try await audioMixer.writePassthrough(
                audioURL: micURL, writerInput: audioInput,
                trimStart: trimStart, trimEnd: trimEnd, volume: micVolume
            )
        }
    }

    // MARK: - Frame Processing

    /// Process frames with frame-rate-aware sampling using requestMediaDataWhenReady
    func processFrames(
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
}
