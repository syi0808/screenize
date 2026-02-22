import Foundation
import CoreGraphics

/// Media asset information
/// References to the original video and mouse data files
struct MediaAsset: Codable {
    /// Relative path within the package (stored in JSON)
    var videoRelativePath: String

    /// Relative path within the package (stored in JSON)
    var mouseDataRelativePath: String

    /// Relative path to microphone audio within the package (nil if no mic was used)
    var micAudioRelativePath: String?

    /// Absolute video file URL (resolved at runtime, NOT stored in JSON)
    var videoURL: URL

    /// Absolute mouse data JSON file URL (resolved at runtime, NOT stored in JSON)
    var mouseDataURL: URL

    /// Absolute mic audio file URL (resolved at runtime, NOT stored in JSON)
    var micAudioURL: URL?

    /// Original video resolution (pixels)
    let pixelSize: CGSize

    /// Original frame rate
    let frameRate: Double

    /// Total duration (seconds)
    let duration: TimeInterval

    /// Whether the source video uses variable frame rate
    let isVariableFrameRate: Bool

    // MARK: - Initializers

    /// Create from package-relative paths
    init(
        videoRelativePath: String,
        mouseDataRelativePath: String,
        micAudioRelativePath: String? = nil,
        packageRootURL: URL,
        pixelSize: CGSize,
        frameRate: Double,
        duration: TimeInterval,
        isVariableFrameRate: Bool = false
    ) {
        self.videoRelativePath = videoRelativePath
        self.mouseDataRelativePath = mouseDataRelativePath
        self.micAudioRelativePath = micAudioRelativePath
        self.videoURL = packageRootURL.appendingPathComponent(videoRelativePath)
        self.mouseDataURL = packageRootURL.appendingPathComponent(mouseDataRelativePath)
        if let micPath = micAudioRelativePath {
            self.micAudioURL = packageRootURL.appendingPathComponent(micPath)
        }
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.duration = duration
        self.isVariableFrameRate = isVariableFrameRate
    }

    // MARK: - URL Resolution

    /// Resolve relative paths to absolute URLs using the package root
    mutating func resolveURLs(from packageRootURL: URL) {
        videoURL = packageRootURL.appendingPathComponent(videoRelativePath)
        mouseDataURL = packageRootURL.appendingPathComponent(mouseDataRelativePath)
        if let micPath = micAudioRelativePath {
            micAudioURL = packageRootURL.appendingPathComponent(micPath)
        }
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

    /// Check whether the mic audio file exists
    var micAudioExists: Bool {
        guard let url = micAudioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Computed Properties

    /// Aspect ratio
    var aspectRatio: CGFloat {
        guard pixelSize.height > 0 else { return 16.0 / 9.0 }
        return pixelSize.width / pixelSize.height
    }

    /// Total frame count (approximate for VFR videos)
    var totalFrames: Int {
        Int(duration * frameRate)
    }

    /// Frame duration in seconds (average for VFR videos)
    var frameDuration: TimeInterval {
        guard frameRate > 0 else { return 1.0 / 60.0 }
        return 1.0 / frameRate
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case videoRelativePath = "videoPath"
        case mouseDataRelativePath = "mouseDataPath"
        case micAudioRelativePath = "micAudioPath"
        case pixelSize
        case frameRate
        case duration
        case isVariableFrameRate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(videoRelativePath, forKey: .videoRelativePath)
        try container.encode(mouseDataRelativePath, forKey: .mouseDataRelativePath)
        try container.encodeIfPresent(micAudioRelativePath, forKey: .micAudioRelativePath)
        try container.encode(pixelSize, forKey: .pixelSize)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(duration, forKey: .duration)
        try container.encode(isVariableFrameRate, forKey: .isVariableFrameRate)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pixelSize = try container.decode(CGSize.self, forKey: .pixelSize)
        frameRate = try container.decode(Double.self, forKey: .frameRate)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        isVariableFrameRate = try container.decodeIfPresent(Bool.self, forKey: .isVariableFrameRate) ?? false
        videoRelativePath = try container.decode(String.self, forKey: .videoRelativePath)
        mouseDataRelativePath = try container.decode(String.self, forKey: .mouseDataRelativePath)
        micAudioRelativePath = try container.decodeIfPresent(String.self, forKey: .micAudioRelativePath)
        // Placeholder URLs - must be resolved by caller via resolveURLs(from:)
        videoURL = URL(fileURLWithPath: videoRelativePath)
        mouseDataURL = URL(fileURLWithPath: mouseDataRelativePath)
        if let micPath = micAudioRelativePath {
            micAudioURL = URL(fileURLWithPath: micPath)
        }
    }
}
