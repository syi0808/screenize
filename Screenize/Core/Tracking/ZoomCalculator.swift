import Foundation
import CoreGraphics

final class ZoomCalculator {
    private let settings: ZoomSettings

    init(settings: ZoomSettings) {
        self.settings = settings
    }

    func calculateZoomRegion(
        mousePosition: CGPoint,
        frameSize: CGSize,
        currentZoom: Double
    ) -> ZoomRegion {
        // Normalize mouse position (0-1 range)
        let normalizedX = mousePosition.x / frameSize.width
        let normalizedY = mousePosition.y / frameSize.height

        // Calculate zoom center with edge padding
        let paddingRatio = settings.edgePadding / min(frameSize.width, frameSize.height)
        let centerX = clamp(normalizedX, min: paddingRatio, max: 1.0 - paddingRatio)
        let centerY = clamp(normalizedY, min: paddingRatio, max: 1.0 - paddingRatio)

        // Calculate visible region size based on zoom level
        let visibleWidth = 1.0 / currentZoom
        let visibleHeight = 1.0 / currentZoom

        // Calculate region bounds
        var x = centerX - visibleWidth / 2
        var y = centerY - visibleHeight / 2

        // Clamp to frame bounds
        x = clamp(x, min: 0, max: 1.0 - visibleWidth)
        y = clamp(y, min: 0, max: 1.0 - visibleHeight)

        return ZoomRegion(
            normalizedRect: CGRect(x: x, y: y, width: visibleWidth, height: visibleHeight),
            center: CGPoint(x: centerX, y: centerY),
            zoom: currentZoom
        )
    }

    func shouldZoom(
        mouseVelocity: CGVector,
        previousVelocity: CGVector,
        frameSize: CGSize
    ) -> Bool {
        guard settings.isEnabled else { return false }

        // Calculate speed
        let speed = sqrt(mouseVelocity.dx * mouseVelocity.dx + mouseVelocity.dy * mouseVelocity.dy)

        // Normalize threshold relative to frame size
        let normalizedThreshold = settings.triggerThreshold * min(frameSize.width, frameSize.height) / 1000.0

        return speed < normalizedThreshold
    }

    func calculateTargetZoom(
        mouseVelocity: CGVector,
        currentZoom: Double,
        frameSize: CGSize
    ) -> Double {
        guard settings.isEnabled else { return 1.0 }

        let speed = sqrt(mouseVelocity.dx * mouseVelocity.dx + mouseVelocity.dy * mouseVelocity.dy)
        let normalizedSpeed = speed / min(frameSize.width, frameSize.height)

        // Faster movement = less zoom
        // Slower/stationary = more zoom (up to settings.zoomLevel)
        let speedFactor = 1.0 - min(1.0, normalizedSpeed * 10)

        // Interpolate between 1.0 (no zoom) and settings.zoomLevel
        let targetZoom = 1.0 + (settings.zoomLevel - 1.0) * speedFactor

        return targetZoom
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

struct ZoomRegion {
    let normalizedRect: CGRect
    let center: CGPoint
    let zoom: Double

    func pixelRect(for frameSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.origin.x * frameSize.width,
            y: normalizedRect.origin.y * frameSize.height,
            width: normalizedRect.width * frameSize.width,
            height: normalizedRect.height * frameSize.height
        )
    }

    var transform: CGAffineTransform {
        let scale = CGFloat(zoom)
        let tx = -normalizedRect.origin.x * scale
        let ty = -normalizedRect.origin.y * scale

        return CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: tx / scale, y: ty / scale)
    }
}
