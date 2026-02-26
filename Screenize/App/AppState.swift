import Foundation
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Combine

/// Global application state
@MainActor
final class AppState: ObservableObject {

    // MARK: - Singleton

    static let shared = AppState()

    // MARK: - Published Properties

    // Recording state
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastRecordingURL: URL?
    // v4 recording metadata (captured before coordinator is released)
    var lastMouseRecording: MouseRecording?
    var lastRecordingStartDate: Date?
    var lastProcessTimeStartMs: Int64 = 0
    var lastMicAudioURL: URL?
    var lastSystemAudioURL: URL?

    // Audio
    @AppStorage("isMicrophoneEnabled") var isMicrophoneEnabled: Bool = false
    @AppStorage("isSystemAudioEnabled") var isSystemAudioEnabled: Bool = true
    @AppStorage("selectedMicrophoneDeviceID") var selectedMicrophoneDeviceID: String = ""

    // Capture frame rate (VFR target: 30, 60, 120, or 240)
    @AppStorage("captureFrameRate") var captureFrameRate: Int = 60

    /// Resolve the persisted microphone device ID to an AVCaptureDevice.
    /// Returns nil if the saved device is unavailable (disconnected, etc.).
    var selectedMicrophoneDevice: AVCaptureDevice? {
        guard !selectedMicrophoneDeviceID.isEmpty else { return nil }
        return AVCaptureDevice(uniqueID: selectedMicrophoneDeviceID)
    }

    // UI state
    @Published var showEditor: Bool = false
    @Published var showExportSheet: Bool = false
    @Published var errorMessage: String?

    // Current project
    @Published var currentProject: ScreenizeProject?
    @Published var currentProjectURL: URL?

    // Capture source
    @Published var selectedTarget: CaptureTarget?
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []

    // Preview
    @Published var previewImage: CGImage?

    // MARK: - Editor State (for menu commands)

    /// Whether undo is available (updated from EditorViewModel)
    @Published var canUndo: Bool = false

    /// Whether redo is available (updated from EditorViewModel)
    @Published var canRedo: Bool = false

    // MARK: - User Preferences

    // Note: BackgroundStyle doesn't support @AppStorage directly
    var backgroundStyle: BackgroundStyle = .solid(.gray)

    // MARK: - Capture Toolbar

    @Published var showCaptureToolbar: Bool = false
    private(set) var captureToolbarCoordinator: CaptureToolbarCoordinator?

    // MARK: - Managers

    private(set) var recordingCoordinator: RecordingCoordinator?
    let permissionsManager = PermissionsManager()

    // MARK: - Private Properties

    private var durationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var recordingFloatingPanel: RecordingFloatingPanel?

    // MARK: - Initialization

    private init() {
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Update UI when recording state changes
        $isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if !recording {
                    self?.stopDurationTimer()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        // Check screen recording permission
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            return false
        }

        // Check accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Check input monitoring permission (for capturing keyboard events)
        if #available(macOS 14.0, *) {
            if !CGPreflightListenEventAccess() {
                CGRequestListenEventAccess()
            }
        }

        return accessibilityEnabled
    }

    // MARK: - Source Selection

    func refreshAvailableSources() async {
        // Request permission if missing
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            // Wait briefly after requesting permission to give the user time
            try? await Task.sleep(nanoseconds: 500_000_000)

            // If still blocked, show guidance
            if !CGPreflightScreenCaptureAccess() {
                errorMessage = "Screen capture permission required. Please enable it in System Settings > Privacy & Security > Screen Recording."
                return
            }
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            availableDisplays = content.displays
            let excludedBundleIDs: Set<String> = [
                Bundle.main.bundleIdentifier ?? "com.screenize.Screenize",
                "com.apple.dock",
                "com.apple.controlcenter",
                "com.apple.systemuiserver",
                "com.apple.notificationcenterui",
                "com.apple.WindowManager",
            ]

            availableWindows = content.windows.filter { window in
                guard let app = window.owningApplication else {
                    return false
                }
                // Exclude system UI elements and Screenize, filter by minimum size
                return !excludedBundleIDs.contains(app.bundleIdentifier)
                    && window.frame.width >= 50
                    && window.frame.height >= 50
            }

            Log.ui.info("Sources refreshed - displays: \(self.availableDisplays.count), windows: \(self.availableWindows.count)")
        } catch {
            Log.ui.error("Failed to refresh sources: \(error)")
            errorMessage = "Failed to get available sources: \(error.localizedDescription)"
        }
    }

    // MARK: - Recording Control

    func startRecording() async {
        guard #available(macOS 15.0, *) else {
            errorMessage = "Recording requires macOS 15.0 or later"
            return
        }

        guard let target = selectedTarget else {
            errorMessage = "Please select a capture source first"
            return
        }

        // Create RecordingCoordinator
        let coordinator = RecordingCoordinator()
        self.recordingCoordinator = coordinator

        // Start recording
        do {
            try await coordinator.startRecording(
                target: target,
                backgroundStyle: backgroundStyle
            )

            isRecording = true
            isPaused = false
            recordingDuration = 0
            startDurationTimer()
            setupPreviewUpdates()
            // Only show standalone panel when capture toolbar is not managing the UI
            if !showCaptureToolbar {
                showRecordingFloatingPanel()
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            recordingCoordinator = nil
        }
    }

    func stopRecording() async {
        guard #available(macOS 15.0, *) else { return }
        guard let coordinator = recordingCoordinator else { return }

        isRecording = false
        isPaused = false
        stopDurationTimer()
        // Only hide standalone panel when capture toolbar is not managing the UI
        if !showCaptureToolbar {
            hideRecordingFloatingPanel()
        }

        // Capture v4 timing metadata before releasing coordinator
        lastRecordingStartDate = coordinator.recordingStartDate
        lastProcessTimeStartMs = coordinator.processTimeStartMs

        if let videoURL = await coordinator.stopRecording() {
            lastRecordingURL = videoURL
            lastMouseRecording = coordinator.lastMouseRecording
            lastMicAudioURL = coordinator.lastMicAudioURL
            lastSystemAudioURL = coordinator.lastSystemAudioURL
            showEditor = true
        } else {
            errorMessage = "Failed to stop recording"
        }

        recordingCoordinator = nil
        showMainWindow()
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

    func toggleRecording() async {
        if isRecording {
            if showCaptureToolbar {
                captureToolbarCoordinator?.stopRecording()
            } else {
                await stopRecording()
            }
        } else if showCaptureToolbar {
            captureToolbarCoordinator?.cancel()
        } else {
            await showCaptureToolbarFlow()
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

    // MARK: - Recording Floating Panel

    private func showRecordingFloatingPanel() {
        let panel = RecordingFloatingPanel(appState: self)
        panel.show()
        self.recordingFloatingPanel = panel
    }

    private func hideRecordingFloatingPanel() {
        recordingFloatingPanel?.dismiss()
        recordingFloatingPanel = nil
    }

    // MARK: - Project Navigation

    /// Close the current project and return to the welcome screen
    func closeProject() {
        currentProject = nil
        currentProjectURL = nil
    }

    /// Close the current project and start a new recording
    func startNewRecording() {
        hideMainWindow()
        currentProject = nil
        currentProjectURL = nil
        Task {
            await showCaptureToolbarFlow()
        }
    }

    // MARK: - Capture Toolbar Flow

    /// Show the capture toolbar for target selection
    func showCaptureToolbarFlow() async {
        if captureToolbarCoordinator == nil {
            captureToolbarCoordinator = CaptureToolbarCoordinator(appState: self)
        }
        showCaptureToolbar = true
        await captureToolbarCoordinator?.showToolbar()
    }

    /// Called when the capture toolbar is dismissed (cancelled or recording stopped)
    func captureToolbarDidDismiss() {
        showCaptureToolbar = false
        captureToolbarCoordinator = nil
        selectedTarget = nil
    }

    // MARK: - Project Creation

    /// Build CaptureMeta from the current selectedTarget, falling back to video dimensions.
    func buildCaptureMeta(videoURL: URL) async -> CaptureMeta? {
        if let target = selectedTarget {
            switch target {
            case .display(let display):
                return CaptureMeta(
                    boundsPt: CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height)),
                    scaleFactor: CGFloat(display.width) / CGFloat(display.width) * 2.0
                )
            case .window(let window):
                return CaptureMeta(boundsPt: window.frame, scaleFactor: 2.0)
            case .region(let rect, _):
                return CaptureMeta(boundsPt: rect, scaleFactor: 2.0)
            }
        } else {
            guard let videoMetadata = await extractVideoMetadata(from: videoURL) else { return nil }
            return CaptureMeta(
                boundsPt: CGRect(x: 0, y: 0, width: videoMetadata.width / 2, height: videoMetadata.height / 2),
                scaleFactor: 2.0
            )
        }
    }

    func createProject(packageInfo: PackageInfo) async -> ScreenizeProject? {
        // Extract video metadata
        guard let videoMetadata = await extractVideoMetadata(from: packageInfo.videoURL) else {
            return nil
        }

        let captureMeta = await buildCaptureMeta(videoURL: packageInfo.videoURL) ?? CaptureMeta(
            boundsPt: CGRect(x: 0, y: 0, width: videoMetadata.width / 2, height: videoMetadata.height / 2),
            scaleFactor: 2.0
        )

        // Create media asset with relative paths
        let media = MediaAsset(
            videoRelativePath: packageInfo.videoRelativePath,
            mouseDataRelativePath: packageInfo.mouseDataRelativePath,
            micAudioRelativePath: packageInfo.micAudioRelativePath,
            systemAudioRelativePath: packageInfo.systemAudioRelativePath,
            packageRootURL: packageInfo.packageURL,
            pixelSize: CGSize(width: videoMetadata.width, height: videoMetadata.height),
            frameRate: videoMetadata.frameRate,
            duration: videoMetadata.duration
        )

        // Generate default timeline
        let timeline = Timeline(
            tracks: [
                AnySegmentTrack.camera(CameraTrack(
                    id: UUID(),
                    name: "Camera",
                    isEnabled: true,
                    segments: []
                )),
                AnySegmentTrack.cursor(CursorTrackV2(
                    id: UUID(),
                    name: "Cursor",
                    isEnabled: true,
                    segments: []
                )),
                AnySegmentTrack.keystroke(KeystrokeTrackV2(
                    id: UUID(),
                    name: "Keystroke",
                    isEnabled: true,
                    segments: []
                ))
            ],
            duration: videoMetadata.duration
        )

        // Adjust cornerRadius/windowInset defaults for full screen source
        var renderSettings = RenderSettings()
        if selectedTarget?.isFullScreen == true {
            renderSettings.cornerRadius = 8.0
            renderSettings.windowInset = 0.0
        }

        return ScreenizeProject(
            name: packageInfo.packageURL.deletingPathExtension().lastPathComponent,
            media: media,
            captureMeta: captureMeta,
            timeline: timeline,
            renderSettings: renderSettings,
            interop: packageInfo.interop
        )
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
        // Bind RecordingCoordinator's previewImage to AppState's previewImage
        guard let coordinator = recordingCoordinator else { return }

        coordinator.$previewImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                self?.previewImage = image
            }
            .store(in: &cancellables)
    }

    private func extractVideoMetadata(from url: URL) async -> (width: Int, height: Int, frameRate: Double, duration: TimeInterval)? {
        let asset = AVAsset(url: url)

        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }

            let size = try await track.load(.naturalSize)
            let nominalFrameRate = try await track.load(.nominalFrameRate)
            let assetDuration = try await asset.load(.duration)

            let frameRate = Double(nominalFrameRate)
            let duration = CMTimeGetSeconds(assetDuration)

            return (Int(size.width), Int(size.height), frameRate, duration)
        } catch {
            Log.project.error("Failed to load video metadata: \(error)")
            return nil
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let editorUndo = Notification.Name("editorUndo")
    static let editorRedo = Notification.Name("editorRedo")
    static let editorCopy = Notification.Name("editorCopy")
    static let editorPaste = Notification.Name("editorPaste")
    static let editorDuplicate = Notification.Name("editorDuplicate")
}

// MARK: - Auto Zoom Settings

struct AutoZoomSettings: Codable {
    var isEnabled: Bool
    var maxZoom: Double

    init(isEnabled: Bool = true, maxZoom: Double = 2.0) {
        self.isEnabled = isEnabled
        self.maxZoom = maxZoom
    }
}
