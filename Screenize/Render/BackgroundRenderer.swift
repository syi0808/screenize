import Foundation
import CoreGraphics
import CoreImage
import SwiftUI
import AppKit

/// Background renderer
/// Generates a background layer for window mode
final class BackgroundRenderer {

    // MARK: - Properties

    private let ciContext: CIContext

    // MARK: - Initialization

    init(ciContext: CIContext) {
        self.ciContext = ciContext
    }

    // MARK: - Public Methods

    /// Create a background image
    /// - Parameters:
    ///   - style: Background style
    ///   - outputSize: Output size
    /// - Returns: Background CIImage
    func render(style: BackgroundStyle, outputSize: CGSize) -> CIImage {
        switch style {
        case .solid(let color):
            return renderSolidColor(color, size: outputSize)
        case .gradient(let gradient):
            return renderGradient(gradient, size: outputSize)
        case .image(let url):
            return renderImage(url, size: outputSize)
        }
    }

    // MARK: - Private Methods

    /// Render a solid color background
    private func renderSolidColor(_ color: Color, size: CGSize) -> CIImage {
        let nsColor = NSColor(color)
        guard let ciColor = CIColor(color: nsColor) else {
            return fallbackBlack(size)
        }
        return CIImage(color: ciColor).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Render a gradient background
    private func renderGradient(_ gradient: GradientStyle, size: CGSize) -> CIImage {
        guard let filter = CIFilter(name: "CILinearGradient") else {
            return fallbackBlack(size)
        }

        // Start and end colors
        let startNSColor = NSColor(gradient.colors.first ?? .black)
        let endNSColor = NSColor(gradient.colors.last ?? .black)

        guard let startColor = CIColor(color: startNSColor),
              let endColor = CIColor(color: endNSColor) else {
            return fallbackBlack(size)
        }

        // Convert UnitPoint to pixel coordinates
        // SwiftUI UnitPoint: (0,0)=topLeading, (1,1)=bottomTrailing
        // CoreImage: (0,0)=bottomLeft
        // Flip the Y axis
        let startPoint = CIVector(
            x: gradient.startPoint.x * size.width,
            y: (1 - gradient.startPoint.y) * size.height
        )
        let endPoint = CIVector(
            x: gradient.endPoint.x * size.width,
            y: (1 - gradient.endPoint.y) * size.height
        )

        filter.setValue(startColor, forKey: "inputColor0")
        filter.setValue(endColor, forKey: "inputColor1")
        filter.setValue(startPoint, forKey: "inputPoint0")
        filter.setValue(endPoint, forKey: "inputPoint1")

        guard let output = filter.outputImage else {
            return fallbackBlack(size)
        }

        return output.cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Render an image background (scale to fill)
    private func renderImage(_ url: URL, size: CGSize) -> CIImage {
        guard let image = CIImage(contentsOf: url) else {
            return fallbackBlack(size)
        }

        // Scale to fill (cover)
        let scaleX = size.width / image.extent.width
        let scaleY = size.height / image.extent.height
        let scale = max(scaleX, scaleY)

        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center and crop
        let offsetX = (scaled.extent.width - size.width) / 2
        let offsetY = (scaled.extent.height - size.height) / 2

        let cropped = scaled.cropped(to: CGRect(
            x: scaled.extent.origin.x + offsetX,
            y: scaled.extent.origin.y + offsetY,
            width: size.width,
            height: size.height
        ))

        // Translate back to the origin
        return cropped.transformed(by: CGAffineTransform(
            translationX: -cropped.extent.origin.x,
            y: -cropped.extent.origin.y
        ))
    }

    /// Black fallback background
    private func fallbackBlack(_ size: CGSize) -> CIImage {
        return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
    }
}
