import Foundation
import CoreGraphics

/// Capture metadata
/// Display and coordinate snapshot recorded at capture time
struct CaptureMeta: Codable {
    /// Captured display ID (nil for window capture)
    let displayID: UInt32?

    /// Capture bounds in points (screen coordinates with bottom-left origin)
    let boundsPt: CGRect

    /// Scale factor (Retina: 2.0, standard: 1.0)
    let scaleFactor: CGFloat

    init(
        displayID: UInt32? = nil,
        boundsPt: CGRect,
        scaleFactor: CGFloat = 2.0
    ) {
        self.displayID = displayID
        self.boundsPt = boundsPt
        self.scaleFactor = scaleFactor
    }

    // MARK: - Computed Properties

    /// Capture bounds in pixels
    var boundsPixel: CGRect {
        CGRect(
            x: boundsPt.origin.x * scaleFactor,
            y: boundsPt.origin.y * scaleFactor,
            width: boundsPt.width * scaleFactor,
            height: boundsPt.height * scaleFactor
        )
    }

    /// Capture size in pixels
    var sizePixel: CGSize {
        CGSize(
            width: boundsPt.width * scaleFactor,
            height: boundsPt.height * scaleFactor
        )
    }

    // MARK: - Coordinate Conversion

    /// Convert screen coordinates to normalized coordinates (0–1, bottom-left origin)
    func normalizePoint(_ point: CGPoint) -> CGPoint {
        let x = (point.x - boundsPt.origin.x) / boundsPt.width
        let y = (point.y - boundsPt.origin.y) / boundsPt.height

        return CGPoint(
            x: clamp(x, min: 0, max: 1),
            y: clamp(y, min: 0, max: 1)
        )
    }

    /// Convert normalized coordinates (0–1, bottom-left origin) back to screen coordinates
    func denormalizePoint(_ normalizedPoint: CGPoint) -> CGPoint {
        let x = normalizedPoint.x * boundsPt.width + boundsPt.origin.x
        let y = normalizedPoint.y * boundsPt.height + boundsPt.origin.y

        return CGPoint(x: x, y: y)
    }

    /// Convert normalized coordinates to pixel coordinates
    func normalizedToPixel(_ normalizedPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * sizePixel.width,
            y: normalizedPoint.y * sizePixel.height
        )
    }

    /// Convert pixel coordinates to normalized coordinates
    func pixelToNormalized(_ pixelPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: clamp(pixelPoint.x / sizePixel.width, min: 0, max: 1),
            y: clamp(pixelPoint.y / sizePixel.height, min: 0, max: 1)
        )
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}
