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
                let anchorTimes = adaptiveFrameAnalysisAnchors(from: mouseDataSource)
                var analysisSettings = VideoFrameAnalyzer.AnalysisSettings.default
                analysisSettings.adaptiveSampling = VideoFrameAnalyzer.AdaptiveSamplingPolicy(
                    enabled: true,
                    anchorTimes: anchorTimes
                )
                frameAnalysis = try await analyzer.analyze(
                    videoURL: project.media.videoURL,
                    settings: analysisSettings,
                    progressHandler: { progress in
                        Task { @MainActor in
                            Log.generator.debug("Frame analysis: \(Int(progress.percentage * 100))%")
                        }
                    },
                    diagnosticsHandler: { diagnostics in
                        Task { @MainActor in
                            let rate = String(format: "%.2f", diagnostics.effectiveSamplesPerSecond)
                            let uplift = String(format: "%.2fx", diagnostics.upliftVsBaseRate)
                            Log.generator.debug(
                                "Adaptive frame sampling: selected=\(diagnostics.selectedSampleCount)/\(diagnostics.sourceSampleCount), rate=\(rate)fps, uplift=\(uplift), anchors=\(diagnostics.anchorCount), missed=\(diagnostics.missedAnchorCount), budget=\(diagnostics.budgetApplied)"
                            )
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

            // 4. Run generation pipeline (V2 or Continuous Camera)
            let generated: GeneratedTimeline
            let springConfig = project.timeline.cursorTrackV2?.springConfig ?? .default

            if cameraGenerationMethod == .continuousCamera {
                var ccSettings = ContinuousCameraSettings()
                ccSettings.springConfig = springConfig
                generated = ContinuousCameraGenerator().generate(
                    from: mouseDataSource,
                    uiStateSamples: uiStateSamples,
                    frameAnalysis: frameAnalysis,
                    screenBounds: project.media.pixelSize,
                    settings: ccSettings
                )
            } else {
                var genSettings = SmartGenerationSettings.default
                genSettings.springConfig = springConfig
                generated = SmartGeneratorV2().generate(
                    from: mouseDataSource,
                    uiStateSamples: uiStateSamples,
                    frameAnalysis: frameAnalysis,
                    screenBounds: project.media.pixelSize,
                    settings: genSettings
                )
            }

            // 5. Apply selected tracks
            updateTimeline(
                cameraTrack: selection.contains(.transform) ? generated.cameraTrack : nil,
                cursorTrack: selection.contains(.cursor) ? generated.cursorTrack : nil,
                keystrokeTrack: selection.contains(.keystroke) ? generated.keystrokeTrack : nil,
                continuousTransforms: selection.contains(.transform) ? generated.continuousTransforms : nil
            )

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
        keystrokeTrack: KeystrokeTrackV2? = nil,
        continuousTransforms: [TimedTransform]? = nil
    ) {
        if let cameraTrack = cameraTrack {
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) {
                project.timeline.tracks[index] = .camera(cameraTrack)
            } else {
                project.timeline.tracks.insert(.camera(cameraTrack), at: 0)
            }
        }

        // Store continuous transforms (nil clears any previous continuous path)
        project.timeline.continuousTransforms = continuousTransforms

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

    private func adaptiveFrameAnalysisAnchors(
        from mouseData: MouseDataSource
    ) -> [TimeInterval] {
        let clickAnchors = mouseData.clicks.map(\.time)
        let keyAnchors = mouseData.keyboardEvents.map(\.time)
        let dragAnchors = mouseData.dragEvents.flatMap { [$0.startTime, $0.endTime] }
        let anchors = (clickAnchors + keyAnchors + dragAnchors)
            .map { min(max(0, $0), mouseData.duration) }
            .sorted()

        guard !anchors.isEmpty else { return [] }
        var deduped: [TimeInterval] = []
        deduped.reserveCapacity(anchors.count)
        for anchor in anchors {
            if let last = deduped.last, abs(last - anchor) < 0.01 {
                continue
            }
            deduped.append(anchor)
        }
        return deduped
    }
}
