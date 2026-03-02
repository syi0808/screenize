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

    /// Camera generation method selection
    @Published var cameraGenerationMethod: CameraGenerationMethod = .continuousCamera

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

    // MARK: - Selection

    /// Select a segment (replaces current selection).
    func selectSegment(_ id: UUID, trackType: TrackType) {
        selection.select(id, trackType: trackType)
    }

    /// Toggle a segment in/out of the selection (for Shift+Click).
    func toggleSegmentSelection(_ id: UUID, trackType: TrackType) {
        selection.toggle(id, trackType: trackType)
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

    /// Update render settings (for window-style changes)
    func updateRenderSettings() {
        previewEngine.updateRenderSettings(project.renderSettings)
    }

    // MARK: - Segment Change Notification

    /// Notify that a segment changed (called from the inspector)
    func notifySegmentChanged() {
        project.timeline.continuousTransforms = nil
        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

}

// MARK: - Camera Generation Method

/// Which camera generation pipeline to use.
enum CameraGenerationMethod: String, CaseIterable {
    case smartGeneration = "Smart Generation"
    case continuousCamera = "Continuous Camera"
}


