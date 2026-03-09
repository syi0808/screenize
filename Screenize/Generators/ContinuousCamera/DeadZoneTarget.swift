import Foundation
import CoreGraphics

/// Computes the camera position target based on viewport-aware dead zone logic.
///
/// When cursor is within the safe zone (center of viewport), camera holds still.
/// When cursor approaches viewport edges, camera moves just enough to maintain
/// visibility with partial correction (not centering).
enum DeadZoneTarget {

    /// Result of dead zone computation including activation state.
    struct Result {
        let target: NormalizedPoint
        let isActive: Bool
    }

    /// Backwards-compatible wrapper that delegates to `computeWithState`.
    static func compute(
        cursorPosition: NormalizedPoint,
        cameraCenter: NormalizedPoint,
        zoom: CGFloat,
        isTyping: Bool,
        settings: DeadZoneSettings
    ) -> NormalizedPoint {
        computeWithState(
            cursorPosition: cursorPosition,
            cameraCenter: cameraCenter,
            zoom: zoom,
            isTyping: isTyping,
            wasActive: false,
            settings: settings
        ).target
    }

    /// Compute dead zone target with hysteresis state tracking.
    ///
    /// - Parameters:
    ///   - wasActive: Whether the dead zone was active on the previous tick.
    /// - Returns: The target position and whether the dead zone is now active.
    static func computeWithState(
        cursorPosition: NormalizedPoint,
        cameraCenter: NormalizedPoint,
        zoom: CGFloat,
        isTyping: Bool,
        wasActive: Bool,
        settings: DeadZoneSettings
    ) -> Result {
        guard zoom > 1.001 else {
            return Result(
                target: NormalizedPoint(x: 0.5, y: 0.5),
                isActive: false
            )
        }

        let viewportHalf = 0.5 / zoom
        let safeFraction = isTyping
            ? settings.safeZoneFractionTyping
            : settings.safeZoneFraction
        let correction = isTyping
            ? settings.correctionFractionTyping
            : settings.correctionFraction
        let safeHalf = viewportHalf * safeFraction
        let gradientHalf = viewportHalf * settings.gradientBandWidth
        let hysteresisHalf = safeHalf * settings.hysteresisMargin

        let offsetX = cursorPosition.x - cameraCenter.x
        let offsetY = cursorPosition.y - cameraCenter.y
        let maxOffset = max(abs(offsetX), abs(offsetY))

        // Hysteresis: different thresholds for entering vs leaving
        let isActive: Bool
        if wasActive {
            // Stay active until cursor retreats well inside safe zone
            isActive = maxOffset >= (safeHalf - hysteresisHalf)
        } else {
            // Require cursor to push further out before activating
            isActive = maxOffset > (safeHalf + hysteresisHalf)
        }

        guard isActive else {
            let clamped = ShotPlanner.clampCenter(cameraCenter, zoom: zoom)
            return Result(target: clamped, isActive: false)
        }

        let targetX = axisTarget(
            offset: offsetX,
            cameraPos: cameraCenter.x,
            cursorPos: cursorPosition.x,
            viewportHalf: viewportHalf,
            safeHalf: safeHalf,
            gradientHalf: gradientHalf,
            correction: correction
        )
        let targetY = axisTarget(
            offset: offsetY,
            cameraPos: cameraCenter.y,
            cursorPos: cursorPosition.y,
            viewportHalf: viewportHalf,
            safeHalf: safeHalf,
            gradientHalf: gradientHalf,
            correction: correction
        )

        let clamped = ShotPlanner.clampCenter(
            NormalizedPoint(x: targetX, y: targetY),
            zoom: zoom
        )
        return Result(target: clamped, isActive: true)
    }

    private static func axisTarget(
        offset: CGFloat,
        cameraPos: CGFloat,
        cursorPos: CGFloat,
        viewportHalf: CGFloat,
        safeHalf: CGFloat,
        gradientHalf: CGFloat,
        correction: CGFloat
    ) -> CGFloat {
        let absOffset = abs(offset)

        if absOffset <= safeHalf {
            return cameraPos
        }

        let minimalTarget = cursorPos - copysign(safeHalf, offset)
        let idealTarget = cursorPos
        let correctedTarget = minimalTarget
            + (idealTarget - minimalTarget) * correction

        let gradientEnd = safeHalf + gradientHalf
        if absOffset < gradientEnd && gradientHalf > 0.001 {
            let gradientProgress = (absOffset - safeHalf) / gradientHalf
            let smoothProgress = gradientProgress * gradientProgress
                * (3 - 2 * gradientProgress)
            return cameraPos
                + (correctedTarget - cameraPos) * smoothProgress
        }

        return correctedTarget
    }
}
