import Foundation
import CoreGraphics
import CoreImage
import Combine
import Metal

/// Preview engine
/// Manages frame rendering and playback for the live preview.
/// All rendering is delegated to a background RenderCoordinator.
/// The main thread only receives completed frames for display.
@MainActor
final class PreviewEngine: ObservableObject {

    // MARK: - Published Properties

    /// Current frame texture (GPU-resident, displayed via MetalPreviewView)
    @Published var currentTexture: MTLTexture?

    /// Display generation counter (incremented on every texture delivery)
    /// Forces SwiftUI to call MetalPreviewView.updateNSView even when the
    /// same MTLTexture reference is reused from the texture pool
    @Published var displayGeneration: Int = 0

    /// Whether playback is active
    @Published var isPlaying: Bool = false

    /// Current time (seconds)
    @Published var currentTime: TimeInterval = 0 {
        didSet {
            // During playback, time is driven by DisplayLink — no extra rendering needed
            if !isPlaying && !isSeeking {
                scrubController.scrub(to: currentTime)
            }
        }
    }

    /// Whether loading is in progress
    @Published var isLoading: Bool = true

    /// Error message
    @Published var errorMessage: String?

    /// Last render error (for UI display)
    @Published var lastRenderError: RenderError?

    /// Cumulative render error count
    @Published var renderErrorCount: Int = 0

    // MARK: - Properties

    /// Render coordinator (background rendering)
    let renderCoordinator: RenderCoordinator

    /// Display link driver (vsync-driven playback)
    let displayLinkDriver: DisplayLinkDriver

    /// Scrub controller (coalesces scrub requests)
    let scrubController: ScrubController

    /// Audio preview player (synchronized AVPlayer-based audio)
    let audioPlayer = AudioPreviewPlayer()

    /// Sequential frame reader for playback
    var sequentialReader: SequentialFrameReader?

    /// Random-access frame extractor for scrubbing
    var frameExtractor: VideoFrameExtractor?

    /// Total duration
    var duration: TimeInterval = 0

    /// Frame rate
    var frameRate: Double = 60

    /// Trim start time
    var trimStart: TimeInterval = 0

    /// Trim end time (uses duration if nil)
    var trimEnd: TimeInterval?

    /// Effective trim start time
    var effectiveTrimStart: TimeInterval {
        max(0, trimStart)
    }

    /// Effective trim end time
    var effectiveTrimEnd: TimeInterval {
        min(duration, trimEnd ?? duration)
    }

    /// Trimmed playback length
    var trimmedDuration: TimeInterval {
        effectiveTrimEnd - effectiveTrimStart
    }

    /// Preview scale (for performance)
    let previewScale: CGFloat

    /// Render generation (incremented on seek to invalidate stale renders)
    var renderGeneration: Int = 0

    /// Whether a seek operation is in progress (prevents didSet re-entry)
    var isSeeking: Bool = false

    /// Project reference (for timeline updates)
    var project: ScreenizeProject?

    /// Raw mouse position data
    var rawMousePositions: [RenderMousePosition] = []

    /// Smoothed mouse position data (spring-based or legacy interpolated)
    var smoothedMousePositions: [RenderMousePosition] = []

    /// Last spring config used for interpolation (to detect changes)
    var lastSpringConfig: SpringCursorConfig?

    /// Click event data (reused during timeline updates)
    var renderClickEvents: [RenderClickEvent] = []

    // MARK: - Initialization

    init(previewScale: CGFloat = 0.5, cacheSize: Int = 180) {
        self.previewScale = previewScale
        self.renderCoordinator = RenderCoordinator(previewScale: previewScale, cacheSize: cacheSize)
        self.displayLinkDriver = DisplayLinkDriver()
        self.scrubController = ScrubController()

        setupCallbacks()
    }

    // MARK: - Error Handling

    /// Dismiss the render error banner
    func clearRenderError() {
        lastRenderError = nil
    }
}

// MARK: - Computed Properties

extension PreviewEngine {
    /// Current frame index (approximate for VFR videos, display only)
    var currentFrameNumber: Int {
        Int(currentTime * frameRate)
    }

    /// Total number of frames (approximate for VFR videos, display only)
    var totalFrames: Int {
        Int(duration * frameRate)
    }

    /// Playback progress (0-1) within the trim range
    var progress: Double {
        guard trimmedDuration > 0 else { return 0 }
        return (currentTime - effectiveTrimStart) / trimmedDuration
    }

    /// Cache statistics
    var cacheStatistics: PreviewTextureCache.Statistics {
        renderCoordinator.cacheStatistics
    }

    /// Video aspect ratio
    var videoAspectRatio: CGFloat {
        guard let extractor = frameExtractor else { return 16.0 / 9.0 }
        let size = extractor.videoSize
        guard size.height > 0 else { return 16.0 / 9.0 }
        return size.width / size.height
    }

    /// Video size
    var videoSize: CGSize {
        frameExtractor?.videoSize ?? CGSize(width: 1920, height: 1080)
    }
}

// MARK: - Errors

enum PreviewEngineError: Error, LocalizedError {
    case setupFailed
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .setupFailed:
            return "Failed to configure preview engine"
        case .renderFailed:
            return "Frame rendering failed"
        }
    }
}

/// User-visible render error
struct RenderError: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let frameIndex: Int
    let message: String

    static func == (lhs: RenderError, rhs: RenderError) -> Bool {
        lhs.id == rhs.id
    }
}
