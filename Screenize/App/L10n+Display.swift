import Foundation

extension L10n {

    static let transformTrackName = string(
        "track.name.transform",
        defaultValue: "Transform"
    )

    static let smartKeystrokeTrackName = string(
        "track.name.keystroke_smart",
        defaultValue: "Keystroke (Smart V2)"
    )

    static let audioTrackNotYetSupported = string(
        "track.error.audio_not_supported",
        defaultValue: "Audio track not yet supported"
    )

    static func renderSettingsCustomResolution(width: Int, height: Int) -> String {
        let template = string("export.settings.resolution.custom_value", defaultValue: "Custom (%@x%@)")
        return String(format: template, locale: Locale.current, String(width), String(height))
    }

    static let renderSettingsOriginal = string(
        "export.settings.common.original",
        defaultValue: "Original"
    )

    static let renderSettings4KUHD = string(
        "export.settings.resolution.4k_uhd",
        defaultValue: "4K UHD (3840x2160)"
    )

    static let renderSettingsQHD = string(
        "export.settings.resolution.qhd",
        defaultValue: "QHD (2560x1440)"
    )

    static let renderSettingsFullHD = string(
        "export.settings.resolution.full_hd",
        defaultValue: "Full HD (1920x1080)"
    )

    static let renderSettingsHD = string(
        "export.settings.resolution.hd",
        defaultValue: "HD (1280x720)"
    )

    static func renderSettingsFPS(_ fps: Int) -> String {
        let template = string("export.settings.frame_rate.value", defaultValue: "%@ fps")
        return String(format: template, locale: Locale.current, String(fps))
    }

    static func pixels(_ value: Int) -> String {
        let template = string("common.unit.pixels", defaultValue: "%@px")
        return String(format: template, locale: Locale.current, String(value))
    }

    static let exportFormatVideo = string(
        "export.settings.format.video",
        defaultValue: "Video"
    )

    static let exportFormatGIF = string(
        "export.settings.format.gif",
        defaultValue: "GIF"
    )

    static let exportQualityLow = string(
        "export.settings.quality.low",
        defaultValue: "Low"
    )

    static let exportQualityMedium = string(
        "export.settings.quality.medium",
        defaultValue: "Medium"
    )

    static let exportQualityHigh = string(
        "export.settings.quality.high",
        defaultValue: "High"
    )

    static let codecH264 = string(
        "export.settings.codec.h264",
        defaultValue: "H.264"
    )

    static let codecHEVC = string(
        "export.settings.codec.hevc",
        defaultValue: "H.265 (HEVC)"
    )

    static let codecProRes422 = string(
        "export.settings.codec.prores_422",
        defaultValue: "ProRes 422"
    )

    static let codecProRes4444 = string(
        "export.settings.codec.prores_4444",
        defaultValue: "ProRes 4444"
    )

    static let colorSpaceAutoSRGB = string(
        "export.settings.color_space.auto_srgb",
        defaultValue: "Auto (sRGB)"
    )

    static let colorSpaceSRGB = string(
        "export.settings.color_space.srgb",
        defaultValue: "sRGB"
    )

    static let colorSpaceDisplayP3 = string(
        "export.settings.color_space.display_p3",
        defaultValue: "Display P3"
    )

    static let colorSpaceBT709 = string(
        "export.settings.color_space.bt709",
        defaultValue: "BT.709"
    )

    static let colorSpaceBT2020 = string(
        "export.settings.color_space.bt2020",
        defaultValue: "BT.2020"
    )

    static let exportStatusIdle = string(
        "export.progress.idle",
        defaultValue: "Idle"
    )

    static let exportStatusPreparing = string(
        "export.progress.preparing",
        defaultValue: "Preparing..."
    )

    static let exportStatusLoadingVideo = string(
        "export.progress.loading_video",
        defaultValue: "Loading video..."
    )

    static let exportStatusLoadingMouseData = string(
        "export.progress.loading_mouse_data",
        defaultValue: "Loading mouse data..."
    )

    static func exportStatusProcessing(frame: Int, total: Int) -> String {
        format("export.progress.processing", defaultValue: "Processing frames... (%d/%d)", frame, total)
    }

    static let exportStatusEncoding = string(
        "export.progress.encoding",
        defaultValue: "Encoding..."
    )

    static let exportStatusFinalizing = string(
        "export.progress.finalizing",
        defaultValue: "Finalizing..."
    )

    static let exportStatusCompleted = string(
        "export.progress.completed",
        defaultValue: "Completed"
    )

    static func exportStatusFailed(message: String) -> String {
        format("export.progress.failed", defaultValue: "Failed: %@", message)
    }

    static let exportStatusCancelled = string(
        "export.progress.cancelled",
        defaultValue: "Cancelled"
    )

    static func analysisInvalidVideo(message: String) -> String {
        format("analysis.error.invalid_video", defaultValue: "Invalid video: %@", message)
    }

    static let analysisFeaturePrintFailed = string(
        "analysis.error.feature_print_failed",
        defaultValue: "Feature print calculation failed"
    )

    static func analysisFilterNotAvailable(name: String) -> String {
        format("analysis.error.filter_not_available", defaultValue: "Core Image filter not available: %@", name)
    }

    static let analysisFilterFailed = string(
        "analysis.error.filter_failed",
        defaultValue: "Core Image filter execution failed"
    )

    static let analysisOpticalFlowFailed = string(
        "analysis.error.optical_flow_failed",
        defaultValue: "Optical flow calculation failed"
    )

    static let keyReturn = string("keystroke.key.return", defaultValue: "Return")
    static let keyTab = string("keystroke.key.tab", defaultValue: "Tab")
    static let keySpace = string("keystroke.key.space", defaultValue: "Space")
    static let keyDelete = string("keystroke.key.delete", defaultValue: "Delete")
    static let keyEscape = string("keystroke.key.escape", defaultValue: "Escape")
    static let keyClear = string("keystroke.key.clear", defaultValue: "Clear")
    static let keyEnter = string("keystroke.key.enter", defaultValue: "Enter")
    static let keyHome = string("keystroke.key.home", defaultValue: "Home")
    static let keyEnd = string("keystroke.key.end", defaultValue: "End")
    static let keyPageUp = string("keystroke.key.page_up", defaultValue: "Page Up")
    static let keyPageDown = string("keystroke.key.page_down", defaultValue: "Page Down")
}
