import Foundation
import CoreGraphics

/// Micro tracking layer for the dual-layer camera system.
///
/// Tracks cursor/caret within the macro frame by computing a small offset.
/// Uses a dead zone to avoid reacting to small movements near frame center.
/// The offset is spring-animated for smooth following.
struct MicroTracker {

    private let settings: MicroTrackerSettings
    private(set) var offset: (x: CGFloat, y: CGFloat) = (0, 0)
    private var velocityX: CGFloat = 0
    private var velocityY: CGFloat = 0

    init(settings: MicroTrackerSettings) {
        self.settings = settings
    }

    /// Update micro offset based on cursor position relative to macro center.
    mutating func update(
        cursorPosition: NormalizedPoint,
        macroCenter: NormalizedPoint,
        zoom: CGFloat,
        dt: CGFloat,
        isIdle: Bool = false
    ) {
        let viewportHalf = 0.5 / max(zoom, 1.0)
        let deadZone = viewportHalf * settings.deadZoneRatio
        let maxOffset = viewportHalf * settings.maxOffsetRatio

        let targetOffset: (x: CGFloat, y: CGFloat)

        if isIdle {
            targetOffset = (0, 0)
        } else {
            let relX = cursorPosition.x - macroCenter.x
            let relY = cursorPosition.y - macroCenter.y

            let excessX = abs(relX) - deadZone
            let excessY = abs(relY) - deadZone

            var tx: CGFloat = 0
            var ty: CGFloat = 0
            if excessX > 0 { tx = copysign(excessX, relX) }
            if excessY > 0 { ty = copysign(excessY, relY) }

            tx = max(-maxOffset, min(maxOffset, tx))
            ty = max(-maxOffset, min(maxOffset, ty))

            targetOffset = (tx, ty)
        }

        let omega = 2.0 * .pi / max(0.001, settings.response)
        let zeta = settings.dampingRatio

        let (newX, newVX) = SpringDamperSimulator.springStep(
            current: offset.x, velocity: velocityX,
            target: targetOffset.x,
            omega: omega, zeta: zeta, dt: dt
        )
        let (newY, newVY) = SpringDamperSimulator.springStep(
            current: offset.y, velocity: velocityY,
            target: targetOffset.y,
            omega: omega, zeta: zeta, dt: dt
        )

        offset = (
            max(-maxOffset, min(maxOffset, newX)),
            max(-maxOffset, min(maxOffset, newY))
        )
        velocityX = newVX
        velocityY = newVY
    }

    /// Compensate micro offset when macro center changes to avoid visual jump.
    mutating func compensateForMacroTransition(
        oldCenter: NormalizedPoint,
        newCenter: NormalizedPoint
    ) {
        offset.x -= (newCenter.x - oldCenter.x)
        offset.y -= (newCenter.y - oldCenter.y)
    }
}
