import Foundation
import os

/// Centralized logging for Screenize using Apple's unified logging system.
///
/// Usage:
///   Log.recording.info("Recording started")
///   Log.capture.error("Failed to stop: \(error)")
///   Log.tracking.debug("Mouse sample: \(position)")  // excluded from release builds
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.screenize.Screenize"

    /// Recording lifecycle (start, stop, pause, resume, session transitions)
    static let recording = Logger(subsystem: subsystem, category: "recording")

    /// Screen capture (ScreenCaptureKit interactions, frame management)
    static let capture = Logger(subsystem: subsystem, category: "capture")

    /// Mouse, click, keyboard, scroll, and drag tracking
    static let tracking = Logger(subsystem: subsystem, category: "tracking")

    /// Export engine and rendering pipeline
    static let export = Logger(subsystem: subsystem, category: "export")

    /// Smart generation pipeline (V2 generators, diagnostics)
    static let generator = Logger(subsystem: subsystem, category: "generator")

    /// Project management (save, load, package operations)
    static let project = Logger(subsystem: subsystem, category: "project")

    /// UI state and navigation
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Permissions (screen capture, accessibility, input monitoring)
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
}
