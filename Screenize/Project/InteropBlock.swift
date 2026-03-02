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
        let uiStates: String?

        init(mouseMoves: String?, mouseClicks: String?, keystrokes: String?, uiStates: String? = nil) {
            self.mouseMoves = mouseMoves
            self.mouseClicks = mouseClicks
            self.keystrokes = keystrokes
            self.uiStates = uiStates
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mouseMoves = try container.decodeIfPresent(String.self, forKey: .mouseMoves)
            mouseClicks = try container.decodeIfPresent(String.self, forKey: .mouseClicks)
            keystrokes = try container.decodeIfPresent(String.self, forKey: .keystrokes)
            uiStates = try container.decodeIfPresent(String.self, forKey: .uiStates)
        }
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
                keystrokes: "recording/keystrokes-0.json",
                uiStates: "recording/uistates-0.json"
            ),
            primaryVideoPath: videoRelativePath
        )
    }
}
