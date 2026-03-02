import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import Combine

/// Export engine
/// Timeline-based final video output with Metal-accelerated GPU pipeline
final class ExportEngine: ObservableObject {

    // MARK: - Published Properties

    /// Current progress state
    @MainActor @Published var progress: ExportProgress = .idle

    /// Statistics info
    @MainActor @Published var statistics: ExportStatistics?

    // MARK: - Properties

    /// Project
    var project: ScreenizeProject?

    /// Export task
    var exportTask: Task<URL, Error>?

    /// Cancellation flag
    var isCancelled: Bool = false

    /// Frame evaluator
    var evaluator: FrameEvaluator?

    /// Renderer
    var renderer: Renderer?

    /// Audio mixer
    let audioMixer = AudioMixer()

    // MARK: - Initialization

    init() {}

    // MARK: - Export

    /// Start export
    /// - Parameters:
    ///   - project: Project to export
    ///   - outputURL: Output file URL
    /// - Returns: URL of the completed file
    func export(project: ScreenizeProject, to outputURL: URL) async throws -> URL {
        // Throw if an export is already in progress
        let isInProgress = await MainActor.run { progress.isInProgress }
        guard !isInProgress else {
            throw ExportEngineError.alreadyExporting
        }

        // Reset stale state from any previous export
        await MainActor.run {
            progress = .idle
            statistics = nil
        }
        self.isCancelled = false

        switch project.renderSettings.exportFormat {
        case .video:
            return try await exportVideo(project: project, to: outputURL)
        case .gif:
            return try await exportGIF(project: project, to: outputURL)
        }
    }

    // MARK: - Cancel

    /// Cancel the export
    func cancel() {
        isCancelled = true
        exportTask?.cancel()
    }

    // MARK: - Reset

    /// Reset the state
    @MainActor
    func reset() {
        progress = .idle
        statistics = nil
        isCancelled = false
    }
}
