import Foundation
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Combine

/// Global application state coordinator.
/// Owns focused child ObservableObjects and provides backward-compatible facades.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Singleton

    static let shared = AppState()

    // MARK: - Child State Objects

    let capture = CaptureSettings()
    let navigation = NavigationState()
    let recording = RecordingState()
    let permissionsManager = PermissionsManager()

    // MARK: - Capture Toolbar

    private(set) var captureToolbarCoordinator: CaptureToolbarCoordinator?

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Backward-Compatibility Facades
    // These delegate to child objects so existing code continues to work.
    // Migrate call sites to use children directly over time.

    // Recording facades
    var isRecording: Bool {
        get { recording.isRecording }
        set { recording.isRecording = newValue }
    }
    var isPaused: Bool {
        get { recording.isPaused }
        set { recording.isPaused = newValue }
    }
    var recordingDuration: TimeInterval {
        get { recording.recordingDuration }
        set { recording.recordingDuration = newValue }
    }
    var lastRecordingURL: URL? {
        get { recording.lastRecordingURL }
        set { recording.lastRecordingURL = newValue }
    }
    var previewImage: CGImage? {
        get { recording.previewImage }
        set { recording.previewImage = newValue }
    }
    var lastMouseRecording: MouseRecording? {
        get { recording.lastMouseRecording }
        set { recording.lastMouseRecording = newValue }
    }
    var lastRecordingStartDate: Date? {
        get { recording.lastRecordingStartDate }
        set { recording.lastRecordingStartDate = newValue }
    }
    var lastProcessTimeStartMs: Int64 {
        get { recording.lastProcessTimeStartMs }
        set { recording.lastProcessTimeStartMs = newValue }
    }
    var lastMicAudioURL: URL? {
        get { recording.lastMicAudioURL }
        set { recording.lastMicAudioURL = newValue }
    }
    var lastSystemAudioURL: URL? {
        get { recording.lastSystemAudioURL }
        set { recording.lastSystemAudioURL = newValue }
    }
    var recordingCoordinator: RecordingCoordinator? {
        recording.recordingCoordinator
    }

    // Capture facades
    var isMicrophoneEnabled: Bool {
        get { capture.isMicrophoneEnabled }
        set { capture.isMicrophoneEnabled = newValue }
    }
    var isSystemAudioEnabled: Bool {
        get { capture.isSystemAudioEnabled }
        set { capture.isSystemAudioEnabled = newValue }
    }
    var selectedMicrophoneDeviceID: String {
        get { capture.selectedMicrophoneDeviceID }
        set { capture.selectedMicrophoneDeviceID = newValue }
    }
    var captureFrameRate: Int {
        get { capture.captureFrameRate }
        set { capture.captureFrameRate = newValue }
    }
    var selectedMicrophoneDevice: AVCaptureDevice? {
        capture.selectedMicrophoneDevice
    }
    var selectedTarget: CaptureTarget? {
        get { capture.selectedTarget }
        set { capture.selectedTarget = newValue }
    }
    var availableDisplays: [SCDisplay] {
        get { capture.availableDisplays }
        set { capture.availableDisplays = newValue }
    }
    var availableWindows: [SCWindow] {
        get { capture.availableWindows }
        set { capture.availableWindows = newValue }
    }
    var backgroundStyle: BackgroundStyle {
        get { capture.backgroundStyle }
        set { capture.backgroundStyle = newValue }
    }

    // Navigation facades
    var showEditor: Bool {
        get { navigation.showEditor }
        set { navigation.showEditor = newValue }
    }
    var showExportSheet: Bool {
        get { navigation.showExportSheet }
        set { navigation.showExportSheet = newValue }
    }
    var errorMessage: String? {
        get { navigation.errorMessage }
        set { navigation.errorMessage = newValue }
    }
    var currentProject: ScreenizeProject? {
        get { navigation.currentProject }
        set { navigation.currentProject = newValue }
    }
    var currentProjectURL: URL? {
        get { navigation.currentProjectURL }
        set { navigation.currentProjectURL = newValue }
    }
    var canUndo: Bool {
        get { navigation.canUndo }
        set { navigation.canUndo = newValue }
    }
    var canRedo: Bool {
        get { navigation.canRedo }
        set { navigation.canRedo = newValue }
    }
    var showCaptureToolbar: Bool {
        get { navigation.showCaptureToolbar }
        set { navigation.showCaptureToolbar = newValue }
    }

    // MARK: - Initialization

    private init() {
        recording.configure(captureSettings: capture, navigationState: navigation)
        forwardChildChanges()
    }

    /// Forward all children's objectWillChange to self so SwiftUI views
    /// using @EnvironmentObject AppState still update.
    private func forwardChildChanges() {
        capture.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        navigation.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recording.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            return false
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if #available(macOS 14.0, *) {
            if !CGPreflightListenEventAccess() {
                CGRequestListenEventAccess()
            }
        }

        return accessibilityEnabled
    }

    // MARK: - Source Selection

    func refreshAvailableSources() async {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            try? await Task.sleep(nanoseconds: 500_000_000)

            if !CGPreflightScreenCaptureAccess() {
                errorMessage = "Screen capture permission required. Please enable it in System Settings > Privacy & Security > Screen Recording."
                return
            }
        }
        await capture.refreshAvailableSources()
    }

    // MARK: - Recording Control

    func startRecording() async {
        guard #available(macOS 15.0, *) else {
            errorMessage = "Recording requires macOS 15.0 or later"
            return
        }

        do {
            try await recording.startRecording(appState: self)

            // Only show standalone panel when capture toolbar is not managing the UI
            if !showCaptureToolbar {
                recording.showRecordingFloatingPanel(appState: self)
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() async {
        guard #available(macOS 15.0, *) else { return }

        // Only hide standalone panel when capture toolbar is not managing the UI
        if !showCaptureToolbar {
            recording.hideRecordingFloatingPanel()
        }

        if let videoURL = await recording.stopRecording() {
            showEditor = true
            _ = videoURL // URL stored in recording.lastRecordingURL
        } else {
            errorMessage = "Failed to stop recording"
        }

        showMainWindow()
    }

    func togglePause() {
        recording.togglePause()
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

    // MARK: - Project Navigation

    func closeProject() {
        navigation.closeProject()
    }

    func startNewRecording() {
        hideMainWindow()
        navigation.closeProject()
        Task {
            await showCaptureToolbarFlow()
        }
    }

    // MARK: - Capture Toolbar Flow

    func showCaptureToolbarFlow() async {
        if captureToolbarCoordinator == nil {
            captureToolbarCoordinator = CaptureToolbarCoordinator(appState: self)
        }
        showCaptureToolbar = true
        await captureToolbarCoordinator?.showToolbar()
    }

    func captureToolbarDidDismiss() {
        showCaptureToolbar = false
        captureToolbarCoordinator = nil
        selectedTarget = nil
    }

    // MARK: - Project Creation

    func buildCaptureMeta(videoURL: URL) async -> CaptureMeta? {
        if let target = selectedTarget {
            switch target {
            case .display(let display):
                let backingScale = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == display.displayID
                })?.backingScaleFactor ?? 2.0
                return CaptureMeta(
                    displayID: display.displayID,
                    boundsPt: CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height)),
                    scaleFactor: backingScale
                )
            case .window(let window):
                let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
                return CaptureMeta(boundsPt: window.frame, scaleFactor: backingScale)
            case .region(let rect, let display):
                let backingScale = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == display.displayID
                })?.backingScaleFactor ?? 2.0
                return CaptureMeta(
                    displayID: display.displayID,
                    boundsPt: rect,
                    scaleFactor: backingScale
                )
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
        guard let videoMetadata = await extractVideoMetadata(from: packageInfo.videoURL) else {
            return nil
        }

        let captureMeta = await buildCaptureMeta(videoURL: packageInfo.videoURL) ?? CaptureMeta(
            boundsPt: CGRect(x: 0, y: 0, width: videoMetadata.width / 2, height: videoMetadata.height / 2),
            scaleFactor: 2.0
        )

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
