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
    @Published private(set) var currentTexture: MTLTexture?

    /// Display generation counter (incremented on every texture delivery)
    /// Forces SwiftUI to call MetalPreviewView.updateNSView even when the
    /// same MTLTexture reference is reused from the texture pool
    @Published private(set) var displayGeneration: Int = 0

    /// Whether playback is active
    @Published private(set) var isPlaying: Bool = false

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
    @Published private(set) var isLoading: Bool = false

    /// Error message
    @Published private(set) var errorMessage: String?

    /// Last render error (for UI display)
    @Published private(set) var lastRenderError: RenderError?

    /// Cumulative render error count
    @Published private(set) var renderErrorCount: Int = 0

    // MARK: - Properties

    /// Render coordinator (background rendering)
    private let renderCoordinator: RenderCoordinator

    /// Display link driver (vsync-driven playback)
    private let displayLinkDriver: DisplayLinkDriver

    /// Scrub controller (coalesces scrub requests)
    private let scrubController: ScrubController

    /// Sequential frame reader for playback
    private var sequentialReader: SequentialFrameReader?

    /// Random-access frame extractor for scrubbing
    private var frameExtractor: VideoFrameExtractor?

    /// Total duration
    private(set) var duration: TimeInterval = 0

    /// Frame rate
    private(set) var frameRate: Double = 60

    /// Trim start time
    private var trimStart: TimeInterval = 0

    /// Trim end time (uses duration if nil)
    private var trimEnd: TimeInterval?

    /// Effective trim start time
    private var effectiveTrimStart: TimeInterval {
        max(0, trimStart)
    }

    /// Effective trim end time
    private var effectiveTrimEnd: TimeInterval {
        min(duration, trimEnd ?? duration)
    }

    /// Trimmed playback length
    var trimmedDuration: TimeInterval {
        effectiveTrimEnd - effectiveTrimStart
    }

    /// Preview scale (for performance)
    private let previewScale: CGFloat

    /// Render generation (incremented on seek to invalidate stale renders)
    private var renderGeneration: Int = 0

    /// Whether a seek operation is in progress (prevents didSet re-entry)
    private var isSeeking: Bool = false

    /// Project reference (for timeline updates)
    private var project: ScreenizeProject?

    /// Raw mouse position data
    private var rawMousePositions: [RenderMousePosition] = []

    /// Smoothed mouse position data (Catmull-Rom interpolated)
    private var smoothedMousePositions: [RenderMousePosition] = []

    /// Click event data (reused during timeline updates)
    private var renderClickEvents: [RenderClickEvent] = []

    // MARK: - Initialization

    init(previewScale: CGFloat = 0.5, cacheSize: Int = 180) {
        self.previewScale = previewScale
        self.renderCoordinator = RenderCoordinator(previewScale: previewScale, cacheSize: cacheSize)
        self.displayLinkDriver = DisplayLinkDriver()
        self.scrubController = ScrubController()

        setupCallbacks()
    }

    // MARK: - Callback Setup

    private func setupCallbacks() {
        // DisplayLink: called from background thread on every vsync
        displayLinkDriver.onFrame = { [weak self] targetVideoTime in
            guard let self = self else { return }

            self.renderCoordinator.requestPlaybackFrame(at: targetVideoTime) { [weak self] texture, actualTime in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    // Stop at trim end
                    if actualTime >= self.effectiveTrimEnd {
                        self.pause()
                        self.isSeeking = true
                        self.currentTime = self.effectiveTrimEnd
                        self.isSeeking = false
                        return
                    }

                    if let texture = texture {
                        self.currentTexture = texture
                        self.displayGeneration += 1
                    }
                    self.isSeeking = true
                    self.currentTime = actualTime
                    self.isSeeking = false

                    // Signal frame delivered so DisplayLink can fire next tick
                    self.displayLinkDriver.markFrameDelivered()
                }
            }
        }

        // ScrubController: request rendering on the render coordinator
        scrubController.onRenderRequest = { [weak self] time, generation, completion in
            guard let self = self else {
                completion(nil)
                return
            }
            self.renderCoordinator.requestScrubFrame(
                at: time, generation: generation, completion: completion
            )
        }

        // ScrubController: deliver texture to main thread
        scrubController.onFrameReady = { [weak self] texture, _ in
            guard let self = self else { return }
            if self.isLoading {
                self.isLoading = false
            }
            if let texture = texture {
                self.currentTexture = texture
                self.displayGeneration += 1
            }
        }
    }

    // MARK: - Setup

    /// Initialize with a project
    func setup(with project: ScreenizeProject) async {
        isLoading = true
        errorMessage = nil

        self.project = project

        do {
            // Configure the random-access frame extractor
            let extractor = try await VideoFrameExtractor(url: project.media.videoURL)
            frameExtractor = extractor

            // Set base properties
            duration = extractor.duration
            frameRate = extractor.frameRate

            // Configure trim range
            trimStart = project.timeline.effectiveTrimStart
            trimEnd = project.timeline.trimEnd

            // Load raw mouse data
            let rawResult = MouseDataConverter.loadAndConvert(from: project)
            rawMousePositions = rawResult.positions
            renderClickEvents = rawResult.clicks

            // Load smoothed mouse data (Catmull-Rom interpolated)
            let smoothedResult = MouseDataConverter.loadAndConvertWithInterpolation(
                from: project,
                frameRate: extractor.frameRate
            )
            smoothedMousePositions = smoothedResult.positions

            // Build the render pipeline (Evaluator + Renderer)
            let pipeline = RenderPipelineFactory.createPreviewPipeline(
                project: project,
                rawMousePositions: rawMousePositions,
                smoothedMousePositions: smoothedMousePositions,
                clickEvents: renderClickEvents,
                frameRate: frameRate,
                sourceSize: extractor.videoSize,
                scale: previewScale
            )

            // Create sequential frame reader for playback
            let reader = try await SequentialFrameReader(
                url: project.media.videoURL,
                ringBufferSize: 8
            )
            try reader.startReading(from: effectiveTrimStart)
            sequentialReader = reader

            // Configure the render coordinator
            renderCoordinator.setup(
                sequentialReader: reader,
                frameExtractor: extractor,
                evaluator: pipeline.evaluator,
                renderer: pipeline.renderer,
                frameRate: frameRate
            )

            // Render the first frame (at trim start)
            isSeeking = true
            currentTime = effectiveTrimStart
            isSeeking = false
            scrubController.scrub(to: effectiveTrimStart)

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Playback Control

    /// Start playback
    func play() {
        guard !isPlaying else { return }

        // When starting playback at the trim end, jump to the trim start
        if currentTime >= effectiveTrimEnd {
            isSeeking = true
            currentTime = effectiveTrimStart
            isSeeking = false
        }

        // If the time is before the trim start, clamp to the trim start
        if currentTime < effectiveTrimStart {
            isSeeking = true
            currentTime = effectiveTrimStart
            isSeeking = false
        }

        // Reposition the sequential reader to current time
        renderCoordinator.seek(to: currentTime)

        isPlaying = true

        // Start vsync-driven playback
        displayLinkDriver.start(fromVideoTime: currentTime, frameRate: frameRate)
    }

    /// Pause playback
    func pause() {
        isPlaying = false
        displayLinkDriver.stop()
    }

    /// Toggle playback/pause
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Seek to a specific time (clamped to trim range)
    func seek(to time: TimeInterval) async {
        let clampedTime = max(effectiveTrimStart, min(effectiveTrimEnd, time))

        isSeeking = true
        renderGeneration += 1
        frameExtractor?.cancelAllPendingRequests()
        renderCoordinator.seek(to: clampedTime)
        currentTime = clampedTime
        isSeeking = false

        if !isPlaying {
            scrubController.scrub(to: clampedTime)
        } else {
            // During playback, update the display link anchor
            displayLinkDriver.updateAnchor(videoTime: clampedTime)
        }
    }

    /// Jump to the start (trim start)
    func seekToStart() async {
        await seek(to: effectiveTrimStart)
    }

    /// Jump to the end (trim end)
    func seekToEnd() async {
        await seek(to: effectiveTrimEnd)
    }

    // MARK: - Timeline Update

    /// Invalidate the cache when the timeline changes
    func invalidateCache(from startTime: TimeInterval, to endTime: TimeInterval) {
        renderCoordinator.invalidateCache(from: startTime, to: endTime)

        // If the current frame falls within a dirty range, re-render
        if currentTime >= startTime && currentTime <= endTime {
            scrubController.scrub(to: currentTime)
        }
    }

    /// Invalidate a specific time range and update the evaluator
    /// More efficient than invalidateAllCache when only a portion of the timeline changed
    func invalidateRange(with timeline: Timeline, from startTime: TimeInterval, to endTime: TimeInterval) {
        guard let project = project else { return }

        // Recreate the evaluator with the updated timeline
        let newEvaluator = RenderPipelineFactory.createEvaluator(
            timeline: timeline,
            project: project,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: renderClickEvents,
            frameRate: frameRate
        )

        renderCoordinator.updateEvaluator(newEvaluator)
        renderCoordinator.invalidateCache(from: startTime, to: endTime)

        // Re-render if the current frame falls within the dirty range
        if currentTime >= startTime && currentTime <= endTime {
            scrubController.scrub(to: currentTime)
        }
    }

    /// Invalidate the entire cache
    /// - Parameter timeline: Updated timeline (nil only clears the cache)
    func invalidateAllCache(with timeline: Timeline? = nil) {
        if let timeline = timeline {
            updateTimeline(timeline)
        } else {
            renderCoordinator.invalidateAllCache()
            scrubController.scrub(to: currentTime)
        }
    }

    /// Update the trim range
    func updateTrimRange(start: TimeInterval, end: TimeInterval?) {
        self.trimStart = start
        self.trimEnd = end

        // Adjust if the current time falls outside the trim range
        isSeeking = true
        if currentTime < effectiveTrimStart {
            currentTime = effectiveTrimStart
        } else if currentTime > effectiveTrimEnd {
            currentTime = effectiveTrimEnd
        }
        isSeeking = false

        // Re-render the current frame
        scrubController.scrub(to: currentTime)
    }

    /// Recreate the evaluator when the timeline updates
    /// - Parameter timeline: New timeline
    func updateTimeline(_ timeline: Timeline) {
        guard let project = project else { return }

        // Create a new evaluator (reuse stored mouse data)
        let newEvaluator = RenderPipelineFactory.createEvaluator(
            timeline: timeline,
            project: project,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: renderClickEvents,
            frameRate: frameRate
        )

        renderCoordinator.updateEvaluator(newEvaluator)
        renderCoordinator.invalidateAllCache()

        // Re-render the current frame
        scrubController.scrub(to: currentTime)
    }

    /// Rebuild the renderer and evaluator when render settings change
    /// - Parameter renderSettings: New render settings
    func updateRenderSettings(_ renderSettings: RenderSettings) {
        guard let extractor = frameExtractor else { return }

        // Update the project's render settings BEFORE capturing the local copy
        // (ScreenizeProject is a struct, so guard let captures a snapshot)
        self.project?.renderSettings = renderSettings

        guard let project = project else { return }

        // Recreate the evaluator (isWindowMode may change)
        let newEvaluator = RenderPipelineFactory.createEvaluator(
            project: project,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: renderClickEvents,
            frameRate: frameRate
        )

        // Recreate the renderer
        let newRenderer = RenderPipelineFactory.createPreviewRenderer(
            renderSettings: renderSettings,
            captureMeta: project.captureMeta,
            sourceSize: extractor.videoSize,
            scale: previewScale
        )

        renderCoordinator.updateEvaluator(newEvaluator)
        renderCoordinator.updateRenderer(newRenderer)
        renderCoordinator.invalidateAllCache()

        // Re-render the current frame
        scrubController.scrub(to: currentTime)
    }

    // MARK: - Error Handling

    /// Dismiss the render error banner
    func clearRenderError() {
        lastRenderError = nil
    }

    // MARK: - Cleanup

    func cleanup() {
        pause()
        scrubController.cancel()
        renderCoordinator.cleanup()
        sequentialReader?.stopReading()
        frameExtractor?.cancelAllPendingRequests()
        currentTexture = nil
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
