import Foundation
import CoreGraphics
import AppKit
import Combine

final class MouseTracker: @unchecked Sendable {
    private(set) var currentPosition: CGPoint = .zero
    private(set) var velocity: CGVector = .zero
    private(set) var isMoving: Bool = false

    private var positionHistory: [TimestampedPosition] = []
    private let historySize = 10
    private let velocityThreshold: CGFloat = 5.0

    private let eventMonitor = EventMonitorManager()
    private var isTracking = false

    private let lock = NSLock()

    struct TimestampedPosition {
        let position: CGPoint
        let timestamp: TimeInterval
    }

    init() {}

    func startTracking() {
        guard !isTracking else { return }

        // Get initial position
        currentPosition = NSEvent.mouseLocation

        // Monitor mouse moved events (global + local)
        eventMonitor.addMouseMovementMonitor { [weak self] event in
            self?.handleMouseEvent(event)
        }

        isTracking = true
    }

    func stopTracking() {
        guard isTracking else { return }

        eventMonitor.removeAllMonitors()
        isTracking = false
    }

    private func handleMouseEvent(_ event: NSEvent) {
        let position = NSEvent.mouseLocation

        lock.lock()
        defer { lock.unlock() }

        let now = ProcessInfo.processInfo.systemUptime

        // Update history
        positionHistory.append(TimestampedPosition(position: position, timestamp: now))
        if positionHistory.count > historySize {
            positionHistory.removeFirst()
        }

        // Calculate velocity
        if positionHistory.count >= 2 {
            let recent = positionHistory.suffix(2)
            if let first = recent.first, let last = recent.last {
                let dt = last.timestamp - first.timestamp

                if dt > 0 {
                    velocity = CGVector(
                        dx: (last.position.x - first.position.x) / dt,
                        dy: (last.position.y - first.position.y) / dt
                    )
                }
            }
        }

        // Determine if moving
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        isMoving = speed > velocityThreshold

        currentPosition = position
    }

    var screenPosition: CGPoint {
        // Convert from screen coordinates (origin at bottom-left) to standard coordinates (top-left origin)
        CoordinateConverter.appKitToTopLeftOrigin(currentPosition, screenHeight: CoordinateConverter.mainScreenHeight)
    }

    func normalizedPosition(in bounds: CGRect) -> CGPoint {
        let screenPos = screenPosition
        return CGPoint(
            x: (screenPos.x - bounds.origin.x) / bounds.width,
            y: (screenPos.y - bounds.origin.y) / bounds.height
        )
    }

    var averageVelocity: CGVector {
        lock.lock()
        defer { lock.unlock() }

        guard positionHistory.count >= 2,
              let first = positionHistory.first,
              let last = positionHistory.last else { return .zero }
        let dt = last.timestamp - first.timestamp

        guard dt > 0 else { return .zero }

        return CGVector(
            dx: (last.position.x - first.position.x) / dt,
            dy: (last.position.y - first.position.y) / dt
        )
    }

    var speed: CGFloat {
        sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
    }

    deinit {
        stopTracking()
    }
}
