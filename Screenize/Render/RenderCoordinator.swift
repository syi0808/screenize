import Foundation
import CoreGraphics
import CoreImage
import AVFoundation
import Metal

/// Render coordinator
/// Schedules and executes frame rendering on a dedicated background queue.
/// Handles both sequential playback (AVAssetReader) and random-access scrubbing (AVAssetImageGenerator).
/// Outputs GPU-resident MTLTexture for zero-copy display via MetalPreviewView.
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

    /// GPU-resident texture cache (replaces CGImage-based PreviewCache)
    private var textureCache: PreviewTextureCache?

    /// Frame rate
    private var frameRate: Double = 60.0

    /// Fixed quantization rate for cache keys (matches CMTime timescale).
    /// Decoupled from source frame rate to support VFR videos.
    private static let cacheQuantizationRate: Double = 600

    /// Preview scale
    private let previewScale: CGFloat

    /// Maximum cache size
    private let maxCacheSize: Int

    /// Whether a playback frame render is in progress (for frame dropping)
    private var isRenderingPlaybackFrame: Bool = false

    /// Current render generation (incremented on seek/invalidation)
    private var renderGeneration: Int = 0

    /// Lock for thread-safe access to shared state
    private let lock = NSLock()

    // MARK: - Initialization

    init(previewScale: CGFloat = 0.5, cacheSize: Int = 180) {
        self.previewScale = previewScale
        self.maxCacheSize = cacheSize
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

        // Create GPU-resident texture cache using the renderer's Metal device
        if let device = renderer.device {
            let outputSize = renderer.outputSize
            self.textureCache = PreviewTextureCache(
                device: device,
                width: Int(outputSize.width),
                height: Int(outputSize.height),
                maxSize: maxCacheSize
            )
        }
    }

    // MARK: - Playback Frame Rendering

    /// Request a frame for playback (called from DisplayLink thread)
    /// Returns immediately if another playback render is in flight (frame drop).
    /// - Parameters:
    ///   - time: Target video time
    ///   - completion: Called with the rendered MTLTexture (on an unspecified thread)
    func requestPlaybackFrame(
        at time: TimeInterval,
        completion: @escaping (MTLTexture?, TimeInterval) -> Void
    ) {
        lock.lock()

        // Frame drop: skip if previous frame not done
        guard !isRenderingPlaybackFrame else {
            lock.unlock()
            return
        }

        let cacheKey = Int(time * Self.cacheQuantizationRate)
        let generation = renderGeneration

        // Check cache
        if let cachedTexture = textureCache?.texture(at: cacheKey) {
            lock.unlock()
            completion(cachedTexture, time)
            return
        }

        isRenderingPlaybackFrame = true
        let evaluator = self.evaluator
        let renderer = self.renderer
        let reader = self.sequentialReader
        let cache = self.textureCache

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

            // Acquire a texture from the cache pool
            guard let targetTexture = cache?.acquireTexture() else {
                return
            }

            // Render to GPU-resident texture (synchronous, waits for GPU)
            guard renderer.renderToTexture(
                sourceFrame: frame.image,
                state: state,
                targetTexture: targetTexture
            ) else { return }

            // Check generation again
            self.lock.lock()
            guard generation == self.renderGeneration else {
                self.lock.unlock()
                return
            }
            self.lock.unlock()

            // Store in cache
            let actualCacheKey = Int(frame.time * Self.cacheQuantizationRate)
            cache?.store(targetTexture, at: actualCacheKey)

            // Deliver
            completion(targetTexture, frame.time)
        }
    }

    // MARK: - Scrub Frame Rendering

    /// Request a frame for scrubbing (called from ScrubController)
    /// Uses AVAssetImageGenerator for random access.
    /// - Parameters:
    ///   - time: Target video time
    ///   - generation: Generation counter from ScrubController
    ///   - completion: Called with the rendered MTLTexture
    func requestScrubFrame(
        at time: TimeInterval,
        generation scrubGeneration: Int,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        lock.lock()
        let cacheKey = Int(time * Self.cacheQuantizationRate)
        let evaluator = self.evaluator
        let renderer = self.renderer
        let extractor = self.frameExtractor
        let cache = self.textureCache
        lock.unlock()

        // Check cache first
        if let cachedTexture = cache?.texture(at: cacheKey) {
            completion(cachedTexture)
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

                    // Acquire texture and render
                    guard let targetTexture = cache?.acquireTexture() else {
                        completion(nil)
                        return
                    }

                    guard renderer.renderToTexture(
                        sourceFrame: sourceFrame,
                        state: state,
                        targetTexture: targetTexture
                    ) else {
                        completion(nil)
                        return
                    }

                    // Cache the result
                    cache?.store(targetTexture, at: cacheKey)
                    completion(targetTexture)

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

        // Recreate texture cache if the output size or max size changed
        if let device = newRenderer.device {
            let outputSize = newRenderer.outputSize
            let currentCache = textureCache
            let needsRecreate = currentCache == nil
                || currentCache?.statistics.maxSize != maxCacheSize
                || currentCache?.textureWidth != Int(outputSize.width)
                || currentCache?.textureHeight != Int(outputSize.height)

            if needsRecreate {
                textureCache = PreviewTextureCache(
                    device: device,
                    width: Int(outputSize.width),
                    height: Int(outputSize.height),
                    maxSize: maxCacheSize
                )
            }
        }

        lock.unlock()
    }

    // MARK: - Cache Management

    /// Invalidate cached frames within a time range
    func invalidateCache(from startTime: TimeInterval, to endTime: TimeInterval) {
        let startKey = Int(startTime * Self.cacheQuantizationRate)
        let endKey = Int(endTime * Self.cacheQuantizationRate)
        textureCache?.invalidate(from: startKey, to: endKey)
    }

    /// Invalidate the entire cache
    func invalidateAllCache() {
        textureCache?.invalidateAll()
    }

    /// Check if a frame at the given time is cached
    func isCached(at time: TimeInterval) -> Bool {
        let cacheKey = Int(time * Self.cacheQuantizationRate)
        return textureCache?.isCached(cacheKey) ?? false
    }

    /// Current cache statistics
    var cacheStatistics: PreviewTextureCache.Statistics {
        textureCache?.statistics ?? PreviewTextureCache.Statistics(
            cachedFrameCount: 0,
            maxSize: maxCacheSize,
            dirtyRangeCount: 0,
            utilizationPercent: 0,
            poolSize: 0
        )
    }

    // MARK: - Cleanup

    func cleanup() {
        lock.lock()
        renderGeneration += 1
        lock.unlock()

        frameExtractor?.cancelAllPendingRequests()
        sequentialReader?.stopReading()
        textureCache?.invalidateAll()
    }
}
