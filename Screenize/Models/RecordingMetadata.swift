import Foundation

// MARK: - Recording Metadata (Polyrecorder Compatible)

/// Recorder manifest stored as `recording/metadata.json` inside the package.
/// Compatible with polyrecorder-v2 format.
struct PolyRecordingMetadata: Codable {
    let formatVersion: Int
    let recorderName: String
    let recorderVersion: String
    let createdAt: String
    let processTimeStartMs: Int64
    let processTimeEndMs: Int64
    let unixTimeStartMs: Int64
    let display: DisplayInfo

    struct DisplayInfo: Codable {
        let widthPx: Int
        let heightPx: Int
        let scaleFactor: Double
    }
}
