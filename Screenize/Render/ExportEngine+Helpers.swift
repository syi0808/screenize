import Foundation
import AVFoundation

// MARK: - Errors

enum ExportEngineError: Error, LocalizedError {
    case alreadyExporting
    case noVideoTrack
    case readerStartFailed
    case writerStartFailed(Error?)
    case writerFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .alreadyExporting:
            return "An export is already in progress"
        case .noVideoTrack:
            return "Could not find a video track"
        case .readerStartFailed:
            return "Failed to start reading video"
        case .writerStartFailed(let underlyingError):
            if let error = underlyingError {
                return "Failed to start writing video: \(error.localizedDescription)"
            }
            return "Failed to start writing video"
        case .writerFailed:
            return "Failed to write video"
        case .cancelled:
            return "Export was cancelled"
        }
    }
}

// MARK: - Audio & Video Helpers

extension ExportEngine {

    /// Check if a URL contains an audio track
    static func hasAudioTrack(url: URL) async -> Bool {
        let asset = AVAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return !tracks.isEmpty
        } catch {
            return false
        }
    }

    /// Create AVFoundation video output settings
    func createVideoSettings(
        size: CGSize,
        codec: VideoCodec,
        quality: ExportQuality,
        frameRate: Double,
        colorSpace: OutputColorSpace = .auto
    ) -> [String: Any] {
        let bitRate = quality.bitRate(for: size)

        var settings: [String: Any] = [
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCodecKey: codec.avCodecType
        ]

        // Compression settings per codec
        switch codec {
        case .h264, .hevc:
            let profileLevel: String = codec == .hevc
                ? "HEVC_Main_AutoLevel"
                : AVVideoProfileLevelH264HighAutoLevel
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: Int(frameRate),
                AVVideoProfileLevelKey: profileLevel
            ]
        case .proRes422, .proRes4444:
            // ProRes does not require bitrate settings
            break
        }

        // Color space metadata tagging (only when explicitly selected)
        if colorSpace != .auto {
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: colorSpace.avColorPrimaries,
                AVVideoTransferFunctionKey: colorSpace.avTransferFunction,
                AVVideoYCbCrMatrixKey: colorSpace.avYCbCrMatrix
            ]
        }

        return settings
    }
}
