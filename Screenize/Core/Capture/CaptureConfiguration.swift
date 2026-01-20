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

    init(
        width: Int = 1920,
        height: Int = 1080,
        frameRate: Int = 60,
        pixelFormat: OSType = kCVPixelFormatType_32BGRA,
        showsCursor: Bool = false,
        capturesAudio: Bool = true,
        scaleFactor: CGFloat = 2.0
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.pixelFormat = pixelFormat
        self.showsCursor = showsCursor
        self.capturesAudio = capturesAudio
        self.scaleFactor = scaleFactor
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
        return config
    }

    static func forTarget(_ target: CaptureTarget, scaleFactor: CGFloat = 2.0) -> Self {
        let width = Int(CGFloat(target.width) * scaleFactor)
        let height = Int(CGFloat(target.height) * scaleFactor)

        return Self(
            width: width,
            height: height,
            frameRate: 60,
            scaleFactor: scaleFactor
        )
    }
}
