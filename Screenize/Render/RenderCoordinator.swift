import Foundation
import CoreGraphics
import CoreImage
import AVFoundation

/// Render coordinator
/// Schedules and executes frame rendering on a dedicated background queue.
/// Handles both sequential playback (AVAssetReader) and random-access scrubbing (AVAssetImageGenerator).
final class RenderCoordinator: @unchecked Sendable {

    // MARK: - Properties

    /// Dedicated render queue (serial, high priority)
    private let renderQueue = DispatchQueue(label: "com.screenize.render", qos: .userInteractive)

    /// Sequential frame reader for playback
    private var sequentialReader: SequentialFrameReader?

    /// Random-access frame extractor for scrubbing
    private var frameExtractor: VideoFrameExtractor?

    /// Frame evaluator (atomically swapped on timeline updates)
    private var evaluator: FrameEvaluator?

    /// Renderer
    private var renderer: Renderer?

    /// Frame cache (LRU with dirty ranges)
    private let cache: PreviewCache

    /// Frame rate
    private var frameRate: Double = 60.0

    /// Preview scale
    private let previewScale: CGFloat

    /// Whether a playback frame render is in progress (for frame dropping)
    private var isRenderingPlaybackFrame: Bool = false

    /// Current render generation (incremented on seek/invalidation)
    private var renderGeneration: Int = 0

    /// Lock for thread-safe access to shared state
    private let lock = NSLock()

    // MARK: - Initialization

    init(previewScale: CGFloat = 0.5, cacheSize: Int = 180) {
        self.previewScale = previewScale
        self.cache = PreviewCache(maxSize: cacheSize)
    }

    // MARK: - Setup

    /// Configure the coordinator with video and pipeline components
    func setup(
        sequentialReader: SequentialFrameReader,
        frameExtractor: VideoFrameExtractor,
        evaluator: FrameEvaluator,
        renderer: Renderer,
        frameRate: Double
    ) {
        lock.lock()
        defer { lock.unlock() }

        self.sequentialReader = sequentialReader
        self.frameExtractor = frameExtractor
        self.evaluator = evaluator
        self.renderer = renderer
        self.frameRate = frameRate
        self.cache.invalidateAll()
    }

    // MARK: - Playback Frame Rendering

    /// Request a frame for playback (called from DisplayLink thread)
    /// Returns immediately if another playback render is in flight (frame drop).
    /// - Parameters:
    ///   - time: Target video time
    ///   - completion: Called with the rendered CGImage (on an unspecified thread)
    func requestPlaybackFrame(
        at time: TimeInterval,
        completion: @escaping (CGImage?, TimeInterval) -> Void
    ) {
        lock.lock()

        // Frame drop: skip if previous frame not done
        guard !isRenderingPlaybackFrame else {
            lock.unlock()
            return
        }

        let frameIndex = Int(time * frameRate)
        let generation = renderGeneration

        // Check cache
        if let cachedFrame = cache.frame(at: frameIndex) {
            lock.unlock()
            completion(cachedFrame, time)
            return
        }

        isRenderingPlaybackFrame = true
        let evaluator = self.evaluator
        let renderer = self.renderer
        let reader = self.sequentialReader

        lock.unlock()

        renderQueue.async { [weak self] in
            guard let self = self else { return }

            defer {
                self.lock.lock()
                self.isRenderingPlaybackFrame = false
                self.lock.unlock()
            }

            // Check generation (seek may have happened)
            self.lock.lock()
            guard generation == self.renderGeneration else {
                self.lock.unlock()
                return
            }
            self.lock.unlock()

            guard let evaluator = evaluator,
                  let renderer = renderer,
                  let reader = reader else {
                return
            }

            // Read next frame from sequential reader
            guard let frame = reader.nextFrame() else { return }

            // Evaluate the state at this time
            let state = evaluator.evaluate(at: frame.time)

            // Render
            guard let rendered = renderer.renderToCGImage(
                sourceFrame: frame.image,
                state: state
            ) else { return }

            // Check generation again
            self.lock.lock()
            guard generation == self.renderGeneration else {
                self.lock.unlock()
                return
            }
            self.lock.unlock()

            // Store in cache
            let actualFrameIndex = Int(frame.time * self.frameRate)
            self.cache.store(rendered, at: actualFrameIndex)

            // Deliver
            completion(rendered, frame.time)
        }
    }

    // MARK: - Scrub Frame Rendering

    /// Request a frame for scrubbing (called from ScrubController)
    /// Uses AVAssetImageGenerator for random access.
    /// - Parameters:
    ///   - time: Target video time
    ///   - generation: Generation counter from ScrubController
    ///   - completion: Called with the rendered CGImage
    func requestScrubFrame(
        at time: TimeInterval,
        generation scrubGeneration: Int,
        completion: @escaping (CGImage?) -> Void
    ) {
        lock.lock()
        let frameIndex = Int(time * frameRate)
        let evaluator = self.evaluator
        let renderer = self.renderer
        let extractor = self.frameExtractor
        lock.unlock()

        // Check cache first
        if let cachedFrame = cache.frame(at: frameIndex) {
            completion(cachedFrame)
            return
        }

        renderQueue.async { [weak self] in
            guard let self = self,
                  let evaluator = evaluator,
                  let renderer = renderer,
                  let extractor = extractor else {
                completion(nil)
                return
            }

            // Extract frame via AVAssetImageGenerator (random access)
            Task {
                do {
                    let sourceFrame = try await extractor.extractFrame(at: time)

                    // Evaluate state
                    let state = evaluator.evaluate(at: time)

                    // Render
                    guard let rendered = renderer.renderToCGImage(
                        sourceFrame: sourceFrame,
                        state: state
                    ) else {
                        completion(nil)
                        return
                    }

                    // Cache the result
                    self.cache.store(rendered, at: frameIndex)
                    completion(rendered)

                } catch {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Seek

    /// Prepare for a seek to a new time
    /// Invalidates in-flight renders and repositions the sequential reader.
    /// - Parameter time: Target seek time
    func seek(to time: TimeInterval) {
        lock.lock()
        renderGeneration += 1
        let reader = sequentialReader
        lock.unlock()

        frameExtractor?.cancelAllPendingRequests()

        // Reposition sequential reader on render queue
        renderQueue.async {
            try? reader?.seek(to: time)
        }
    }

    // MARK: - Timeline & Settings Updates

    /// Update the frame evaluator (called when timeline changes)
    func updateEvaluator(_ newEvaluator: FrameEvaluator) {
        lock.lock()
        evaluator = newEvaluator
        lock.unlock()
    }

    /// Update the renderer (called when render settings change)
    func updateRenderer(_ newRenderer: Renderer) {
        lock.lock()
        renderer = newRenderer
        lock.unlock()
    }

    // MARK: - Cache Management

    /// Invalidate cached frames within a time range
    func invalidateCache(from startTime: TimeInterval, to endTime: TimeInterval) {
        let startFrame = Int(startTime * frameRate)
        let endFrame = Int(endTime * frameRate)
        cache.invalidate(from: startFrame, to: endFrame)
    }

    /// Invalidate the entire cache
    func invalidateAllCache() {
        cache.invalidateAll()
    }

    /// Check if a frame at the given time is cached
    func isCached(at time: TimeInterval) -> Bool {
        let frameIndex = Int(time * frameRate)
        return cache.isCached(frameIndex)
    }

    /// Current cache statistics
    var cacheStatistics: PreviewCache.Statistics {
        cache.statistics
    }

    // MARK: - Cleanup

    func cleanup() {
        lock.lock()
        renderGeneration += 1
        lock.unlock()

        frameExtractor?.cancelAllPendingRequests()
        sequentialReader?.stopReading()
        cache.invalidateAll()
    }
}
