import Foundation
import CoreGraphics
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

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

    /// Export format (video or GIF)
    var exportFormat: ExportFormat = .video

    /// GIF-specific settings (used when exportFormat == .gif)
    var gifSettings: GIFSettings = .default

    /// Output color space
    var outputColorSpace: OutputColorSpace = .auto

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
    var windowInset: CGFloat = 0.0

    /// Motion blur settings
    var motionBlur: MotionBlurSettings = .default

    /// System audio volume (0.0–1.0)
    var systemAudioVolume: Float = 1.0

    /// Microphone audio volume (0.0–1.0)
    var microphoneAudioVolume: Float = 1.0

    /// Include system audio in export
    var includeSystemAudio: Bool = true

    /// Include microphone audio in export
    var includeMicrophoneAudio: Bool = true

    /// File extension for the current export format
    var fileExtension: String {
        switch exportFormat {
        case .video: return codec.fileExtension
        case .gif: return "gif"
        }
    }

    /// UTType for the current export format
    var exportUTType: UTType {
        switch exportFormat {
        case .video: return codec.utType
        case .gif: return .gif
        }
    }

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
        case exportFormat
        case gifSettings
        case outputColorSpace
        case backgroundEnabled
        case backgroundStyle
        case cornerRadius
        case shadowRadius
        case shadowOpacity
        case padding
        case windowInset
        case motionBlur
        case systemAudioVolume
        case microphoneAudioVolume
        case includeSystemAudio
        case includeMicrophoneAudio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        outputResolution = try container.decodeIfPresent(OutputResolution.self, forKey: .outputResolution) ?? .original
        outputFrameRate = try container.decodeIfPresent(OutputFrameRate.self, forKey: .outputFrameRate) ?? .original
        codec = try container.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .hevc
        quality = try container.decodeIfPresent(ExportQuality.self, forKey: .quality) ?? .high
        exportFormat = try container.decodeIfPresent(ExportFormat.self, forKey: .exportFormat) ?? .video
        gifSettings = try container.decodeIfPresent(GIFSettings.self, forKey: .gifSettings) ?? .default
        outputColorSpace = try container.decodeIfPresent(OutputColorSpace.self, forKey: .outputColorSpace) ?? .auto
        backgroundEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? false
        backgroundStyle = try container.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? .gradient(.defaultGradient)
        cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 22.0
        shadowRadius = try container.decodeIfPresent(CGFloat.self, forKey: .shadowRadius) ?? 40.0
        shadowOpacity = try container.decodeIfPresent(Float.self, forKey: .shadowOpacity) ?? 0.7
        padding = try container.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 40.0
        windowInset = try container.decodeIfPresent(CGFloat.self, forKey: .windowInset) ?? 0.0
        motionBlur = try container.decodeIfPresent(MotionBlurSettings.self, forKey: .motionBlur) ?? .default
        systemAudioVolume = try container.decodeIfPresent(Float.self, forKey: .systemAudioVolume) ?? 1.0
        microphoneAudioVolume = try container.decodeIfPresent(Float.self, forKey: .microphoneAudioVolume) ?? 1.0
        includeSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .includeSystemAudio) ?? true
        includeMicrophoneAudio = try container.decodeIfPresent(Bool.self, forKey: .includeMicrophoneAudio) ?? true
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

    /// Validate and create a custom resolution with even, positive dimensions
    static func validatedCustom(width: Int, height: Int) -> OutputResolution? {
        guard width >= 2, height >= 2, width <= 7680, height <= 4320 else {
            return nil
        }
        let evenWidth = width.isMultiple(of: 2) ? width : width + 1
        let evenHeight = height.isMultiple(of: 2) ? height : height + 1
        return .custom(width: evenWidth, height: evenHeight)
    }
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
    static let fps120 = Self.fixed(120)
    static let fps240 = Self.fixed(240)

    /// Preset list (used by the picker)
    static let allCases: [Self] = [.original, .fps24, .fps30, .fps60, .fps120, .fps240]

    /// Validate a custom frame rate value (1-240 fps)
    static func validatedCustom(fps: Int) -> OutputFrameRate? {
        guard fps >= 1, fps <= 240 else { return nil }
        return .fixed(fps)
    }
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

    var avFileType: AVFileType {
        switch self {
        case .h264, .hevc: return .mp4
        case .proRes422, .proRes4444: return .mov
        }
    }

    var utType: UTType {
        switch self {
        case .h264, .hevc: return .mpeg4Movie
        case .proRes422, .proRes4444: return .quickTimeMovie
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

// MARK: - Export Format

/// Export format type
enum ExportFormat: String, Codable, CaseIterable {
    case video = "video"
    case gif = "gif"

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .gif: return "GIF"
        }
    }
}

// MARK: - GIF Settings

/// Settings for GIF export
struct GIFSettings: Codable, Equatable {
    /// Frame rate for GIF output (typically 10-20 fps)
    var frameRate: Int = 15

    /// Loop count (0 = infinite loop)
    var loopCount: Int = 0

    /// Maximum width in pixels (height scales proportionally)
    var maxWidth: Int = 640

    // MARK: - Presets

    static let `default` = Self()
    static let compact = Self(frameRate: 10, loopCount: 0, maxWidth: 480)
    static let balanced = Self(frameRate: 15, loopCount: 0, maxWidth: 640)
    static let highQuality = Self(frameRate: 20, loopCount: 0, maxWidth: 960)

    // MARK: - Computed

    /// Calculate effective output size, scaling down if source exceeds maxWidth
    func effectiveSize(sourceSize: CGSize) -> CGSize {
        guard sourceSize.width > CGFloat(maxWidth) else { return sourceSize }
        let scale = CGFloat(maxWidth) / sourceSize.width
        let w = CGFloat(maxWidth)
        let h = (sourceSize.height * scale).rounded(.down)
        let evenHeight = Int(h) % 2 == 0 ? Int(h) : Int(h) + 1
        return CGSize(width: Int(w), height: evenHeight)
    }

    /// GIF frame delay in seconds
    var frameDelay: Double {
        1.0 / Double(max(1, frameRate))
    }

    /// Estimated file size in bytes (rough heuristic)
    func estimatedFileSize(duration: TimeInterval) -> Int64 {
        let frameCount = Int(duration * Double(frameRate))
        let bytesPerFrame: Int64 = Int64(maxWidth) * 40
        return Int64(frameCount) * bytesPerFrame
    }
}

// MARK: - Output Color Space

/// Color space for video export
enum OutputColorSpace: String, Codable, CaseIterable {
    case auto = "auto"
    case sRGB = "srgb"
    case displayP3 = "displayP3"
    case bt709 = "bt709"
    case bt2020 = "bt2020"

    var displayName: String {
        switch self {
        case .auto: return "Auto (sRGB)"
        case .sRGB: return "sRGB"
        case .displayP3: return "Display P3"
        case .bt709: return "BT.709"
        case .bt2020: return "BT.2020"
        }
    }

    /// CGColorSpace for CIContext rendering
    var cgColorSpace: CGColorSpace {
        switch self {
        case .auto, .sRGB:
            return .screenizeSRGB
        case .displayP3:
            return .screenizeP3
        case .bt709:
            return .screenizeBT709
        case .bt2020:
            return .screenizeBT2020
        }
    }

    /// AVFoundation color primaries
    var avColorPrimaries: String {
        switch self {
        case .auto, .sRGB, .bt709:
            return AVVideoColorPrimaries_ITU_R_709_2
        case .displayP3:
            return AVVideoColorPrimaries_P3_D65
        case .bt2020:
            return AVVideoColorPrimaries_ITU_R_2020
        }
    }

    /// AVFoundation transfer function
    var avTransferFunction: String {
        return AVVideoTransferFunction_ITU_R_709_2
    }

    /// AVFoundation YCbCr matrix
    var avYCbCrMatrix: String {
        switch self {
        case .auto, .sRGB, .bt709, .displayP3:
            return AVVideoYCbCrMatrix_ITU_R_709_2
        case .bt2020:
            return AVVideoYCbCrMatrix_ITU_R_2020
        }
    }

    /// Whether this color space is wide gamut
    var isWideGamut: Bool {
        switch self {
        case .displayP3, .bt2020: return true
        case .auto, .sRGB, .bt709: return false
        }
    }
}
