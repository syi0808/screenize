import Foundation
import ScreenCaptureKit
import CoreGraphics

struct CaptureConfiguration {
    var width: Int
    var height: Int
    var frameRate: Int
    var pixelFormat: OSType
    var showsCursor: Bool
    var capturesAudio: Bool
    var scaleFactor: CGFloat
    var capturesShadow: Bool
    var sourceRect: CGRect?

    init(
        width: Int = 1920,
        height: Int = 1080,
        frameRate: Int = 60,
        pixelFormat: OSType = kCVPixelFormatType_32BGRA,
        showsCursor: Bool = false,
        capturesAudio: Bool = true,
        scaleFactor: CGFloat = 2.0,
        capturesShadow: Bool = true,
        sourceRect: CGRect? = nil
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.pixelFormat = pixelFormat
        self.showsCursor = showsCursor
        self.capturesAudio = capturesAudio
        self.scaleFactor = scaleFactor
        self.capturesShadow = capturesShadow
        self.sourceRect = sourceRect
    }

    static let `default` = Self()

    static let highQuality = Self(
        width: 3840,
        height: 2160,
        frameRate: 60,
        scaleFactor: 2.0
    )

    static let mediumQuality = Self(
        width: 1920,
        height: 1080,
        frameRate: 30,
        scaleFactor: 1.0
    )

    static let lowQuality = Self(
        width: 1280,
        height: 720,
        frameRate: 30,
        scaleFactor: 1.0
    )

    func createStreamConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = pixelFormat
        config.showsCursor = showsCursor
        config.capturesAudio = capturesAudio
        config.scalesToFit = true
        if #available(macOS 14.0, *) {
            config.ignoreShadowsSingleWindow = !capturesShadow
        }
        if let sourceRect {
            config.sourceRect = sourceRect
        }
        return config
    }

    static func forTarget(_ target: CaptureTarget, scaleFactor: CGFloat = 2.0, frameRate: Int = 60) -> Self {
        let width = Int(CGFloat(target.width) * scaleFactor)
        let height = Int(CGFloat(target.height) * scaleFactor)

        var sourceRect: CGRect?
        if case .window(let scWindow) = target {
            sourceRect = Self.computeSourceRect(for: scWindow)
        }

        return Self(
            width: width,
            height: height,
            frameRate: frameRate,
            scaleFactor: scaleFactor,
            capturesShadow: !target.isWindow,
            sourceRect: sourceRect
        )
    }

    /// Compute the sourceRect for a window relative to its containing display.
    /// sourceRect is in the display's CG coordinate space.
    private static func computeSourceRect(for window: SCWindow) -> CGRect {
        let windowCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)

        // Find the display containing the window's center
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(maxDisplays, &displayIDs, &displayCount)

        var displayOrigin = CGPoint.zero
        for i in 0..<Int(displayCount) {
            let bounds = CGDisplayBounds(displayIDs[i])
            if bounds.contains(windowCenter) {
                displayOrigin = bounds.origin
                break
            }
        }

        // sourceRect is relative to the display's origin
        return CGRect(
            x: window.frame.origin.x - displayOrigin.x,
            y: window.frame.origin.y - displayOrigin.y,
            width: window.frame.width,
            height: window.frame.height
        )
    }
}
