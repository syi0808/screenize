import Foundation
import AVFoundation

/// Project creator
/// Generates new projects from recordings or existing videos
struct ProjectCreator {

    // MARK: - Create from Recording

    /// Create a project from a recording
    /// - Parameters:
    ///   - packageInfo: Package info from PackageManager.createPackage
    ///   - captureMeta: Capture metadata
    /// - Returns: New project
    static func createFromRecording(
        packageInfo: PackageInfo,
        captureMeta: CaptureMeta
    ) async throws -> ScreenizeProject {
        // Load video information
        let videoInfo = try await loadVideoInfo(from: packageInfo.videoURL)

        // Create a media asset with relative paths
        let media = MediaAsset(
            videoRelativePath: packageInfo.videoRelativePath,
            mouseDataRelativePath: packageInfo.mouseDataRelativePath,
            micAudioRelativePath: packageInfo.micAudioRelativePath,
            packageRootURL: packageInfo.packageURL,
            pixelSize: videoInfo.size,
            frameRate: videoInfo.frameRate,
            duration: videoInfo.duration,
            isVariableFrameRate: videoInfo.isVariableFrameRate
        )

        // Create a default timeline
        let timeline = createDefaultTimeline(duration: videoInfo.duration)

        // Create the project
        return ScreenizeProject(
            name: packageInfo.packageURL.deletingPathExtension().lastPathComponent,
            media: media,
            captureMeta: captureMeta,
            timeline: timeline,
            renderSettings: RenderSettings(),
            interop: packageInfo.interop
        )
    }

    // MARK: - Create from Video

    /// Create a project from an existing video file (already in package)
    /// - Parameter packageInfo: Package info from PackageManager.createPackage
    /// - Returns: New project
    static func createFromVideo(
        packageInfo: PackageInfo
    ) async throws -> ScreenizeProject {
        // Load video information
        let videoInfo = try await loadVideoInfo(from: packageInfo.videoURL)

        // Create a media asset with relative paths
        let media = MediaAsset(
            videoRelativePath: packageInfo.videoRelativePath,
            mouseDataRelativePath: packageInfo.mouseDataRelativePath,
            packageRootURL: packageInfo.packageURL,
            pixelSize: videoInfo.size,
            frameRate: videoInfo.frameRate,
            duration: videoInfo.duration,
            isVariableFrameRate: videoInfo.isVariableFrameRate
        )

        // Basic capture metadata based on video size
        let scaleFactor = detectScaleFactor(videoSize: videoInfo.size)
        let pointSize = CGSize(
            width: videoInfo.size.width / scaleFactor,
            height: videoInfo.size.height / scaleFactor
        )
        let captureMeta = CaptureMeta(
            boundsPt: CGRect(origin: .zero, size: pointSize),
            scaleFactor: scaleFactor
        )

        // Create a default timeline
        let timeline = createDefaultTimeline(duration: videoInfo.duration)

        return ScreenizeProject(
            name: packageInfo.packageURL.deletingPathExtension().lastPathComponent,
            media: media,
            captureMeta: captureMeta,
            timeline: timeline,
            renderSettings: RenderSettings()
        )
    }

    // MARK: - Video Info

    private struct VideoInfo {
        let size: CGSize
        let frameRate: Double
        let duration: TimeInterval
        let isVariableFrameRate: Bool
    }

    private static func loadVideoInfo(from url: URL) async throws -> VideoInfo {
        let asset = AVAsset(url: url)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProjectCreatorError.noVideoTrack
        }

        let size = try await videoTrack.load(.naturalSize)
        let nominalFrameRate = try await Double(videoTrack.load(.nominalFrameRate))
        let duration = try await CMTimeGetSeconds(asset.load(.duration))

        let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 60.0

        // Detect variable frame rate by comparing minFrameDuration with nominal
        let minFrameDuration = try await videoTrack.load(.minFrameDuration)
        let minFrameDurationSec = CMTimeGetSeconds(minFrameDuration)
        let isVFR: Bool
        if minFrameDurationSec > 0 && nominalFrameRate > 0 {
            let minFPS = 1.0 / minFrameDurationSec
            isVFR = abs(minFPS - nominalFrameRate) / nominalFrameRate > 0.1
        } else {
            isVFR = false
        }

        return VideoInfo(
            size: size,
            frameRate: frameRate,
            duration: duration,
            isVariableFrameRate: isVFR
        )
    }

    // MARK: - Scale Factor Detection

    private static func detectScaleFactor(videoSize: CGSize) -> CGFloat {
        let totalPixels = videoSize.width * videoSize.height

        if totalPixels >= 3840 * 2160 {
            return 2.0
        } else if totalPixels >= 2560 * 1440 {
            return 2.0
        } else if totalPixels >= 1920 * 1080 {
            return 2.0
        }

        return 1.0
    }

    // MARK: - Default Timeline

    private static func createDefaultTimeline(duration: TimeInterval) -> Timeline {
        Timeline(
            tracks: [
                AnySegmentTrack.camera(CameraTrack(
                    id: UUID(),
                    name: "Camera",
                    isEnabled: true,
                    segments: [
                        CameraSegment(
                            startTime: 0,
                            endTime: max(0.1, duration),
                            startTransform: .identity,
                            endTransform: .identity,
                            interpolation: .easeInOut
                        ),
                    ]
                )),
                AnySegmentTrack.cursor(CursorTrackV2(
                    id: UUID(),
                    name: "Cursor",
                    isEnabled: true,
                    segments: [
                        CursorSegment(startTime: 0, endTime: max(0.1, duration), style: .arrow, visible: true, scale: 1.5),
                    ]
                )),
                AnySegmentTrack.keystroke(KeystrokeTrackV2(
                    id: UUID(),
                    name: "Keystroke",
                    isEnabled: true,
                    segments: []
                )),
            ],
            duration: duration
        )
    }
}

// MARK: - Errors

enum ProjectCreatorError: Error, LocalizedError {
    case noVideoTrack
    case invalidVideoFile
    case mouseDataNotFound

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in the file"
        case .invalidVideoFile:
            return "Invalid or corrupted video file"
        case .mouseDataNotFound:
            return "Mouse data file not found"
        }
    }
}

// MARK: - Project Creator Options

/// Project creator options
struct ProjectCreatorOptions {
    /// Default zoom level
    var defaultZoom: CGFloat = 1.0

    /// Default cursor style
    var defaultCursorStyle: CursorStyle = .arrow

    /// Default cursor scale
    var defaultCursorScale: CGFloat = 1.5

    /// Auto-run smart generators
    var autoGenerateKeyframes: Bool = false

    /// Generator types to auto-run
    var autoGeneratorTypes: Set<AutoGeneratorType> = []

    enum AutoGeneratorType {
        case clickZoom
        case cursorSmooth
    }

    static let `default` = Self()
}
