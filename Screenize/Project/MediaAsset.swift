import Foundation
import CoreGraphics

/// Media asset information
/// References to the original video and mouse data files
struct MediaAsset: Codable {
    /// Relative path within the package (stored in JSON)
    var videoRelativePath: String

    /// Relative path within the package (stored in JSON)
    var mouseDataRelativePath: String

    /// Absolute video file URL (resolved at runtime, NOT stored in JSON)
    var videoURL: URL

    /// Absolute mouse data JSON file URL (resolved at runtime, NOT stored in JSON)
    var mouseDataURL: URL

    /// Original video resolution (pixels)
    let pixelSize: CGSize

    /// Original frame rate
    let frameRate: Double

    /// Total duration (seconds)
    let duration: TimeInterval

    // MARK: - Initializers

    /// Create from package-relative paths
    init(
        videoRelativePath: String,
        mouseDataRelativePath: String,
        packageRootURL: URL,
        pixelSize: CGSize,
        frameRate: Double,
        duration: TimeInterval
    ) {
        self.videoRelativePath = videoRelativePath
        self.mouseDataRelativePath = mouseDataRelativePath
        self.videoURL = packageRootURL.appendingPathComponent(videoRelativePath)
        self.mouseDataURL = packageRootURL.appendingPathComponent(mouseDataRelativePath)
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.duration = duration
    }

    // MARK: - URL Resolution

    /// Resolve relative paths to absolute URLs using the package root
    mutating func resolveURLs(from packageRootURL: URL) {
        videoURL = packageRootURL.appendingPathComponent(videoRelativePath)
        mouseDataURL = packageRootURL.appendingPathComponent(mouseDataRelativePath)
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

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case videoRelativePath = "videoPath"
        case mouseDataRelativePath = "mouseDataPath"
        case pixelSize
        case frameRate
        case duration
        // MARK: - Legacy (remove in next minor version)
        case legacyVideoURL = "videoURL"
        case legacyMouseDataURL = "mouseDataURL"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(videoRelativePath, forKey: .videoRelativePath)
        try container.encode(mouseDataRelativePath, forKey: .mouseDataRelativePath)
        try container.encode(pixelSize, forKey: .pixelSize)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(duration, forKey: .duration)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pixelSize = try container.decode(CGSize.self, forKey: .pixelSize)
        frameRate = try container.decode(Double.self, forKey: .frameRate)
        duration = try container.decode(TimeInterval.self, forKey: .duration)

        if let videoPath = try container.decodeIfPresent(String.self, forKey: .videoRelativePath),
           let mousePath = try container.decodeIfPresent(String.self, forKey: .mouseDataRelativePath) {
            // Version 2 format: relative paths
            videoRelativePath = videoPath
            mouseDataRelativePath = mousePath
            // Placeholder URLs - must be resolved by caller via resolveURLs(from:)
            videoURL = URL(fileURLWithPath: videoPath)
            mouseDataURL = URL(fileURLWithPath: mousePath)
        } else {
            // MARK: - Legacy (remove in next minor version)
            // Version 1 format: absolute URLs stored directly
            videoURL = try container.decode(URL.self, forKey: .legacyVideoURL)
            mouseDataURL = try container.decode(URL.self, forKey: .legacyMouseDataURL)
            videoRelativePath = ""
            mouseDataRelativePath = ""
        }
    }
}
