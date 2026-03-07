import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Design Colors

/// Centralized color namespace for the app.
/// Replaces scattered `Color(nsColor:)` calls and inline color literals.
enum DesignColors {

    // MARK: Surfaces

    /// Main window background
    static let windowBackground = Color(nsColor: .windowBackgroundColor)

    /// Control/panel background (sidebars, headers, inspector)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)

    /// Overlay base color (for dimming layers)
    static let overlay = Color.black

    // MARK: Track Colors

    /// Transform/Camera track color
    static let trackTransform = Color.blue

    /// Cursor track color
    static let trackCursor = Color.orange

    /// Keystroke track color
    static let trackKeystroke = Color.cyan

    /// Audio track color
    static let trackAudio = Color.green

    /// Returns the color for a given track type
    static func trackColor(for type: TrackType) -> Color {
        switch type {
        case .transform: return trackTransform
        case .cursor: return trackCursor
        case .keystroke: return trackKeystroke
        case .audio: return trackAudio
        }
    }

    // MARK: Semantic Colors

    /// Destructive actions (delete, stop recording)
    static let destructive = Color.red

    /// Recording state indicator
    static let recording = Color.red

    /// Warning states (trim handles, caution)
    static let warning = Color.yellow

    /// Success states (generation complete)
    static let success = Color.green

    /// Primary accent color
    static let accent = Color.accentColor

    // MARK: Inspector Section Icons

    /// Cursor settings section icon color
    static let sectionCursor = Color.orange

    /// Background settings section icon color
    static let sectionBackground = Color.purple
}

// MARK: - Color+Hex

extension Color {
    /// Initialize a Color from a hex string (e.g., "#FF0000" or "FF0000")
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    /// Convert a Color to its hex string representation
    var hexString: String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
