import Foundation

/// Export progress states
enum ExportProgress: Equatable {
    case idle
    case preparing
    case loadingVideo
    case loadingMouseData
    case processing(frame: Int, total: Int)
    case encoding
    case finalizing
    case completed(URL)
    case failed(String)
    case cancelled

    // MARK: - Computed Properties

    /// Progress (0.0–1.0)
    var progress: Double {
        switch self {
        case .idle:
            return 0
        case .preparing:
            return 0.02
        case .loadingVideo:
            return 0.05
        case .loadingMouseData:
            return 0.08
        case .processing(let frame, let total):
            guard total > 0 else { return 0.1 }
            // Processing phase ranges from 10% to 90%
            return 0.1 + (Double(frame) / Double(total)) * 0.8
        case .encoding:
            return 0.92
        case .finalizing:
            return 0.98
        case .completed:
            return 1.0
        case .failed, .cancelled:
            return 0
        }
    }

    /// Percentage (0–100)
    var percentComplete: Int {
        Int(progress * 100)
    }

    /// Status text
    var statusText: String {
        switch self {
        case .idle:
            return "Idle"
        case .preparing:
            return "Preparing..."
        case .loadingVideo:
            return "Loading video..."
        case .loadingMouseData:
            return "Loading mouse data..."
        case .processing(let frame, let total):
            return "Processing frames... (\(frame)/\(total))"
        case .encoding:
            return "Encoding..."
        case .finalizing:
            return "Finalizing..."
        case .completed:
            return "Completed"
        case .failed(let message):
            return "Failed: \(message)"
        case .cancelled:
            return "Cancelled"
        }
    }

    /// Completion flag
    var isCompleted: Bool {
        if case .completed = self {
            return true
        }
        return false
    }

    /// Failure flag
    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    /// Cancellation flag
    var isCancelled: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }

    /// In-progress flag
    var isInProgress: Bool {
        switch self {
        case .preparing, .loadingVideo, .loadingMouseData, .processing, .encoding, .finalizing:
            return true
        default:
            return false
        }
    }

    /// Output URL (present only on completion)
    var outputURL: URL? {
        if case .completed(let url) = self {
            return url
        }
        return nil
    }

    /// Error message (present only on failure)
    var errorMessage: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
    }
}

// MARK: - Export Statistics

/// Export statistics information
struct ExportStatistics {
    /// Total frame count
    let totalFrames: Int

    /// Processed frame count
    let processedFrames: Int

    /// Start time
    let startTime: Date

    /// Current time
    let currentTime: Date

    /// Elapsed time (seconds)
    var elapsedTime: TimeInterval {
        currentTime.timeIntervalSince(startTime)
    }

    /// Processing speed (fps)
    var processingFPS: Double {
        guard elapsedTime > 0 else { return 0 }
        return Double(processedFrames) / elapsedTime
    }

    /// Estimated remaining time (seconds)
    var estimatedRemainingTime: TimeInterval? {
        guard processedFrames > 0, processingFPS > 0 else { return nil }
        let remainingFrames = totalFrames - processedFrames
        return Double(remainingFrames) / processingFPS
    }

    /// Estimated total time (seconds)
    var estimatedTotalTime: TimeInterval? {
        guard processingFPS > 0 else { return nil }
        return Double(totalFrames) / processingFPS
    }
}
