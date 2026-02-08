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

    /// Selected keyframe ID
    @Published var selectedKeyframeID: UUID?

    /// Selected track type
    @Published var selectedTrackType: TrackType?

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

        // Migrate: add keystroke track if missing (for projects created before this feature)
        if self.project.timeline.keystrokeTrack == nil {
            self.project.timeline.tracks.append(.keystroke(KeystrokeTrack()))
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
            selectedKeyframeID: selectedKeyframeID,
            selectedTrackType: selectedTrackType
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
        selectedKeyframeID = snapshot.selectedKeyframeID
        selectedTrackType = snapshot.selectedTrackType
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
        let transformCount = project.timeline.transformTrack?.keyframes.count ?? 0
        let rippleCount = project.timeline.rippleTrack?.keyframes.count ?? 0
        return transformCount == 0 && rippleCount == 0
    }

    // MARK: - Smart Generation

    /// Auto-generate keyframes using mouse data
    /// - Parameter selection: Which track types to generate. Unselected types are preserved.
    func runSmartGeneration(
        for selection: Set<TrackType> = [.transform, .ripple, .cursor, .keystroke]
    ) async {
        await runSmartZoomGeneration(for: selection)
    }

    /// Smart generation with selective track types (video analysis + UI state)
    private func runSmartZoomGeneration(for selection: Set<TrackType>) async {
        saveUndoSnapshot()
        guard project.media.mouseDataExists else {
            print("Smart generation skipped: No mouse data available")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // 1. Load mouse data
            let mouseRecording = try MouseRecording.load(from: project.media.mouseDataURL)

            let mouseDataSource = MouseRecordingAdapter(
                recording: mouseRecording,
                duration: project.media.duration,
                frameRate: project.media.frameRate
            )

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

                let uiStateSamples = mouseRecording.uiStateSamples
                transformTrack = SmartZoomGenerator().generate(
                    from: mouseDataSource,
                    frameAnalysisArray: frameAnalysis,
                    uiStateSamples: uiStateSamples,
                    screenBounds: CGSize(
                        width: mouseRecording.screenBounds.width,
                        height: mouseRecording.screenBounds.height
                    ),
                    settings: settings.smartZoom
                )
            }

            let rippleTrack = selection.contains(.ripple)
                ? RippleGenerator().generate(from: mouseDataSource, settings: settings) : nil
            let cursorTrack = selection.contains(.cursor)
                ? ClickCursorGenerator().generate(from: mouseDataSource, settings: settings) : nil
            let keystrokeTrack = selection.contains(.keystroke)
                ? KeystrokeGenerator().generate(from: mouseDataSource, settings: settings) : nil

            updateTimeline(
                transformTrack: transformTrack,
                rippleTrack: rippleTrack,
                cursorTrack: cursorTrack,
                keystrokeTrack: keystrokeTrack
            )

            print("Smart generation completed for \(selection.count) track type(s)")

            hasUnsavedChanges = true
            invalidatePreviewCache()

        } catch {
            print("Smart generation failed: \(error.localizedDescription)")
            errorMessage = "Failed to generate keyframes: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Invalidate the frame analysis cache
    func invalidateFrameAnalysisCache() {
        project.frameAnalysisCache = nil
        hasUnsavedChanges = true
    }

    /// Apply the generated tracks to the timeline (nil = preserve existing)
    private func updateTimeline(
        transformTrack: TransformTrack? = nil,
        rippleTrack: RippleTrack? = nil,
        cursorTrack: CursorTrack? = nil,
        keystrokeTrack: KeystrokeTrack? = nil
    ) {
        // Update the transform track (only if provided)
        if let transformTrack = transformTrack {
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) {
                project.timeline.tracks[index] = .transform(transformTrack)
            } else {
                project.timeline.tracks.append(.transform(transformTrack))
            }
        }

        // Update the ripple track (only if provided)
        if let rippleTrack = rippleTrack {
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .ripple }) {
                project.timeline.tracks[index] = .ripple(rippleTrack)
            } else {
                project.timeline.tracks.append(.ripple(rippleTrack))
            }
        }

        // Update the cursor track (if present)
        if let cursorTrack = cursorTrack {
            if let index = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }) {
                project.timeline.tracks[index] = .cursor(cursorTrack)
            } else {
                project.timeline.tracks.append(.cursor(cursorTrack))
            }
        }

        // Update the keystroke track (if present)
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

    /// Add a keyframe at the current time
    func addKeyframe(to trackType: TrackType) {
        addKeyframe(to: trackType, at: currentTime)
    }

    /// Add a keyframe at a specified time
    func addKeyframe(to trackType: TrackType, at time: TimeInterval) {
        saveUndoSnapshot()
        switch trackType {
        case .transform:
            addTransformKeyframe(at: time)
        case .ripple:
            addRippleKeyframe(at: time)
        case .cursor:
            addCursorKeyframe(at: time)
        case .keystroke:
            addKeystrokeKeyframe(at: time)
        case .audio:
            break  // TODO: implement audio tracks in the future
        }

        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    private func addTransformKeyframe(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) else {
            return
        }

        guard case .transform(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        // Create a keyframe based on the current state
        let newKeyframe = TransformKeyframe(
            time: time,
            zoom: 1.0,
            centerX: 0.5,
            centerY: 0.5
        )

        track.keyframes.append(newKeyframe)
        track.keyframes.sort { $0.time < $1.time }

        project.timeline.tracks[trackIndex] = .transform(track)
        selectedKeyframeID = newKeyframe.id
        selectedTrackType = .transform
    }

    private func addRippleKeyframe(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .ripple }) else {
            return
        }

        guard case .ripple(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let newKeyframe = RippleKeyframe(
            time: time,
            x: 0.5,
            y: 0.5
        )

        track.keyframes.append(newKeyframe)
        track.keyframes.sort { $0.time < $1.time }

        project.timeline.tracks[trackIndex] = .ripple(track)
        selectedKeyframeID = newKeyframe.id
        selectedTrackType = .ripple
    }

    private func addCursorKeyframe(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }) else {
            return
        }

        guard case .cursor(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let newKeyframe = CursorStyleKeyframe(
            time: time,
            style: .arrow,
            visible: true,
            scale: 1.0
        )

        var keyframes = track.styleKeyframes ?? []
        keyframes.append(newKeyframe)
        keyframes.sort { $0.time < $1.time }
        track = CursorTrack(
            id: track.id,
            name: track.name,
            isEnabled: track.isEnabled,
            defaultStyle: track.defaultStyle,
            defaultScale: track.defaultScale,
            defaultVisible: track.defaultVisible,
            styleKeyframes: keyframes
        )

        project.timeline.tracks[trackIndex] = .cursor(track)
        selectedKeyframeID = newKeyframe.id
        selectedTrackType = .cursor
    }

    private func addKeystrokeKeyframe(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }) else {
            return
        }

        guard case .keystroke(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let newKeyframe = KeystrokeKeyframe(
            time: time,
            displayText: "⌘"
        )

        track.keyframes.append(newKeyframe)
        track.keyframes.sort { $0.time < $1.time }

        project.timeline.tracks[trackIndex] = .keystroke(track)
        selectedKeyframeID = newKeyframe.id
        selectedTrackType = .keystroke
        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    /// Delete a keyframe
    func deleteKeyframe(_ id: UUID, from trackType: TrackType) {
        saveUndoSnapshot()
        switch trackType {
        case .transform:
            deleteTransformKeyframe(id)
        case .ripple:
            deleteRippleKeyframe(id)
        case .cursor:
            deleteCursorKeyframe(id)
        case .keystroke:
            deleteKeystrokeKeyframe(id)
        case .audio:
            break  // TODO: implement audio tracks in the future
        }

        if selectedKeyframeID == id {
            selectedKeyframeID = nil
        }

        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    private func deleteTransformKeyframe(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) else {
            return
        }

        guard case .transform(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.keyframes.removeAll { $0.id == id }
        project.timeline.tracks[trackIndex] = .transform(track)
    }

    private func deleteRippleKeyframe(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .ripple }) else {
            return
        }

        guard case .ripple(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.keyframes.removeAll { $0.id == id }
        project.timeline.tracks[trackIndex] = .ripple(track)
    }

    private func deleteCursorKeyframe(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }) else {
            return
        }

        guard case .cursor(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        var keyframes = track.styleKeyframes ?? []
        keyframes.removeAll { $0.id == id }
        track = CursorTrack(
            id: track.id,
            name: track.name,
            isEnabled: track.isEnabled,
            defaultStyle: track.defaultStyle,
            defaultScale: track.defaultScale,
            defaultVisible: track.defaultVisible,
            styleKeyframes: keyframes
        )
        project.timeline.tracks[trackIndex] = .cursor(track)
    }

    private func deleteKeystrokeKeyframe(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }) else {
            return
        }

        guard case .keystroke(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.keyframes.removeAll { $0.id == id }
        project.timeline.tracks[trackIndex] = .keystroke(track)
    }

    /// Update a keyframe time
    func updateKeyframeTime(_ id: UUID, to newTime: TimeInterval) {
        saveBindingUndoSnapshot()
        // Find and update the keyframe time
        for (trackIndex, anyTrack) in project.timeline.tracks.enumerated() {
            switch anyTrack {
            case .transform(var track):
                if let keyframeIndex = track.keyframes.firstIndex(where: { $0.id == id }) {
                    track.keyframes[keyframeIndex].time = newTime
                    track.keyframes.sort { $0.time < $1.time }
                    project.timeline.tracks[trackIndex] = .transform(track)
                    hasUnsavedChanges = true
                    invalidatePreviewCache()
                    return
                }

            case .ripple(var track):
                if let keyframeIndex = track.keyframes.firstIndex(where: { $0.id == id }) {
                    track.keyframes[keyframeIndex].time = newTime
                    track.keyframes.sort { $0.time < $1.time }
                    project.timeline.tracks[trackIndex] = .ripple(track)
                    hasUnsavedChanges = true
                    invalidatePreviewCache()
                    return
                }

            case .cursor(var track):
                if var keyframes = track.styleKeyframes,
                   let keyframeIndex = keyframes.firstIndex(where: { $0.id == id }) {
                    keyframes[keyframeIndex].time = newTime
                    keyframes.sort { $0.time < $1.time }
                    track = CursorTrack(
                        id: track.id,
                        name: track.name,
                        isEnabled: track.isEnabled,
                        defaultStyle: track.defaultStyle,
                        defaultScale: track.defaultScale,
                        defaultVisible: track.defaultVisible,
                        styleKeyframes: keyframes
                    )
                    project.timeline.tracks[trackIndex] = .cursor(track)
                    hasUnsavedChanges = true
                    invalidatePreviewCache()
                    return
                }

            case .keystroke(var track):
                if let keyframeIndex = track.keyframes.firstIndex(where: { $0.id == id }) {
                    track.keyframes[keyframeIndex].time = newTime
                    track.keyframes.sort { $0.time < $1.time }
                    project.timeline.tracks[trackIndex] = .keystroke(track)
                    hasUnsavedChanges = true
                    invalidatePreviewCache()
                    return
                }
            }
        }
    }

    // MARK: - Selection

    /// Select a keyframe
    func selectKeyframe(_ id: UUID, trackType: TrackType) {
        selectedKeyframeID = id
        selectedTrackType = trackType
    }

    /// Delete all keyframes
    func deleteAllKeyframes() {
        saveUndoSnapshot()
        for (trackIndex, anyTrack) in project.timeline.tracks.enumerated() {
            switch anyTrack {
            case .transform(var track):
                track.keyframes.removeAll()
                project.timeline.tracks[trackIndex] = .transform(track)
            case .ripple(var track):
                track.keyframes.removeAll()
                project.timeline.tracks[trackIndex] = .ripple(track)
            case .cursor(var track):
                track = CursorTrack(
                    id: track.id,
                    name: track.name,
                    isEnabled: track.isEnabled,
                    defaultStyle: track.defaultStyle,
                    defaultScale: track.defaultScale,
                    defaultVisible: track.defaultVisible,
                    styleKeyframes: nil
                )
                project.timeline.tracks[trackIndex] = .cursor(track)
            case .keystroke(var track):
                track.keyframes.removeAll()
                project.timeline.tracks[trackIndex] = .keystroke(track)
            }
        }

        selectedKeyframeID = nil
        selectedTrackType = nil
        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    /// Clear the selection
    func clearSelection() {
        selectedKeyframeID = nil
    }

    /// Jump to the selected keyframe
    func goToSelectedKeyframe() async {
        guard let id = selectedKeyframeID,
              let trackType = selectedTrackType else {
            return
        }

        // Locate the keyframe time
        let time: TimeInterval?

        switch trackType {
        case .transform:
            if let track = project.timeline.transformTrack,
               let keyframe = track.keyframes.first(where: { $0.id == id }) {
                time = keyframe.time
            } else {
                time = nil
            }

        case .ripple:
            if let track = project.timeline.rippleTrack,
               let keyframe = track.keyframes.first(where: { $0.id == id }) {
                time = keyframe.time
            } else {
                time = nil
            }

        case .cursor:
            if let track = project.timeline.cursorTrack,
               let keyframes = track.styleKeyframes,
               let keyframe = keyframes.first(where: { $0.id == id }) {
                time = keyframe.time
            } else {
                time = nil
            }

        case .keystroke:
            if let track = project.timeline.keystrokeTrack,
               let keyframe = track.keyframes.first(where: { $0.id == id }) {
                time = keyframe.time
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

    // MARK: - Keyframe Change Notification

    /// Notify that a keyframe changed (called from the inspector)
    func notifyKeyframeChanged() {
        hasUnsavedChanges = true
        invalidatePreviewCache()
    }
}

// MARK: - MouseRecordingAdapter

/// Adapter that converts MouseRecording into a MouseDataSource
struct MouseRecordingAdapter: MouseDataSource {
    let recording: MouseRecording
    let duration: TimeInterval
    let frameRate: Double

    var positions: [MousePositionData] {
        recording.positions.map { pos in
            // Convert screen coordinates to normalized space
            let normalizedX = pos.x / recording.screenBounds.width
            let normalizedY = pos.y / recording.screenBounds.height
            return MousePositionData(
                time: pos.timestamp,
                x: normalizedX,
                y: normalizedY,
                appBundleID: nil,
                elementInfo: nil
            )
        }
    }

    var clicks: [ClickEventData] {
        recording.clicks.map { click in
            // Convert screen coordinates into normalized values
            let normalizedX = click.x / recording.screenBounds.width
            let normalizedY = click.y / recording.screenBounds.height

            // Convert ClickType (MouseEvent → ClickEventData)
            let clickType: ClickEventData.ClickType
            switch click.type {
            case .left:
                clickType = .leftDown
            case .right:
                clickType = .rightDown
            }

            return ClickEventData(
                time: click.timestamp,
                x: normalizedX,
                y: normalizedY,
                clickType: clickType,
                appBundleID: click.targetElement?.applicationName,
                elementInfo: click.targetElement
            )
        }
    }

    var keyboardEvents: [KeyboardEventData] {
        recording.keyboardEvents.map { event in
            let eventType: KeyboardEventData.EventType
            switch event.type {
            case .keyDown:
                eventType = .keyDown
            case .keyUp:
                eventType = .keyUp
            }

            var modifiers: KeyboardEventData.ModifierFlags = []
            if event.modifiers.shift { modifiers.insert(.shift) }
            if event.modifiers.control { modifiers.insert(.control) }
            if event.modifiers.option { modifiers.insert(.option) }
            if event.modifiers.command { modifiers.insert(.command) }

            return KeyboardEventData(
                time: event.timestamp,
                keyCode: event.keyCode,
                eventType: eventType,
                modifiers: modifiers,
                character: event.character
            )
        }
    }

    var dragEvents: [DragEventData] {
        recording.dragEvents.map { drag in
            // Convert screen coordinates to normalized space
            let normalizedStartX = drag.startX / recording.screenBounds.width
            let normalizedStartY = drag.startY / recording.screenBounds.height
            let normalizedEndX = drag.endX / recording.screenBounds.width
            let normalizedEndY = drag.endY / recording.screenBounds.height

            // Convert the drag type
            let dragType: DragEventData.DragType
            switch drag.type {
            case .selection:
                dragType = .selection
            case .move:
                dragType = .move
            case .resize:
                dragType = .resize
            }

            return DragEventData(
                startTime: drag.startTimestamp,
                endTime: drag.endTimestamp,
                startPosition: NormalizedPoint(x: normalizedStartX, y: normalizedStartY),
                endPosition: NormalizedPoint(x: normalizedEndX, y: normalizedEndY),
                dragType: dragType
            )
        }
    }
}
