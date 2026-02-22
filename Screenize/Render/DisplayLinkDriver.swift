import Foundation
import CoreVideo

/// Display link driver
/// Provides vsync-driven frame callbacks for smooth playback timing
/// Uses CVDisplayLink for all macOS versions (13+)
final class DisplayLinkDriver: @unchecked Sendable {

    // MARK: - Types

    /// Frame callback with target video time
    typealias FrameCallback = (_ targetVideoTime: TimeInterval) -> Void

    // MARK: - Properties

    /// Frame callback (called from display link thread, NOT main thread)
    var onFrame: FrameCallback?

    /// Whether the display link is running
    private(set) var isRunning: Bool = false

    /// Wall-clock time when playback started (mach_absolute_time units)
    private var playbackStartMachTime: UInt64 = 0

    /// Video time when playback started
    private var playbackStartVideoTime: TimeInterval = 0

    /// Frame rate of the video
    private var videoFrameRate: Double = 60.0

    /// Whether the previous frame has been delivered (for frame dropping)
    private var previousFrameDelivered: Bool = true

    /// Lock for thread-safe state access
    private let lock = NSLock()

    /// Mach timebase info for converting mach_absolute_time to seconds
    private let machTimebaseInfo: mach_timebase_info_data_t

    /// CVDisplayLink
    private var displayLink: CVDisplayLink?

    // MARK: - Initialization

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.machTimebaseInfo = info
    }

    deinit {
        stop()
    }

    // MARK: - Control

    /// Start the display link
    /// - Parameters:
    ///   - videoTime: Video time to start from
    ///   - frameRate: Video frame rate
    func start(fromVideoTime videoTime: TimeInterval, frameRate: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        playbackStartVideoTime = videoTime
        playbackStartMachTime = mach_absolute_time()
        videoFrameRate = frameRate
        previousFrameDelivered = true
        isRunning = true

        startDisplayLink()
    }

    /// Stop the display link
    func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else { return }
        isRunning = false

        stopDisplayLink()
    }

    /// Signal that the previous frame has been delivered
    /// Call this from the render completion path
    func markFrameDelivered() {
        lock.lock()
        defer { lock.unlock() }
        previousFrameDelivered = true
    }

    /// Update the playback anchor (e.g., after a seek during playback)
    func updateAnchor(videoTime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        playbackStartVideoTime = videoTime
        playbackStartMachTime = mach_absolute_time()
    }

    // MARK: - CVDisplayLink

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard let newLink = link else { return }
        displayLink = newLink

        let callbackPointer = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(
            newLink,
            { (_, _, _, _, _, userInfo) -> CVReturn in
                guard let userInfo = userInfo else { return kCVReturnError }
                let driver = Unmanaged<DisplayLinkDriver>.fromOpaque(userInfo).takeUnretainedValue()
                driver.handleDisplayLinkTick()
                return kCVReturnSuccess
            },
            callbackPointer
        )

        CVDisplayLinkStart(newLink)
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    // MARK: - Frame Tick

    /// Called from CVDisplayLink's high-priority thread on every vsync
    private func handleDisplayLinkTick() {
        lock.lock()

        guard isRunning else {
            lock.unlock()
            return
        }

        // Frame drop: skip if previous frame not yet delivered
        guard previousFrameDelivered else {
            lock.unlock()
            return
        }

        // Compute target video time from wall-clock elapsed
        let now = mach_absolute_time()
        let elapsed = now - playbackStartMachTime
        let elapsedNanos = Double(elapsed) * Double(machTimebaseInfo.numer) / Double(machTimebaseInfo.denom)
        let elapsedSeconds = elapsedNanos / 1_000_000_000.0
        let targetVideoTime = playbackStartVideoTime + elapsedSeconds

        // Mark as not delivered until render completes
        previousFrameDelivered = false

        lock.unlock()

        // Fire the callback (from CVDisplayLink's background thread)
        onFrame?(targetVideoTime)
    }
}
