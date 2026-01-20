import Foundation
import CoreGraphics

/// Motion blur configuration
/// Parameters that adjust the blur when the camera zooms or pans
struct MotionBlurSettings: Codable, Equatable {

    // MARK: - Properties

    /// Whether motion blur is enabled
    var enabled: Bool = true

    /// Blur strength multiplier (0.0–1.0, default 0.2)
    /// A higher value results in stronger blur
    var intensity: CGFloat = 0.2

    /// Zoom change threshold — blur applies when the zoom delta exceeds this
    /// Lower values react more sensitively (per second)
    /// Example: 1.0 = blur when zoom changes by 1.0 or more per second
    var zoomThreshold: CGFloat = 1.0

    /// Pan change threshold (based on normalized coordinates)
    /// Lower values respond more sensitively (per second)
    /// Example: 0.25 = blur when moving more than 25% of the view per second
    var panThreshold: CGFloat = 0.25

    /// Maximum blur radius (pixels)
    /// Caps the blur intensity
    var maxRadius: CGFloat = 10.0

    // MARK: - Presets

    /// Default configuration (enabled)
    static let `default` = Self()

    /// Disabled configuration
    static let disabled = Self(enabled: false)

    /// Default configuration when enabled
    static let enabled = Self(
        enabled: true,
        intensity: 0.2,
        zoomThreshold: 1.0,
        panThreshold: 0.25,
        maxRadius: 10.0
    )

    /// Gentle settings (higher thresholds, lighter blur)
    static let subtle = Self(
        enabled: true,
        intensity: 0.15,
        zoomThreshold: 1.0,
        panThreshold: 0.3,
        maxRadius: 8.0
    )

    /// Strong settings (lower thresholds, heavier blur)
    static let strong = Self(
        enabled: true,
        intensity: 0.5,
        zoomThreshold: 0.5,
        panThreshold: 0.15,
        maxRadius: 20.0
    )
}
