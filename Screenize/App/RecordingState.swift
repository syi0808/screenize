import Foundation
import CoreGraphics
import Combine
import AppKit

/// Recording lifecycle state: start, stop, pause, duration, preview.
@MainActor
final class RecordingState: ObservableObject {

    // MARK: - Published Properties

    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastRecordingURL: URL?
    @Published var previewImage: CGImage?

    // MARK: - Recording Metadata (captured before coordinator is released)

    var lastMouseRecording: MouseRecording?
    var lastRecordingStartDate: Date?
    var lastProcessTimeStartMs: Int64 = 0
    var lastMicAudioURL: URL?
    var lastSystemAudioURL: URL?

    // MARK: - Managers

    private(set) var recordingCoordinator: RecordingCoordinator?

    // MARK: - Private Properties

    private var durationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var recordingFloatingPanel: RecordingFloatingPanel?

    // MARK: - Dependencies

    private weak var captureSettings: CaptureSettings?
    private weak var navigationState: NavigationState?

    func configure(captureSettings: CaptureSettings, navigationState: NavigationState) {
        self.captureSettings = captureSettings
        self.navigationState = navigationState
    }

    // MARK: - Recording Control

    @available(macOS 15.0, *)
    func startRecording(appState: AppState) async throws {
        guard let captureSettings = captureSettings else { return }
        guard let target = captureSettings.selectedTarget else {
            navigationState?.errorMessage = "Please select a capture source first"
            return
        }

        let coordinator = RecordingCoordinator()
        self.recordingCoordinator = coordinator

        try await coordinator.startRecording(
            target: target,
            backgroundStyle: captureSettings.backgroundStyle,
            frameRate: captureSettings.captureFrameRate,
            isSystemAudioEnabled: captureSettings.isSystemAudioEnabled,
            isMicrophoneEnabled: captureSettings.isMicrophoneEnabled,
            microphoneDevice: captureSettings.selectedMicrophoneDevice
        )

        isRecording = true
        isPaused = false
        recordingDuration = 0
        startDurationTimer()
        setupPreviewUpdates()
    }

    @available(macOS 15.0, *)
    func stopRecording() async -> URL? {
        guard let coordinator = recordingCoordinator else { return nil }

        isRecording = false
        isPaused = false
        stopDurationTimer()

        // Capture v4 timing metadata before releasing coordinator
        lastRecordingStartDate = coordinator.recordingStartDate
        lastProcessTimeStartMs = coordinator.processTimeStartMs

        let videoURL = await coordinator.stopRecording()
        if let videoURL = videoURL {
            lastRecordingURL = videoURL
            lastMouseRecording = coordinator.lastMouseRecording
            lastMicAudioURL = coordinator.lastMicAudioURL
            lastSystemAudioURL = coordinator.lastSystemAudioURL
        }

        recordingCoordinator = nil
        return videoURL
    }

    func togglePause() {
        guard isRecording else { return }

        isPaused.toggle()

        if isPaused {
            recordingCoordinator?.pauseRecording()
        } else {
            recordingCoordinator?.resumeRecording()
        }
    }

    // MARK: - Recording Floating Panel

    func showRecordingFloatingPanel(appState: AppState) {
        let panel = RecordingFloatingPanel(appState: appState)
        panel.show()
        self.recordingFloatingPanel = panel
    }

    func hideRecordingFloatingPanel() {
        recordingFloatingPanel?.dismiss()
        recordingFloatingPanel = nil
    }

    // MARK: - Private Helpers

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRecording, !self.isPaused else { return }
                self.recordingDuration += 0.1
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func setupPreviewUpdates() {
        guard let coordinator = recordingCoordinator else { return }

        coordinator.$previewImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                self?.previewImage = image
            }
            .store(in: &cancellables)
    }
}
