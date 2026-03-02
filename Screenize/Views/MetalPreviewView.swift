import SwiftUI
import Metal
import QuartzCore
import CoreImage

/// Metal-backed preview view for zero-copy GPU display
/// Receives pre-rendered MTLTexture and displays it via CAMetalLayer
struct MetalPreviewView: NSViewRepresentable {

    /// Texture to display
    let texture: MTLTexture?

    /// Generation counter (forces SwiftUI to call updateNSView on each new render)
    var generation: Int = 0

    func makeNSView(context: Context) -> MetalDisplayView {
        MetalDisplayView()
    }

    func updateNSView(_ nsView: MetalDisplayView, context: Context) {
        nsView.displayTexture(texture)
    }
}

/// NSView backed by CAMetalLayer for zero-copy GPU texture display
final class MetalDisplayView: NSView {

    // MARK: - Properties

    /// Metal layer for display
    private let metalLayer = CAMetalLayer()

    /// Metal device
    private let device: MTLDevice

    /// Command queue for display blit operations
    private let commandQueue: MTLCommandQueue

    /// CIContext for GPU-to-GPU blit with aspect-fit scaling
    private let ciContext: CIContext

    /// Last texture received (re-rendered on layout changes)
    private var lastTexture: MTLTexture?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is not supported on this device")
        }

        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: false,
            .priorityRequestLow: false
        ])

        super.init(frame: frameRect)

        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = CGColor.black
        layer = metalLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateDrawableSize()
        renderCurrentTexture()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateDrawableSize()
            renderCurrentTexture()
        }
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }

    // MARK: - Display

    /// Display a pre-rendered MTLTexture with aspect-fit scaling
    /// GPU-to-GPU blit: no CPU memory involvement
    func displayTexture(_ texture: MTLTexture?) {
        lastTexture = texture
        renderCurrentTexture()
    }

    /// Render the stored texture to the Metal layer
    private func renderCurrentTexture() {
        guard let texture = lastTexture,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let drawableW = CGFloat(drawable.texture.width)
        let drawableH = CGFloat(drawable.texture.height)
        let textureW = CGFloat(texture.width)
        let textureH = CGFloat(texture.height)

        // Wrap the source texture as CIImage (GPU-resident, zero-copy)
        // CIImage(mtlTexture:) flips Y to match CIImage convention (bottom-left origin)
        guard let sourceImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpace.screenizeSRGB
        ]) else { return }

        // Compute aspect-fit transform
        let scaleX = drawableW / textureW
        let scaleY = drawableH / textureH
        let scale = min(scaleX, scaleY)

        let scaledW = textureW * scale
        let scaledH = textureH * scale
        let offsetX = (drawableW - scaledW) / 2
        let offsetY = (drawableH - scaledH) / 2

        let fitTransform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))

        let scaledImage = sourceImage.transformed(by: fitTransform)

        // Black background filling the entire drawable
        let black = CIImage(color: .black).cropped(to: CGRect(
            origin: .zero,
            size: CGSize(width: drawableW, height: drawableH)
        ))
        let composited = scaledImage.composited(over: black)

        // Render to drawable texture (GPU-to-GPU, no CPU involvement)
        ciContext.render(
            composited,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: CGSize(width: drawableW, height: drawableH)),
            colorSpace: .screenizeSRGB
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
