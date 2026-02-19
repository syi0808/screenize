import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import Metal

/// Unified renderer
/// Shared rendering logic for both Preview and Export
final class Renderer {

    // MARK: - Properties

    /// Rendering context
    private let context: RenderContext

    /// Transform applicator (Screen mode)
    private let transformApplicator: TransformApplicator

    /// Effect compositor
    private let compositor: EffectCompositor

    /// Motion blur settings
    private let motionBlurSettings: MotionBlurSettings?

    /// Renderer used in window mode
    private let windowModeRenderer: WindowModeRenderer?

    /// Indicates whether window mode is active
    private let isWindowMode: Bool

    /// Rendering settings for window mode
    private let renderSettings: RenderSettings?

    // MARK: - Initialization

    init(
        context: RenderContext,
        motionBlurSettings: MotionBlurSettings? = nil,
        isWindowMode: Bool = false,
        renderSettings: RenderSettings? = nil
    ) {
        self.context = context
        self.transformApplicator = TransformApplicator()
        self.compositor = EffectCompositor(ciContext: context.ciContext)
        self.motionBlurSettings = motionBlurSettings

        self.isWindowMode = isWindowMode
        self.renderSettings = renderSettings
        self.windowModeRenderer = isWindowMode ? WindowModeRenderer(ciContext: context.ciContext) : nil
    }

    // MARK: - Main Render

    /// Render a single frame
    /// - Parameters:
    ///   - sourceFrame: Source video frame
    ///   - state: Evaluated frame state
    /// - Returns: Rendered image
    func render(
        sourceFrame: CIImage,
        state: EvaluatedFrameState
    ) -> CIImage? {
        var result = sourceFrame

        // 1. Render cursor (over source frame, before transform)
        // The cursor renders at the source frame's absolute position and scales/moves with the transform
        if state.cursor.visible {
            if let cursorImage = compositor.renderCursor(state.cursor, frameSize: context.sourceSize) {
                result = cursorImage.composited(over: result)
            }
        }

        // 2. Apply transform (mode-specific branch)
        if isWindowMode, let windowRenderer = windowModeRenderer, let settings = renderSettings {
            // Window mode: background + window scale/offset + effects
            result = windowRenderer.render(
                sourceFrame: result,
                transform: state.transform,
                sourceSize: context.sourceSize,
                outputSize: context.outputSize,
                settings: settings
            )
        } else {
            // Screen mode: standard crop/zoom workflow
            result = transformApplicator.apply(
                to: result,
                transform: state.transform,
                sourceSize: context.sourceSize,
                outputSize: context.outputSize,
                motionBlurSettings: motionBlurSettings
            )
        }

        // 3. Keystroke overlay (after transform — fixed screen position)
        if !state.keystrokes.isEmpty {
            if let keystrokeOverlay = compositor.renderKeystrokeOverlay(
                state.keystrokes,
                frameSize: context.outputSize
            ) {
                result = keystrokeOverlay.composited(over: result)
            }
        }

        return result
    }

    // MARK: - Pixel Buffer Output

    /// Render a frame to a CVPixelBuffer
    /// - Parameters:
    ///   - sourceFrame: Source video frame
    ///   - state: Evaluated frame state
    /// - Returns: Rendered pixel buffer
    func renderToPixelBuffer(
        sourceFrame: CIImage,
        state: EvaluatedFrameState
    ) -> CVPixelBuffer? {
        guard let rendered = render(sourceFrame: sourceFrame, state: state) else {
            return nil
        }

        return createPixelBuffer(from: rendered)
    }

    /// Convert a CIImage to a CVPixelBuffer
    private func createPixelBuffer(from image: CIImage) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        // Acquire from the pixel buffer pool
        if let pool = context.pixelBufferPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                return nil
            }
            pixelBuffer = buffer
        } else {
            // Create a new one
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(context.outputSize.width),
                kCVPixelBufferHeightKey as String: Int(context.outputSize.height),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]

            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(context.outputSize.width),
                Int(context.outputSize.height),
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary,
                &pixelBuffer
            )

            guard status == kCVReturnSuccess else { return nil }
        }

        guard let buffer = pixelBuffer else { return nil }

        // Render the CIImage into the CVPixelBuffer
        context.ciContext.render(
            image,
            to: buffer,
            bounds: CGRect(origin: .zero, size: context.outputSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return buffer
    }

    // MARK: - MTLTexture Output

    /// Render a frame directly to an MTLTexture (GPU-resident, no CPU readback)
    /// The CIContext must be Metal-backed (created via CIContext(mtlDevice:))
    /// Passing nil for commandBuffer makes the call synchronous (waits for GPU completion)
    /// - Parameters:
    ///   - sourceFrame: Source video frame
    ///   - state: Evaluated frame state
    ///   - targetTexture: Destination MTLTexture (must have .renderTarget usage)
    /// - Returns: Whether rendering succeeded
    func renderToTexture(
        sourceFrame: CIImage,
        state: EvaluatedFrameState,
        targetTexture: MTLTexture
    ) -> Bool {
        guard let rendered = render(sourceFrame: sourceFrame, state: state) else {
            return false
        }

        // Synchronous render: CIContext creates its own command buffer, commits, and waits
        context.ciContext.render(
            rendered,
            to: targetTexture,
            commandBuffer: nil,
            bounds: CGRect(origin: .zero, size: context.outputSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return true
    }

    // MARK: - CGImage Output

    /// Render a frame to a CGImage (used by export pipeline)
    /// - Parameters:
    ///   - sourceFrame: Source video frame
    ///   - state: Evaluated frame state
    /// - Returns: Rendered CGImage
    func renderToCGImage(
        sourceFrame: CIImage,
        state: EvaluatedFrameState
    ) -> CGImage? {
        guard let rendered = render(sourceFrame: sourceFrame, state: state) else {
            return nil
        }

        return context.ciContext.createCGImage(
            rendered,
            from: CGRect(origin: .zero, size: context.outputSize)
        )
    }
}

// MARK: - Metal Accessors

extension Renderer {
    /// Metal device from the render context (nil if not Metal-backed)
    var device: MTLDevice? { context.device }

    /// Metal command queue from the render context
    var commandQueue: MTLCommandQueue? { context.commandQueue }

    /// Output size from the render context
    var outputSize: CGSize { context.outputSize }
}

// MARK: - Batch Rendering

extension Renderer {
    /// Batch render multiple frames
    /// - Parameters:
    ///   - sourceFrames: Array of source frames
    ///   - states: Array of frame states
    /// - Returns: Array of rendered CGImages
    func renderBatch(
        sourceFrames: [CIImage],
        states: [EvaluatedFrameState]
    ) -> [CGImage?] {
        guard sourceFrames.count == states.count else {
            return []
        }

        return zip(sourceFrames, states).map { sourceFrame, state in
            renderToCGImage(sourceFrame: sourceFrame, state: state)
        }
    }
}

// MARK: - Renderer Factory

extension Renderer {
    /// Create a renderer for preview
    static func forPreview(
        sourceSize: CGSize,
        scale: CGFloat = 0.5,
        motionBlurSettings: MotionBlurSettings? = nil,
        isWindowMode: Bool = false,
        renderSettings: RenderSettings? = nil
    ) -> Renderer {
        let context = RenderContext.forPreview(sourceSize: sourceSize, scale: scale)
        return Renderer(
            context: context,
            motionBlurSettings: motionBlurSettings,
            isWindowMode: isWindowMode,
            renderSettings: renderSettings
        )
    }

    /// Create a renderer for export
    static func forExport(
        sourceSize: CGSize,
        outputSize: CGSize? = nil,
        motionBlurSettings: MotionBlurSettings? = nil,
        isWindowMode: Bool = false,
        renderSettings: RenderSettings? = nil
    ) -> Renderer {
        let context = RenderContext.forExport(sourceSize: sourceSize, outputSize: outputSize)
        return Renderer(
            context: context,
            motionBlurSettings: motionBlurSettings,
            isWindowMode: isWindowMode,
            renderSettings: renderSettings
        )
    }
}
