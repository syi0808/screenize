import Foundation
import ScreenCaptureKit
import CoreGraphics

enum CaptureTarget: Identifiable, Hashable {
    case display(SCDisplay)
    case window(SCWindow)
    case region(CGRect, SCDisplay)

    var id: String {
        switch self {
        case .display(let display):
            return "display-\(display.displayID)"
        case .window(let window):
            return "window-\(window.windowID)"
        case .region(let rect, let display):
            return "region-\(display.displayID)-\(rect.origin.x)-\(rect.origin.y)-\(rect.width)-\(rect.height)"
        }
    }

    var displayName: String {
        switch self {
        case .display(let display):
            return "Display \(display.displayID)"
        case .window(let window):
            return window.title ?? window.owningApplication?.applicationName ?? "Unknown Window"
        case .region(_, let display):
            return "Region on Display \(display.displayID)"
        }
    }

    var frame: CGRect {
        switch self {
        case .display(let display):
            return CGRect(x: 0, y: 0, width: display.width, height: display.height)
        case .window(let window):
            return window.frame
        case .region(let rect, _):
            return rect
        }
    }

    var width: Int {
        Int(frame.width)
    }

    var height: Int {
        Int(frame.height)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Source Type Helpers

    /// Indicates whether the capture target is a window
    /// Window captures add a background and use Screen Studio-style zoom
    var isWindow: Bool {
        switch self {
        case .window: return true
        default: return false
        }
    }

    /// Indicates whether the capture target is full-screen (display or region)
    /// Full-screen captures zoom while preserving aspect ratio without a background
    var isFullScreen: Bool {
        switch self {
        case .display, .region: return true
        case .window: return false
        }
    }
}
