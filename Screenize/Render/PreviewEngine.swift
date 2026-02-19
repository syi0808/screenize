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

    /// Last render error (for UI display)
    @Published private(set) var lastRenderError: RenderError?

    /// Cumulative render error count
    @Published private(set) var renderErrorCount: Int = 0

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

    /// Playback task (replaces timer for controlled async loop)
    private var playbackTask: Task<Void, Never>?

    /// Render generation (incremented on seek to invalidate stale renders)
    private var renderGeneration: Int = 0

    /// Prefetch task (decodes frames ahead of playback)
    private var prefetchTask: Task<Void, Never>?

    /// Last prefetched frame index (reset on seek)
    private var lastPrefetchedIndex: Int = -1

    /// Wall-clock time when playback started (for real-time sync)
    private var playbackStartWallTime: ContinuousClock.Instant?

    /// Video time when playback started (for real-time sync)
    private var playbackStartVideoTime: TimeInterval = 0

    /// Last render time (for performance metrics)
    private var lastRenderTime: Date?

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
            print("Loaded mouse data: \(rawMousePositions.count) raw, \(smoothedMousePositions.count) smoothed positions")

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

        // Record wall-clock anchor for real-time sync
        playbackStartWallTime = ContinuousClock.now
        playbackStartVideoTime = currentTime

        isPlaying = true
        startPlaybackLoop()
        startPrefetching()
    }

    /// Pause playback
    func pause() {
        isPlaying = false
        playbackStartWallTime = nil
        stopPlaybackLoop()
        stopPrefetching()
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

        // Invalidate in-flight renders, cancel pending extractions, reset prefetch
        renderGeneration += 1
        frameExtractor?.cancelAllPendingRequests()
        lastPrefetchedIndex = -1

        currentTime = clampedTime

        if isPlaying {
            // Re-anchor wall-clock so the playback loop continues from the seek position
            playbackStartWallTime = ContinuousClock.now
            playbackStartVideoTime = clampedTime
        } else {
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
        let generation = renderGeneration

        // Check the cache
        if let cachedFrame = cache.frame(at: frameIndex) {
            currentFrame = cachedFrame
            return
        }

        do {
            // Extract the frame
            let sourceFrame = try await extractor.extractFrame(at: time)

            // Abort if a seek invalidated this render
            guard generation == renderGeneration else { return }

            // Evaluate rendering state
            let state = evaluator.evaluate(at: time)

            // Perform rendering
            if let rendered = renderer.renderToCGImage(
                sourceFrame: sourceFrame, state: state
            ) {
                guard generation == renderGeneration else { return }
                cache.store(rendered, at: frameIndex)
                currentFrame = rendered
            }

        } catch {
            guard generation == renderGeneration else { return }
            handleRenderError(error, at: time)
        }
    }

    /// Record a render error and expose it to the UI
    private func handleRenderError(_ error: Error, at time: TimeInterval) {
        renderErrorCount += 1
        lastRenderError = RenderError(
            time: time,
            frameIndex: Int(time * frameRate),
            message: error.localizedDescription
        )
    }

    /// Dismiss the render error banner
    func clearRenderError() {
        lastRenderError = nil
    }

    // MARK: - Playback Loop

    private func startPlaybackLoop() {
        let frameDuration = 1.0 / frameRate

        playbackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self,
                      self.isPlaying,
                      let wallStart = self.playbackStartWallTime else { break }

                // Compute target video time from wall-clock elapsed time
                let wallElapsed = ContinuousClock.now - wallStart
                let elapsedSeconds = Double(wallElapsed.components.seconds)
                    + Double(wallElapsed.components.attoseconds) / 1e18
                let newTime = self.playbackStartVideoTime + elapsedSeconds

                // Stop playback at trim end
                if newTime >= self.effectiveTrimEnd {
                    self.currentTime = self.effectiveTrimEnd
                    self.pause()
                    break
                }

                self.currentTime = newTime

                // Render frame (one at a time — no task piling)
                await self.renderFrame(at: newTime)

                // Sleep until the next frame boundary
                let nextFrameVideoTime = (floor(newTime / frameDuration) + 1.0) * frameDuration
                let nextFrameWallTime = wallStart + Duration.seconds(
                    nextFrameVideoTime - self.playbackStartVideoTime
                )
                let sleepDuration = nextFrameWallTime - ContinuousClock.now
                if sleepDuration > .zero {
                    try? await Task.sleep(for: sleepDuration)
                }
            }
        }
    }

    private func stopPlaybackLoop() {
        playbackTask?.cancel()
        playbackTask = nil
    }

    // MARK: - Frame Prefetching

    private func startPrefetching() {
        stopPrefetching()

        prefetchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self,
                      let extractor = self.frameExtractor,
                      let evaluator = self.evaluator,
                      let renderer = self.renderer else { break }

                let currentIdx = Int(self.currentTime * self.frameRate)
                let maxFrame = self.totalFrames - 1

                // Prefetch 10–120 frames ahead of current position
                let prefetchStart = min(maxFrame, currentIdx + 10)
                let prefetchEnd = min(maxFrame, currentIdx + 120)

                guard prefetchStart <= prefetchEnd,
                      prefetchStart > self.lastPrefetchedIndex else {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }

                // Collect uncached frames
                var timesToFetch: [(index: Int, time: TimeInterval)] = []
                for idx in prefetchStart...prefetchEnd {
                    if !self.cache.isCached(idx) {
                        timesToFetch.append((idx, Double(idx) / self.frameRate))
                    }
                }

                // Batch extract (up to 30 at a time)
                let batchSize = 30
                for batchStart in stride(from: 0, to: timesToFetch.count, by: batchSize) {
                    guard !Task.isCancelled else { break }

                    let batchEnd = min(batchStart + batchSize, timesToFetch.count)
                    let batch = Array(timesToFetch[batchStart..<batchEnd])
                    let times = batch.map { $0.time }

                    do {
                        let frames = try await extractor.extractFrames(at: times)

                        for (extracted, info) in zip(frames, batch) {
                            guard !Task.isCancelled else { break }
                            let state = evaluator.evaluate(at: extracted.0)
                            if let img = renderer.renderToCGImage(
                                sourceFrame: extracted.1, state: state
                            ) {
                                self.cache.store(img, at: info.index)
                            }
                        }
                    } catch {
                        break // Skip remaining batches on error
                    }
                }

                self.lastPrefetchedIndex = prefetchEnd
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func stopPrefetching() {
        prefetchTask?.cancel()
        prefetchTask = nil
        lastPrefetchedIndex = -1
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
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
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
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
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
        stopPrefetching()
        frameExtractor?.cancelAllPendingRequests()
        cache.invalidateAll()
        currentFrame = nil
    }

    deinit {
        playbackTask?.cancel()
        prefetchTask?.cancel()
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
