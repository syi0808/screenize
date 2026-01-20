import Foundation
import CoreGraphics
import CoreImage
import AppKit

/// Effect compositor
/// Renders ripple effects and the cursor
final class EffectCompositor {

    /// CoreImage context
    private let ciContext: CIContext

    /// Cache for cursor images
    private var cursorImageCache: [CursorStyle: CIImage] = [:]

    /// Cache for cursor hotspots (actual NSCursor hotSpot values)
    private var cursorHotspotCache: [CursorStyle: CGPoint] = [:]

    init(ciContext: CIContext? = nil) {
        self.ciContext = ciContext ?? CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: true
        ])
    }

    // MARK: - Ripple Rendering

    /// Render a ripple effect
    /// - Parameters:
    ///   - ripple: Active ripple information
    ///   - frameSize: Frame size
    /// - Returns: Ripple effect image
    func renderRipple(_ ripple: ActiveRipple, frameSize: CGSize) -> CIImage? {
        // Base radius
        let baseRadius: CGFloat = 50
        let currentRadius = ripple.radius(baseRadius: baseRadius * (frameSize.width / 1920))

        // Enforce a minimum radius
        guard currentRadius > 1 else { return nil }

        // Compute position (normalized -> CoreImage pixels, bottom-left origin)
        let center = CoordinateConverter.normalizedToCoreImage(ripple.position, frameSize: frameSize)
        let centerX = center.x
        let centerY = center.y

        // Ripple color
        let color = ripple.color.ciColor

        // Ring width
        let ringWidth: CGFloat = max(2, currentRadius * 0.15)

        // Generate gradient ripple
        guard let rippleImage = createRippleImage(
            center: CGPoint(x: centerX, y: centerY),
            radius: currentRadius,
            ringWidth: ringWidth,
            color: color,
            opacity: ripple.opacity,
            frameSize: frameSize
        ) else { return nil }

        return rippleImage
    }

    /// Create the ripple image
    private func createRippleImage(
        center: CGPoint,
        radius: CGFloat,
        ringWidth: CGFloat,
        color: CIColor,
        opacity: CGFloat,
        frameSize: CGSize
    ) -> CIImage? {
        // Outer radius
        let outerRadius = radius
        let innerRadius = max(0, radius - ringWidth)

        // Use CIRadialGradient
        guard let gradientFilter = CIFilter(name: "CIRadialGradient") else { return nil }

        // Create a fade-out ring effect
        let fadeColor = CIColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha * opacity
        )
        let transparentColor = CIColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: 0
        )

        gradientFilter.setValue(CIVector(x: center.x, y: center.y), forKey: "inputCenter")
        gradientFilter.setValue(innerRadius, forKey: "inputRadius0")
        gradientFilter.setValue(outerRadius, forKey: "inputRadius1")
        gradientFilter.setValue(fadeColor, forKey: "inputColor0")
        gradientFilter.setValue(transparentColor, forKey: "inputColor1")

        guard var gradient = gradientFilter.outputImage else { return nil }

        // Crop to the frame size
        gradient = gradient.cropped(to: CGRect(origin: .zero, size: frameSize))

        return gradient
    }

    // MARK: - Cursor Rendering

    /// Render a cursor
    /// - Parameters:
    ///   - cursor: Cursor state
    ///   - frameSize: Frame size
    /// - Returns: Cursor image
    func renderCursor(_ cursor: CursorState, frameSize: CGSize) -> CIImage? {
        guard cursor.visible else { return nil }

        // Retrieve the cursor image (uses cache)
        guard let cursorImage = getCursorImage(style: cursor.style, scale: cursor.scale) else {
            return nil
        }

        // Determine the position (normalized -> CoreImage pixels, bottom-left origin)
        let pos = CoordinateConverter.normalizedToCoreImage(cursor.position, frameSize: frameSize)
        let posX = pos.x
        let posY = pos.y

        // Cursor size
        let cursorSize = cursorImage.extent.size

        // Adjust the cursor position using hotspot correction
        // CoreImage uses a bottom-left origin, while hotspotOffset assumes top-left, so convert
        // Position the bottom of the image at (posY - cursorHeight + hotspotOffset.y)
        // That places the hotspot exactly at posY
        let hotspotOffset = hotspotOffset(for: cursor.style, scale: cursor.scale)
        // Fine correction: shift slightly up-left to reduce perceived offset from actual click
        let correctionX: CGFloat = -2.0
        let correctionY: CGFloat = 2.0  // Positive goes upward due to CoreImage bottom-left origin
        let finalX = posX - hotspotOffset.x + correctionX
        let finalY = posY - cursorSize.height + hotspotOffset.y + correctionY

        // Translate
        let translated = cursorImage.transformed(by: CGAffineTransform(
            translationX: finalX,
            y: finalY
        ))

        // Expand to the frame size (including transparency)
        let fullFrame = translated.cropped(to: CGRect(origin: .zero, size: frameSize))

        return fullFrame
    }

    /// Get a cursor image (with caching)
    private func getCursorImage(style: CursorStyle, scale: CGFloat) -> CIImage? {
        // Check the cache
        if let cached = cursorImageCache[style] {
            return cached.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        // Acquire the native macOS cursor
        let nsCursor: NSCursor
        switch style {
        case .arrow:
            nsCursor = .arrow
        case .pointer:
            nsCursor = .pointingHand
        case .iBeam:
            nsCursor = .iBeam
        case .crosshair:
            nsCursor = .crosshair
        case .openHand:
            nsCursor = .openHand
        case .closedHand:
            nsCursor = .closedHand
        case .contextMenu:
            nsCursor = .contextualMenu
        }

        // Convert NSImage to CIImage
        guard let cgImage = nsCursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        cursorImageCache[style] = ciImage

        // Cache the hotspot using NSCursor's actual hotSpot value
        cursorHotspotCache[style] = nsCursor.hotSpot

        return ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Cursor hotspot offset
    /// Uses NSCursor's actual hotSpot values (pulled from the cache)
    private func hotspotOffset(for style: CursorStyle, scale: CGFloat) -> CGPoint {
        // Use the cached hotspot (populated by getCursorImage)
        if let cachedHotspot = cursorHotspotCache[style] {
            return CGPoint(x: cachedHotspot.x * scale, y: cachedHotspot.y * scale)
        }

        // Fall back to querying NSCursor directly when missing in cache
        let nsCursor: NSCursor
        switch style {
        case .arrow:
            nsCursor = .arrow
        case .pointer:
            nsCursor = .pointingHand
        case .iBeam:
            nsCursor = .iBeam
        case .crosshair:
            nsCursor = .crosshair
        case .openHand:
            nsCursor = .openHand
        case .closedHand:
            nsCursor = .closedHand
        case .contextMenu:
            nsCursor = .contextualMenu
        }

        let hotspot = nsCursor.hotSpot
        cursorHotspotCache[style] = hotspot

        return CGPoint(x: hotspot.x * scale, y: hotspot.y * scale)
    }

    // MARK: - Keystroke Overlay Rendering

    /// Render keystroke overlay
    /// - Parameters:
    ///   - keystrokes: Active keystroke list
    ///   - frameSize: Frame size
    /// - Returns: Keystroke overlay image
    func renderKeystrokeOverlay(_ keystrokes: [ActiveKeystroke], frameSize: CGSize) -> CIImage? {
        guard !keystrokes.isEmpty else { return nil }

        var result: CIImage?

        for keystroke in keystrokes {
            guard let pillImage = renderSingleKeystroke(keystroke, frameSize: frameSize) else {
                continue
            }
            if let existing = result {
                result = pillImage.composited(over: existing)
            } else {
                result = pillImage
            }
        }

        return result
    }

    /// Render a single keystroke pill at its position
    private func renderSingleKeystroke(_ keystroke: ActiveKeystroke, frameSize: CGSize) -> CIImage? {
        // Font size: 3% of frame height
        let fontSize: CGFloat = max(24, frameSize.height * 0.03)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let cornerRadius: CGFloat = fontSize * 0.4
        let paddingH: CGFloat = fontSize * 0.8
        let paddingV: CGFloat = fontSize * 0.4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        let textSize = (keystroke.displayText as NSString).size(withAttributes: attributes)
        let pillWidth = textSize.width + paddingH * 2
        let pillHeight = textSize.height + paddingV * 2

        let bitmapWidth = Int(ceil(pillWidth))
        let bitmapHeight = Int(ceil(pillHeight))

        guard bitmapWidth > 0, bitmapHeight > 0 else { return nil }

        // Create bitmap context
        guard let context = CGContext(
            data: nil,
            width: bitmapWidth,
            height: bitmapHeight,
            bitsPerComponent: 8,
            bytesPerRow: bitmapWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        // Rounded rectangle background
        let pillRect = CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0.1, alpha: 0.75 * keystroke.opacity).setFill()
        path.fill()

        // Text
        let textRect = CGRect(x: paddingH, y: paddingV, width: textSize.width, height: textSize.height)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(keystroke.opacity)
        ]
        (keystroke.displayText as NSString).draw(in: textRect, withAttributes: textAttributes)

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { return nil }
        var ciImage = CIImage(cgImage: cgImage)

        // Position: NormalizedPoint uses top-left origin (y=0 top, y=1 bottom)
        // CoreImage uses bottom-left origin (y=0 bottom, y=height top), so flip Y
        let posX = keystroke.position.x * frameSize.width - CGFloat(bitmapWidth) / 2
        let posY = (1.0 - keystroke.position.y) * frameSize.height - CGFloat(bitmapHeight) / 2
        ciImage = ciImage.transformed(by: CGAffineTransform(translationX: posX, y: posY))

        // Crop to frame size
        ciImage = ciImage.cropped(to: CGRect(origin: .zero, size: frameSize))

        return ciImage
    }

    // MARK: - Cache Management

    /// Clear the cursor caches
    func clearCursorCache() {
        cursorImageCache.removeAll()
        cursorHotspotCache.removeAll()
    }
}

// MARK: - RippleColor Extension

extension RippleColor {
    var ciColor: CIColor {
        switch self {
        case .leftClick:
            return CIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.6)
        case .rightClick:
            return CIColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 0.6)
        case .custom(let r, let g, let b, let a):
            return CIColor(red: r, green: g, blue: b, alpha: a)
        }
    }
}
