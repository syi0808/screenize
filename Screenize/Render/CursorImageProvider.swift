import Foundation
import CoreGraphics
import CoreImage
import AppKit

/// Provides resolution-independent cursor images drawn programmatically via Core Graphics.
/// Replaces NSCursor-based raster images to ensure sharp rendering at any zoom level.
final class CursorImageProvider {

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let style: CursorStyle
        let pixelSize: Int
    }

    private var imageCache: [CacheKey: CIImage] = [:]

    // MARK: - Design Constants

    /// Base design size for the arrow cursor (matches macOS cursor proportions).
    /// All styles are drawn relative to this reference height.
    private static let arrowDesignSize = CGSize(width: 17, height: 25)

    // MARK: - Public API

    /// Return a cursor image at the requested pixel height, rendered sharply via Core Graphics.
    /// - Parameters:
    ///   - style: Cursor style
    ///   - pixelHeight: Target image height in pixels
    /// - Returns: CIImage with transparency, or nil on failure
    func cursorImage(style: CursorStyle, pixelHeight: CGFloat) -> CIImage? {
        let rounded = roundToGrid(pixelHeight)
        let key = CacheKey(style: style, pixelSize: rounded)

        if let cached = imageCache[key] {
            return cached
        }

        guard let image = renderCursor(style: style, pixelHeight: CGFloat(rounded)) else {
            return nil
        }

        imageCache[key] = image
        return image
    }

    /// Normalized hotspot position for a cursor style (top-left origin, 0-1 range).
    /// Values are derived from actual tip coordinates in the custom drawing paths,
    /// expressed as (designX / designWidth, designY / designHeight).
    func normalizedHotspot(style: CursorStyle) -> CGPoint {
        switch style {
        case .arrow:
            // Tip at design (1.5, 1.0) in 17x25 space
            return CGPoint(x: 1.5 / 17.0, y: 1.0 / 25.0)
        case .pointer:
            // Fingertip at design (~6.25, 1.0) in 19x24 space
            return CGPoint(x: 6.25 / 19.0, y: 1.0 / 24.0)
        case .iBeam:
            return CGPoint(x: 0.5, y: 0.5)
        case .crosshair:
            return CGPoint(x: 0.5, y: 0.5)
        case .openHand:
            return CGPoint(x: 0.5, y: 0.5)
        case .closedHand:
            return CGPoint(x: 0.5, y: 0.5)
        case .contextMenu:
            // Arrow tip at design (1.5, 1.0) in 25x25 space
            return CGPoint(x: 1.5 / 25.0, y: 1.0 / 25.0)
        }
    }

    /// Clear the image cache.
    func clearCache() {
        imageCache.removeAll()
    }

    // MARK: - Private Helpers

    /// Round pixel size to a 4px grid to avoid cache thrashing.
    private func roundToGrid(_ value: CGFloat) -> Int {
        max(8, Int(ceil(value / 4.0)) * 4)
    }

    // MARK: - Rendering Dispatch

    private func renderCursor(style: CursorStyle, pixelHeight: CGFloat) -> CIImage? {
        switch style {
        case .arrow:
            return renderArrow(pixelHeight: pixelHeight)
        case .pointer:
            return renderPointer(pixelHeight: pixelHeight)
        case .iBeam:
            return renderIBeam(pixelHeight: pixelHeight)
        case .crosshair:
            return renderCrosshair(pixelHeight: pixelHeight)
        case .openHand:
            return renderOpenHand(pixelHeight: pixelHeight)
        case .closedHand:
            return renderClosedHand(pixelHeight: pixelHeight)
        case .contextMenu:
            return renderContextMenu(pixelHeight: pixelHeight)
        }
    }

    // MARK: - CGContext Factory

    private func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func ciImage(from context: CGContext) -> CIImage? {
        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Arrow Cursor

    private func renderArrow(pixelHeight: CGFloat) -> CIImage? {
        let designW: CGFloat = 17
        let designH: CGFloat = 25
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        // Flip to top-left origin for easier path definition
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        // Arrow path (macOS-style pointer)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1.5, y: 1.0))
        path.addLine(to: CGPoint(x: 1.5, y: 18.5))
        path.addLine(to: CGPoint(x: 5.5, y: 14.5))
        path.addLine(to: CGPoint(x: 9.5, y: 22.5))
        path.addLine(to: CGPoint(x: 12.0, y: 21.5))
        path.addLine(to: CGPoint(x: 8.0, y: 13.5))
        path.addLine(to: CGPoint(x: 13.5, y: 13.5))
        path.closeSubpath()

        // Shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.5),
            blur: 3.0,
            color: CGColor(gray: 0, alpha: 0.35)
        )
        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        // Black fill
        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()

        // White stroke
        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()

        return ciImage(from: ctx)
    }

    // MARK: - Pointer (Pointing Hand) Cursor

    private func renderPointer(pixelHeight: CGFloat) -> CIImage? {
        let designW: CGFloat = 19
        let designH: CGFloat = 24
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        // Pointing hand — simplified outline
        let path = CGMutablePath()
        // Index finger
        path.move(to: CGPoint(x: 7.0, y: 1.0))
        path.addLine(to: CGPoint(x: 5.5, y: 1.0))
        path.addCurve(to: CGPoint(x: 4.5, y: 3.0),
                      control1: CGPoint(x: 4.5, y: 1.0),
                      control2: CGPoint(x: 4.5, y: 2.0))
        path.addLine(to: CGPoint(x: 4.5, y: 10.0))
        // Thumb side
        path.addLine(to: CGPoint(x: 2.5, y: 10.5))
        path.addCurve(to: CGPoint(x: 1.0, y: 12.5),
                      control1: CGPoint(x: 1.5, y: 10.5),
                      control2: CGPoint(x: 1.0, y: 11.5))
        path.addLine(to: CGPoint(x: 1.0, y: 14.0))
        // Palm bottom
        path.addCurve(to: CGPoint(x: 3.0, y: 21.0),
                      control1: CGPoint(x: 1.0, y: 17.0),
                      control2: CGPoint(x: 1.5, y: 19.5))
        path.addCurve(to: CGPoint(x: 8.0, y: 23.0),
                      control1: CGPoint(x: 4.5, y: 22.5),
                      control2: CGPoint(x: 6.0, y: 23.0))
        path.addLine(to: CGPoint(x: 13.0, y: 23.0))
        path.addCurve(to: CGPoint(x: 17.5, y: 19.0),
                      control1: CGPoint(x: 15.5, y: 23.0),
                      control2: CGPoint(x: 17.5, y: 21.5))
        path.addLine(to: CGPoint(x: 17.5, y: 12.5))
        // Other fingers
        path.addLine(to: CGPoint(x: 17.5, y: 10.5))
        path.addCurve(to: CGPoint(x: 16.0, y: 9.0),
                      control1: CGPoint(x: 17.5, y: 9.5),
                      control2: CGPoint(x: 17.0, y: 9.0))
        path.addCurve(to: CGPoint(x: 14.5, y: 10.5),
                      control1: CGPoint(x: 15.0, y: 9.0),
                      control2: CGPoint(x: 14.5, y: 9.5))
        path.addLine(to: CGPoint(x: 14.5, y: 9.0))
        path.addCurve(to: CGPoint(x: 13.0, y: 7.5),
                      control1: CGPoint(x: 14.5, y: 8.0),
                      control2: CGPoint(x: 14.0, y: 7.5))
        path.addCurve(to: CGPoint(x: 11.5, y: 9.0),
                      control1: CGPoint(x: 12.0, y: 7.5),
                      control2: CGPoint(x: 11.5, y: 8.0))
        path.addLine(to: CGPoint(x: 11.5, y: 8.5))
        path.addCurve(to: CGPoint(x: 10.0, y: 7.0),
                      control1: CGPoint(x: 11.5, y: 7.5),
                      control2: CGPoint(x: 11.0, y: 7.0))
        path.addCurve(to: CGPoint(x: 8.5, y: 8.5),
                      control1: CGPoint(x: 9.0, y: 7.0),
                      control2: CGPoint(x: 8.5, y: 7.5))
        path.addLine(to: CGPoint(x: 8.5, y: 3.0))
        path.addCurve(to: CGPoint(x: 7.0, y: 1.0),
                      control1: CGPoint(x: 8.5, y: 2.0),
                      control2: CGPoint(x: 8.5, y: 1.0))
        path.closeSubpath()

        // Shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.5),
            blur: 3.0,
            color: CGColor(gray: 0, alpha: 0.3)
        )
        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()

        return ciImage(from: ctx)
    }

    // MARK: - I-Beam Cursor

    private func renderIBeam(pixelHeight: CGFloat) -> CIImage? {
        let designW: CGFloat = 10
        let designH: CGFloat = 18
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        let midX: CGFloat = 5.0
        let serifWidth: CGFloat = 3.0

        // White outline (draw thicker first)
        let outlinePath = CGMutablePath()
        // Top serif
        outlinePath.move(to: CGPoint(x: midX - serifWidth, y: 1.0))
        outlinePath.addCurve(to: CGPoint(x: midX, y: 3.0),
                             control1: CGPoint(x: midX - serifWidth, y: 2.0),
                             control2: CGPoint(x: midX - 1.0, y: 3.0))
        outlinePath.addCurve(to: CGPoint(x: midX + serifWidth, y: 1.0),
                             control1: CGPoint(x: midX + 1.0, y: 3.0),
                             control2: CGPoint(x: midX + serifWidth, y: 2.0))
        // Vertical stem (go back)
        outlinePath.move(to: CGPoint(x: midX, y: 3.0))
        outlinePath.addLine(to: CGPoint(x: midX, y: 15.0))
        // Bottom serif
        outlinePath.move(to: CGPoint(x: midX - serifWidth, y: 17.0))
        outlinePath.addCurve(to: CGPoint(x: midX, y: 15.0),
                             control1: CGPoint(x: midX - serifWidth, y: 16.0),
                             control2: CGPoint(x: midX - 1.0, y: 15.0))
        outlinePath.addCurve(to: CGPoint(x: midX + serifWidth, y: 17.0),
                             control1: CGPoint(x: midX + 1.0, y: 15.0),
                             control2: CGPoint(x: midX + serifWidth, y: 16.0))

        ctx.setStrokeColor(CGColor.black)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.addPath(outlinePath)
        ctx.strokePath()

        // White foreground
        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        ctx.addPath(outlinePath)
        ctx.strokePath()

        return ciImage(from: ctx)
    }

    // MARK: - Crosshair Cursor

    private func renderCrosshair(pixelHeight: CGFloat) -> CIImage? {
        let designS: CGFloat = 22
        let scale = pixelHeight / designS
        let size = Int(ceil(designS * scale))

        guard let ctx = makeContext(width: size, height: size) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: scale, y: -scale)

        let mid: CGFloat = 11.0
        let armLen: CGFloat = 7.0
        let gap: CGFloat = 2.5

        let path = CGMutablePath()
        // Top arm
        path.move(to: CGPoint(x: mid, y: mid - gap - armLen))
        path.addLine(to: CGPoint(x: mid, y: mid - gap))
        // Bottom arm
        path.move(to: CGPoint(x: mid, y: mid + gap))
        path.addLine(to: CGPoint(x: mid, y: mid + gap + armLen))
        // Left arm
        path.move(to: CGPoint(x: mid - gap - armLen, y: mid))
        path.addLine(to: CGPoint(x: mid - gap, y: mid))
        // Right arm
        path.move(to: CGPoint(x: mid + gap, y: mid))
        path.addLine(to: CGPoint(x: mid + gap + armLen, y: mid))

        // Black outline
        ctx.setStrokeColor(CGColor.black)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()

        // White foreground
        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()

        // Center dot
        let dotRect = CGRect(x: mid - 1.0, y: mid - 1.0, width: 2.0, height: 2.0)
        ctx.setFillColor(CGColor.white)
        ctx.fillEllipse(in: dotRect)

        return ciImage(from: ctx)
    }

    // MARK: - Open Hand Cursor

    private func renderOpenHand(pixelHeight: CGFloat) -> CIImage? {
        let designW: CGFloat = 20
        let designH: CGFloat = 20
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        let path = CGMutablePath()
        // Palm body
        path.move(to: CGPoint(x: 4.0, y: 8.0))
        // Left side of palm
        path.addLine(to: CGPoint(x: 4.0, y: 13.0))
        path.addCurve(to: CGPoint(x: 5.5, y: 17.5),
                      control1: CGPoint(x: 4.0, y: 15.0),
                      control2: CGPoint(x: 4.5, y: 16.5))
        path.addCurve(to: CGPoint(x: 10.0, y: 19.0),
                      control1: CGPoint(x: 6.5, y: 18.5),
                      control2: CGPoint(x: 8.0, y: 19.0))
        path.addCurve(to: CGPoint(x: 14.5, y: 17.5),
                      control1: CGPoint(x: 12.0, y: 19.0),
                      control2: CGPoint(x: 13.5, y: 18.5))
        path.addCurve(to: CGPoint(x: 16.0, y: 13.0),
                      control1: CGPoint(x: 15.5, y: 16.5),
                      control2: CGPoint(x: 16.0, y: 15.0))
        // Right side fingers
        path.addLine(to: CGPoint(x: 16.0, y: 7.0))
        path.addCurve(to: CGPoint(x: 15.0, y: 5.5),
                      control1: CGPoint(x: 16.0, y: 6.0),
                      control2: CGPoint(x: 15.5, y: 5.5))
        path.addCurve(to: CGPoint(x: 14.0, y: 7.0),
                      control1: CGPoint(x: 14.5, y: 5.5),
                      control2: CGPoint(x: 14.0, y: 6.0))
        path.addLine(to: CGPoint(x: 14.0, y: 5.5))
        path.addCurve(to: CGPoint(x: 13.0, y: 4.0),
                      control1: CGPoint(x: 14.0, y: 4.5),
                      control2: CGPoint(x: 13.5, y: 4.0))
        path.addCurve(to: CGPoint(x: 12.0, y: 5.5),
                      control1: CGPoint(x: 12.5, y: 4.0),
                      control2: CGPoint(x: 12.0, y: 4.5))
        path.addLine(to: CGPoint(x: 12.0, y: 4.0))
        path.addCurve(to: CGPoint(x: 10.5, y: 2.0),
                      control1: CGPoint(x: 12.0, y: 3.0),
                      control2: CGPoint(x: 11.5, y: 2.0))
        path.addCurve(to: CGPoint(x: 9.0, y: 4.0),
                      control1: CGPoint(x: 9.5, y: 2.0),
                      control2: CGPoint(x: 9.0, y: 3.0))
        path.addLine(to: CGPoint(x: 9.0, y: 3.5))
        path.addCurve(to: CGPoint(x: 7.5, y: 1.5),
                      control1: CGPoint(x: 9.0, y: 2.5),
                      control2: CGPoint(x: 8.5, y: 1.5))
        path.addCurve(to: CGPoint(x: 6.0, y: 3.5),
                      control1: CGPoint(x: 6.5, y: 1.5),
                      control2: CGPoint(x: 6.0, y: 2.5))
        path.addLine(to: CGPoint(x: 6.0, y: 8.5))
        // Thumb
        path.addLine(to: CGPoint(x: 5.0, y: 9.5))
        path.addCurve(to: CGPoint(x: 4.0, y: 8.0),
                      control1: CGPoint(x: 4.5, y: 9.5),
                      control2: CGPoint(x: 4.0, y: 9.0))
        path.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.0),
            blur: 2.0,
            color: CGColor(gray: 0, alpha: 0.25)
        )
        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()

        return ciImage(from: ctx)
    }

    // MARK: - Closed Hand Cursor

    private func renderClosedHand(pixelHeight: CGFloat) -> CIImage? {
        let designW: CGFloat = 18
        let designH: CGFloat = 18
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        let path = CGMutablePath()
        // Closed fist shape
        path.move(to: CGPoint(x: 4.0, y: 7.0))
        // Knuckles
        path.addCurve(to: CGPoint(x: 5.0, y: 5.0),
                      control1: CGPoint(x: 4.0, y: 6.0),
                      control2: CGPoint(x: 4.5, y: 5.0))
        path.addCurve(to: CGPoint(x: 6.0, y: 5.5),
                      control1: CGPoint(x: 5.5, y: 5.0),
                      control2: CGPoint(x: 6.0, y: 5.0))
        path.addLine(to: CGPoint(x: 6.5, y: 4.5))
        path.addCurve(to: CGPoint(x: 8.0, y: 3.5),
                      control1: CGPoint(x: 6.5, y: 3.5),
                      control2: CGPoint(x: 7.0, y: 3.5))
        path.addCurve(to: CGPoint(x: 9.0, y: 4.5),
                      control1: CGPoint(x: 8.5, y: 3.5),
                      control2: CGPoint(x: 9.0, y: 4.0))
        path.addLine(to: CGPoint(x: 9.5, y: 4.0))
        path.addCurve(to: CGPoint(x: 11.0, y: 3.5),
                      control1: CGPoint(x: 9.5, y: 3.0),
                      control2: CGPoint(x: 10.0, y: 3.5))
        path.addCurve(to: CGPoint(x: 12.0, y: 5.0),
                      control1: CGPoint(x: 11.5, y: 3.5),
                      control2: CGPoint(x: 12.0, y: 4.0))
        path.addLine(to: CGPoint(x: 12.5, y: 4.5))
        path.addCurve(to: CGPoint(x: 14.0, y: 4.0),
                      control1: CGPoint(x: 12.5, y: 3.5),
                      control2: CGPoint(x: 13.0, y: 4.0))
        path.addCurve(to: CGPoint(x: 15.0, y: 5.5),
                      control1: CGPoint(x: 14.5, y: 4.0),
                      control2: CGPoint(x: 15.0, y: 4.5))
        // Right side
        path.addLine(to: CGPoint(x: 15.0, y: 12.0))
        path.addCurve(to: CGPoint(x: 13.5, y: 16.0),
                      control1: CGPoint(x: 15.0, y: 14.0),
                      control2: CGPoint(x: 14.5, y: 15.5))
        path.addCurve(to: CGPoint(x: 9.5, y: 17.0),
                      control1: CGPoint(x: 12.5, y: 16.5),
                      control2: CGPoint(x: 11.0, y: 17.0))
        path.addCurve(to: CGPoint(x: 5.5, y: 16.0),
                      control1: CGPoint(x: 8.0, y: 17.0),
                      control2: CGPoint(x: 6.5, y: 16.5))
        path.addCurve(to: CGPoint(x: 4.0, y: 12.0),
                      control1: CGPoint(x: 4.5, y: 15.5),
                      control2: CGPoint(x: 4.0, y: 14.0))
        path.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.0),
            blur: 2.0,
            color: CGColor(gray: 0, alpha: 0.25)
        )
        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()

        return ciImage(from: ctx)
    }

    // MARK: - Context Menu Cursor

    private func renderContextMenu(pixelHeight: CGFloat) -> CIImage? {
        // Context menu cursor: arrow + small menu icon to the right
        let designW: CGFloat = 25
        let designH: CGFloat = 25
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        // Draw arrow part (same as arrow cursor)
        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: 1.5, y: 1.0))
        arrowPath.addLine(to: CGPoint(x: 1.5, y: 18.5))
        arrowPath.addLine(to: CGPoint(x: 5.5, y: 14.5))
        arrowPath.addLine(to: CGPoint(x: 9.5, y: 22.5))
        arrowPath.addLine(to: CGPoint(x: 12.0, y: 21.5))
        arrowPath.addLine(to: CGPoint(x: 8.0, y: 13.5))
        arrowPath.addLine(to: CGPoint(x: 13.5, y: 13.5))
        arrowPath.closeSubpath()

        // Shadow for arrow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.5),
            blur: 3.0,
            color: CGColor(gray: 0, alpha: 0.35)
        )
        ctx.setFillColor(CGColor.black)
        ctx.addPath(arrowPath)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setFillColor(CGColor.black)
        ctx.addPath(arrowPath)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.addPath(arrowPath)
        ctx.strokePath()

        // Mini menu icon (top-right area)
        let menuX: CGFloat = 14.0
        let menuY: CGFloat = 2.0
        let menuW: CGFloat = 10.0
        let menuH: CGFloat = 10.0
        let menuRect = CGRect(x: menuX, y: menuY, width: menuW, height: menuH)
        let menuPath = CGPath(roundedRect: menuRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)

        ctx.setFillColor(CGColor.black)
        ctx.addPath(menuPath)
        ctx.fillPath()
        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.0)
        ctx.addPath(menuPath)
        ctx.strokePath()

        // Menu lines
        let lineInset: CGFloat = 2.0
        let lineSpacing: CGFloat = 2.5
        ctx.setStrokeColor(CGColor(gray: 0.8, alpha: 1.0))
        ctx.setLineWidth(0.8)
        for i in 0..<3 {
            let lineY = menuY + 2.5 + CGFloat(i) * lineSpacing
            ctx.move(to: CGPoint(x: menuX + lineInset, y: lineY))
            ctx.addLine(to: CGPoint(x: menuX + menuW - lineInset, y: lineY))
        }
        ctx.strokePath()

        return ciImage(from: ctx)
    }
}
