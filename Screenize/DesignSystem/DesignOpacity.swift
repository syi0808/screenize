import SwiftUI

// MARK: - Design Opacity

/// Semantic opacity values for consistent layering and depth.
/// Replaces scattered hardcoded opacity values throughout the codebase.
enum DesignOpacity {
    /// 0.1 — Tinted backgrounds, very subtle overlays
    static let subtle: Double = 0.1

    /// 0.15 — Slightly visible borders, light tints
    static let faint: Double = 0.15

    /// 0.2 — Borders, grid lines, light backgrounds
    static let light: Double = 0.2

    /// 0.3 — Handles, dividers, dimmed content
    static let medium: Double = 0.3

    /// 0.5 — Trimmed segment overlay, prominent dimming
    static let prominent: Double = 0.5

    /// 0.6 — Unselected segment fill
    static let muted: Double = 0.6

    /// 0.7 — Overlay text backgrounds, strong dimming
    static let strong: Double = 0.7

    /// 0.8 — Trim handle default, near-opaque
    static let heavy: Double = 0.8

    /// 0.85 — Banners, floating panel backgrounds
    static let intense: Double = 0.85

    /// 0.9 — Selected segment fill, near fully opaque
    static let opaque: Double = 0.9
}
