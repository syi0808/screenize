import Foundation

// MARK: - Smart Generation

extension EditorViewModel {

    /// Auto-generate keyframes using mouse data
    /// - Parameter selection: Which track types to generate. Unselected types are preserved.
    func runSmartGeneration(
        for selection: Set<TrackType> = [.transform, .cursor, .keystroke]
    ) async {
        await runSmartZoomGeneration(for: selection)
    }

    /// Smart generation with selective track types (video analysis + UI state)
    private func runSmartZoomGeneration(for selection: Set<TrackType>) async {
        saveUndoSnapshot()

        isLoading = true
        errorMessage = nil

        do {
            // 1. Load mouse data source (prefers v4 event streams, falls back to v2)
            guard let mouseDataSource = loadMouseDataSource() else {
                Log.generator.info("Smart generation skipped: No mouse data available")
                isLoading = false
                return
            }

            // 2. Load frame analysis (cached or fresh)
            let frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis]
            if let cached = project.frameAnalysisCache, !cached.isEmpty {
                frameAnalysis = cached
            } else {
                let analyzer = VideoFrameAnalyzer()
                frameAnalysis = try await analyzer.analyze(
                    videoURL: project.media.videoURL,
                    progressHandler: { progress in
                        Task { @MainActor in
                            Log.generator.debug("Frame analysis: \(Int(progress.percentage * 100))%")
                        }
                    }
                )
                project.frameAnalysisCache = frameAnalysis
            }

            // 3. Load UI state samples from event streams
            let uiStateSamples: [UIStateSample]
            if let interop = project.interop, let packageURL = projectURL {
                uiStateSamples = EventStreamLoader.loadUIStateSamples(
                    from: packageURL,
                    interop: interop
                )
            } else {
                uiStateSamples = []
            }

            // 4. Run generation pipeline (off main thread to avoid UI freeze)
            let springConfig = project.timeline.cursorTrackV2?.springConfig ?? .default

            let generationSettings = GenerationSettingsManager.shared.effectiveSettings(for: project)
            var ccSettings = ContinuousCameraSettings(from: generationSettings)
            ccSettings.springConfig = springConfig
            let screenBounds = project.media.pixelSize
            let mode = generationSettings.mode

            let generated: GeneratedTimeline = try await Task.detached(priority: .userInitiated) {
                switch mode {
                case .continuous:
                    return ContinuousCameraGenerator().generate(
                        from: mouseDataSource,
                        uiStateSamples: uiStateSamples,
                        frameAnalysis: frameAnalysis,
                        screenBounds: screenBounds,
                        settings: ccSettings
                    )
                case .segmentBased:
                    return SegmentCameraGenerator().generate(
                        from: mouseDataSource,
                        uiStateSamples: uiStateSamples,
                        frameAnalysis: frameAnalysis,
                        screenBounds: screenBounds,
                        settings: ccSettings
                    )
                }
            }.value

            // 5. Apply selected tracks
            updateTimeline(
                cameraTrack: selection.contains(.transform) ? generated.cameraTrack : nil,
                cursorTrack: selection.contains(.cursor) ? generated.cursorTrack : nil,
                keystrokeTrack: selection.contains(.keystroke) ? generated.keystrokeTrack : nil
            )

            // 6. Populate spring cache from generation metadata
            if selection.contains(.transform),
               let cameraTrack = project.timeline.cameraTrack {
                invalidateSpringCache()
                springCache.populate(
                    segments: cameraTrack.segments,
                    config: generated.springConfig ?? .init(),
                    cursorSpeeds: generated.cursorSpeeds
                )
            }

            Log.generator.info("Smart generation V2 completed for \(selection.count) track type(s)")

            hasUnsavedChanges = true
            invalidatePreviewCache()

        } catch {
            Log.generator.error("Smart generation failed: \(error.localizedDescription)")
            errorMessage = "Failed to generate segments: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Load mouse data source, preferring v4 event streams over legacy recording.mouse.json.
    private func loadMouseDataSource() -> MouseDataSource? {
        // v4 path: load from event streams
        if let interop = project.interop, let packageURL = projectURL {
            if let source = EventStreamLoader.load(
                from: packageURL,
                interop: interop,
                duration: project.media.duration,
                frameRate: project.media.frameRate
            ) {
                return source
            }
        }

        return nil
    }

    /// Invalidate the frame analysis cache
    func invalidateFrameAnalysisCache() {
        project.frameAnalysisCache = nil
        hasUnsavedChanges = true
    }

    /// Apply generated segment tracks to the timeline.
    private func updateTimeline(
        cameraTrack: CameraTrack? = nil,
        cursorTrack: CursorTrackV2? = nil,
        keystrokeTrack: KeystrokeTrackV2? = nil
    ) {
        if let cameraTrack = cameraTrack {
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) {
                project.timeline.tracks[index] = .camera(cameraTrack)
            } else {
                project.timeline.tracks.insert(.camera(cameraTrack), at: 0)
            }
        }

        if let cursorTrack = cursorTrack {
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }) {
                project.timeline.tracks[index] = .cursor(cursorTrack)
            } else {
                project.timeline.tracks.append(.cursor(cursorTrack))
            }
        }

        if let keystrokeTrack = keystrokeTrack {
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }) {
                project.timeline.tracks[index] = .keystroke(keystrokeTrack)
            } else {
                project.timeline.tracks.append(.keystroke(keystrokeTrack))
            }
        }
    }
}
