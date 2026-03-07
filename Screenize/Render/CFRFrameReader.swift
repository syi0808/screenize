import Foundation
import CoreImage

/// CFR (Constant Frame Rate) frame reader
/// Wraps a SequentialFrameReader to provide time-based frame access that fills
/// VFR gaps by holding the latest source frame before the requested time.
/// Consumers see a gap-free stream regardless of the source video's frame timing.
final class CFRFrameReader {

    // MARK: - Properties

    /// Underlying VFR source reader
    private let source: SequentialFrameReader

    /// Latest source frame with time <= last requested time
    private var heldFrame: (time: TimeInterval, image: CIImage)?

    /// First source frame with time > last requested time (buffered for next call)
    private var lookaheadFrame: (time: TimeInterval, image: CIImage)?

    // MARK: - Initialization

    init(source: SequentialFrameReader) {
        self.source = source
    }

    // MARK: - Frame Access

    /// Return the frame that should be displayed at the given time.
    /// Fills VFR gaps by holding the latest source frame before `time`.
    /// - Parameter time: Target display time
    /// - Returns: Tuple of (requested time, CIImage) or nil at EOF with no held frame
    func frame(at time: TimeInterval) -> (time: TimeInterval, image: CIImage)? {
        // 1. Promote lookahead to held if it's now at or before the requested time
        if let lookahead = lookaheadFrame, lookahead.time <= time {
            heldFrame = lookahead
            lookaheadFrame = nil
        }

        // 2. Read from source only when no lookahead is buffered
        if lookaheadFrame == nil {
            while let nextFrame = source.nextFrame() {
                if nextFrame.time > time {
                    // Future frame — buffer it, keep current held
                    lookaheadFrame = nextFrame
                    break
                }
                // At or before requested time — update held
                heldFrame = nextFrame
            }
        }

        // 3. Return held frame at the requested time (not the source PTS)
        guard let frame = heldFrame else { return nil }
        return (time, frame.image)
    }

    // MARK: - Seeking

    /// Seek to a new time. Clears held/lookahead state and repositions the source reader.
    func seek(to time: TimeInterval) throws {
        heldFrame = nil
        lookaheadFrame = nil
        try source.seek(to: time)
    }

    // MARK: - Lifecycle

    /// Stop reading and release resources
    func stopReading() {
        heldFrame = nil
        lookaheadFrame = nil
        source.stopReading()
    }

    // MARK: - Status

    var isReading: Bool { source.isReading }
    var frameRate: Double { source.frameRate }
    var duration: TimeInterval { source.duration }
}
