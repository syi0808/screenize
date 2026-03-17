import Foundation
import SwiftUI
import Combine
import AppKit
import ScreenCaptureKit

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

    /// Scenario model (runtime-only, loaded from separate file)
    @Published var scenario: Scenario?

    /// ID of the currently selected scenario step
    @Published var selectedStepId: UUID?

    /// Raw events for the scenario (runtime-only, loaded from separate file)
    @Published var scenarioRawEvents: ScenarioRawEvents?

    // MARK: - Engines

    /// Preview engine
    let previewEngine: PreviewEngine

    /// Export engine
    let exportEngine: ExportEngine

    /// Spring simulation cache for smooth camera transitions
    let springCache = SpringSimulationCache()

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
        self.scenario = project.scenario
        self.scenarioRawEvents = project.scenarioRawEvents
        self.previewEngine = PreviewEngine(previewScale: 0.5)
        self.exportEngine = ExportEngine()
        self.previewEngine.springCache = springCache
        self.exportEngine.springCache = springCache

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
            selection: selection,
            scenario: scenario
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
        scenario = snapshot.scenario
        project.scenario = snapshot.scenario
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

        // Populate spring cache for existing projects with .manual segments
        populateSpringCacheIfNeeded()

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

    // MARK: - Spring Cache

    /// Invalidate the spring simulation cache
    func invalidateSpringCache() {
        springCache.invalidate()
    }

    /// Populate the spring cache if it is not already valid
    func populateSpringCacheIfNeeded() {
        guard !springCache.isValid else { return }
        guard let cameraTrack = project.timeline.cameraTrack else { return }
        springCache.populate(segments: cameraTrack.segments)
    }

    // MARK: - Segment Change Notification

    /// Notify that a segment changed (called from the inspector)
    func notifySegmentChanged() {
        hasUnsavedChanges = true
        invalidateSpringCache()
        populateSpringCacheIfNeeded()
        invalidatePreviewCache()
    }

    // MARK: - Scenario Binding

    /// Two-way binding for the scenario, keeping project in sync
    var scenarioBinding: Binding<Scenario?> {
        Binding(
            get: { self.scenario },
            set: { newValue in
                self.scenario = newValue
                self.project.scenario = newValue
                self.hasUnsavedChanges = true
            }
        )
    }

    // MARK: - Scenario Step Operations

    /// Select a step and seek the preview to its start time
    func selectStep(_ id: UUID) {
        selectedStepId = id
        if let scenario, let index = scenario.steps.firstIndex(where: { $0.id == id }) {
            let time = scenario.startTime(forStepAt: index)
            Task { await seek(to: time) }
        }
    }

    /// Clear the current step selection
    func clearStepSelection() {
        selectedStepId = nil
    }

    /// Delete a step by ID
    func deleteStep(_ id: UUID) {
        guard var scenario else { return }
        saveUndoSnapshot()
        scenario.steps.removeAll { $0.id == id }
        self.scenario = scenario
        self.project.scenario = scenario
        self.hasUnsavedChanges = true
        if selectedStepId == id { selectedStepId = nil }
    }

    /// Duplicate a step, inserting the copy immediately after the original
    func duplicateStep(_ id: UUID) {
        guard var scenario else { return }
        guard let index = scenario.steps.firstIndex(where: { $0.id == id }) else { return }
        saveUndoSnapshot()
        let original = scenario.steps[index]
        let copy = ScenarioStep(
            id: UUID(),
            type: original.type,
            description: original.description,
            durationMs: original.durationMs,
            target: original.target,
            path: original.path,
            rawTimeRange: original.rawTimeRange,
            app: original.app,
            keyCombo: original.keyCombo,
            content: original.content,
            typingSpeedMs: original.typingSpeedMs,
            direction: original.direction,
            amount: original.amount
        )
        scenario.steps.insert(copy, at: index + 1)
        self.scenario = scenario
        self.project.scenario = scenario
        self.hasUnsavedChanges = true
    }

    /// Move a step from one index to another
    func moveStep(fromIndex: Int, toIndex: Int) {
        guard var scenario else { return }
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < scenario.steps.count,
              toIndex >= 0, toIndex < scenario.steps.count else { return }
        saveUndoSnapshot()
        let step = scenario.steps.remove(at: fromIndex)
        scenario.steps.insert(step, at: toIndex)
        self.scenario = scenario
        self.project.scenario = scenario
        self.hasUnsavedChanges = true
    }

    /// Insert a step at the given index (clamped to valid range)
    func addStep(_ step: ScenarioStep, at index: Int) {
        guard var scenario else { return }
        saveUndoSnapshot()
        let clampedIndex = min(max(index, 0), scenario.steps.count)
        scenario.steps.insert(step, at: clampedIndex)
        self.scenario = scenario
        self.project.scenario = scenario
        self.hasUnsavedChanges = true
    }

    /// Replace a step (matched by ID) with an updated version.
    /// Uses debounced undo snapshots to coalesce rapid edits (e.g. text field keystrokes).
    func updateStep(_ step: ScenarioStep) {
        guard var scenario else { return }
        guard let index = scenario.steps.firstIndex(where: { $0.id == step.id }) else { return }
        saveBindingUndoSnapshot()
        scenario.steps[index] = step
        self.scenario = scenario
        self.project.scenario = scenario
        self.hasUnsavedChanges = true
    }

    // MARK: - Scenario Waypoint Generation

    /// Extract waypoints from raw events for the given step and assign them to its path
    func generateWaypoints(forStepId id: UUID, hz: Int) {
        guard let rawEvents = scenarioRawEvents,
              var scenario,
              let stepIndex = scenario.steps.firstIndex(where: { $0.id == id }),
              let timeRange = scenario.steps[stepIndex].rawTimeRange else { return }

        saveUndoSnapshot()
        let points = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: hz,
            captureArea: rawEvents.captureArea
        )
        scenario.steps[stepIndex].path = .waypoints(points: points)
        self.scenario = scenario
        self.project.scenario = scenario
        self.hasUnsavedChanges = true
    }

    // MARK: - Replay

    @Published var isReplaying: Bool = false

    private var replayHUDPanel: (any NSObjectProtocol)?

    /// Start full scenario replay with recording.
    @available(macOS 15.0, *)
    func startReplay() async {
        guard let scenario else { return }
        let appState = AppState.shared

        // Restore capture target from project's captureMeta instead of transient selectedTarget
        let target: CaptureTarget
        do {
            target = try await resolveCaptureTarget(from: project.captureMeta)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let config = ReplayConfiguration(
            captureTarget: target,
            backgroundStyle: appState.capture.backgroundStyle,
            frameRate: appState.capture.captureFrameRate,
            isSystemAudioEnabled: appState.capture.isSystemAudioEnabled,
            isMicrophoneEnabled: appState.capture.isMicrophoneEnabled,
            microphoneDevice: appState.capture.selectedMicrophoneDevice
        )

        let coordinator = RecordingCoordinator()
        let player = ScenarioPlayer()
        isReplaying = true

        showReplayHUD(player: player)

        minimizeAppWindows()

        await player.start(
            scenario: scenario,
            mode: .replayAll,
            config: config,
            recordingCoordinator: coordinator
        )

        // Surface any error from the player to the editor UI
        if case .error(_, let message) = player.state {
            errorMessage = message
            // Keep HUD visible briefly so user can read the error before it dismisses
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }

        dismissReplayHUD()
        isReplaying = false
        restoreAppWindows()

        // Create a new project from the replay recording
        await handlePostReplayRecording(coordinator: coordinator, appState: appState)
    }

    /// Start re-rehearsal from a specific step index.
    @available(macOS 15.0, *)
    func startReRehearsal(fromStepIndex: Int) async {
        guard let scenario else { return }
        let appState = AppState.shared

        // Restore capture target from project's captureMeta instead of transient selectedTarget
        let target: CaptureTarget
        do {
            target = try await resolveCaptureTarget(from: project.captureMeta)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let config = ReplayConfiguration(
            captureTarget: target,
            backgroundStyle: appState.capture.backgroundStyle,
            frameRate: appState.capture.captureFrameRate,
            isSystemAudioEnabled: appState.capture.isSystemAudioEnabled,
            isMicrophoneEnabled: appState.capture.isMicrophoneEnabled,
            microphoneDevice: appState.capture.selectedMicrophoneDevice
        )

        let coordinator = RecordingCoordinator()
        let player = ScenarioPlayer()
        isReplaying = true

        showReplayHUD(player: player)

        minimizeAppWindows()

        await player.start(
            scenario: scenario,
            mode: .replayUntilStep(fromStepIndex),
            config: config,
            recordingCoordinator: coordinator
        )

        // Surface any error from the player to the editor UI
        if case .error(_, let message) = player.state {
            errorMessage = message
            // Keep HUD visible briefly so user can read the error before it dismisses
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }

        dismissReplayHUD()
        isReplaying = false
        restoreAppWindows()

        // If re-rehearsal completed, merge scenarios
        if let newRawEvents = player.getRehearsalRawEvents() {
            let merged = player.mergeScenarios(
                original: scenario,
                newRawEvents: newRawEvents,
                splitAtIndex: fromStepIndex,
                replayDurationMs: player.getReplayDurationMs()
            )
            saveUndoSnapshot()
            self.scenario = merged
            self.project.scenario = merged
            self.scenarioRawEvents = newRawEvents
            self.hasUnsavedChanges = true
        }
    }

    // MARK: - Replay HUD Lifecycle

    @available(macOS 15.0, *)
    private func showReplayHUD(player: ScenarioPlayer) {
        let panel = ReplayHUDPanel(player: player)
        panel.show()
        replayHUDPanel = panel
    }

    @available(macOS 15.0, *)
    private func dismissReplayHUD() {
        (replayHUDPanel as? ReplayHUDPanel)?.dismiss()
        replayHUDPanel = nil
    }

    // MARK: - Window Management for Replay

    /// Minimize all Screenize windows so they don't appear in the recording.
    /// The replay HUD panel is excluded since it is a floating NSPanel.
    private func minimizeAppWindows() {
        NSApp.windows.forEach { window in
            if !(window is NSPanel), !window.isMiniaturized {
                window.miniaturize(nil)
            }
        }
    }

    /// Restore previously minimized Screenize windows after replay ends.
    private func restoreAppWindows() {
        NSApp.windows.forEach { window in
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
        }
    }

    // MARK: - Capture Target Resolution

    /// Resolve a CaptureTarget from the project's CaptureMeta using ScreenCaptureKit.
    /// Falls back to the main display if the original display is unavailable.
    /// Reconstruct a CaptureTarget from CaptureMeta for replay recording.
    /// - Display capture (displayID != nil): returns `.display()`
    /// - Window capture (displayID == nil): returns `.region(boundsPt, display)` so
    ///   CaptureConfiguration sets sourceRect to crop to the original window area.
    private func resolveCaptureTarget(from captureMeta: CaptureMeta) async throws -> CaptureTarget {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        if let displayID = captureMeta.displayID,
           let display = content.displays.first(where: { $0.displayID == displayID }) {
            // Display capture — full display
            return .display(display)
        }

        // Window capture (displayID is nil) — use region with boundsPt.
        // Find the display that contains the window's center point.
        let windowCenter = CGPoint(
            x: captureMeta.boundsPt.midX,
            y: captureMeta.boundsPt.midY
        )
        if let display = content.displays.first(where: { display in
            let bounds = CGDisplayBounds(display.displayID)
            return bounds.contains(windowCenter)
        }) {
            return .region(captureMeta.boundsPt, display)
        }

        // Fallback: use main display with region
        if let mainDisplay = content.displays.first {
            return .region(captureMeta.boundsPt, mainDisplay)
        }

        throw ReplayCaptureError.noDisplayAvailable
    }

    // MARK: - Post-Replay Project Creation

    /// After replay finishes, transfer recording data to AppState and trigger project creation.
    @available(macOS 15.0, *)
    private func handlePostReplayRecording(coordinator: RecordingCoordinator, appState: AppState) async {
        // The ScenarioPlayer already called coordinator.stopRecording() internally.
        // Transfer the coordinator's results to AppState so ContentView.createProjectFromRecording() picks them up.
        guard let videoURL = coordinator.lastVideoURL else {
            Log.project.info("Replay completed but no recording URL available.")
            return
        }

        appState.lastRecordingURL = videoURL
        appState.lastMouseRecording = coordinator.lastMouseRecording
        appState.lastMicAudioURL = coordinator.lastMicAudioURL
        appState.lastSystemAudioURL = coordinator.lastSystemAudioURL
        appState.lastScenarioRawEvents = coordinator.lastScenarioRawEvents
        // Carry the original scenario to the new project. During replay
        // isRehearsalMode=false so ScenarioEventRecorder never runs and
        // lastScenarioRawEvents is nil. The original scenario is still valid.
        appState.lastReplayScenario = self.scenario
        appState.showEditor = true
    }

}

// MARK: - Replay Errors

enum ReplayCaptureError: LocalizedError {
    case noDisplayAvailable

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display available. Cannot start replay without a connected display."
        }
    }
}
