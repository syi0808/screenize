import Foundation

extension L10n {

    static var transformTrackName: String {
        string("track.name.transform", defaultValue: "Transform")
    }

    static var smartKeystrokeTrackName: String {
        string("track.name.keystroke_smart", defaultValue: "Keystroke (Smart V2)")
    }

    static var audioTrackNotYetSupported: String {
        string("track.error.audio_not_supported", defaultValue: "Audio track not yet supported")
    }

    static func renderSettingsCustomResolution(width: Int, height: Int) -> String {
        let template = string("export.settings.resolution.custom_value", defaultValue: "Custom (%@x%@)")
        return String(format: template, locale: AppLanguageManager.shared.formattingLocale, String(width), String(height))
    }

    static var renderSettingsOriginal: String {
        string("export.settings.common.original", defaultValue: "Original")
    }

    static var renderSettings4KUHD: String {
        string("export.settings.resolution.4k_uhd", defaultValue: "4K UHD (3840x2160)")
    }

    static var renderSettingsQHD: String {
        string("export.settings.resolution.qhd", defaultValue: "QHD (2560x1440)")
    }

    static var renderSettingsFullHD: String {
        string("export.settings.resolution.full_hd", defaultValue: "Full HD (1920x1080)")
    }

    static var renderSettingsHD: String {
        string("export.settings.resolution.hd", defaultValue: "HD (1280x720)")
    }

    static func renderSettingsFPS(_ fps: Int) -> String {
        let template = string("export.settings.frame_rate.value", defaultValue: "%@ fps")
        return String(format: template, locale: AppLanguageManager.shared.formattingLocale, String(fps))
    }

    static func pixels(_ value: Int) -> String {
        let template = string("common.unit.pixels", defaultValue: "%@px")
        return String(format: template, locale: AppLanguageManager.shared.formattingLocale, String(value))
    }

    static var exportFormatVideo: String {
        string("export.settings.format.video", defaultValue: "Video")
    }

    static var exportFormatGIF: String {
        string("export.settings.format.gif", defaultValue: "GIF")
    }

    static var exportQualityLow: String {
        string("export.settings.quality.low", defaultValue: "Low")
    }

    static var exportQualityMedium: String {
        string("export.settings.quality.medium", defaultValue: "Medium")
    }

    static var exportQualityHigh: String {
        string("export.settings.quality.high", defaultValue: "High")
    }

    static var codecH264: String {
        string("export.settings.codec.h264", defaultValue: "H.264")
    }

    static var codecHEVC: String {
        string("export.settings.codec.hevc", defaultValue: "H.265 (HEVC)")
    }

    static var codecProRes422: String {
        string("export.settings.codec.prores_422", defaultValue: "ProRes 422")
    }

    static var codecProRes4444: String {
        string("export.settings.codec.prores_4444", defaultValue: "ProRes 4444")
    }

    static var colorSpaceAutoSRGB: String {
        string("export.settings.color_space.auto_srgb", defaultValue: "Auto (sRGB)")
    }

    static var colorSpaceSRGB: String {
        string("export.settings.color_space.srgb", defaultValue: "sRGB")
    }

    static var colorSpaceDisplayP3: String {
        string("export.settings.color_space.display_p3", defaultValue: "Display P3")
    }

    static var colorSpaceBT709: String {
        string("export.settings.color_space.bt709", defaultValue: "BT.709")
    }

    static var colorSpaceBT2020: String {
        string("export.settings.color_space.bt2020", defaultValue: "BT.2020")
    }

    static var exportStatusIdle: String {
        string("export.progress.idle", defaultValue: "Idle")
    }

    static var exportStatusPreparing: String {
        string("export.progress.preparing", defaultValue: "Preparing...")
    }

    static var exportStatusLoadingVideo: String {
        string("export.progress.loading_video", defaultValue: "Loading video...")
    }

    static var exportStatusLoadingMouseData: String {
        string("export.progress.loading_mouse_data", defaultValue: "Loading mouse data...")
    }

    static func exportStatusProcessing(frame: Int, total: Int) -> String {
        format("export.progress.processing", defaultValue: "Processing frames... (%d/%d)", frame, total)
    }

    static var exportStatusEncoding: String {
        string("export.progress.encoding", defaultValue: "Encoding...")
    }

    static var exportStatusFinalizing: String {
        string("export.progress.finalizing", defaultValue: "Finalizing...")
    }

    static var exportStatusCompleted: String {
        string("export.progress.completed", defaultValue: "Completed")
    }

    static func exportStatusFailed(message: String) -> String {
        format("export.progress.failed", defaultValue: "Failed: %@", message)
    }

    static var exportStatusCancelled: String {
        string("export.progress.cancelled", defaultValue: "Cancelled")
    }

    static func analysisInvalidVideo(message: String) -> String {
        format("analysis.error.invalid_video", defaultValue: "Invalid video: %@", message)
    }

    static var analysisFeaturePrintFailed: String {
        string("analysis.error.feature_print_failed", defaultValue: "Feature print calculation failed")
    }

    static func analysisFilterNotAvailable(name: String) -> String {
        format("analysis.error.filter_not_available", defaultValue: "Core Image filter not available: %@", name)
    }

    static var analysisFilterFailed: String {
        string("analysis.error.filter_failed", defaultValue: "Core Image filter execution failed")
    }

    static var analysisOpticalFlowFailed: String {
        string("analysis.error.optical_flow_failed", defaultValue: "Optical flow calculation failed")
    }

    static var keyReturn: String { string("keystroke.key.return", defaultValue: "Return") }
    static var keyTab: String { string("keystroke.key.tab", defaultValue: "Tab") }
    static var keySpace: String { string("keystroke.key.space", defaultValue: "Space") }
    static var keyDelete: String { string("keystroke.key.delete", defaultValue: "Delete") }
    static var keyEscape: String { string("keystroke.key.escape", defaultValue: "Escape") }
    static var keyClear: String { string("keystroke.key.clear", defaultValue: "Clear") }
    static var keyEnter: String { string("keystroke.key.enter", defaultValue: "Enter") }
    static var keyHome: String { string("keystroke.key.home", defaultValue: "Home") }
    static var keyEnd: String { string("keystroke.key.end", defaultValue: "End") }
    static var keyPageUp: String { string("keystroke.key.page_up", defaultValue: "Page Up") }
    static var keyPageDown: String { string("keystroke.key.page_down", defaultValue: "Page Down") }
}
