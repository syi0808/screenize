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
            return L10n.exportAlreadyInProgress
        case .noVideoTrack:
            return L10n.noVideoTrackFound
        case .readerStartFailed:
            return L10n.failedToStartReadingVideo
        case .writerStartFailed(let underlyingError):
            if let error = underlyingError {
                return L10n.failedToStartWritingVideo(detail: error.localizedDescription)
            }
            return L10n.failedToStartWritingVideo
        case .writerFailed:
            return L10n.failedToWriteVideo
        case .cancelled:
            return L10n.exportWasCancelled
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
