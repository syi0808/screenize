import Foundation
import CoreGraphics

/// Media asset information
/// References to the original video and mouse data files
struct MediaAsset: Codable {
    /// Original video file URL
    var videoURL: URL

    /// Mouse data JSON file URL
    var mouseDataURL: URL

    /// Original video resolution (pixels)
    let pixelSize: CGSize

    /// Original frame rate
    let frameRate: Double

    /// Total duration (seconds)
    let duration: TimeInterval

    init(
        videoURL: URL,
        mouseDataURL: URL,
        pixelSize: CGSize,
        frameRate: Double,
        duration: TimeInterval
    ) {
        self.videoURL = videoURL
        self.mouseDataURL = mouseDataURL
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.duration = duration
    }

    // MARK: - Validation

    /// Check whether both media files exist
    var filesExist: Bool {
        FileManager.default.fileExists(atPath: videoURL.path) &&
        FileManager.default.fileExists(atPath: mouseDataURL.path)
    }

    /// Check whether the video file exists
    var videoExists: Bool {
        FileManager.default.fileExists(atPath: videoURL.path)
    }

    /// Check whether the mouse data file exists
    var mouseDataExists: Bool {
        FileManager.default.fileExists(atPath: mouseDataURL.path)
    }

    // MARK: - Computed Properties

    /// Aspect ratio
    var aspectRatio: CGFloat {
        guard pixelSize.height > 0 else { return 16.0 / 9.0 }
        return pixelSize.width / pixelSize.height
    }

    /// Total frame count
    var totalFrames: Int {
        Int(duration * frameRate)
    }

    /// Frame duration (seconds)
    var frameDuration: TimeInterval {
        guard frameRate > 0 else { return 1.0 / 60.0 }
        return 1.0 / frameRate
    }
}
