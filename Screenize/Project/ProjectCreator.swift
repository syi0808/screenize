import Foundation
import AVFoundation

/// Project creator
/// Generates new projects from recordings or existing videos
struct ProjectCreator {

    // MARK: - Create from Recording

    /// Create a project from a recording
    /// - Parameters:
    ///   - videoURL: Recorded video file URL
    ///   - mouseDataURL: Mouse data file URL
    ///   - captureMeta: Capture metadata
    /// - Returns: New project
    static func createFromRecording(
        videoURL: URL,
        mouseDataURL: URL,
        captureMeta: CaptureMeta
    ) async throws -> ScreenizeProject {
        // Load video information
        let videoInfo = try await loadVideoInfo(from: videoURL)

        // Create a media asset
        let media = MediaAsset(
            videoURL: videoURL,
            mouseDataURL: mouseDataURL,
            pixelSize: videoInfo.size,
            frameRate: videoInfo.frameRate,
            duration: videoInfo.duration
        )

        // Create a default timeline
        let timeline = createDefaultTimeline(duration: videoInfo.duration)

        // Create the project
        return ScreenizeProject(
            name: videoURL.deletingPathExtension().lastPathComponent,
            media: media,
            captureMeta: captureMeta,
            timeline: timeline,
            renderSettings: RenderSettings()
        )
    }

    // MARK: - Create from Video

    /// Create a project from an existing video file
    /// - Parameters:
    ///   - videoURL: Video file URL
    ///   - mouseDataURL: Mouse data file URL (falls back if nil)
    /// - Returns: New project
    static func createFromVideo(
        videoURL: URL,
        mouseDataURL: URL? = nil
    ) async throws -> ScreenizeProject {
        // Load video information
        let videoInfo = try await loadVideoInfo(from: videoURL)

        // Mouse data URL (fall back to default if missing)
        let mouseURL = mouseDataURL ?? findMouseDataURL(for: videoURL)

        // Create a media asset
        let media = MediaAsset(
            videoURL: videoURL,
            mouseDataURL: mouseURL,
            pixelSize: videoInfo.size,
            frameRate: videoInfo.frameRate,
            duration: videoInfo.duration
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
            name: videoURL.deletingPathExtension().lastPathComponent,
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

        return VideoInfo(
            size: size,
            frameRate: frameRate,
            duration: duration
        )
    }

    // MARK: - Mouse Data

    private static func findMouseDataURL(for videoURL: URL) -> URL {
        // Look for a .mouse.json file next to the video
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let directory = videoURL.deletingLastPathComponent()

        // Candidate filenames to try
        let candidates = [
            "\(baseName).mouse.json",
            "\(baseName)_mouse.json",
            "mouse.json"
        ]

        for candidate in candidates {
            let candidateURL = directory.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        // Return the default path if none are present (file may be created later)
        return directory.appendingPathComponent("\(baseName).mouse.json")
    }

    // MARK: - Scale Factor Detection

    private static func detectScaleFactor(videoSize: CGSize) -> CGFloat {
        // Estimate scale based on common resolutions
        // 4K or above: 2.0
        // 1440p up to 4K: 2.0
        // 1080p: 1.0 or 2.0
        // Others: 1.0

        let totalPixels = videoSize.width * videoSize.height

        if totalPixels >= 3840 * 2160 { // 4K or greater
            return 2.0
        } else if totalPixels >= 2560 * 1440 { // 1440p or greater
            return 2.0
        } else if totalPixels >= 1920 * 1080 { // 1080p
            // Most macOS displays are Retina, so estimate 2.0
            return 2.0
        }

        return 1.0
    }

    // MARK: - Default Timeline

    private static func createDefaultTimeline(duration: TimeInterval) -> Timeline {
        // Create a default timeline with empty tracks
        Timeline(
            tracks: [
                AnyTrack(TransformTrack(
                    id: UUID(),
                    name: "Transform",
                    isEnabled: true,
                    keyframes: [
                        // Start with one default keyframe
                        TransformKeyframe(
                            time: 0,
                            zoom: 1.0,
                            centerX: 0.5,
                            centerY: 0.5,
                            easing: .easeInOut
                        )
                    ]
                )),
                AnyTrack(RippleTrack(
                    id: UUID(),
                    name: "Ripple",
                    isEnabled: true,
                    keyframes: []
                )),
                AnyTrack(CursorTrack(
                    id: UUID(),
                    name: "Cursor",
                    isEnabled: true,
                    styleKeyframes: [
                        // Default cursor style
                        CursorStyleKeyframe(
                            time: 0,
                            style: .arrow,
                            visible: true,
                            scale: 1.5,
                            easing: .linear
                        )
                    ]
                )),
                AnyTrack(KeystrokeTrack(
                    id: UUID(),
                    name: "Keystroke",
                    isEnabled: true,
                    keyframes: []
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
        case ripple
        case cursorSmooth
    }

    static let `default` = Self()
}
