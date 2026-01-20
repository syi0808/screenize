import Foundation
import CoreGraphics
import CoreImage

/// Window mode transform applicator
/// Screen Studio style: scale and reposition the window (no cropping)
final class WindowTransformApplicator {

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// Apply the window-mode transform
    /// - Parameters:
    ///   - image: Source window image
    ///   - transform: Transform state
    ///   - sourceSize: Source image size
    ///   - outputSize: Output size
    ///   - padding: Padding around the window
    /// - Returns: Transformed image
    ///
    /// ## Transform logic
    /// - zoom 1.0: window fits within the padded area
    /// - zoom 2.0: window scales to twice the fit size
    /// - center (0.5, 0.5): window center aligns with screen center
    /// - center (0.3, 0.5): 30% point of the window aligns with the screen center → window moves right
    func apply(
        to image: CIImage,
        transform: TransformState,
        sourceSize: CGSize,
        outputSize: CGSize,
        padding: CGFloat
    ) -> CIImage {
        // ========================================
        // Step 1: Calculate the base 'fit' scale
        // ========================================
        // Scale so the window fits within the padded area
        let availableWidth = outputSize.width - padding * 2
        let availableHeight = outputSize.height - padding * 2

        // Guard against division by zero
        guard sourceSize.width > 0, sourceSize.height > 0,
              availableWidth > 0, availableHeight > 0 else {
            return image
        }

        let scaleX = availableWidth / sourceSize.width
        let scaleY = availableHeight / sourceSize.height
        let baseScale = min(scaleX, scaleY)  // fit (contain)

        // ========================================
        // Step 2: Apply the final zoom
        // ========================================
        // zoom 1.0 = fit size
        // zoom 2.0 = twice the fit size
        let finalScale = baseScale * transform.zoom

        // ========================================
        // Step 3: Apply the scaling transform
        // ========================================
        var result = image.transformed(by: CGAffineTransform(scaleX: finalScale, y: finalScale))

        // Dimensions of the scaled window
        let scaledWidth = sourceSize.width * finalScale
        let scaledHeight = sourceSize.height * finalScale

        // ========================================
        // Step 4: Compute position based on center
        // ========================================
        // The center values locate a specific point within the window that should align with the screen center
        // This mirrors the concept of "crop center" from screen mode

        // Screen center coordinates
        let screenCenterX = outputSize.width / 2
        let screenCenterY = outputSize.height / 2

        // Point inside the scaled window targeted by the center values
        let windowPointX = transform.centerX * scaledWidth
        let windowPointY = transform.centerY * scaledHeight

        // Window origin = screen center minus the window point
        // This aligns the window point with the screen center
        let windowOriginX = screenCenterX - windowPointX
        let windowOriginY = screenCenterY - windowPointY

        // ========================================
        // Step 5: Apply the translation transform
        // ========================================
        result = result.transformed(by: CGAffineTransform(translationX: windowOriginX, y: windowOriginY))

        return result
    }

    // MARK: - Utility Methods

    /// Calculate the scaled window size
    /// - Parameters:
    ///   - sourceSize: Source size
    ///   - outputSize: Output size
    ///   - padding: Padding
    ///   - zoom: Zoom factor
    /// - Returns: Scaled size
    func calculateScaledSize(
        sourceSize: CGSize,
        outputSize: CGSize,
        padding: CGFloat,
        zoom: CGFloat
    ) -> CGSize {
        let availableWidth = outputSize.width - padding * 2
        let availableHeight = outputSize.height - padding * 2

        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return .zero
        }

        let scaleX = availableWidth / sourceSize.width
        let scaleY = availableHeight / sourceSize.height
        let baseScale = min(scaleX, scaleY)
        let finalScale = baseScale * zoom

        return CGSize(
            width: sourceSize.width * finalScale,
            height: sourceSize.height * finalScale
        )
    }

    /// Calculate the window origin (for debugging/preview)
    /// - Parameters:
    ///   - transform: Transform state
    ///   - sourceSize: Source size
    ///   - outputSize: Output size
    ///   - padding: Padding
    /// - Returns: Window origin coordinates
    func calculateWindowOrigin(
        transform: TransformState,
        sourceSize: CGSize,
        outputSize: CGSize,
        padding: CGFloat
    ) -> CGPoint {
        let scaledSize = calculateScaledSize(
            sourceSize: sourceSize,
            outputSize: outputSize,
            padding: padding,
            zoom: transform.zoom
        )

        let screenCenterX = outputSize.width / 2
        let screenCenterY = outputSize.height / 2

        let windowPointX = transform.centerX * scaledSize.width
        let windowPointY = transform.centerY * scaledSize.height

        return CGPoint(
            x: screenCenterX - windowPointX,
            y: screenCenterY - windowPointY
        )
    }
}
