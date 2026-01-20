import Foundation
import CoreGraphics
import CoreImage
import CoreVideo

/// Rendering context
/// Shared rendering environment for preview and export
struct RenderContext {
    /// Output size
    let outputSize: CGSize

    /// Source video size
    let sourceSize: CGSize

    /// CoreImage context
    let ciContext: CIContext

    /// Pixel buffer pool (for performance optimization)
    let pixelBufferPool: CVPixelBufferPool?

    /// Whether this is preview mode
    let isPreview: Bool

    /// Preview scale (0.5 = 50% resolution)
    let previewScale: CGFloat

    init(
        outputSize: CGSize,
        sourceSize: CGSize,
        ciContext: CIContext? = nil,
        pixelBufferPool: CVPixelBufferPool? = nil,
        isPreview: Bool = false,
        previewScale: CGFloat = 0.5
    ) {
        self.outputSize = outputSize
        self.sourceSize = sourceSize
        self.ciContext = ciContext ?? Self.createOptimizedContext()
        self.pixelBufferPool = pixelBufferPool
        self.isPreview = isPreview
        self.previewScale = previewScale
    }

    /// Create an optimized CIContext for performance
    static func createOptimizedContext() -> CIContext {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: false,
            .cacheIntermediates: true,
            .priorityRequestLow: false
        ])
    }

    /// Create a context for preview
    static func forPreview(sourceSize: CGSize, scale: CGFloat = 0.5) -> Self {
        let scaledSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        return Self(
            outputSize: scaledSize,
            sourceSize: sourceSize,
            isPreview: true,
            previewScale: scale
        )
    }

    /// Create a context for export
    static func forExport(sourceSize: CGSize, outputSize: CGSize? = nil) -> Self {
        let finalSize = outputSize ?? sourceSize

        return Self(
            outputSize: finalSize,
            sourceSize: sourceSize,
            pixelBufferPool: createPixelBufferPool(size: finalSize),
            isPreview: false,
            previewScale: 1.0
        )
    }

    /// Create a pixel buffer pool
    static func createPixelBufferPool(size: CGSize) -> CVPixelBufferPool? {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )

        guard status == kCVReturnSuccess else {
            return nil
        }

        return pool
    }

    // MARK: - Computed Properties

    /// Output scale relative to the source
    var outputScale: CGFloat {
        outputSize.width / sourceSize.width
    }

    /// Aspect ratio
    var aspectRatio: CGFloat {
        outputSize.width / outputSize.height
    }
}
