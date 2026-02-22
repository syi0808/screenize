import Foundation
import CoreGraphics
import CoreImage

/// Window mode renderer
/// Screen Studio-style rendering: fixed background plus window scale/position and effects
final class WindowModeRenderer {

    // MARK: - Properties

    private let backgroundRenderer: BackgroundRenderer
    private let transformApplicator: WindowTransformApplicator
    private let effectApplicator: WindowEffectApplicator
    private let isPreview: Bool

    // Background caching (reuse when style and size match)
    private var cachedBackground: CIImage?
    private var cachedBackgroundStyle: BackgroundStyle?
    private var cachedBackgroundSize: CGSize?

    // MARK: - Initialization

    init(ciContext: CIContext, isPreview: Bool) {
        self.backgroundRenderer = BackgroundRenderer(ciContext: ciContext)
        self.transformApplicator = WindowTransformApplicator()
        self.effectApplicator = WindowEffectApplicator(ciContext: ciContext)
        self.isPreview = isPreview
    }

    // MARK: - Public Methods

    /// Render in window mode
    /// - Parameters:
    ///   - sourceFrame: Source window frame
    ///   - transform: Transform state
    ///   - sourceSize: Source size
    ///   - outputSize: Output size
    ///   - settings: Render settings
    /// - Returns: Rendered image (background + window + effects)
    func render(
        sourceFrame: CIImage,
        transform: TransformState,
        sourceSize: CGSize,
        outputSize: CGSize,
        settings: RenderSettings
    ) -> CIImage {
        // 0. Normalize the source frame's extent origin to (0, 0)
        // CIImage scales around its origin, so if the origin is not (0,0),
        // the offset also scales and causes positional drift
        var processedFrame = sourceFrame
        var processedSourceSize = sourceSize

        let initialOrigin = processedFrame.extent.origin
        if initialOrigin != .zero {
            processedFrame = processedFrame.transformed(
                by: CGAffineTransform(translationX: -initialOrigin.x, y: -initialOrigin.y)
            )
        }

        // 1. Apply window inset (trim the edges)
        if settings.windowInset > 0 {
            let inset = settings.windowInset
            let currentExtent = processedFrame.extent
            let cropRect = CGRect(
                x: inset,
                y: inset,
                width: currentExtent.width - inset * 2,
                height: currentExtent.height - inset * 2
            )

            // If the inset exceeds the image, keep the original
            if cropRect.width > 0 && cropRect.height > 0 {
                processedFrame = processedFrame.cropped(to: cropRect)
                processedSourceSize = cropRect.size

                // After cropping, re-normalize the extent origin to (0, 0)
                // Adjust because the cropped image's origin becomes (inset, inset)
                processedFrame = processedFrame.transformed(
                    by: CGAffineTransform(translationX: -inset, y: -inset)
                )
            }
        }

        // 2. Generate the background (with caching)
        let backgroundStyle: BackgroundStyle = settings.backgroundEnabled
            ? settings.backgroundStyle
            : .solid(isPreview ? .white : .clear)
        let background = getOrCreateBackground(
            style: backgroundStyle,
            outputSize: outputSize
        )

        // 3. Apply the window transform (scale + position)
        var window = transformApplicator.apply(
            to: processedFrame,
            transform: transform,
            sourceSize: processedSourceSize,
            outputSize: outputSize,
            padding: settings.padding
        )

        // 4. Window effects (rounded corners + shadow)
        // Scale corner radius and shadow radius by the same factor used in the transform
        // so they remain visually consistent at all zoom levels
        let availableWidth = outputSize.width - settings.padding * 2
        let availableHeight = outputSize.height - settings.padding * 2
        let scaleX = availableWidth / processedSourceSize.width
        let scaleY = availableHeight / processedSourceSize.height
        let baseScale = min(scaleX, scaleY)
        let finalScale = baseScale * transform.zoom

        window = effectApplicator.apply(
            to: window,
            cornerRadius: settings.cornerRadius * finalScale,
            shadowRadius: settings.shadowRadius * finalScale,
            shadowOpacity: settings.shadowOpacity
        )

        // 5. Composite the window over the background
        return window.composited(over: background)
    }

    /// Clear the cache
    func clearCache() {
        cachedBackground = nil
        cachedBackgroundStyle = nil
        cachedBackgroundSize = nil
    }

    // MARK: - Private Methods

    /// Retrieve or create the background (using caching)
    private func getOrCreateBackground(style: BackgroundStyle, outputSize: CGSize) -> CIImage {
        // Check for a cache hit
        if let cached = cachedBackground,
           cachedBackgroundStyle == style,
           cachedBackgroundSize == outputSize {
            return cached
        }

        // Create a new background
        let background = backgroundRenderer.render(style: style, outputSize: outputSize)

        // Save to cache
        cachedBackground = background
        cachedBackgroundStyle = style
        cachedBackgroundSize = outputSize

        return background
    }
}
