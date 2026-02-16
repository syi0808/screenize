import Foundation
import SwiftUI
import Combine

/// Main editor view model
/// Coordinates project, preview, and timeline state
@MainActor
final class EditorViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Project
    @Published var project: ScreenizeProject

    /// Current playback time
    @Published var currentTime: TimeInterval = 0

    /// Playback state
    @Published var isPlaying: Bool = false

    /// Selected segment ID
    @Published var selectedSegmentID: UUID?

    /// Selected segment track type
    @Published var selectedSegmentTrackType: TrackType?

    /// Loading state
    @Published var isLoading: Bool = false

    /// Error message
    @Published var errorMessage: String?

    /// Tracks whether there are unsaved changes
    @Published var hasUnsavedChanges: Bool = false

    /// URL of the project file
    var projectURL: URL?

    // MARK: - Engines

    /// Preview engine
    let previewEngine: PreviewEngine

    /// Export engine
    let exportEngine: ExportEngine

    // MARK: - Properties

    /// Undo stack for snapshot-based undo/redo
    let undoStack = UndoStack()

    /// Cancellation tokens
    private var cancellables = Set<AnyCancellable>()

    /// Whether a binding edit is in progress (for debouncing undo snapshots)
    private var isInBindingEdit: Bool = false

    /// Timer to reset binding edit state after inactivity
    private var bindingEditTimer: Timer?

    // MARK: - Computed Properties

    /// Total duration
    var duration: TimeInterval {
        project.media.duration
    }

    /// Frame rate
    var frameRate: Double {
        project.media.frameRate
    }

    /// Binding to the timeline
    var timelineBinding: Binding<Timeline> {
        Binding(
            get: { self.project.timeline },
            set: { newValue in
                self.saveBindingUndoSnapshot()
                self.project.timeline = newValue
                self.hasUnsavedChanges = true
                self.invalidatePreviewCache()
            }
        )
    }

    /// Binding to render settings
    var renderSettingsBinding: Binding<RenderSettings> {
        Binding(
            get: { self.project.renderSettings },
            set: { newValue in
                self.saveBindingUndoSnapshot()
                self.project.renderSettings = newValue
                self.hasUnsavedChanges = true
                self.updateRenderSettings()
            }
        )
    }

    /// Whether window mode is enabled (nil displayID indicates window capture)
    var isWindowMode: Bool {
        project.captureMeta.displayID == nil
    }

    /// Binding to the trim start value
    var trimStartBinding: Binding<TimeInterval> {
        Binding(
            get: { self.project.timeline.trimStart },
            set: { newValue in
                self.saveBindingUndoSnapshot()
                self.project.timeline.trimStart = newValue
                self.hasUnsavedChanges = true
                self.previewEngine.updateTrimRange(
                    start: newValue,
                    end: self.project.timeline.trimEnd
                )
            }
        )
    }

    /// Binding to the trim end value
    var trimEndBinding: Binding<TimeInterval?> {
        Binding(
            get: { self.project.timeline.trimEnd },
            set: { newValue in
                self.saveBindingUndoSnapshot()
                self.project.timeline.trimEnd = newValue
                self.hasUnsavedChanges = true
                self.previewEngine.updateTrimRange(
                    start: self.project.timeline.trimStart,
                    end: newValue
                )
            }
        )
    }

    /// Trimmed duration
    var trimmedDuration: TimeInterval {
        project.timeline.trimmedDuration
    }

    /// Configure the trim range
    func setTrimRange(start: TimeInterval, end: TimeInterval?) {
        saveBindingUndoSnapshot()
        project.timeline.trimStart = start
        project.timeline.trimEnd = end
        hasUnsavedChanges = true
        previewEngine.updateTrimRange(start: start, end: end)
    }

    /// Reset the trim range
    func resetTrim() {
        setTrimRange(start: 0, end: nil)
    }

    // MARK: - Initialization

    init(project: ScreenizeProject, projectURL: URL? = nil) {
        self.project = project
        self.projectURL = projectURL
        self.previewEngine = PreviewEngine(previewScale: 0.5)
        self.exportEngine = ExportEngine()

        if self.project.timeline.cameraTrack == nil {
            self.project.timeline.tracks.insert(.camera(CameraTrack()), at: 0)
        }
        if self.project.timeline.cursorTrackV2 == nil {
            self.project.timeline.tracks.append(.cursor(CursorTrackV2()))
        }
        if self.project.timeline.keystrokeTrackV2 == nil {
            self.project.timeline.tracks.append(.keystroke(KeystrokeTrackV2()))
        }

        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Synchronize preview engine state
        previewEngine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.isPlaying = playing
            }
            .store(in: &cancellables)

        previewEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.currentTime = time
            }
            .store(in: &cancellables)
    }

    // MARK: - Undo/Redo

    /// Capture the current state as a snapshot
    private func currentSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            timeline: project.timeline,
            renderSettings: project.renderSettings,
            selectedSegmentID: selectedSegmentID,
            selectedSegmentTrackType: selectedSegmentTrackType
        )
    }

    /// Save a snapshot before a mutation
    private func saveUndoSnapshot() {
        undoStack.push(currentSnapshot())
    }

    /// Save a snapshot for binding edits with debounce (coalesces rapid changes)
    private func saveBindingUndoSnapshot() {
        if !isInBindingEdit {
            isInBindingEdit = true
            saveUndoSnapshot()
        }
        // Reset debounce timer
        bindingEditTimer?.invalidate()
        bindingEditTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isInBindingEdit = false
            }
        }
    }

    /// Undo the last change
    func undo() {
        guard let snapshot = undoStack.undo(current: currentSnapshot()) else { return }
        applySnapshot(snapshot)
    }

    /// Redo the last undone change
    func redo() {
        guard let snapshot = undoStack.redo(current: currentSnapshot()) else { return }
        applySnapshot(snapshot)
    }

    /// Apply a snapshot to restore editor state
    private func applySnapshot(_ snapshot: EditorSnapshot) {
        project.timeline = snapshot.timeline
        project.renderSettings = snapshot.renderSettings
        selectedSegmentID = snapshot.selectedSegmentID
        selectedSegmentTrackType = snapshot.selectedSegmentTrackType
        hasUnsavedChanges = true
        invalidatePreviewCache()
        updateRenderSettings()
    }

    // MARK: - Lifecycle

    /// Initialize the editor
    func setup(autoGenerateKeyframes: Bool = false) async {
        isLoading = true
        errorMessage = nil

        await previewEngine.setup(with: project)

        // Run smart generation when the timeline is empty and auto-generation is enabled
        if autoGenerateKeyframes && isTimelineEmpty {
            await runSmartGeneration()
        }

        isLoading = false
    }

    /// Check whether the timeline is empty
    private var isTimelineEmpty: Bool {
        project.timeline.totalSegmentCount == 0
    }

    // MARK: - Smart Generation

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
                print("Smart generation skipped: No mouse data available")
                isLoading = false
                return
            }

            let settings = GeneratorSettings.default

            // 2. Generate transform track (includes expensive video analysis)
            var transformTrack: TransformTrack?
            if selection.contains(.transform) {
                let frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis]
                if let cached = project.frameAnalysisCache, !cached.isEmpty {
                    frameAnalysis = cached
                } else {
                    let analyzer = VideoFrameAnalyzer()
                    frameAnalysis = try await analyzer.analyze(
                        videoURL: project.media.videoURL,
                        progressHandler: { progress in
                            Task { @MainActor in
                                print("Frame analysis: \(Int(progress.percentage * 100))%")
                            }
                        }
                    )
                    project.frameAnalysisCache = frameAnalysis
                }

                // Load UI state samples from event streams
                let uiStateSamples: [UIStateSample]
                let screenBounds: CGSize
                if let interop = project.interop, let packageURL = projectURL {
                    uiStateSamples = EventStreamLoader.loadUIStateSamples(
                        from: packageURL,
                        interop: interop
                    )
                } else {
                    uiStateSamples = []
                }
                screenBounds = project.media.pixelSize

                transformTrack = SmartZoomGenerator().generate(
                    from: mouseDataSource,
                    frameAnalysisArray: frameAnalysis,
                    uiStateSamples: uiStateSamples,
                    screenBounds: screenBounds,
                    settings: settings.smartZoom
                )
            }

            let cursorTrack = selection.contains(.cursor)
                ? ClickCursorGenerator().generate(from: mouseDataSource, settings: settings) : nil
            let keystrokeTrack = selection.contains(.keystroke)
                ? KeystrokeGenerator().generate(from: mouseDataSource, settings: settings) : nil

            updateTimeline(
                transformTrack: transformTrack,
                cursorTrack: cursorTrack,
                keystrokeTrack: keystrokeTrack
            )

            print("Smart generation completed for \(selection.count) track type(s)")

            hasUnsavedChanges = true
            invalidatePreviewCache()

        } catch {
            print("Smart generation failed: \(error.localizedDescription)")
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

    /// Apply generated keyframe tracks after converting them into segment tracks.
    private func updateTimeline(
        transformTrack: TransformTrack? = nil,
        cursorTrack: CursorTrack? = nil,
        keystrokeTrack: KeystrokeTrack? = nil
    ) {
        if let transformTrack = transformTrack {
            let convertedTrack = convertToCameraTrack(transformTrack)
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) {
                project.timeline.tracks[index] = .camera(convertedTrack)
            } else {
                project.timeline.tracks.insert(.camera(convertedTrack), at: 0)
            }
        }

        if let cursorTrack = cursorTrack {
            let convertedTrack = convertToCursorTrack(cursorTrack)
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }) {
                project.timeline.tracks[index] = .cursor(convertedTrack)
            } else {
                project.timeline.tracks.append(.cursor(convertedTrack))
            }
        }

        if let keystrokeTrack = keystrokeTrack {
            let convertedTrack = convertToKeystrokeTrack(keystrokeTrack)
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }) {
                project.timeline.tracks[index] = .keystroke(convertedTrack)
            } else {
                project.timeline.tracks.append(.keystroke(convertedTrack))
            }
        }
    }

    /// Cleanup resources
    func cleanup() {
        previewEngine.cleanup()
    }

    // MARK: - Playback Control

    /// Toggle playback
    func togglePlayback() {
        previewEngine.togglePlayback()
    }

    /// Start playback
    func play() {
        previewEngine.play()
    }

    /// Pause playback
    func pause() {
        previewEngine.pause()
    }

    /// Seek to a specific time
    func seek(to time: TimeInterval) async {
        await previewEngine.seek(to: time)
    }

    /// Seek to the beginning
    func seekToStart() async {
        await previewEngine.seekToStart()
    }

    /// Seek to the end
    func seekToEnd() async {
        await previewEngine.seekToEnd()
    }

    /// Step backward one frame
    func stepBackward() async {
        let frameTime = 1.0 / frameRate
        let newTime = max(0, currentTime - frameTime)
        await seek(to: newTime)
    }

    /// Step forward one frame
    func stepForward() async {
        let frameTime = 1.0 / frameRate
        let newTime = min(duration, currentTime + frameTime)
        await seek(to: newTime)
    }

    // MARK: - Keyframe Management

    /// Add a segment at the current time.
    func addSegment(to trackType: TrackType) {
        addSegment(to: trackType, at: currentTime)
    }

    /// Add a segment at a specified time.
    func addSegment(to trackType: TrackType, at time: TimeInterval) {
        saveUndoSnapshot()
        switch trackType {
        case .transform:
            addTransformSegment(at: time)
        case .cursor:
            addCursorSegment(at: time)
        case .keystroke:
            addKeystrokeSegment(at: time)
        case .audio:
            break  // TODO: implement audio tracks in the future
        }

        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    private func addTransformSegment(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) else {
            return
        }

        guard case .camera(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let endTime = min(duration, time + 1.0)
        let newSegment = CameraSegment(
            startTime: time,
            endTime: max(time + 0.05, endTime),
            startTransform: .identity,
            endTransform: .identity
        )

        _ = track.addSegment(newSegment)

        project.timeline.tracks[trackIndex] = .camera(track)
        selectedSegmentID = newSegment.id
        selectedSegmentTrackType = .transform
    }

    private func addCursorSegment(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }) else {
            return
        }

        guard case .cursor(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let newSegment = CursorSegment(
            startTime: time,
            endTime: min(duration, time + 1.0),
            style: .arrow,
            visible: true,
            scale: 2.5
        )

        _ = track.addSegment(newSegment)

        project.timeline.tracks[trackIndex] = .cursor(track)
        selectedSegmentID = newSegment.id
        selectedSegmentTrackType = .cursor
    }

    private func addKeystrokeSegment(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }) else {
            return
        }

        guard case .keystroke(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let newSegment = KeystrokeSegment(
            startTime: time,
            endTime: min(duration, time + 1.5),
            displayText: "⌘"
        )

        track.addSegment(newSegment)

        project.timeline.tracks[trackIndex] = .keystroke(track)
        selectedSegmentID = newSegment.id
        selectedSegmentTrackType = .keystroke
        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    /// Delete a segment.
    func deleteSegment(_ id: UUID, from trackType: TrackType) {
        saveUndoSnapshot()
        switch trackType {
        case .transform:
            deleteTransformSegment(id)
        case .cursor:
            deleteCursorSegment(id)
        case .keystroke:
            deleteKeystrokeSegment(id)
        case .audio:
            break  // TODO: implement audio tracks in the future
        }

        if selectedSegmentID == id {
            selectedSegmentID = nil
        }

        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    private func deleteTransformSegment(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) else {
            return
        }

        guard case .camera(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.removeSegment(id: id)
        project.timeline.tracks[trackIndex] = .camera(track)
    }

    private func deleteCursorSegment(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }) else {
            return
        }

        guard case .cursor(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.removeSegment(id: id)
        project.timeline.tracks[trackIndex] = .cursor(track)
    }

    private func deleteKeystrokeSegment(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }) else {
            return
        }

        guard case .keystroke(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.removeSegment(id: id)
        project.timeline.tracks[trackIndex] = .keystroke(track)
    }

    /// Update segment start/end time as a single edit operation.
    @discardableResult
    func updateSegmentTimeRange(_ id: UUID, startTime: TimeInterval, endTime: TimeInterval) -> Bool {
        let clampedStart = max(0, min(duration, startTime))
        let clampedEnd = min(duration, max(clampedStart + 0.001, endTime))

        for (trackIndex, anyTrack) in project.timeline.tracks.enumerated() {
            switch anyTrack {
            case .camera(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }

                saveUndoSnapshot()
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else {
                    return false
                }

                project.timeline.tracks[trackIndex] = .camera(track)
                hasUnsavedChanges = true
                invalidatePreviewCache()
                return true

            case .cursor(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }

                saveUndoSnapshot()
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else {
                    return false
                }

                project.timeline.tracks[trackIndex] = .cursor(track)
                hasUnsavedChanges = true
                invalidatePreviewCache()
                return true

            case .keystroke(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }

                saveUndoSnapshot()
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else {
                    return false
                }

                project.timeline.tracks[trackIndex] = .keystroke(track)
                hasUnsavedChanges = true
                invalidatePreviewCache()
                return true
            }
        }

        return false
    }

    // MARK: - Selection

    /// Select a segment.
    func selectSegment(_ id: UUID, trackType: TrackType) {
        selectedSegmentID = id
        selectedSegmentTrackType = trackType
    }

    /// Delete all segments.
    func deleteAllSegments() {
        saveUndoSnapshot()
        for (trackIndex, anyTrack) in project.timeline.tracks.enumerated() {
            switch anyTrack {
            case .camera(var track):
                track.segments.removeAll()
                project.timeline.tracks[trackIndex] = .camera(track)
            case .cursor(var track):
                track.segments.removeAll()
                project.timeline.tracks[trackIndex] = .cursor(track)
            case .keystroke(var track):
                track.segments.removeAll()
                project.timeline.tracks[trackIndex] = .keystroke(track)
            }
        }

        selectedSegmentID = nil
        selectedSegmentTrackType = nil
        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    /// Clear the selection
    func clearSelection() {
        selectedSegmentID = nil
        selectedSegmentTrackType = nil
    }

    /// Jump to the selected segment.
    func goToSelectedSegment() async {
        guard let id = selectedSegmentID,
              let trackType = selectedSegmentTrackType else {
            return
        }

        // Locate the segment start time
        let time: TimeInterval?

        switch trackType {
        case .transform:
            if let track = project.timeline.cameraTrack,
               let segment = track.segments.first(where: { $0.id == id }) {
                time = segment.startTime
            } else {
                time = nil
            }

        case .cursor:
            if let track = project.timeline.cursorTrackV2,
               let segment = track.segments.first(where: { $0.id == id }) {
                time = segment.startTime
            } else {
                time = nil
            }

        case .keystroke:
            if let track = project.timeline.keystrokeTrackV2,
               let segment = track.segments.first(where: { $0.id == id }) {
                time = segment.startTime
            } else {
                time = nil
            }

        case .audio:
            time = nil  // TODO: support audio tracks later
        }

        if let time = time {
            await seek(to: time)
        }
    }

    // MARK: - Cache Management

    /// Invalidate the preview cache (updates the evaluator on timeline changes)
    func invalidatePreviewCache() {
        previewEngine.invalidateAllCache(with: project.timeline)
    }

    /// Update render settings (for window-style changes)
    func updateRenderSettings() {
        previewEngine.updateRenderSettings(project.renderSettings)
    }

    // MARK: - Segment Change Notification

    /// Notify that a segment changed (called from the inspector)
    func notifySegmentChanged() {
        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

}

private extension EditorViewModel {
    func convertToCameraTrack(_ track: TransformTrack) -> CameraTrack {
        let sorted = track.keyframes.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else {
            return CameraTrack(id: track.id, name: track.name, isEnabled: track.isEnabled, segments: [])
        }

        var segments: [CameraSegment] = []
        for index in 0..<sorted.count {
            let current = sorted[index]
            let nextTime = index + 1 < sorted.count ? sorted[index + 1].time : duration
            let endTime = max(current.time + 0.001, nextTime)
            segments.append(
                CameraSegment(
                    startTime: current.time,
                    endTime: min(duration, endTime),
                    startTransform: current.value,
                    endTransform: index + 1 < sorted.count ? sorted[index + 1].value : current.value,
                    interpolation: current.easing
                )
            )
        }

        return CameraTrack(id: track.id, name: track.name, isEnabled: track.isEnabled, segments: segments)
    }

    func convertToCursorTrack(_ track: CursorTrack) -> CursorTrackV2 {
        let sorted = (track.styleKeyframes ?? []).sorted { $0.time < $1.time }

        guard !sorted.isEmpty else {
            return CursorTrackV2(
                id: track.id,
                name: track.name,
                isEnabled: track.isEnabled,
                segments: [
                    CursorSegment(
                        startTime: 0,
                        endTime: duration,
                        style: track.defaultStyle,
                        visible: track.defaultVisible,
                        scale: track.defaultScale,
                        position: nil
                    ),
                ]
            )
        }

        var segments: [CursorSegment] = []
        for index in 0..<sorted.count {
            let current = sorted[index]
            let endTime = index + 1 < sorted.count ? sorted[index + 1].time : duration
            segments.append(
                CursorSegment(
                    startTime: current.time,
                    endTime: max(current.time + 0.001, endTime),
                    style: current.style,
                    visible: current.visible,
                    scale: current.scale,
                    position: current.position
                )
            )
        }

        return CursorTrackV2(id: track.id, name: track.name, isEnabled: track.isEnabled, segments: segments)
    }

    func convertToKeystrokeTrack(_ track: KeystrokeTrack) -> KeystrokeTrackV2 {
        let segments = track.keyframes.map { keyframe in
            KeystrokeSegment(
                id: keyframe.id,
                startTime: keyframe.time,
                endTime: keyframe.endTime,
                displayText: keyframe.displayText,
                position: keyframe.position,
                fadeInDuration: keyframe.fadeInDuration,
                fadeOutDuration: keyframe.fadeOutDuration
            )
        }

        return KeystrokeTrackV2(id: track.id, name: track.name, isEnabled: track.isEnabled, segments: segments)
    }
}

