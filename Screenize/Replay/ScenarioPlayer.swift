import Foundation
import Combine
import AppKit

/// Main playback controller for scenario replay.
/// Manages the state machine, step execution loop, and recording bridge.
@available(macOS 15.0, *)
@MainActor
final class ScenarioPlayer: ObservableObject {

    // MARK: - Published State

    @Published var state: PlaybackState = .idle
    @Published var currentStepIndex: Int = 0
    @Published var totalStepCount: Int = 0
    @Published var currentStepDescription: String = ""
    @Published var errorMessage: String = ""

    // MARK: - Playback State

    enum PlaybackState: Equatable {
        case idle
        case playing
        case paused(PauseReason)
        case error(stepIndex: Int, message: String)
        /// Re-rehearse: waiting for user to press Start
        case waitingForUser
        /// Re-rehearse: countdown 3..2..1
        case countdown(Int)
        /// Re-rehearse: user operating manually
        case rehearsing
        case completed
    }

    enum PauseReason: Equatable {
        case userRequested
        case doManually
    }

    enum PlaybackMode: Equatable {
        case replayAll
        /// Replay up to (but not including) the given 0-based step index, then hand off to user.
        case replayUntilStep(Int)
    }

    // MARK: - Private

    private var scenario: Scenario?
    private var mode: PlaybackMode = .replayAll
    private var config: ReplayConfiguration?
    private let stepExecutor = StepExecutor()
    private var isCancelled = false
    private var recordingCoordinator: RecordingCoordinator?
    private var continuationForManual: CheckedContinuation<Void, Never>?
    private var continuationForUserStart: CheckedContinuation<Void, Never>?
    private var replayStartTime: Date?

    // MARK: - Public API

    /// Begin scenario playback with recording.
    func start(
        scenario: Scenario,
        mode: PlaybackMode,
        config: ReplayConfiguration,
        recordingCoordinator: RecordingCoordinator
    ) async {
        self.scenario = scenario
        self.mode = mode
        self.config = config
        self.recordingCoordinator = recordingCoordinator
        self.isCancelled = false
        self.totalStepCount = scenario.steps.count

        // Start recording (replay phase — no ScenarioEventRecorder)
        do {
            recordingCoordinator.isRehearsalMode = false
            try await recordingCoordinator.startRecording(
                target: config.captureTarget,
                backgroundStyle: config.backgroundStyle,
                frameRate: config.frameRate,
                isSystemAudioEnabled: config.isSystemAudioEnabled,
                isMicrophoneEnabled: config.isMicrophoneEnabled,
                microphoneDevice: config.microphoneDevice
            )
        } catch {
            Log.recording.error("Replay recording failed to start: \(error)")
            state = .error(
                stepIndex: 0,
                message: "Recording failed to start: \(error.localizedDescription)"
            )
            return
        }

        replayStartTime = Date()

        // Activate the target app so CGEvent injections land on the correct window.
        // Without this, events go to whatever app is frontmost after Screenize minimizes.
        if let appContext = scenario.appContext {
            NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == appContext })?
                .activate(options: .activateIgnoringOtherApps)
            // Small delay for the app to come to front before injecting events
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        state = .playing
        await executeStepLoop()
    }

    /// Stop playback and recording immediately.
    func stop() async {
        isCancelled = true
        stepExecutor.cancel()
        continuationForManual?.resume()
        continuationForManual = nil
        continuationForUserStart?.resume()
        continuationForUserStart = nil
        _ = await recordingCoordinator?.stopRecording()
        state = .completed
    }

    /// Skip the current errored step and move to the next one.
    func skip() {
        state = .playing
    }

    /// Enter manual mode so the user can perform the failed step by hand.
    func doManually() {
        state = .paused(.doManually)
    }

    /// Resume playback after the user manually performed the step.
    func continueAfterManual() {
        continuationForManual?.resume()
        continuationForManual = nil
        state = .playing
    }

    /// User pressed Start in the re-rehearse waitingForUser state.
    func startRehearsal() {
        continuationForUserStart?.resume()
        continuationForUserStart = nil
    }

    // MARK: - Step Loop

    private func executeStepLoop() async {
        guard let scenario else { return }

        for (index, step) in scenario.steps.enumerated() {
            guard !isCancelled else { break }

            currentStepIndex = index
            currentStepDescription = step.description

            // Re-rehearse: transition when we reach the target step
            if case .replayUntilStep(let targetIndex) = mode, index == targetIndex {
                await transitionToRehearsal()
                return
            }

            let previousPosition = index > 0
                ? lastPosition(for: scenario.steps[index - 1])
                : nil

            let result = await stepExecutor.execute(
                step: step,
                previousPosition: previousPosition,
                steps: scenario.steps,
                stepIndex: index,
                captureArea: config?.captureTarget.frame ?? .zero,
                isCancelled: { self.isCancelled }
            )

            switch result {
            case .success:
                continue
            case .error(let message):
                state = .error(stepIndex: index, message: message)
                errorMessage = message
                await waitForErrorResolution()
                if isCancelled { break }
                if case .paused(.doManually) = state {
                    await waitForManualCompletion()
                    if isCancelled { break }
                }
            case .cancelled:
                break
            }
        }

        if !isCancelled {
            // Allow the last step's visual effects (animations, transitions) to settle
            // before stopping the recording. Without this delay, the final ~2-3 seconds
            // of on-screen activity are cut off because recording stops immediately
            // after the last CGEvent is injected.
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            _ = await recordingCoordinator?.stopRecording()
            state = .completed
        }
    }

    // MARK: - Re-rehearse Transition

    private func transitionToRehearsal() async {
        state = .waitingForUser

        // Wait for user to press Start
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuationForUserStart = continuation
        }

        guard !isCancelled else { return }

        // Countdown 3..2..1
        for i in stride(from: 3, through: 1, by: -1) {
            state = .countdown(i)
            await TimingController.delay(ms: 1000)
            guard !isCancelled else { return }
        }

        // Activate ScenarioEventRecorder mid-session
        recordingCoordinator?.activateScenarioRecorder()

        state = .rehearsing
        // User now operates manually. Recording continues.
        // Stop is handled by stop() when user clicks Stop on HUD.
    }

    // MARK: - Error Resolution Helpers

    private func waitForErrorResolution() async {
        // Poll until state changes from .error (user picks skip / doManually / stop)
        while case .error = state, !isCancelled {
            await TimingController.delay(ms: 50)
        }
    }

    private func waitForManualCompletion() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuationForManual = continuation
        }
    }

    // MARK: - Helpers

    private func lastPosition(for step: ScenarioStep) -> CGPoint? {
        step.target?.absoluteCoord
    }

    /// Get the scenario raw events captured during re-rehearsal.
    func getRehearsalRawEvents() -> ScenarioRawEvents? {
        recordingCoordinator?.lastScenarioRawEvents
    }

    /// Get elapsed replay duration in milliseconds (useful as offset for scenario merging).
    func getReplayDurationMs() -> Int {
        guard let start = replayStartTime else { return 0 }
        return Int(Date().timeIntervalSince(start) * 1000)
    }

    /// Merge original scenario with new rehearsal data.
    /// Keeps steps before splitAtIndex from the original, generates new steps from raw events,
    /// and offsets their time ranges by the replay duration.
    func mergeScenarios(
        original: Scenario,
        newRawEvents: ScenarioRawEvents,
        splitAtIndex: Int,
        replayDurationMs: Int
    ) -> Scenario {
        let keptSteps = Array(original.steps.prefix(splitAtIndex))
        var newScenario = ScenarioGenerator.generate(from: newRawEvents)

        for i in 0..<newScenario.steps.count {
            if let range = newScenario.steps[i].rawTimeRange {
                newScenario.steps[i].rawTimeRange = TimeRange(
                    startMs: range.startMs + replayDurationMs,
                    endMs: range.endMs + replayDurationMs
                )
            }
        }

        return Scenario(
            version: original.version,
            appContext: original.appContext,
            steps: keptSteps + newScenario.steps
        )
    }
}
