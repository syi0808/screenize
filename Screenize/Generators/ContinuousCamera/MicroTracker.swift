import Foundation
import CoreGraphics

/// Idle re-centering layer (Layer 2) for the dual-layer camera system.
///
/// When cursor velocity drops below threshold (idle), slowly applies a
/// correction offset to drift the camera center toward the cursor.
/// When cursor is actively moving, correction decays toward zero
/// (Layer 1's fast spring handles tracking).
struct MicroTracker {

    private let settings: MicroTrackerSettings
    private(set) var correction: (x: CGFloat, y: CGFloat) = (0, 0)
    private var velocityX: CGFloat = 0
    private var velocityY: CGFloat = 0
    private var previousCursorPosition: NormalizedPoint?

    init(settings: MicroTrackerSettings) {
        self.settings = settings
    }

    /// Update re-centering correction based on cursor activity.
    mutating func update(
        cursorPosition: NormalizedPoint,
        cameraCenter: NormalizedPoint,
        zoom: CGFloat,
        dt: CGFloat
    ) {
        // Compute cursor velocity for idle detection
        let cursorVelocity: CGFloat
        if let prev = previousCursorPosition {
            let dx = cursorPosition.x - prev.x
            let dy = cursorPosition.y - prev.y
            cursorVelocity = sqrt(dx * dx + dy * dy) / max(dt, 0.001)
        } else {
            cursorVelocity = 0
        }
        previousCursorPosition = cursorPosition

        let isIdle = cursorVelocity < settings.idleVelocityThreshold

        if isIdle {
            // Target: correct the gap between camera and cursor
            var targetX = cursorPosition.x - cameraCenter.x
            var targetY = cursorPosition.y - cameraCenter.y

            // Clamp target to viewport bounds
            let halfCrop = 0.5 / max(zoom, 1.0)
            let maxCenterX = 1.0 - halfCrop
            let minCenterX = halfCrop
            let maxCenterY = 1.0 - halfCrop
            let minCenterY = halfCrop

            if cameraCenter.x + targetX > maxCenterX {
                targetX = maxCenterX - cameraCenter.x
            } else if cameraCenter.x + targetX < minCenterX {
                targetX = minCenterX - cameraCenter.x
            }

            if cameraCenter.y + targetY > maxCenterY {
                targetY = maxCenterY - cameraCenter.y
            } else if cameraCenter.y + targetY < minCenterY {
                targetY = minCenterY - cameraCenter.y
            }

            let omega = 2.0 * .pi / max(0.001, settings.response)
            let zeta = settings.dampingRatio

            let (newX, newVX) = SpringDamperSimulator.springStep(
                current: correction.x, velocity: velocityX,
                target: targetX,
                omega: omega, zeta: zeta, dt: dt
            )
            let (newY, newVY) = SpringDamperSimulator.springStep(
                current: correction.y, velocity: velocityY,
                target: targetY,
                omega: omega, zeta: zeta, dt: dt
            )

            correction = (newX, newY)
            velocityX = newVX
            velocityY = newVY
        } else {
            // Active: decay correction toward zero
            let decayOmega = 2.0 * .pi / max(0.001, settings.response * 0.5)
            let decayZeta: CGFloat = 1.0

            let (newX, newVX) = SpringDamperSimulator.springStep(
                current: correction.x, velocity: velocityX,
                target: 0,
                omega: decayOmega, zeta: decayZeta, dt: dt
            )
            let (newY, newVY) = SpringDamperSimulator.springStep(
                current: correction.y, velocity: velocityY,
                target: 0,
                omega: decayOmega, zeta: decayZeta, dt: dt
            )

            correction = (newX, newY)
            velocityX = newVX
            velocityY = newVY
        }
    }
}
