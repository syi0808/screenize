import Foundation
import AVFoundation
import CoreImage

// MARK: - GIF Export

extension ExportEngine {

    func exportGIF(project: ScreenizeProject, to outputURL: URL) async throws -> URL {
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
            let trimmedDuration = project.timeline.trimmedDuration
            let trimEnd = project.timeline.effectiveTrimEnd

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
            Log.export.info("GIF Export: Loaded mouse data - \(rawResult.positions.count) raw, \(smoothedResult.positions.count) smoothed positions")

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
            Log.export.info("GIF Export completed - \(totalWritten) frames")

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
}
