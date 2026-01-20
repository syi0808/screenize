import Foundation
import CoreGraphics
import CoreImage

/// Transform applicator
/// Applies zoom/pan transforms to a CIImage
final class TransformApplicator {

    init() {}

    /// Apply a TransformState to a CIImage
    /// - Parameters:
    ///   - image: Source image
    ///   - transform: Transform state
    ///   - sourceSize: Source image size
    ///   - outputSize: Output size
    ///   - motionBlurSettings: Motion blur settings (disabled when nil)
    /// - Returns: The transformed image
    func apply(
        to image: CIImage,
        transform: TransformState,
        sourceSize: CGSize,
        outputSize: CGSize,
        motionBlurSettings: MotionBlurSettings? = nil
    ) -> CIImage {
        // Return immediately for identity transforms (performance)
        if transform == .identity {
            // Apply scaling only when source and output sizes differ
            if sourceSize != outputSize {
                return scaleToFit(image: image, sourceSize: sourceSize, outputSize: outputSize)
            }
            return image
        }

        // Calculate the crop area
        let cropRect = calculateCropRect(
            transform: transform,
            sourceSize: sourceSize
        )

        // Apply the crop
        let cropped = image.cropped(to: cropRect)

        // Scale to the output size
        let scaleX = outputSize.width / cropRect.width
        let scaleY = outputSize.height / cropRect.height

        // Translate to the origin before scaling
        let translated = cropped.transformed(by: CGAffineTransform(
            translationX: -cropRect.origin.x,
            y: -cropRect.origin.y
        ))

        var result = translated.transformed(by: CGAffineTransform(
            scaleX: scaleX,
            y: scaleY
        ))

        // Apply motion blur
        if let settings = motionBlurSettings, settings.enabled {
            result = applyMotionBlur(to: result, transform: transform, settings: settings)
        }

        return result
    }

    // MARK: - Motion Blur

    /// Apply motion blur effects
    /// - Parameters:
    ///   - image: Image after transform
    ///   - transform: Transform state (includes velocity)
    ///   - settings: Motion blur settings
    /// - Returns: Image with motion blur applied
    private func applyMotionBlur(
        to image: CIImage,
        transform: TransformState,
        settings: MotionBlurSettings
    ) -> CIImage {
        // Skip when movement is below thresholds (filters out hold states)
        let shouldApplyZoomBlur = transform.zoomVelocity > settings.zoomThreshold
        let shouldApplyPanBlur = transform.panVelocity > settings.panThreshold

        guard shouldApplyZoomBlur || shouldApplyPanBlur else {
            return image
        }

        // Compute blur radius and angle
        let baseRadius: CGFloat
        let angle: CGFloat

        if shouldApplyPanBlur && transform.panVelocity > transform.zoomVelocity * 0.3 {
            // Pan-dominant: blur along the movement direction
            baseRadius = (transform.panVelocity - settings.panThreshold) * 30.0
            angle = transform.panDirection
        } else {
            // Zoom-dominant: apply horizontal blur
            baseRadius = (transform.zoomVelocity - settings.zoomThreshold) * 8.0
            angle = 0  // horizontal direction
        }

        // Apply intensity and clamp to the maximum radius
        let radius = min(baseRadius * settings.intensity, settings.maxRadius)

        // Skip very small blur (needs at least 2 pixels to be meaningful)
        guard radius > 2.0 else {
            return image
        }

        // Apply the CIMotionBlur filter
        guard let filter = CIFilter(name: "CIMotionBlur") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(angle, forKey: kCIInputAngleKey)

        return filter.outputImage ?? image
    }

    /// Calculate the crop rectangle based on transforms
    /// - Parameters:
    ///   - transform: Transform state
    ///   - sourceSize: Source image size
    /// - Returns: Crop rectangle
    func calculateCropRect(transform: TransformState, sourceSize: CGSize) -> CGRect {
        // Compute crop size based on zoom (zoom 2.0 shows only 50% area)
        let cropWidth = sourceSize.width / transform.zoom
        let cropHeight = sourceSize.height / transform.zoom

        // Position the crop around the center (centerX/Y are normalized 0-1 coordinates)
        let centerX = transform.centerX * sourceSize.width
        let centerY = transform.centerY * sourceSize.height

        // Crop origin (with boundary clamping)
        var cropX = centerX - cropWidth / 2
        var cropY = centerY - cropHeight / 2

        // Clamp the crop so it stays within the image bounds
        cropX = clamp(cropX, min: 0, max: sourceSize.width - cropWidth)
        cropY = clamp(cropY, min: 0, max: sourceSize.height - cropHeight)

        return CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
    }

    /// Scale the image to match the output size
    private func scaleToFit(image: CIImage, sourceSize: CGSize, outputSize: CGSize) -> CIImage {
        let scaleX = outputSize.width / sourceSize.width
        let scaleY = outputSize.height / sourceSize.height

        return image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

// MARK: - Transform Validation

extension TransformApplicator {
    /// Validate a transform
    func isValid(transform: TransformState, sourceSize: CGSize) -> Bool {
        // Ensure the zoom is at least 1.0
        guard transform.zoom >= 1.0 else { return false }

        // Ensure the center stays within the normalized 0-1 range
        guard transform.centerX >= 0, transform.centerX <= 1 else { return false }
        guard transform.centerY >= 0, transform.centerY <= 1 else { return false }

        // Ensure the crop rectangle is valid
        let cropRect = calculateCropRect(transform: transform, sourceSize: sourceSize)
        guard cropRect.width > 0, cropRect.height > 0 else { return false }
        guard cropRect.maxX <= sourceSize.width else { return false }
        guard cropRect.maxY <= sourceSize.height else { return false }

        return true
    }

    /// Clamp a transform into its valid range
    func sanitize(transform: TransformState, sourceSize: CGSize) -> TransformState {
        var zoom = max(1.0, transform.zoom)
        var centerX = clamp(transform.centerX, min: 0, max: 1)
        var centerY = clamp(transform.centerY, min: 0, max: 1)

        // Adjust the allowed center range based on zoom level
        // Higher zoom levels prevent the center from reaching the edges
        let halfCropRatioX = 0.5 / zoom
        let halfCropRatioY = 0.5 / zoom

        centerX = clamp(centerX, min: halfCropRatioX, max: 1 - halfCropRatioX)
        centerY = clamp(centerY, min: halfCropRatioY, max: 1 - halfCropRatioY)

        return TransformState(zoom: zoom, centerX: centerX, centerY: centerY)
    }
}
