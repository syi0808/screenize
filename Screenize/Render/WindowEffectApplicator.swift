import Foundation
import CoreGraphics
import CoreImage
import SwiftUI

/// Window effect applicator
/// Applies rounded corners and a drop shadow
final class WindowEffectApplicator {

    // MARK: - Properties

    private let ciContext: CIContext

    // MARK: - Initialization

    init(ciContext: CIContext) {
        self.ciContext = ciContext
    }

    // MARK: - Public Methods

    /// Apply window effects (rounded corners + shadow)
    /// - Parameters:
    ///   - image: Window image (after transform)
    ///   - cornerRadius: Radius for rounded corners
    ///   - shadowRadius: Shadow blur radius
    ///   - shadowOpacity: Shadow opacity (0-1)
    ///   - shadowOffsetY: Shadow Y offset (downward)
    /// - Returns: Image with effects applied
    func apply(
        to image: CIImage,
        cornerRadius: CGFloat,
        shadowRadius: CGFloat,
        shadowOpacity: Float,
        shadowOffsetY: CGFloat = 10
    ) -> CIImage {
        var result = image
        let bounds = image.extent

        // Check for an empty image
        guard bounds.width > 0, bounds.height > 0 else {
            return image
        }

        // ========================================
        // Step 1: Apply rounded corners
        // ========================================
        if cornerRadius > 0 {
            result = applyRoundedCorners(to: result, cornerRadius: cornerRadius)
        }

        // ========================================
        // Step 2: Create and composite the shadow
        // ========================================
        if shadowRadius > 0 && shadowOpacity > 0 {
            let shadow = createShadow(
                for: result,
                radius: shadowRadius,
                opacity: shadowOpacity,
                offsetY: shadowOffsetY
            )
            // Composite the window over the shadow
            result = result.composited(over: shadow)
        }

        return result
    }

    // MARK: - Private Methods

    /// Apply rounded corners
    private func applyRoundedCorners(to image: CIImage, cornerRadius: CGFloat) -> CIImage {
        let bounds = image.extent

        // Create a mask
        let maskImage = createRoundedRectMask(
            size: bounds.size,
            origin: bounds.origin,
            cornerRadius: cornerRadius
        )

        // Apply the CIBlendWithMask filter
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return image
        }

        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.clear, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }

    /// Create a rounded rectangle mask
    private func createRoundedRectMask(size: CGSize, origin: CGPoint, cornerRadius: CGFloat) -> CIImage {
        // Validate the size
        guard size.width > 0, size.height > 0 else {
            return CIImage.white
        }

        let width = Int(size.width)
        let height = Int(size.height)

        // Create the mask using CGContext (Grayscale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return CIImage.white.cropped(to: CGRect(origin: .zero, size: size))
        }

        // Black background (transparent = 0 in the mask)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        // White rounded rectangle (opaque = 1 in the mask)
        context.setFillColor(gray: 1, alpha: 1)
        let path = Path(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerRadius: cornerRadius,
            style: .continuous
        ).cgPath
        context.addPath(path)
        context.fillPath()

        guard let cgImage = context.makeImage() else {
            return CIImage.white.cropped(to: CGRect(origin: .zero, size: size))
        }

        // Translate to match the original image's position
        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    /// Create the shadow
    private func createShadow(
        for image: CIImage,
        radius: CGFloat,
        opacity: Float,
        offsetY: CGFloat
    ) -> CIImage {
        let bounds = image.extent

        // 1. Generate a silhouette with black color and opacity
        let shadowColor = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(opacity)))
            .cropped(to: bounds)

        // 2. Use alpha channel to create shadow silhouette
        // CISourceInCompositing (Porter-Duff "Source In"): result = source * dest.alpha
        // This correctly uses the alpha channel (not luminance) to determine shadow shape
        guard let sourceInFilter = CIFilter(name: "CISourceInCompositing") else {
            return CIImage.clear
        }

        sourceInFilter.setValue(shadowColor, forKey: kCIInputImageKey)
        sourceInFilter.setValue(image, forKey: kCIInputBackgroundImageKey)

        guard var shadow = sourceInFilter.outputImage else {
            return CIImage.clear
        }

        // 3. Apply a Gaussian blur
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return shadow
        }

        blurFilter.setValue(shadow, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)

        shadow = blurFilter.outputImage ?? shadow

        // 4. Apply the downward offset
        // CoreImage's Y axis increases upward, so use -offsetY to move downward
        shadow = shadow.transformed(by: CGAffineTransform(translationX: 0, y: -offsetY))

        return shadow
    }
}

// MARK: - CIImage Extension

private extension CIImage {
    /// Transparent image
    static var clear: CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
    }

    /// White image
    static var white: CIImage {
        CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
    }
}
