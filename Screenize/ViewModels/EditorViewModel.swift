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

    /// Segment selection (supports multi-select)
    @Published var selection = SegmentSelection()

    /// Internal clipboard for segment copy/paste
    var clipboard: [CopiedSegment] = []

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
        if self.project.timeline.systemAudioTrack == nil && self.project.media.systemAudioExists {
            self.project.timeline.tracks.append(.audio(AudioTrack(
                id: UUID(),
                name: "System Audio",
                isEnabled: true,
                audioSource: .system,
                segments: [
                    AudioSegment(startTime: 0, endTime: self.project.timeline.duration)
                ]
            )))
        }
        if self.project.timeline.micAudioTrack == nil && self.project.media.micAudioExists {
            self.project.timeline.tracks.append(.audio(AudioTrack(
                id: UUID(),
                name: "Mic Audio",
                isEnabled: true,
                audioSource: .microphone,
                segments: [
                    AudioSegment(startTime: 0, endTime: self.project.timeline.duration)
                ]
            )))
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
            selection: selection
        )
    }

    /// Save a snapshot before a mutation
    func saveUndoSnapshot() {
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
        selection = snapshot.selection
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
                            print("Frame analysis: \(Int(progress.percentage * 100))%")
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

            // 4. Run V2 smart generation pipeline
            let generated = SmartGeneratorV2().generate(
                from: mouseDataSource,
                uiStateSamples: uiStateSamples,
                frameAnalysis: frameAnalysis,
                screenBounds: project.media.pixelSize,
                settings: .default
            )

            // 5. Apply selected tracks
            updateTimeline(
                cameraTrack: selection.contains(.transform) ? generated.cameraTrack : nil,
                cursorTrack: selection.contains(.cursor) ? generated.cursorTrack : nil,
                keystrokeTrack: selection.contains(.keystroke) ? generated.keystrokeTrack : nil
            )

            print("Smart generation V2 completed for \(selection.count) track type(s)")

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
            addAudioSegment(at: time)
        }

        hasUnsavedChanges = true
        // Use the selected segment's time range for targeted invalidation
        if let selectedID = selection.single?.id,
           let (start, end) = segmentTimeRange(for: selectedID) {
            invalidatePreviewCache(from: start, to: end)
        } else {
            invalidatePreviewCache()
        }
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
        selection.select(newSegment.id, trackType: .transform)
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
        selection.select(newSegment.id, trackType: .cursor)
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
        selection.select(newSegment.id, trackType: .keystroke)
    }

    /// Delete a segment.
    func deleteSegment(_ id: UUID, from trackType: TrackType) {
        saveUndoSnapshot()

        // Capture time range before deletion for range-based invalidation
        let timeRange = segmentTimeRange(for: id)

        switch trackType {
        case .transform:
            deleteTransformSegment(id)
        case .cursor:
            deleteCursorSegment(id)
        case .keystroke:
            deleteKeystrokeSegment(id)
        case .audio:
            deleteAudioSegment(id)
        }

        selection.remove(id)

        hasUnsavedChanges = true
        if let (start, end) = timeRange {
            invalidatePreviewCache(from: start, to: end)
        } else {
            invalidatePreviewCache()
        }
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

    private func addAudioSegment(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .audio }) else {
            return
        }

        guard case .audio(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let newSegment = AudioSegment(
            startTime: time,
            endTime: min(duration, time + 5.0)
        )

        guard track.addSegment(newSegment) else { return }

        project.timeline.tracks[trackIndex] = .audio(track)
        selection.select(newSegment.id, trackType: .audio)
    }

    private func deleteAudioSegment(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .audio }) else {
            return
        }

        guard case .audio(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.removeSegment(id: id)
        project.timeline.tracks[trackIndex] = .audio(track)
    }

    /// Update segment start/end time as a single edit operation.
    @discardableResult
    func updateSegmentTimeRange(_ id: UUID, startTime: TimeInterval, endTime: TimeInterval) -> Bool {
        saveUndoSnapshot()
        let result = updateSegmentTimeRangeNoUndo(id, startTime: startTime, endTime: endTime)
        if result {
            hasUnsavedChanges = true
            invalidatePreviewCache(from: startTime, to: endTime)
        }
        return result
    }

    /// Batch update multiple segments' time ranges in a single undo operation.
    func batchUpdateSegmentTimeRanges(_ changes: [(UUID, TimeInterval, TimeInterval)]) {
        saveUndoSnapshot()
        var anyChanged = false
        var rangeStart = TimeInterval.greatestFiniteMagnitude
        var rangeEnd = TimeInterval.zero
        for (id, startTime, endTime) in changes {
            if updateSegmentTimeRangeNoUndo(id, startTime: startTime, endTime: endTime) {
                anyChanged = true
                rangeStart = min(rangeStart, startTime)
                rangeEnd = max(rangeEnd, endTime)
            }
        }
        if anyChanged {
            hasUnsavedChanges = true
            invalidatePreviewCache(from: rangeStart, to: rangeEnd)
        }
    }

    /// Update a segment's time range without saving an undo snapshot.
    private func updateSegmentTimeRangeNoUndo(
        _ id: UUID, startTime: TimeInterval, endTime: TimeInterval
    ) -> Bool {
        let clampedStart = max(0, min(duration, startTime))
        let clampedEnd = min(duration, max(clampedStart + 0.001, endTime))

        for (trackIndex, anyTrack) in project.timeline.tracks.enumerated() {
            switch anyTrack {
            case .camera(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else { return false }
                project.timeline.tracks[trackIndex] = .camera(track)
                return true

            case .cursor(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else { return false }
                project.timeline.tracks[trackIndex] = .cursor(track)
                return true

            case .keystroke(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else { return false }
                project.timeline.tracks[trackIndex] = .keystroke(track)
                return true

            case .audio(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else { return false }
                project.timeline.tracks[trackIndex] = .audio(track)
                return true
            }
        }

        return false
    }

    // MARK: - Selection

    /// Select a segment (replaces current selection).
    func selectSegment(_ id: UUID, trackType: TrackType) {
        selection.select(id, trackType: trackType)
    }

    /// Toggle a segment in/out of the selection (for Shift+Click).
    func toggleSegmentSelection(_ id: UUID, trackType: TrackType) {
        selection.toggle(id, trackType: trackType)
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
            case .audio(var track):
                track.segments.removeAll()
                project.timeline.tracks[trackIndex] = .audio(track)
            }
        }

        selection.clear()
        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    /// Clear the selection
    func clearSelection() {
        selection.clear()
    }

    /// Jump to the selected segment (single selection only).
    func goToSelectedSegment() async {
        guard let selected = selection.single else {
            return
        }
        let id = selected.id
        let trackType = selected.trackType

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
            if let track = project.timeline.audioTrack,
               let segment = track.segments.first(where: { $0.id == id }) {
                time = segment.startTime
            } else {
                time = nil
            }
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

    /// Invalidate a specific time range of the preview cache
    func invalidatePreviewCache(from startTime: TimeInterval, to endTime: TimeInterval) {
        previewEngine.invalidateRange(with: project.timeline, from: startTime, to: endTime)
    }

    /// Find the time range of a segment by ID across all tracks
    /// Returns (startTime, endTime) or nil if the segment is not found
    private func segmentTimeRange(for id: UUID) -> (TimeInterval, TimeInterval)? {
        for track in project.timeline.tracks {
            switch track {
            case .camera(let cameraTrack):
                if let segment = cameraTrack.segments.first(where: { $0.id == id }) {
                    return (segment.startTime, segment.endTime)
                }
            case .cursor(let cursorTrack):
                if let segment = cursorTrack.segments.first(where: { $0.id == id }) {
                    return (segment.startTime, segment.endTime)
                }
            case .keystroke(let keystrokeTrack):
                if let segment = keystrokeTrack.segments.first(where: { $0.id == id }) {
                    return (segment.startTime, segment.endTime)
                }
            case .audio(let audioTrack):
                if let segment = audioTrack.segments.first(where: { $0.id == id }) {
                    return (segment.startTime, segment.endTime)
                }
            }
        }
        return nil
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


