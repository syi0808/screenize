import Foundation

// MARK: - Interop Block (v4)

/// Polyrecorder interoperability block embedded in project.json v4.
/// Describes event stream locations and recording metadata path.
struct InteropBlock: Codable {
    let sourceKind: String
    let eventBundleVersion: Int
    let recordingMetadataPath: String
    let streams: StreamMap
    let primaryVideoPath: String

    struct StreamMap: Codable {
        let mouseMoves: String?
        let mouseClicks: String?
        let keystrokes: String?
    }

    /// Create a default interop block for a new recording.
    /// - Parameter videoRelativePath: Relative path to the video file within the package
    static func forRecording(videoRelativePath: String) -> Self {
        Self(
            sourceKind: "polyrecorder-v2",
            eventBundleVersion: 1,
            recordingMetadataPath: "recording/metadata.json",
            streams: StreamMap(
                mouseMoves: "recording/mousemoves-0.json",
                mouseClicks: "recording/mouseclicks-0.json",
                keystrokes: "recording/keystrokes-0.json"
            ),
            primaryVideoPath: videoRelativePath
        )
    }
}
