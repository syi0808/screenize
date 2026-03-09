import Foundation
import CoreGraphics

/// Computes the camera position target based on viewport-aware dead zone logic.
///
/// When cursor is within the safe zone (center of viewport), camera holds still.
/// When cursor approaches viewport edges, camera moves just enough to maintain
/// visibility with partial correction (not centering).
enum DeadZoneTarget {

    static func compute(
        cursorPosition: NormalizedPoint,
        cameraCenter: NormalizedPoint,
        zoom: CGFloat,
        isTyping: Bool,
        settings: DeadZoneSettings
    ) -> NormalizedPoint {
        guard zoom > 1.001 else {
            return NormalizedPoint(x: 0.5, y: 0.5)
        }

        let viewportHalf = 0.5 / zoom
        let safeFraction = isTyping ? settings.safeZoneFractionTyping : settings.safeZoneFraction
        let correction = isTyping ? settings.correctionFractionTyping : settings.correctionFraction
        let safeHalf = viewportHalf * safeFraction
        let gradientHalf = viewportHalf * settings.gradientBandWidth

        let offsetX = cursorPosition.x - cameraCenter.x
        let offsetY = cursorPosition.y - cameraCenter.y

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

        return ShotPlanner.clampCenter(
            NormalizedPoint(x: targetX, y: targetY),
            zoom: zoom
        )
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
        let correctedTarget = minimalTarget + (idealTarget - minimalTarget) * correction

        let gradientEnd = safeHalf + gradientHalf
        if absOffset < gradientEnd && gradientHalf > 0.001 {
            let gradientProgress = (absOffset - safeHalf) / gradientHalf
            let smoothProgress = gradientProgress * gradientProgress * (3 - 2 * gradientProgress)
            return cameraPos + (correctedTarget - cameraPos) * smoothProgress
        }

        return correctedTarget
    }
}
