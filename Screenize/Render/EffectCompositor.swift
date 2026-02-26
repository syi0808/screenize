import Foundation
import CoreGraphics
import CoreImage
import AppKit

/// Effect compositor
/// Renders cursor and keystroke overlays
final class EffectCompositor {

    /// CoreImage context
    private let ciContext: CIContext

    /// Cache for cursor images
    private var cursorImageCache: [CursorStyle: CIImage] = [:]

    /// Cache for cursor hotspots (actual NSCursor hotSpot values)
    private var cursorHotspotCache: [CursorStyle: CGPoint] = [:]

    /// Cache for keystroke pill images (displayText -> fully opaque pill CIImage)
    /// Opacity is applied at render time via CIColorMatrix, not baked in
    private var keystrokePillCache: [String: CIImage] = [:]

    /// Frame size used for the current keystroke pill cache (invalidated on size change)
    private var keystrokePillCacheFrameSize: CGSize = .zero

    /// DEBUG: Counter for first-call logging
    private var debugCursorRenderCount = 0

    init(ciContext: CIContext? = nil) {
        self.ciContext = ciContext ?? CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: true
        ])
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
        let effectiveScale = cursor.scale * cursor.clickScaleModifier

        guard let cursorImage = getCursorImage(style: cursor.style, scale: effectiveScale) else {
            return nil
        }

        // Determine the position (normalized -> CoreImage pixels, bottom-left origin)
        let pos = CoordinateConverter.normalizedToCoreImage(cursor.position, frameSize: frameSize)
        let posX = pos.x
        let posY = pos.y

        // DEBUG: Log first cursor render
        if debugCursorRenderCount == 0 {
            Log.export.debug("EffectCompositor.renderCursor: normalized=(\(cursor.position.x), \(cursor.position.y)), frameSize=\(String(describing: frameSize)), ciPos=(\(posX), \(posY))")
        }
        debugCursorRenderCount += 1

        // Cursor size
        let cursorSize = cursorImage.extent.size

        // Adjust the cursor position using hotspot correction
        // CoreImage uses a bottom-left origin, while hotspotOffset assumes top-left, so convert
        // Position the bottom of the image at (posY - cursorHeight + hotspotOffset.y)
        // That places the hotspot exactly at posY
        let hotspotOffset = hotspotOffset(for: cursor.style, scale: effectiveScale)
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

    // MARK: - High-Resolution Cursor Rendering (Post-Transform)

    /// Render cursor at output resolution after the zoom transform has been applied.
    /// The cursor is drawn at the exact pixel size needed, avoiding any upscale artifacts.
    /// - Parameters:
    ///   - cursor: Cursor state
    ///   - outputPosition: Cursor hotspot position in output pixel coordinates (bottom-left origin)
    ///   - outputSize: Output frame size
    ///   - zoomLevel: Current zoom level (for proportional cursor sizing)
    ///   - outputScale: Ratio of output height to source height (accounts for resolution difference)
    ///   - cursorImageProvider: Provider for resolution-independent cursor images
    /// - Returns: Cursor image sized to the output frame
    func renderCursorAtOutputResolution(
        _ cursor: CursorState,
        outputPosition: CGPoint,
        outputSize: CGSize,
        zoomLevel: CGFloat,
        outputScale: CGFloat,
        cursorImageProvider: CursorImageProvider
    ) -> CIImage? {
        guard cursor.visible else { return nil }

        let effectiveScale = cursor.scale * cursor.clickScaleModifier

        // Base cursor height matches the NSCursor image size (~28 design units for arrow).
        // The final pixel height accounts for user scale, zoom level, and output/source ratio.
        let baseCursorHeight: CGFloat = 28.0
        let cursorPixelHeight = baseCursorHeight * effectiveScale * zoomLevel * outputScale

        guard let cursorImage = cursorImageProvider.cursorImage(style: cursor.style, pixelHeight: cursorPixelHeight) else {
            return nil
        }

        let cursorSize = cursorImage.extent.size
        let hotspot = cursorImageProvider.normalizedHotspot(style: cursor.style)

        // Hotspot pixel offset (hotspot is in top-left origin, convert for CoreImage bottom-left)
        let hotspotPixelX = hotspot.x * cursorSize.width
        let hotspotPixelY = hotspot.y * cursorSize.height

        // Position: place cursor so hotspot aligns with outputPosition
        // CoreImage uses bottom-left origin; hotspot.y is from top
        let finalX = outputPosition.x - hotspotPixelX
        let finalY = outputPosition.y - cursorSize.height + hotspotPixelY

        let translated = cursorImage.transformed(by: CGAffineTransform(
            translationX: finalX,
            y: finalY
        ))

        return translated.cropped(to: CGRect(origin: .zero, size: outputSize))
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
    /// Uses pill cache to avoid per-frame CGContext text rendering
    private func renderSingleKeystroke(_ keystroke: ActiveKeystroke, frameSize: CGSize) -> CIImage? {
        // Invalidate cache if frame size changed (font size depends on frame height)
        if keystrokePillCacheFrameSize != frameSize {
            keystrokePillCache.removeAll()
            keystrokePillCacheFrameSize = frameSize
        }

        // Get or create the fully-opaque pill image
        let pillImage: CIImage
        if let cached = keystrokePillCache[keystroke.displayText] {
            pillImage = cached
        } else {
            guard let rendered = renderPillImage(for: keystroke.displayText, frameSize: frameSize) else {
                return nil
            }
            keystrokePillCache[keystroke.displayText] = rendered
            pillImage = rendered
        }

        let pillSize = pillImage.extent.size

        // Apply opacity via CIColorMatrix (multiply all RGBA channels for premultiplied alpha)
        let opacity = keystroke.opacity
        var opacityApplied = pillImage
        if opacity < 1.0 {
            guard let colorMatrix = CIFilter(name: "CIColorMatrix") else { return nil }
            colorMatrix.setValue(opacityApplied, forKey: kCIInputImageKey)
            colorMatrix.setValue(CIVector(x: opacity, y: 0, z: 0, w: 0), forKey: "inputRVector")
            colorMatrix.setValue(CIVector(x: 0, y: opacity, z: 0, w: 0), forKey: "inputGVector")
            colorMatrix.setValue(CIVector(x: 0, y: 0, z: opacity, w: 0), forKey: "inputBVector")
            colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: opacity), forKey: "inputAVector")
            colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
            guard let output = colorMatrix.outputImage else { return nil }
            opacityApplied = output
        }

        // Position: NormalizedPoint uses top-left origin (y=0 top, y=1 bottom)
        // CoreImage uses bottom-left origin (y=0 bottom, y=height top), so flip Y
        let posX = keystroke.position.x * frameSize.width - pillSize.width / 2
        let posY = (1.0 - keystroke.position.y) * frameSize.height - pillSize.height / 2
        let positioned = opacityApplied.transformed(
            by: CGAffineTransform(translationX: posX, y: posY)
        )

        // Crop to frame size
        return positioned.cropped(to: CGRect(origin: .zero, size: frameSize))
    }

    /// Render a fully-opaque pill image for the given display text (cacheable)
    private func renderPillImage(for displayText: String, frameSize: CGSize) -> CIImage? {
        let fontSize: CGFloat = max(24, frameSize.height * 0.03)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let cornerRadius: CGFloat = fontSize * 0.4
        let paddingH: CGFloat = fontSize * 0.8
        let paddingV: CGFloat = fontSize * 0.4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        let textSize = (displayText as NSString).size(withAttributes: attributes)
        let pillWidth = textSize.width + paddingH * 2
        let pillHeight = textSize.height + paddingV * 2

        let bitmapWidth = Int(ceil(pillWidth))
        let bitmapHeight = Int(ceil(pillHeight))

        guard bitmapWidth > 0, bitmapHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: bitmapWidth,
            height: bitmapHeight,
            bitsPerComponent: 8,
            bytesPerRow: bitmapWidth * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        // Rounded rectangle background at fixed opacity (0.75)
        let pillRect = CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0.1, alpha: 0.75).setFill()
        path.fill()

        // White text at full opacity
        let textRect = CGRect(x: paddingH, y: paddingV, width: textSize.width, height: textSize.height)
        (displayText as NSString).draw(in: textRect, withAttributes: attributes)

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Cache Management

    /// Clear the cursor caches
    func clearCursorCache() {
        cursorImageCache.removeAll()
        cursorHotspotCache.removeAll()
    }

    /// Clear the keystroke pill cache
    func clearKeystrokePillCache() {
        keystrokePillCache.removeAll()
        keystrokePillCacheFrameSize = .zero
    }

    /// Clear all caches (cursor + keystroke)
    func clearAllCaches() {
        clearCursorCache()
        clearKeystrokePillCache()
    }
}
