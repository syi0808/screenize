import Foundation
import ScreenCaptureKit
import CoreMedia
import Combine
import AppKit

protocol ScreenCaptureDelegate: AnyObject {
    func captureManager(_ manager: ScreenCaptureManager, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer)
    func captureManager(_ manager: ScreenCaptureManager, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer)
    func captureManager(_ manager: ScreenCaptureManager, didStopWithError error: Error?)
    func captureManager(_ manager: ScreenCaptureManager, didFinishRecordingTo url: URL)
}

// Provide default implementations for delegate methods
extension ScreenCaptureDelegate {
    func captureManager(_ manager: ScreenCaptureManager, didFinishRecordingTo url: URL) {}
}

final class ScreenCaptureManager: NSObject, @unchecked Sendable {
    weak var delegate: ScreenCaptureDelegate?

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var contentFilter: SCContentFilter?

    private let captureQueue = DispatchQueue(label: "com.screenize.capture", qos: .userInteractive)
    private var isCapturing = false

    private var recordingURL: URL?

    // CFR recording manager (locked at 60fps)
    fileprivate var cfrRecordingManager: CFRRecordingManager?

    // Used to wait safely for recording finalization to complete
    private let recordingFinished = RecordingFinishSignal()

    override init() {
        super.init()
    }

    // MARK: - Start recording (CFR locked at 60fps)

    @available(macOS 15.0, *)
    func startRecording(
        target: CaptureTarget,
        configuration: CaptureConfiguration,
        outputURL: URL
    ) async throws {
        guard !isCapturing else {
            throw CaptureError.alreadyCapturing
        }

        // Create a content filter excluding Screenize, Dock, and the menu bar
        let filter = try await createContentFilterExcludingSystemUI(for: target)
        self.contentFilter = filter
        self.recordingURL = outputURL

        let streamConfig = configuration.createStreamConfiguration()

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        self.stream = stream

        // Set up stream output for preview
        let output = StreamOutput(delegate: self)
        self.streamOutput = output
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)

        if configuration.capturesAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: captureQueue)
        }

        // CFR recording: capture at a fixed 60fps rate
        let cfrManager = CFRRecordingManager()
        cfrManager.onRecordingFinished = { [weak self] url in
            self?.recordingFinished.signal()
            if let url = url {
                self?.delegate?.captureManager(self!, didFinishRecordingTo: url)
            }
        }
        try cfrManager.startRecording(to: outputURL, configuration: configuration)
        self.cfrRecordingManager = cfrManager

        recordingFinished.reset()
        try await stream.startCapture()
        isCapturing = true

        print("🎬 [ScreenCaptureManager] CFR recording started (60fps): \(outputURL.path)")
    }

    @available(macOS 15.0, *)
    func stopRecording() async -> URL? {
        guard isCapturing, let stream = stream else { return nil }

        do {
            // Remove the stream output first
            if let output = streamOutput {
                try stream.removeStreamOutput(output, type: .screen)
            }

            try await stream.stopCapture()
        } catch {
            print("❌ [ScreenCaptureManager] Error stopping recording: \(error)")
        }

        // End CFR recording
        let finalURL = await cfrRecordingManager?.stopRecording()
        self.cfrRecordingManager = nil

        self.stream = nil
        self.streamOutput = nil
        self.contentFilter = nil
        self.recordingURL = nil
        isCapturing = false

        print("🎬 [ScreenCaptureManager] CFR recording stopped: \(finalURL?.path ?? "nil")")
        return finalURL
    }

    // MARK: - Preview-only capture (no recording)

    func startCapture(target: CaptureTarget, configuration: CaptureConfiguration) async throws {
        guard !isCapturing else {
            throw CaptureError.alreadyCapturing
        }

        let filter = try await createContentFilterExcludingSystemUI(for: target)
        self.contentFilter = filter

        let streamConfig = configuration.createStreamConfiguration()

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        self.stream = stream

        let output = StreamOutput(delegate: self)
        self.streamOutput = output

        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)

        if configuration.capturesAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: captureQueue)
        }

        try await stream.startCapture()
        isCapturing = true
    }

    func stopCapture() async {
        guard isCapturing, let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            print("Error stopping capture: \(error)")
        }

        self.stream = nil
        self.streamOutput = nil
        self.contentFilter = nil
        isCapturing = false
    }

    func updateConfiguration(_ configuration: CaptureConfiguration) async throws {
        guard let stream = stream else {
            throw CaptureError.notCapturing
        }

        let streamConfig = configuration.createStreamConfiguration()
        try await stream.updateConfiguration(streamConfig)
    }

    // MARK: - Content Filter (Exclude system UI)

    /// Create a content filter excluding Screenize, Dock, and the menu bar
    private func createContentFilterExcludingSystemUI(for target: CaptureTarget) async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Find the Screenize app
        let screenizeApp = content.applications.first { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        // Find the Dock app
        let dockApp = content.applications.first { app in
            app.bundleIdentifier == "com.apple.dock"
        }

        // Apps to exclude
        var excludedApps: [SCRunningApplication] = []
        if let screenize = screenizeApp {
            excludedApps.append(screenize)
        }
        if let dock = dockApp {
            excludedApps.append(dock)
        }

        // Exclude system UI windows (menu bar, control center, etc.) — compute for future use
        _ = content.windows.filter { window in
            // Exclude menu bar windows
            if window.owningApplication?.bundleIdentifier == "com.apple.controlcenter" {
                return true
            }
            // Exclude the system UI server (menu bar)
            if window.owningApplication?.bundleIdentifier == "com.apple.systemuiserver" {
                return true
            }
            // Exclude Notification Center
            if window.owningApplication?.bundleIdentifier == "com.apple.notificationcenterui" {
                return true
            }
            return false
        }

        switch target {
        case .display(let display):
            guard let scDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
                throw CaptureError.targetNotFound
            }

            // Exclude apps and windows when capturing a display
            return SCContentFilter(
                display: scDisplay,
                excludingApplications: excludedApps,
                exceptingWindows: []
            )

        case .window(let window):
            guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
                throw CaptureError.targetNotFound
            }
            return SCContentFilter(desktopIndependentWindow: scWindow)

        case .region(_, let display):
            guard let scDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
                throw CaptureError.targetNotFound
            }
            return SCContentFilter(
                display: scDisplay,
                excludingApplications: excludedApps,
                exceptingWindows: []
            )
        }
    }

    static func getAvailableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isCapturing = false
        delegate?.captureManager(self, didStopWithError: error)
    }
}

// MARK: - StreamOutput

private final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    weak var delegate: ScreenCaptureManager?

    init(delegate: ScreenCaptureManager) {
        self.delegate = delegate
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            // CFR recording mode: forward frames to CFRRecordingManager
            delegate?.cfrRecordingManager?.receiveFrame(sampleBuffer)

            // Also forward to the delegate (for preview, etc.)
            delegate?.delegate?.captureManager(delegate!, didOutputVideoSampleBuffer: sampleBuffer)
        case .audio:
            delegate?.delegate?.captureManager(delegate!, didOutputAudioSampleBuffer: sampleBuffer)
        case .microphone:
            // Microphone audio - currently unused
            break
        @unknown default:
            break
        }
    }
}

// MARK: - CaptureError

enum CaptureError: LocalizedError {
    case alreadyCapturing
    case notCapturing
    case targetNotFound
    case permissionDenied
    case configurationFailed
    case recordingNotSupported

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "Capture is already in progress"
        case .notCapturing:
            return "No capture in progress"
        case .targetNotFound:
            return "Capture target not found"
        case .permissionDenied:
            return "Screen capture permission denied"
        case .configurationFailed:
            return "Failed to configure capture"
        case .recordingNotSupported:
            return "Recording requires macOS 15.0 or later"
        }
    }
}

// MARK: - RecordingFinishSignal

/// Synchronization utility to safely wait for recording finalization
final class RecordingFinishSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private var continuation: CheckedContinuation<Void, Never>?

    /// Reset when recording starts
    func reset() {
        lock.lock()
        isFinished = false
        continuation = nil
        lock.unlock()
    }

    /// Called when recording finishes (from the delegate callback)
    func signal() {
        lock.lock()
        isFinished = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }

    /// Wait for finalization to complete (returns immediately if already done)
    func wait() async {
        lock.lock()
        if isFinished {
            lock.unlock()
            return
        }
        lock.unlock()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.lock.lock()
            if self.isFinished {
                self.lock.unlock()
                cont.resume()
            } else {
                self.continuation = cont
                self.lock.unlock()
            }
        }
    }
}
