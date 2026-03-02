import Foundation
import AppKit

/// Drag event handler
final class DragEventHandler {

    // MARK: - Types

    struct PendingDrag {
        let start: TimeInterval
        let startPosition: CGPoint
    }

    // MARK: - Properties

    private var dragEvents: [DragEvent] = []
    private var pendingDrag: PendingDrag?
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

    func handleDrag(_ event: NSEvent, screenBounds: CGRect) {
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timestamp = currentTime - recordingStartTime()
        let position = NSEvent.mouseLocation
        let relativePosition = convertToScreenBounds(position, screenBounds: screenBounds)

        lock.withLock {
            if pendingDrag == nil {
                // Start dragging
                pendingDrag = PendingDrag(start: timestamp, startPosition: relativePosition)
            }
            // While dragging, only update the current position (track the end location)
        }
    }

    // MARK: - Finalization

    func finalizePendingDrag(screenBounds: CGRect) {
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timestamp = currentTime - recordingStartTime()
        let position = NSEvent.mouseLocation
        let relativePosition = convertToScreenBounds(position, screenBounds: screenBounds)

        lock.withLock {
            guard let pending = pendingDrag else { return }

            // Enforce a minimum drag distance (at least 10 pixels)
            let dx = relativePosition.x - pending.startPosition.x
            let dy = relativePosition.y - pending.startPosition.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance >= 10 {
                let dragEvent = DragEvent(
                    startTimestamp: pending.start,
                    endTimestamp: timestamp,
                    startX: pending.startPosition.x,
                    startY: pending.startPosition.y,
                    endX: relativePosition.x,
                    endY: relativePosition.y,
                    type: .selection
                )
                dragEvents.append(dragEvent)
            }

            pendingDrag = nil
        }
    }

    // MARK: - Results

    func getDragEvents() -> [DragEvent] {
        lock.withLock { dragEvents }
    }

    func reset() {
        lock.withLock {
            dragEvents.removeAll()
            pendingDrag = nil
        }
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
