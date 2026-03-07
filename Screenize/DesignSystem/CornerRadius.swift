import SwiftUI

// MARK: - Corner Radius

/// Semantic corner radius scale for consistent rounding across the app.
enum CornerRadius {
    /// 2pt — Progress bars, inline indicators, playhead
    static let xs: CGFloat = 2

    /// 4pt — Timeline segments, small badges
    static let sm: CGFloat = 4

    /// 6pt — Preset chips, status badges
    static let md: CGFloat = 6

    /// 8pt — Cards, panels, preview corners, recording overlay
    static let lg: CGFloat = 8

    /// 10pt — Floating panels, recording control bar
    static let xl: CGFloat = 10

    /// 12pt — Drop zones, permission list, large containers
    static let xxl: CGFloat = 12
}
