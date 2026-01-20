import Foundation
import CoreGraphics
import CoreImage
import Combine

/// Preview engine
/// Manages frame rendering and playback for the live preview
@MainActor
final class PreviewEngine: ObservableObject {

    // MARK: - Published Properties

    /// Current frame image
    @Published private(set) var currentFrame: CGImage?

    /// Whether playback is active
    @Published private(set) var isPlaying: Bool = false

    /// Current time (seconds)
    @Published var currentTime: TimeInterval = 0 {
        didSet {
            // Render the corresponding frame when time changes
            if !isPlaying {
                Task {
                    await renderFrame(at: currentTime)
                }
            }
        }
    }

    /// Whether loading is in progress
    @Published private(set) var isLoading: Bool = false

    /// Error message
    @Published private(set) var errorMessage: String?

    // MARK: - Properties

    /// Frame evaluator
    private var evaluator: FrameEvaluator?

    /// Renderer
    private var renderer: Renderer?

    /// Video frame extractor
    private var frameExtractor: VideoFrameExtractor?

    /// Frame cache
    private let cache: PreviewCache

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

    /// Playback timer
    private var playbackTimer: Timer?

    /// Last render time (for performance metrics)
    private var lastRenderTime: Date?

    /// Project reference (for timeline updates)
    private var project: ScreenizeProject?

    /// Mouse position data (reused during timeline updates)
    private var renderMousePositions: [RenderMousePosition] = []

    /// Click event data (reused during timeline updates)
    private var renderClickEvents: [RenderClickEvent] = []

    // MARK: - Initialization

    init(previewScale: CGFloat = 0.5, cacheSize: Int = 60) {
        self.previewScale = previewScale
        self.cache = PreviewCache(maxSize: cacheSize)
    }

    // MARK: - Setup

    /// Initialize with a project
    func setup(with project: ScreenizeProject) async {
        isLoading = true
        errorMessage = nil

        // Store the project reference
        self.project = project

        do {
            // Configure the video frame extractor
            frameExtractor = try await VideoFrameExtractor(url: project.media.videoURL)

            guard let extractor = frameExtractor else {
                throw PreviewEngineError.setupFailed
            }

            // Set base properties
            duration = extractor.duration
            frameRate = extractor.frameRate

            // Configure trim range
            trimStart = project.timeline.effectiveTrimStart
            trimEnd = project.timeline.trimEnd

            // Load mouse data
            // Load and convert mouse data (with interpolation)
            do {
                let result = try MouseDataConverter.loadAndConvertWithInterpolation(
                    from: project,
                    frameRate: extractor.frameRate
                )
                renderMousePositions = result.positions
                renderClickEvents = result.clicks
                print("Loaded mouse data: \(renderMousePositions.count) positions, \(renderClickEvents.count) clicks")
            } catch {
                renderMousePositions = []
                renderClickEvents = []
                print("Failed to load mouse data: \(error.localizedDescription)")
                // Continue without mouse data
            }

            // Build the render pipeline (Evaluator + Renderer)
            let pipeline = RenderPipelineFactory.createPreviewPipeline(
                project: project,
                mousePositions: renderMousePositions,
                clickEvents: renderClickEvents,
                frameRate: frameRate,
                sourceSize: extractor.videoSize,
                scale: previewScale
            )
            evaluator = pipeline.evaluator
            renderer = pipeline.renderer

            // Reset the cache
            cache.invalidateAll()

            // Render the first frame (starting at trim start)
            await renderFrame(at: effectiveTrimStart)

            isLoading = false

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
            currentTime = effectiveTrimStart
        }

        // If the time is before the trim start, clamp to the trim start
        if currentTime < effectiveTrimStart {
            currentTime = effectiveTrimStart
        }

        isPlaying = true
        startPlaybackLoop()
    }

    /// Pause playback
    func pause() {
        isPlaying = false
        stopPlaybackLoop()
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
        currentTime = clampedTime

        if !isPlaying {
            await renderFrame(at: clampedTime)
        }
    }

    /// Seek to a specific frame
    func seek(toFrame frame: Int) async {
        let time = Double(frame) / frameRate
        await seek(to: time)
    }

    /// Jump to the start (trim start)
    func seekToStart() async {
        await seek(to: effectiveTrimStart)
    }

    /// Jump to the end (trim end)
    func seekToEnd() async {
        await seek(to: effectiveTrimEnd)
    }

    // MARK: - Frame Rendering

    /// Render the frame at a specific time
    func renderFrame(at time: TimeInterval) async {
        guard let extractor = frameExtractor,
              let evaluator = evaluator,
              let renderer = renderer else {
            return
        }

        let frameIndex = Int(time * frameRate)

        // Check the cache
        if let cachedFrame = cache.frame(at: frameIndex) {
            currentFrame = cachedFrame
            return
        }

        do {
            // Extract the frame
            let sourceFrame = try await extractor.extractFrame(at: time)

            // Evaluate rendering state
            let state = evaluator.evaluate(at: time)

            // Perform rendering
            if let rendered = renderer.renderToCGImage(sourceFrame: sourceFrame, state: state) {
                // Store in cache
                cache.store(rendered, at: frameIndex)
                currentFrame = rendered
            }

        } catch {
            // Ignore errors (skip frame)
            print("Preview render error at \(time): \(error)")
        }
    }

    // MARK: - Playback Loop

    private func startPlaybackLoop() {
        let frameDuration = 1.0 / frameRate

        playbackTimer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPlaying else { return }

                // Advance the time
                let newTime = self.currentTime + frameDuration

                // Stop playback when reaching the trim end
                if newTime >= self.effectiveTrimEnd {
                    self.pause()
                    return
                }

                self.currentTime = newTime

                // Render the current frame
                await self.renderFrame(at: newTime)
            }
        }

        RunLoop.main.add(playbackTimer!, forMode: .common)
    }

    private func stopPlaybackLoop() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Timeline Update

    /// Invalidate the cache when the timeline changes
    func invalidateCache(from startTime: TimeInterval, to endTime: TimeInterval) {
        let startFrame = Int(startTime * frameRate)
        let endFrame = Int(endTime * frameRate)
        cache.invalidate(from: startFrame, to: endFrame)

        // If the current frame falls within a dirty range, re-render
        let currentFrame = Int(currentTime * frameRate)
        if currentFrame >= startFrame && currentFrame <= endFrame {
            Task {
                await renderFrame(at: currentTime)
            }
        }
    }

    /// Invalidate the entire cache
    /// - Parameter timeline: Updated timeline (nil only clears the cache)
    func invalidateAllCache(with timeline: Timeline? = nil) {
        if let timeline = timeline {
            updateTimeline(timeline)
        } else {
            cache.invalidateAll()
            Task {
                await renderFrame(at: currentTime)
            }
        }
    }

    /// Update the trim range
    func updateTrimRange(start: TimeInterval, end: TimeInterval?) {
        self.trimStart = start
        self.trimEnd = end

        // Adjust if the current time falls outside the trim range
        if currentTime < effectiveTrimStart {
            currentTime = effectiveTrimStart
        } else if currentTime > effectiveTrimEnd {
            currentTime = effectiveTrimEnd
        }

        // Re-render the current frame
        Task {
            await renderFrame(at: currentTime)
        }
    }

    /// Recreate the evaluator when the timeline updates
    /// - Parameter timeline: New timeline
    func updateTimeline(_ timeline: Timeline) {
        guard let project = project else { return }

        // Create a new evaluator (reuse stored mouse data)
        evaluator = RenderPipelineFactory.createEvaluator(
            timeline: timeline,
            project: project,
            mousePositions: renderMousePositions,
            clickEvents: renderClickEvents,
            frameRate: frameRate
        )

        // Invalidate the cache
        cache.invalidateAll()

        // Re-render the current frame
        Task {
            await renderFrame(at: currentTime)
        }
    }

    /// Rebuild the renderer and evaluator when render settings change
    /// - Parameter renderSettings: New render settings
    func updateRenderSettings(_ renderSettings: RenderSettings) {
        guard let project = project,
              let extractor = frameExtractor else { return }

        // Update the project's render settings (reference)
        self.project?.renderSettings = renderSettings

        // Recreate the evaluator (isWindowMode may change)
        evaluator = RenderPipelineFactory.createEvaluator(
            project: project,
            mousePositions: renderMousePositions,
            clickEvents: renderClickEvents,
            frameRate: frameRate
        )

        // Recreate the renderer
        renderer = RenderPipelineFactory.createPreviewRenderer(
            renderSettings: renderSettings,
            captureMeta: project.captureMeta,
            sourceSize: extractor.videoSize,
            scale: previewScale
        )

        // Invalidate the cache
        cache.invalidateAll()

        // Re-render the current frame
        Task {
            await renderFrame(at: currentTime)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        pause()
        frameExtractor?.cancelAllPendingRequests()
        cache.invalidateAll()
        currentFrame = nil
    }

    deinit {
        playbackTimer?.invalidate()
    }
}

// MARK: - Computed Properties

extension PreviewEngine {
    /// Current frame index
    var currentFrameNumber: Int {
        Int(currentTime * frameRate)
    }

    /// Total number of frames
    var totalFrames: Int {
        Int(duration * frameRate)
    }

    /// Playback progress (0–1) within the trim range
    var progress: Double {
        guard trimmedDuration > 0 else { return 0 }
        return (currentTime - effectiveTrimStart) / trimmedDuration
    }

    /// Cache statistics
    var cacheStatistics: PreviewCache.Statistics {
        cache.statistics
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
