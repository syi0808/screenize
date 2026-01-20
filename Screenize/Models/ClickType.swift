import Foundation
import AppKit

// MARK: - Click Type

/// Mouse click types
enum ClickType: String, Codable, Sendable {
    case left
    case right

    /// Default color for each click type
    var color: NSColor {
        switch self {
        case .left: return .systemBlue
        case .right: return .systemOrange
        }
    }
}
