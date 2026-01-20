import Foundation
import CoreGraphics
import AVFoundation
import SwiftUI

/// Rendering settings
struct RenderSettings: Codable {
    /// Output resolution
    var outputResolution: OutputResolution = .original

    /// Output frame rate
    var outputFrameRate: OutputFrameRate = .original

    /// Video codec
    var codec: VideoCodec = .hevc

    /// Output quality
    var quality: ExportQuality = .high

    /// Enable background (for window mode)
    var backgroundEnabled: Bool = false

    /// Background style (for window mode)
    var backgroundStyle: BackgroundStyle = .gradient(.defaultGradient)

    /// Rounded corner radius
    var cornerRadius: CGFloat = 22.0

    /// Shadow radius
    var shadowRadius: CGFloat = 40.0

    /// Shadow opacity
    var shadowOpacity: Float = 0.7

    /// Padding (for window mode)
    var padding: CGFloat = 40.0

    /// Window inset (for trimming borders)
    var windowInset: CGFloat = 12.0

    /// Motion blur settings
    var motionBlur: MotionBlurSettings = .default

    init(
        outputResolution: OutputResolution = .original,
        outputFrameRate: OutputFrameRate = .original,
        codec: VideoCodec = .hevc,
        quality: ExportQuality = .high,
        motionBlur: MotionBlurSettings = .default
    ) {
        self.outputResolution = outputResolution
        self.outputFrameRate = outputFrameRate
        self.codec = codec
        self.quality = quality
        self.motionBlur = motionBlur
    }

    // MARK: - Codable (for backward compatibility)

    private enum CodingKeys: String, CodingKey {
        case outputResolution
        case outputFrameRate
        case codec
        case quality
        case backgroundEnabled
        case backgroundStyle
        case cornerRadius
        case shadowRadius
        case shadowOpacity
        case padding
        case windowInset
        case motionBlur
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        outputResolution = try container.decodeIfPresent(OutputResolution.self, forKey: .outputResolution) ?? .original
        outputFrameRate = try container.decodeIfPresent(OutputFrameRate.self, forKey: .outputFrameRate) ?? .original
        codec = try container.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .hevc
        quality = try container.decodeIfPresent(ExportQuality.self, forKey: .quality) ?? .high
        backgroundEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? false
        backgroundStyle = try container.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? .gradient(.defaultGradient)
        cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 22.0
        shadowRadius = try container.decodeIfPresent(CGFloat.self, forKey: .shadowRadius) ?? 40.0
        shadowOpacity = try container.decodeIfPresent(Float.self, forKey: .shadowOpacity) ?? 0.7
        padding = try container.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 40.0
        windowInset = try container.decodeIfPresent(CGFloat.self, forKey: .windowInset) ?? 12.0
        // Older projects might not have the motionBlur field, so use the default
        motionBlur = try container.decodeIfPresent(MotionBlurSettings.self, forKey: .motionBlur) ?? .default
    }
}

// MARK: - Output Resolution

enum OutputResolution: Codable, Equatable, Hashable {
    case original
    case uhd4k       // 3840x2160
    case qhd1440     // 2560x1440
    case fhd1080     // 1920x1080
    case hd720       // 1280x720
    case custom(width: Int, height: Int)

    /// Convert to CGSize (use sourceSize when original)
    func size(sourceSize: CGSize) -> CGSize {
        switch self {
        case .original:
            return sourceSize
        case .uhd4k:
            return CGSize(width: 3840, height: 2160)
        case .qhd1440:
            return CGSize(width: 2560, height: 1440)
        case .fhd1080:
            return CGSize(width: 1920, height: 1080)
        case .hd720:
            return CGSize(width: 1280, height: 720)
        case .custom(let width, let height):
            return CGSize(width: width, height: height)
        }
    }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .uhd4k: return "4K UHD (3840x2160)"
        case .qhd1440: return "QHD (2560x1440)"
        case .fhd1080: return "Full HD (1920x1080)"
        case .hd720: return "HD (1280x720)"
        case .custom(let w, let h): return "Custom (\(w)x\(h))"
        }
    }

    /// Preset list (used by the picker)
    static let allCases: [Self] = [.original, .uhd4k, .qhd1440, .fhd1080, .hd720]
}

// MARK: - Output Frame Rate

enum OutputFrameRate: Codable, Equatable, Hashable {
    case original
    case fixed(Int)

    /// Returns a frame rate value (uses sourceFrameRate when original)
    func value(sourceFrameRate: Double) -> Double {
        switch self {
        case .original:
            return sourceFrameRate
        case .fixed(let fps):
            return Double(fps)
        }
    }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .fixed(let fps): return "\(fps) fps"
        }
    }

    // Presets
    static let fps24 = Self.fixed(24)
    static let fps30 = Self.fixed(30)
    static let fps60 = Self.fixed(60)

    /// Preset list (used by the picker)
    static let allCases: [Self] = [.original, .fps24, .fps30, .fps60]
}

// MARK: - Video Codec

enum VideoCodec: String, Codable, CaseIterable {
    case h264 = "h264"
    case hevc = "hevc"  // H.265
    case proRes422 = "prores422"
    case proRes4444 = "prores4444"

    var avCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        case .proRes422: return .proRes422
        case .proRes4444: return .proRes4444
        }
    }

    var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "H.265 (HEVC)"
        case .proRes422: return "ProRes 422"
        case .proRes4444: return "ProRes 4444"
        }
    }

    var fileExtension: String {
        switch self {
        case .h264, .hevc: return "mp4"
        case .proRes422, .proRes4444: return "mov"
        }
    }
}

// MARK: - Export Quality

enum ExportQuality: String, Codable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case original = "original"

    /// Bitrate multiplier (applied to resolution)
    var bitRateMultiplier: Double {
        switch self {
        case .low: return 2.0
        case .medium: return 4.0
        case .high: return 8.0
        case .original: return 12.0
        }
    }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .original: return "Original"
        }
    }

    /// Calculate the bitrate for the given resolution (bps)
    func bitRate(for size: CGSize) -> Int {
        let pixels = size.width * size.height
        let baseBitRate = pixels * bitRateMultiplier
        return Int(baseBitRate)
    }
}
