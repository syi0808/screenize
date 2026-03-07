import Foundation
import CoreGraphics
import CoreImage

// MARK: - Setup & Lifecycle

extension PreviewEngine {

    /// Wire callbacks between DisplayLinkDriver, ScrubController, and RenderCoordinator
    func setupCallbacks() {
        // DisplayLink: called from background thread on every vsync
        displayLinkDriver.onFrame = { [weak self] targetVideoTime in
            guard let self = self else { return }

            self.renderCoordinator.requestPlaybackFrame(at: targetVideoTime) { [weak self] texture, actualTime in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    // Stop at trim end
                    if actualTime >= self.effectiveTrimEnd {
                        self.pause()
                        self.isSeeking = true
                        self.currentTime = self.effectiveTrimEnd
                        self.isSeeking = false
                        return
                    }

                    if let texture = texture {
                        self.currentTexture = texture
                        self.displayGeneration += 1
                    }
                    self.isSeeking = true
                    self.currentTime = actualTime
                    self.isSeeking = false

                    // Signal frame delivered so DisplayLink can fire next tick
                    self.displayLinkDriver.markFrameDelivered()
                }
            }
        }

        // ScrubController: request rendering on the render coordinator
        scrubController.onRenderRequest = { [weak self] time, generation, completion in
            guard let self = self else {
                completion(nil)
                return
            }
            self.renderCoordinator.requestScrubFrame(
                at: time, generation: generation, completion: completion
            )
        }

        // ScrubController: deliver texture to main thread
        scrubController.onFrameReady = { [weak self] texture, _ in
            guard let self = self else { return }
            if let texture = texture {
                self.currentTexture = texture
                self.displayGeneration += 1
                if self.isLoading {
                    self.isLoading = false
                }
            }
        }
    }

    /// Initialize with a project
    func setup(with project: ScreenizeProject) async {
        isLoading = true
        errorMessage = nil

        self.project = project

        do {
            // Configure the random-access frame extractor
            let extractor = try await VideoFrameExtractor(url: project.media.videoURL)
            frameExtractor = extractor

            // Set base properties
            duration = extractor.duration
            frameRate = extractor.frameRate

            // Configure trim range
            trimStart = project.timeline.effectiveTrimStart
            trimEnd = project.timeline.trimEnd

            // Load raw mouse data
            let rawResult = MouseDataConverter.loadAndConvert(from: project)
            rawMousePositions = rawResult.positions
            renderClickEvents = rawResult.clicks

            // Load smoothed mouse data (spring-based or legacy interpolation)
            let springConfig = project.timeline.cursorTrackV2?.springConfig
            let smoothedResult = MouseDataConverter.loadAndConvertWithInterpolation(
                from: project,
                frameRate: extractor.frameRate,
                springConfig: springConfig
            )
            smoothedMousePositions = smoothedResult.positions
            lastSpringConfig = springConfig

            // Build the render pipeline (Evaluator + Renderer)
            let pipeline = RenderPipelineFactory.createPreviewPipeline(
                project: project,
                rawMousePositions: rawMousePositions,
                smoothedMousePositions: smoothedMousePositions,
                clickEvents: renderClickEvents,
                frameRate: frameRate,
                sourceSize: extractor.videoSize,
                scale: previewScale
            )

            // Create sequential frame reader for playback
            let reader = try await SequentialFrameReader(
                url: project.media.videoURL,
                ringBufferSize: 8
            )
            try reader.startReading(from: effectiveTrimStart)
            sequentialReader = reader

            // Configure the render coordinator with CFR frame reader (fills VFR gaps)
            let cfrReader = CFRFrameReader(source: reader)
            renderCoordinator.setup(
                frameReader: cfrReader,
                frameExtractor: extractor,
                evaluator: pipeline.evaluator,
                renderer: pipeline.renderer,
                frameRate: frameRate
            )

            // Set up audio preview player
            await audioPlayer.setup(
                systemAudioURL: project.media.systemAudioURL,
                micAudioURL: project.media.micAudioURL,
                renderSettings: project.renderSettings
            )
            await audioPlayer.seek(to: effectiveTrimStart)

            // Render the first frame (at trim start)
            isSeeking = true
            currentTime = effectiveTrimStart
            isSeeking = false
            scrubController.scrub(to: effectiveTrimStart)

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Clean up all resources
    func cleanup() {
        pause()
        audioPlayer.cleanup()
        scrubController.cancel()
        renderCoordinator.cleanup()
        sequentialReader?.stopReading()
        frameExtractor?.cancelAllPendingRequests()
        currentTexture = nil
    }
}
