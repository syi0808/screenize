import Foundation
import ScreenCaptureKit
import AppKit
import Combine

/// Orchestrates the capture toolbar flow:
/// show toolbar → hover to select target → countdown → recording → stop
@MainActor
final class CaptureToolbarCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var captureMode: CaptureMode = .entireScreen {
        didSet {
            guard oldValue != captureMode else { return }
            overlayController.updateMode(captureMode)
            hoveredScreen = nil
            hoveredWindow = nil
        }
    }

    @Published var toolbarPhase: ToolbarPhase = .selecting
    @Published var hoveredScreen: SCDisplay?
    @Published var hoveredWindow: SCWindow?

    var hasValidTarget: Bool {
        switch captureMode {
        case .entireScreen:
            return hoveredScreen != nil
        case .window:
            return hoveredWindow != nil
        }
    }

    /// Mirrors AppState.isPaused for the toolbar recording UI
    @Published var isPaused: Bool = false

    /// Mirrors AppState.recordingDuration for the toolbar recording UI
    @Published var recordingDuration: TimeInterval = 0

    // MARK: - Private Properties

    private var toolbarPanel: CaptureToolbarPanel?
    private let overlayController = CaptureOverlayController()
    private weak var appState: AppState?
    private var countdownTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(appState: AppState) {
        self.appState = appState
        setupOverlayCallbacks()
        setupAppStateBindings()
    }

    // MARK: - Public API

    /// Show the capture toolbar and overlays
    func showToolbar() async {
        guard let appState else { return }

        await appState.refreshAvailableSources()
        hideMainWindow()

        let panel = CaptureToolbarPanel(coordinator: self)
        panel.show()
        self.toolbarPanel = panel

        overlayController.activate(
            mode: captureMode,
            displays: appState.availableDisplays,
            windows: appState.availableWindows
        )
    }

    /// Confirm the current target and start countdown
    func confirmAndRecord() {
        guard let appState else { return }

        let target: CaptureTarget?
        switch captureMode {
        case .entireScreen:
            target = hoveredScreen.map { .display($0) }
        case .window:
            target = hoveredWindow.map { .window($0) }
        }

        guard let target else { return }

        appState.selectedTarget = target

        // Dismiss overlays but keep toolbar panel visible
        overlayController.deactivate()

        // Start countdown in the same panel
        toolbarPhase = .countdown(3)
        startCountdownTimer()
    }

    /// Cancel countdown and dismiss
    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        cancel()
    }

    /// Cancel the toolbar and return to welcome screen
    func cancel() {
        overlayController.deactivate()
        countdownTimer?.invalidate()
        countdownTimer = nil
        toolbarPanel?.dismiss()
        toolbarPanel = nil
        showMainWindow()
        appState?.captureToolbarDidDismiss()
    }

    /// Stop the current recording
    func stopRecording() {
        Task {
            await appState?.stopRecording()
            toolbarPanel?.dismiss()
            toolbarPanel = nil
            appState?.captureToolbarDidDismiss()
        }
    }

    /// Toggle pause/resume
    func togglePause() {
        appState?.togglePause()
    }

    // MARK: - Private Methods

    private func setupOverlayCallbacks() {
        overlayController.onScreenHovered = { [weak self] display in
            self?.hoveredScreen = display
        }

        overlayController.onWindowHovered = { [weak self] window in
            self?.hoveredWindow = window
        }

        overlayController.onRecordClicked = { [weak self] in
            self?.confirmAndRecord()
        }
    }

    private func setupAppStateBindings() {
        guard let appState else { return }

        // Mirror isPaused from AppState
        appState.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                self?.isPaused = paused
            }
            .store(in: &cancellables)

        // Mirror recordingDuration from AppState
        appState.$recordingDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                self?.recordingDuration = duration
            }
            .store(in: &cancellables)
    }

    // MARK: - Countdown

    private func startCountdownTimer() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.countdownTick()
            }
        }
    }

    private func countdownTick() {
        guard case .countdown(let remaining) = toolbarPhase else { return }

        if remaining <= 1 {
            countdownTimer?.invalidate()
            countdownTimer = nil
            toolbarPhase = .recording
            Task {
                await appState?.startRecording()
            }
        } else {
            toolbarPhase = .countdown(remaining - 1)
        }
    }

    // MARK: - Window Management

    private func hideMainWindow() {
        NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }?.orderOut(nil)
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
    }
}
