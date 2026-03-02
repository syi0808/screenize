import Foundation
import AppKit

/// Handles mouse click events
final class ClickEventHandler {

    // MARK: - Types

    struct PendingClick {
        let start: TimeInterval
        let position: CGPoint
        let type: ClickType
        let targetElement: UIElementInfo?
    }

    // MARK: - Properties

    private var pendingClicks: [UUID: PendingClick] = [:]
    private var clicks: [MouseClickEvent] = []
    private let lock = NSLock()

    private let accessibilityInspector: AccessibilityInspector
    private let coordinateConverter: () -> CoordinateConverter?
    private let recordingStartTime: () -> TimeInterval

    // MARK: - Initialization

    init(
        accessibilityInspector: AccessibilityInspector,
        coordinateConverter: @escaping () -> CoordinateConverter?,
        recordingStartTime: @escaping () -> TimeInterval
    ) {
        self.accessibilityInspector = accessibilityInspector
        self.coordinateConverter = coordinateConverter
        self.recordingStartTime = recordingStartTime
    }

    // MARK: - Event Handling

    func handleMouseDown(_ event: NSEvent, screenBounds: CGRect) {
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timestamp = currentTime - recordingStartTime()
        let position = NSEvent.mouseLocation

        let clickType: ClickType
        switch event.type {
        case .leftMouseDown:
            clickType = .left
        case .rightMouseDown:
            clickType = .right
        default:
            return
        }

        let clickId = UUID()
        let relativePosition = convertToScreenBounds(position, screenBounds: screenBounds)

        // Accessibility API needs absolute screen coordinates (top-left origin, CG coordinate space)
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let accessibilityPoint = CGPoint(x: position.x, y: screenHeight - position.y)
        let targetElement = accessibilityInspector.elementAt(screenPoint: accessibilityPoint)

        lock.withLock {
            pendingClicks[clickId] = PendingClick(
                start: timestamp,
                position: relativePosition,
                type: clickType,
                targetElement: targetElement
            )
        }

        // Set a timeout for short clicks (auto finalize after 1 second)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.finalizePendingClick(id: clickId)
        }
    }

    func handleMouseUp(_ event: NSEvent) {
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timestamp = currentTime - recordingStartTime()

        let clickType: ClickType
        switch event.type {
        case .leftMouseUp:
            clickType = .left
        case .rightMouseUp:
            clickType = .right
        default:
            return
        }

        lock.withLock {
            // Find the oldest pending click of that type
            if let (id, pending) = pendingClicks.first(where: { $0.value.type == clickType }) {
                let duration = timestamp - pending.start
                let clickEvent = MouseClickEvent(
                    timestamp: pending.start,
                    x: pending.position.x,
                    y: pending.position.y,
                    type: clickType,
                    duration: max(0.05, duration),  // Minimum 50ms
                    targetElement: pending.targetElement
                )
                clicks.append(clickEvent)
                pendingClicks.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Finalization

    private func finalizePendingClick(id: UUID) {
        lock.withLock {
            guard let pending = pendingClicks[id] else { return }

            let clickEvent = MouseClickEvent(
                timestamp: pending.start,
                x: pending.position.x,
                y: pending.position.y,
                type: pending.type,
                duration: 0.1,  // Default duration
                targetElement: pending.targetElement
            )
            clicks.append(clickEvent)
            pendingClicks.removeValue(forKey: id)
        }
    }

    func finalizePendingClicks() {
        lock.withLock {
            for (_, pending) in pendingClicks {
                let clickEvent = MouseClickEvent(
                    timestamp: pending.start,
                    x: pending.position.x,
                    y: pending.position.y,
                    type: pending.type,
                    duration: 0.1,
                    targetElement: pending.targetElement
                )
                clicks.append(clickEvent)
            }
            pendingClicks.removeAll()
        }
    }

    // MARK: - Results

    func getClicks() -> [MouseClickEvent] {
        lock.withLock { clicks }
    }

    func reset() {
        lock.withLock {
            clicks.removeAll()
            pendingClicks.removeAll()
        }
    }

    // MARK: - Coordinate Conversion

    private func convertToScreenBounds(_ screenPosition: CGPoint, screenBounds: CGRect) -> CGPoint {
        guard let converter = coordinateConverter() else {
            // Fallback: calculate manually
            let relativeX = screenPosition.x - screenBounds.origin.x
            let relativeY = screenPosition.y - screenBounds.origin.y
            return CGPoint(x: relativeX, y: relativeY)
        }

        let capturePixel = converter.screenToCapturePixel(screenPosition)
        return capturePixel.toCGPoint()
    }
}
