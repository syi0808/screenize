import SwiftUI

// MARK: - Spacing

/// 8-point grid spacing scale used throughout the app.
/// Provides consistent rhythm and visual alignment.
enum Spacing {
    /// 2pt — Tight inline elements (e.g., grip lines in trim handles)
    static let xxs: CGFloat = 2

    /// 4pt — Icon-to-label gaps, minimal separation
    static let xs: CGFloat = 4

    /// 8pt — Within-component spacing (e.g., track header elements)
    static let sm: CGFloat = 8

    /// 12pt — Standard inter-element spacing
    static let md: CGFloat = 12

    /// 16pt — Section padding, toolbar horizontal padding
    static let lg: CGFloat = 16

    /// 20pt — Major section gaps
    static let xl: CGFloat = 20

    /// 24pt — Between action cards, large section separation
    static let xxl: CGFloat = 24

    /// 32pt — Screen-level vertical spacing
    static let xxxl: CGFloat = 32

    /// 40pt — Screen-level horizontal padding (e.g., permission wizard)
    static let xxxxl: CGFloat = 40
}
