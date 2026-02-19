import Foundation
import CoreGraphics

/// Scrub controller
/// Coalesces rapid scrub events into single render requests (latest-value-wins pattern)
/// Guarantees at most one render in flight during scrubbing
final class ScrubController: @unchecked Sendable {

    // MARK: - Types

    /// Render request callback
    typealias RenderRequest = (_ time: TimeInterval, _ generation: Int, _ completion: @escaping (CGImage?) -> Void) -> Void

    /// Frame delivery callback
    typealias FrameDelivery = (_ frame: CGImage?, _ time: TimeInterval) -> Void

    // MARK: - Properties

    /// Callback to request a frame render (called on render queue)
    var onRenderRequest: RenderRequest?

    /// Callback when a frame is ready (called on main queue)
    var onFrameReady: FrameDelivery?

    /// Pending scrub time (latest value wins)
    private var pendingTime: TimeInterval?

    /// Whether a render is currently in flight
    private var isRendering: Bool = false

    /// Generation counter for discarding stale results
    private var generation: Int = 0

    /// Lock for thread-safe state access
    private let lock = NSLock()

    // MARK: - Initialization

    init() {}

    // MARK: - Scrub Interface

    /// Submit a scrub position
    /// Called from main thread when user scrubs the timeline
    /// - Parameter time: Target time to render
    func scrub(to time: TimeInterval) {
        lock.lock()
        generation += 1
        pendingTime = time
        let shouldDispatch = !isRendering
        lock.unlock()

        if shouldDispatch {
            dispatchNext()
        }
    }

    /// Cancel all pending scrub requests
    func cancel() {
        lock.lock()
        generation += 1
        pendingTime = nil
        lock.unlock()
    }

    // MARK: - Internal

    private func dispatchNext() {
        lock.lock()

        guard let time = pendingTime else {
            lock.unlock()
            return
        }

        pendingTime = nil
        isRendering = true
        let currentGeneration = generation

        lock.unlock()

        // Dispatch render request
        onRenderRequest?(time, currentGeneration) { [weak self] frame in
            guard let self = self else { return }

            self.lock.lock()
            let isStale = currentGeneration != self.generation
            self.isRendering = false
            let hasMore = self.pendingTime != nil
            self.lock.unlock()

            // Deliver the frame if not stale
            if !isStale {
                DispatchQueue.main.async {
                    self.onFrameReady?(frame, time)
                }
            }

            // If another scrub came in during rendering, dispatch it now
            if hasMore {
                self.dispatchNext()
            }
        }
    }
}
