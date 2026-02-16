import Foundation
import CoreMedia
import CoreImage
import Combine
import AppKit

@MainActor
final class RecordingCoordinator: ObservableObject {

    // MARK: - Published State
    // Note: isRecording and isPaused are @Published to support SwiftUI bindings.
    // They could be derived from currentSession?.state, but we maintain separate state for responsive UI updates.

    @Published private(set) var currentSession: RecordingSession?
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var previewImage: CGImage?

    // MARK: - Private Properties

    private var captureManager: ScreenCaptureManager?
    private var mouseDataRecorder: MouseDataRecorder?

    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var captureConfiguration: CaptureConfiguration?
    private var captureTarget: CaptureTarget?
    private var captureBounds: CGRect = .zero

    // v4 event stream timebase
    private(set) var recordingStartDate: Date?
    private(set) var processTimeStartMs: Int64 = 0
    private(set) var lastMouseRecording: MouseRecording?

    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: false,
        .cacheIntermediates: false,
        .priorityRequestLow: false
    ])

    // MARK: - Thread-Safe State (for Capture Callbacks)
    // Note: ScreenCaptureDelegate methods run on the capture queue,
    // so nonisolated (unsafe) usage allows bypassing MainActor isolation.

    nonisolated(unsafe) private var _captureSession: RecordingSession?
    nonisolated(unsafe) private var _captureIsPaused: Bool = false

    nonisolated var captureSession: RecordingSession? { _captureSession }
    nonisolated var captureIsPaused: Bool { _captureIsPaused }

    // MARK: - Computed State

    /// Return the current recording state (based on the session)
    var recordingState: RecordingSession.RecordingState {
        currentSession?.state ?? .idle
    }

    init() {}

    /// Start recording using SCRecordingOutput (macOS 15+)
    @available(macOS 15.0, *)
    func startRecording(
        target: CaptureTarget,
        backgroundStyle: BackgroundStyle,
        zoomSettings: ZoomSettings
    ) async throws {
        guard currentSession == nil else {
            throw RecordingError.alreadyRecording
        }

        // Create session
        let session = RecordingSession(target: target)
        currentSession = session
        session.transition(to: .preparing)

        // Store the capture target
        self.captureTarget = target
        self.captureBounds = calculateCaptureBounds(for: target)

        // Setup capture configuration
        let captureConfig = CaptureConfiguration.forTarget(target)

        // DEBUG: Log capture setup details
        print("🔍 [DEBUG] Recording target: \(target), captureBounds: \(captureBounds)")
        print("🔍 [DEBUG] captureConfig: \(captureConfig.width)x\(captureConfig.height), shadow: \(captureConfig.capturesShadow)")
        self.captureConfiguration = captureConfig

        // Sync nonisolated variables
        _captureSession = session
        _captureIsPaused = false

        // Setup and start capture with SCRecordingOutput
        captureManager = ScreenCaptureManager()
        captureManager?.delegate = self

        try await captureManager?.startRecording(
            target: target,
            configuration: captureConfig,
            outputURL: session.outputURL
        )

        // Start mouse recording after video capture begins (synchronize timestamps)
        recordingStartDate = Date()
        processTimeStartMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        mouseDataRecorder = MouseDataRecorder()
        mouseDataRecorder?.startRecording(screenBounds: captureBounds, scaleFactor: captureConfig.scaleFactor)

        session.transition(to: .recording)
        isRecording = true
        isPaused = false
        recordingStartTime = Date()

        startDurationTimer()
        print("🎬 [RecordingCoordinator] Started recording via SCRecordingOutput")
    }

    @available(macOS 15.0, *)
    func stopRecording() async -> URL? {
        guard let session = currentSession else { return nil }

        session.transition(to: .stopping)
        isRecording = false
        isPaused = false

        // Clean up nonisolated variables
        _captureIsPaused = true
        _captureSession = nil

        stopDurationTimer()

        // Collect mouse data (written to package later by EventStreamWriter)
        if let mouseRecording = mouseDataRecorder?.stopRecording() {
            lastMouseRecording = mouseRecording
        }
        mouseDataRecorder = nil

        // Stop SCRecordingOutput recording
        let outputURL = await captureManager?.stopRecording()

        if let url = outputURL {
            session.transition(to: .completed(url))
            print("🎬 [RecordingCoordinator] Recording finished - source: \(url.path)")
        } else {
            session.transition(to: .failed("Recording file save failed"))
        }

        currentSession = nil
        return outputURL
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        _captureIsPaused = true
        stopDurationTimer()
        mouseDataRecorder?.pauseRecording()
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        _captureIsPaused = false
        startDurationTimer()
        mouseDataRecorder?.resumeRecording()
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
                self.currentSession?.updateDuration(self.currentDuration)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStartTime = nil
    }

    private func updatePreviewImage(from pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            self.previewImage = cgImage
        }
    }

    /// Calculate the capture target's screen bounds (AppKit coordinates, bottom-left origin)
    /// Used for mouse coordinate conversion
    private func calculateCaptureBounds(for target: CaptureTarget) -> CGRect {
        switch target {
        case .display(let display):
            if let screen = NSScreen.screens.first(where: { Int($0.frame.width) == display.width }) {
                return screen.frame
            }
            return CGRect(x: 0, y: 0, width: display.width, height: display.height)

        case .window(let window):
            // SCWindow.frame uses CG coordinates (top-left origin, Y increases downwards)
            // NSEvent.mouseLocation uses AppKit coordinates (bottom-left origin, Y increases upwards)
            // Convert to AppKit coordinates for mouse coordinate translation
            //
            // Find the screen containing the window (fall back to main screen)
            // This ensures correct conversion on multi-display setups where NSScreen.main
            // may not be the screen the window is on.
            let windowMidX = window.frame.origin.x + window.frame.width / 2
            let windowCGMidY = window.frame.origin.y + window.frame.height / 2
            let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0

            let screenHeight: CGFloat
            if let containingScreen = NSScreen.screens.first(where: { screen in
                // Convert AppKit screen frame to CG coordinates for comparison with SCWindow.frame
                let screenCGOriginY = primaryScreenHeight - screen.frame.origin.y - screen.frame.height
                let screenCGRect = CGRect(
                    x: screen.frame.origin.x, y: screenCGOriginY,
                    width: screen.frame.width, height: screen.frame.height
                )
                return screenCGRect.contains(CGPoint(x: windowMidX, y: windowCGMidY))
            }) {
                // Use the containing screen's top edge in CG coordinates
                // For primary screen: primaryScreenHeight. For others: convert accordingly.
                screenHeight = primaryScreenHeight - containingScreen.frame.origin.y
            } else {
                screenHeight = NSScreen.main?.frame.height ?? 0
            }

            let appKitOriginY = screenHeight - window.frame.origin.y - window.frame.height
            print("🔍 [DEBUG] Window bounds: CG frame=\(window.frame), screenHeight=\(screenHeight), appKitOriginY=\(appKitOriginY)")
            return CGRect(
                x: window.frame.origin.x,
                y: appKitOriginY,
                width: window.frame.width,
                height: window.frame.height
            )

        case .region(let rect, _):
            return rect
        }
    }
}

// MARK: - ScreenCaptureDelegate

extension RecordingCoordinator: ScreenCaptureDelegate {
    nonisolated func captureManager(_ manager: ScreenCaptureManager, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        // SCRecordingOutput handles recording, so here we only update preview
        guard !captureIsPaused else { return }

        // Increment the frame count
        captureSession?.incrementFrameCount()

        // Update the preview every 10 frames
        let frameCount = captureSession?.frameCount ?? 0
        if frameCount % 10 == 0 {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            Task { @MainActor in
                self.updatePreviewImage(from: pixelBuffer)
            }
        }
    }

    nonisolated func captureManager(_ manager: ScreenCaptureManager, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        // SCRecordingOutput also handles audio capture
    }

    nonisolated func captureManager(_ manager: ScreenCaptureManager, didStopWithError error: Error?) {
        Task { @MainActor in
            if let error = error {
                currentSession?.transition(to: .failed(error.localizedDescription))
            }
            if #available(macOS 15.0, *) {
                _ = await stopRecording()
            }
        }
    }

    nonisolated func captureManager(_ manager: ScreenCaptureManager, didFinishRecordingTo url: URL) {
        print("🎬 [RecordingCoordinator] Completed recording file: \(url.path)")
    }
}

// MARK: - RecordingError

enum RecordingError: LocalizedError {
    case alreadyRecording
    case notRecording
    case noTarget
    case captureFailed(Error)
    case writeFailed(Error)
    case recordingNotSupported

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress"
        case .notRecording:
            return "No recording in progress"
        case .noTarget:
            return "No capture target selected"
        case .captureFailed(let error):
            return "Capture failed: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Write failed: \(error.localizedDescription)"
        case .recordingNotSupported:
            return "Recording requires macOS 15.0 or later"
        }
    }
}
