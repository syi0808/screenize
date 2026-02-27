import Foundation
import AppKit

/// Scroll event handler
final class ScrollEventHandler {

    // MARK: - Properties

    private var scrollEvents: [ScrollEvent] = []
    private let lock = NSLock()

    private let coordinateConverter: () -> CoordinateConverter?
    private let recordingStartTime: () -> TimeInterval

    // MARK: - Initialization

    init(
        coordinateConverter: @escaping () -> CoordinateConverter?,
        recordingStartTime: @escaping () -> TimeInterval
    ) {
        self.coordinateConverter = coordinateConverter
        self.recordingStartTime = recordingStartTime
    }

    // MARK: - Event Handling

    func handleScroll(_ event: NSEvent, screenBounds: CGRect) {
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timestamp = currentTime - recordingStartTime()
        let position = NSEvent.mouseLocation
        let relativePosition = convertToScreenBounds(position, screenBounds: screenBounds)

        // Scroll delta (trackpad produces finer values)
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY

        // Ignore extremely small scrolls (noise filtering)
        guard abs(deltaX) > 0.1 || abs(deltaY) > 0.1 else { return }

        let scrollEvent = ScrollEvent(
            timestamp: timestamp,
            x: relativePosition.x,
            y: relativePosition.y,
            deltaX: deltaX,
            deltaY: deltaY,
            isTrackpad: event.hasPreciseScrollingDeltas
        )

        lock.withLock { scrollEvents.append(scrollEvent) }
    }

    // MARK: - Results

    func getScrollEvents() -> [ScrollEvent] {
        lock.withLock { scrollEvents }
    }

    func reset() {
        lock.withLock { scrollEvents.removeAll() }
    }

    // MARK: - Coordinate Conversion

    private func convertToScreenBounds(_ screenPosition: CGPoint, screenBounds: CGRect) -> CGPoint {
        guard let converter = coordinateConverter() else {
            let relativeX = screenPosition.x - screenBounds.origin.x
            let relativeY = screenPosition.y - screenBounds.origin.y
            return CGPoint(x: relativeX, y: relativeY)
        }

        let capturePixel = converter.screenToCapturePixel(screenPosition)
        return capturePixel.toCGPoint()
    }
}
