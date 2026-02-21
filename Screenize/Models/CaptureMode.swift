import Foundation

/// Capture selection mode for the capture toolbar
enum CaptureMode: Equatable {
    /// Select an entire screen/display to record
    case entireScreen
    /// Select a specific window to record
    case window
}

/// Phase of the unified capture toolbar lifecycle
enum ToolbarPhase: Equatable {
    /// User is selecting a capture target
    case selecting
    /// Countdown before recording starts
    case countdown(Int)
    /// Recording in progress
    case recording
}
