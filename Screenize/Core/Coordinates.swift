import Foundation
import CoreGraphics
import AppKit

// MARK: - Normalized Point

/// Normalized coordinates (0–1, bottom-left origin) used as the internal standard
/// Matches the macOS/CoreImage/CoreGraphics coordinate space
struct NormalizedPoint: Equatable, Codable, Hashable {
    let x: CGFloat  // 0.0–1.0, left is 0
    let y: CGFloat  // 0.0–1.0, bottom is 0

    static let zero = Self(x: 0, y: 0)
    static let center = Self(x: 0.5, y: 0.5)

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    /// Convert to CGPoint
    func toCGPoint() -> CGPoint {
        CGPoint(x: x, y: y)
    }

    /// Returns clamped coordinates (ensures 0–1 range)
    func clamped() -> Self {
        Self(
            x: clamp(x, min: 0, max: 1),
            y: clamp(y, min: 0, max: 1)
        )
    }

    /// Euclidean distance between two points
    func distance(to other: Self) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Interpolate toward another point
    /// - Parameters:
    ///   - other: Target point
    ///   - amount: Interpolation ratio (0 = current point, 1 = target point)
    func interpolated(to other: Self, amount: CGFloat) -> Self {
        let clampedAmount = clamp(amount, min: 0, max: 1)
        return Self(
            x: x + (other.x - x) * clampedAmount,
            y: y + (other.y - y) * clampedAmount
        )
    }

}

// MARK: - Collection Operations

extension Collection where Element == NormalizedPoint {
    /// Calculate the bounding box of the points
    /// - Returns: (minX, minY, maxX, maxY) tuple, nil for empty collections
    func boundingBox() -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat)? {
        guard !isEmpty else { return nil }

        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var maxY: CGFloat = -.infinity

        for point in self {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }

        return (minX, minY, maxX, maxY)
    }

    /// Calculate the centroid (average) of the points
    /// - Returns: centroid, nil if empty
    func center() -> NormalizedPoint? {
        guard !isEmpty else { return nil }

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0

        for point in self {
            sumX += point.x
            sumY += point.y
        }

        let count = CGFloat(count)
        return NormalizedPoint(x: sumX / count, y: sumY / count)
    }

    /// Return the bounding box center
    /// - Returns: bounding box center, nil if empty
    func boundingBoxCenter() -> NormalizedPoint? {
        guard let box = boundingBox() else { return nil }
        return NormalizedPoint(
            x: (box.minX + box.maxX) / 2,
            y: (box.minY + box.maxY) / 2
        )
    }
}

// MARK: - Viewport Detection

extension NormalizedPoint {

    /// Compute viewport bounds based on zoom level and center
    /// - Parameters:
    ///   - zoom: Zoom level (1.0 = full screen, 2.0 = 50% of the area)
    ///   - center: Viewport center (normalized coordinates)
    /// - Returns: Viewport bounds (minX, maxX, minY, maxY)
    static func viewportBounds(zoom: CGFloat, center: NormalizedPoint) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let halfWidth = 0.5 / max(zoom, 1.0)
        let halfHeight = 0.5 / max(zoom, 1.0)

        return (
            minX: center.x - halfWidth,
            maxX: center.x + halfWidth,
            minY: center.y - halfHeight,
            maxY: center.y + halfHeight
        )
    }

    /// Determine if this point lies outside the viewport
    /// - Parameters:
    ///   - zoom: Zoom level
    ///   - center: Viewport center
    ///   - margin: Extra margin from bounds (0.0 triggers immediately, 0.05 gives 5% buffer)
    /// - Returns: True if the point is outside the viewport
    func isOutsideViewport(zoom: CGFloat, center: NormalizedPoint, margin: CGFloat = 0.0) -> Bool {
        guard zoom > 1.0 else { return false }  // If zoom <= 1.0 the full screen is visible, so the point is always inside

        let bounds = Self.viewportBounds(zoom: zoom, center: center)
        let effectiveMargin = margin / zoom  // Adjust the margin relative to zoom

        return x < (bounds.minX + effectiveMargin) ||
               x > (bounds.maxX - effectiveMargin) ||
               y < (bounds.minY + effectiveMargin) ||
               y > (bounds.maxY - effectiveMargin)
    }

    /// Calculate a new center to keep this point within the viewport
    /// - Parameters:
    ///   - zoom: Zoom level
    ///   - currentCenter: Current viewport center
    ///   - padding: Padding from the edges so the point stays away from the border
    /// - Returns: New center (returns current center if already inside)
    func centerToIncludeInViewport(zoom: CGFloat, currentCenter: NormalizedPoint, padding: CGFloat = 0.05) -> NormalizedPoint {
        guard zoom > 1.0 else { return currentCenter }

        let halfWidth = 0.5 / zoom
        let halfHeight = 0.5 / zoom
        let effectivePadding = padding / zoom

        var newCenterX = currentCenter.x
        var newCenterY = currentCenter.y

        // X-axis: move the center left if the point is outside the left boundary
        let leftBound = currentCenter.x - halfWidth + effectivePadding
        let rightBound = currentCenter.x + halfWidth - effectivePadding

        if x < leftBound {
            newCenterX = x + halfWidth - effectivePadding
        } else if x > rightBound {
            newCenterX = x - halfWidth + effectivePadding
        }

        // Y-axis: move the center down if the point is outside the bottom boundary
        let bottomBound = currentCenter.y - halfHeight + effectivePadding
        let topBound = currentCenter.y + halfHeight - effectivePadding

        if y < bottomBound {
            newCenterY = y + halfHeight - effectivePadding
        } else if y > topBound {
            newCenterY = y - halfHeight + effectivePadding
        }

        // Clamp the center so it stays within screen bounds
        let clampedX = clamp(newCenterX, min: halfWidth, max: 1.0 - halfWidth)
        let clampedY = clamp(newCenterY, min: halfHeight, max: 1.0 - halfHeight)

        return NormalizedPoint(x: clampedX, y: clampedY)
    }

    /// Relative position of the point within the viewport (0–1, 0.5 is centered)
    /// - Parameters:
    ///   - zoom: Zoom level
    ///   - center: Viewport center
    /// - Returns: Relative position inside the viewport (can be <0 or >1 if outside)
    func relativePositionInViewport(zoom: CGFloat, center: NormalizedPoint) -> NormalizedPoint {
        guard zoom > 1.0 else { return NormalizedPoint(x: x, y: y) }

        let bounds = Self.viewportBounds(zoom: zoom, center: center)
        let viewportWidth = bounds.maxX - bounds.minX
        let viewportHeight = bounds.maxY - bounds.minY

        return NormalizedPoint(
            x: (x - bounds.minX) / viewportWidth,
            y: (y - bounds.minY) / viewportHeight
        )
    }
}

// MARK: - Capture Pixel Point

/// Pixel coordinates relative to the capture area (origin bottom-left)
/// Used when saving MouseRecording
struct CapturePixelPoint: Equatable, Codable {
    let x: CGFloat
    let y: CGFloat

    static let zero = Self(x: 0, y: 0)

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    func toCGPoint() -> CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - Screen Point

/// macOS screen coordinates (origin at bottom-left)
/// Used by macOS APIs such as NSEvent.mouseLocation
struct ScreenPoint: Equatable {
    let x: CGFloat
    let y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    func toCGPoint() -> CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - Coordinate Converter

/// Coordinate conversion utilities
/// Centralizes conversions to ensure consistency
struct CoordinateConverter {
    /// Capture bounds (points in the macOS coordinate system)
    let captureBounds: CGRect

    /// Full screen height (points)
    let screenHeight: CGFloat

    /// Scale factor (Retina: 2.0, standard: 1.0)
    let scaleFactor: CGFloat

    /// Capture size in pixels
    var captureSizePixel: CGSize {
        CGSize(
            width: captureBounds.width * scaleFactor,
            height: captureBounds.height * scaleFactor
        )
    }

    // MARK: - Initialization

    init(captureBounds: CGRect, screenHeight: CGFloat, scaleFactor: CGFloat = 1.0) {
        self.captureBounds = captureBounds
        self.screenHeight = screenHeight
        self.scaleFactor = scaleFactor
    }

    // MARK: - macOS Screen → Capture Pixel

    /// Convert macOS screen coordinates (bottom-left origin) to capture pixel coordinates (bottom-left origin)
        func screenToCapturePixel(_ screenPoint: ScreenPoint) -> CapturePixelPoint {
        // Y-axis conversion is unnecessary because the coordinate systems already align
        let relativeX = screenPoint.x - captureBounds.origin.x
        let relativeY = screenPoint.y - captureBounds.origin.y

        return CapturePixelPoint(x: relativeX, y: relativeY)
    }

    /// CGPoint version (convenience)
    func screenToCapturePixel(_ point: CGPoint) -> CapturePixelPoint {
        screenToCapturePixel(ScreenPoint(point))
    }

    // MARK: - Capture Pixel → Normalized

    /// Convert capture pixel coordinates to normalized coordinates (0–1)
    func capturePixelToNormalized(_ pixel: CapturePixelPoint) -> NormalizedPoint {
        guard captureBounds.width > 0, captureBounds.height > 0 else {
            return .center
        }

        return NormalizedPoint(
            x: clamp(pixel.x / captureBounds.width, min: 0, max: 1),
            y: clamp(pixel.y / captureBounds.height, min: 0, max: 1)
        )
    }

    /// CGPoint version (convenience)
    func capturePixelToNormalized(_ point: CGPoint) -> NormalizedPoint {
        capturePixelToNormalized(CapturePixelPoint(point))
    }

    // MARK: - Screen → Normalized (combined)

    /// Convert macOS screen coordinates to normalized coordinates in one step
    func screenToNormalized(_ screenPoint: ScreenPoint) -> NormalizedPoint {
        let pixel = screenToCapturePixel(screenPoint)
        return capturePixelToNormalized(pixel)
    }

    /// CGPoint version (convenience)
    func screenToNormalized(_ point: CGPoint) -> NormalizedPoint {
        screenToNormalized(ScreenPoint(point))
    }

    // MARK: - Normalized → Video Pixel

    /// Convert normalized coordinates to video frame pixel coordinates (origin bottom-left)
    func normalizedToVideoPixel(_ normalized: NormalizedPoint, videoSize: CGSize) -> CGPoint {
        CGPoint(
            x: normalized.x * videoSize.width,
            y: normalized.y * videoSize.height
        )
    }

    // MARK: - Normalized → CoreImage

    /// Convert normalized coordinates to Core Image coordinates (origin bottom-left)
    func normalizedToCoreImage(_ normalized: NormalizedPoint, frameSize: CGSize) -> CGPoint {
        CGPoint(
            x: normalized.x * frameSize.width,
            y: normalized.y * frameSize.height
        )
    }

    // MARK: - Normalized → Capture Pixel (reverse conversion)

    /// Convert normalized coordinates to capture pixel coordinates
    func normalizedToCapturePixel(_ normalized: NormalizedPoint) -> CapturePixelPoint {
        CapturePixelPoint(
            x: normalized.x * captureBounds.width,
            y: normalized.y * captureBounds.height
        )
    }

    // MARK: - Static Convenience

    /// Convert macOS bottom-left origin coordinates to top-left origin
    /// - Parameters:
    ///   - point: macOS screen coordinates (bottom-left origin)
    ///   - screenHeight: Screen height
    /// - Returns: Coordinates with a top-left origin
    static func appKitToTopLeftOrigin(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: screenHeight - point.y)
    }

    /// Convert top-left origin coordinates back to macOS bottom-left origin
    /// - Parameters:
    ///   - point: Coordinates with a top-left origin
    ///   - screenHeight: Screen height
    /// - Returns: macOS screen coordinates (bottom-left origin)
    static func topLeftOriginToAppKit(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: screenHeight - point.y)
    }

    /// Return the current main screen height (convenience)
    static var mainScreenHeight: CGFloat {
        NSScreen.main?.frame.height ?? 0
    }

    /// Convert normalized coordinates to Core Image pixel coordinates (without a converter)
    static func normalizedToCoreImage(_ normalized: NormalizedPoint, frameSize: CGSize) -> CGPoint {
        CGPoint(
            x: normalized.x * frameSize.width,
            y: normalized.y * frameSize.height
        )
    }

    /// Convert normalized coordinates to pixel coordinates (without a converter)
    static func normalizedToPixel(_ normalized: NormalizedPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: normalized.x * size.width,
            y: normalized.y * size.height
        )
    }

    /// Convert pixel coordinates to normalized coordinates (without a converter)
    static func pixelToNormalized(_ pixel: CGPoint, size: CGSize) -> NormalizedPoint {
        guard size.width > 0, size.height > 0 else {
            return .center
        }
        return NormalizedPoint(
            x: clamp(pixel.x / size.width, min: 0, max: 1),
            y: clamp(pixel.y / size.height, min: 0, max: 1)
        )
    }
}

// MARK: - Helper

private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
    Swift.max(minValue, Swift.min(maxValue, value))
}
