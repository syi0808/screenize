import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import Metal

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

    /// Metal device (available for GPU-resident pipeline)
    let device: MTLDevice?

    /// Metal command queue
    let commandQueue: MTLCommandQueue?

    /// Reusable color space (avoid per-frame allocation)
    let colorSpace: CGColorSpace

    init(
        outputSize: CGSize,
        sourceSize: CGSize,
        ciContext: CIContext? = nil,
        pixelBufferPool: CVPixelBufferPool? = nil,
        isPreview: Bool = false,
        previewScale: CGFloat = 0.5,
        device: MTLDevice? = nil,
        commandQueue: MTLCommandQueue? = nil,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) {
        self.outputSize = outputSize
        self.sourceSize = sourceSize
        self.pixelBufferPool = pixelBufferPool
        self.isPreview = isPreview
        self.previewScale = previewScale
        self.device = device
        self.commandQueue = commandQueue
        self.colorSpace = colorSpace

        // Use Metal-backed CIContext when device is available
        if let ciContext = ciContext {
            self.ciContext = ciContext
        } else if let device = device {
            var ciOptions: [CIContextOption: Any] = [
                .cacheIntermediates: true,
                .priorityRequestLow: false
            ]
            // Only set workingColorSpace for wide-gamut color spaces.
            // sRGB is CIContext's default — setting it explicitly forces
            // unnecessary per-pixel color conversion.
            if Self.isWideGamut(colorSpace) {
                ciOptions[.workingColorSpace] = colorSpace
            }
            self.ciContext = CIContext(mtlDevice: device, options: ciOptions)
        } else {
            self.ciContext = Self.createOptimizedContext(colorSpace: colorSpace)
        }
    }

    /// Create an optimized CIContext for performance (non-Metal fallback)
    static func createOptimizedContext(
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) -> CIContext {
        var options: [CIContextOption: Any] = [
            .useSoftwareRenderer: false,
            .highQualityDownsample: false,
            .cacheIntermediates: true,
            .priorityRequestLow: false
        ]
        if isWideGamut(colorSpace) {
            options[.workingColorSpace] = colorSpace
        }
        return CIContext(options: options)
    }

    /// Check if a color space is wide gamut (requires explicit working color space)
    private static func isWideGamut(_ colorSpace: CGColorSpace) -> Bool {
        colorSpace != CGColorSpace(name: CGColorSpace.sRGB)!
            && colorSpace != CGColorSpace(name: CGColorSpace.itur_709)!
    }

    /// Create a context for preview (Metal-backed for GPU-resident pipeline)
    static func forPreview(
        sourceSize: CGSize,
        scale: CGFloat = 0.5,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) -> Self {
        let scaledSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        let device = MTLCreateSystemDefaultDevice()
        let commandQueue = device?.makeCommandQueue()

        return Self(
            outputSize: scaledSize,
            sourceSize: sourceSize,
            isPreview: true,
            previewScale: scale,
            device: device,
            commandQueue: commandQueue,
            colorSpace: colorSpace
        )
    }

    /// Create a context for export (Metal-backed for GPU-accelerated rendering)
    static func forExport(
        sourceSize: CGSize,
        outputSize: CGSize? = nil,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) -> Self {
        let finalSize = outputSize ?? sourceSize

        let device = MTLCreateSystemDefaultDevice()
        let commandQueue = device?.makeCommandQueue()

        return Self(
            outputSize: finalSize,
            sourceSize: sourceSize,
            pixelBufferPool: createPixelBufferPool(size: finalSize),
            isPreview: false,
            previewScale: 1.0,
            device: device,
            commandQueue: commandQueue,
            colorSpace: colorSpace
        )
    }

    /// Create a pixel buffer pool
    static func createPixelBufferPool(size: CGSize) -> CVPixelBufferPool? {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 6
        ]

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
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
