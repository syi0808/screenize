import Foundation
import CoreMedia

final class RecordingSession: Identifiable, @unchecked Sendable {
    let id: UUID
    let startDate: Date
    let target: CaptureTarget
    let outputURL: URL

    private(set) var state: RecordingState = .idle
    private(set) var duration: TimeInterval = 0
    private(set) var frameCount: Int = 0
    private(set) var droppedFrameCount: Int = 0

    private var stateChangeCallbacks: [(RecordingState) -> Void] = []
    private let lock = NSLock()

    init(target: CaptureTarget) {
        self.id = UUID()
        self.startDate = Date()
        self.target = target
        self.outputURL = Self.generateOutputURL(id: id)
    }

    enum RecordingState: Equatable {
        case idle
        case preparing
        case recording
        case paused
        case stopping
        case completed(URL)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .recording, .paused:
                return true
            default:
                return false
            }
        }
    }

    func transition(to newState: RecordingState) {
        lock.lock()
        defer { lock.unlock() }

        let oldState = state
        state = newState

        // Notify callbacks
        for callback in stateChangeCallbacks {
            callback(newState)
        }

        Log.recording.info("Session \(self.id): \(String(describing: oldState)) -> \(String(describing: newState))")
    }

    func onStateChange(_ callback: @escaping (RecordingState) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        stateChangeCallbacks.append(callback)
    }

    func incrementFrameCount() {
        lock.lock()
        defer { lock.unlock() }
        frameCount += 1
    }

    func incrementDroppedFrameCount() {
        lock.lock()
        defer { lock.unlock() }
        droppedFrameCount += 1
    }

    func updateDuration(_ newDuration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        duration = newDuration
    }

    var metadata: RecordingMetadata {
        RecordingMetadata(
            id: id,
            startDate: startDate,
            duration: duration,
            targetType: targetTypeString,
            outputURL: outputURL,
            frameCount: frameCount,
            droppedFrameCount: droppedFrameCount
        )
    }

    private var targetTypeString: String {
        switch target {
        case .display: return "display"
        case .window: return "window"
        case .region: return "region"
        }
    }

    private static func generateOutputURL(id: UUID) -> URL {
        #if DEBUG
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Recording/
            .deletingLastPathComponent() // Core/
            .deletingLastPathComponent() // Screenize/
            .deletingLastPathComponent() // repo root
        let screenizeFolder = repoRoot.appendingPathComponent("projects", isDirectory: true)
        #else
        let documentsPath = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let screenizeFolder = documentsPath.appendingPathComponent("Screenize", isDirectory: true)
        #endif

        try? FileManager.default.createDirectory(at: screenizeFolder, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())

        return screenizeFolder.appendingPathComponent("Recording_\(dateString).mp4")
    }
}

struct RecordingMetadata: Codable {
    let id: UUID
    let startDate: Date
    let duration: TimeInterval
    let targetType: String
    let outputURL: URL
    let frameCount: Int
    let droppedFrameCount: Int

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var dropRate: Double {
        guard frameCount > 0 else { return 0 }
        return Double(droppedFrameCount) / Double(frameCount) * 100
    }
}
