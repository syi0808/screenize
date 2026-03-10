import SwiftUI
import AppKit

/// Manages the singleton Advanced Generation Settings window.
@MainActor
final class GenerationSettingsWindowController {

    static let shared = GenerationSettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = GenerationSettingsView()
            .environmentObject(GenerationSettingsManager.shared)

        let hostingController = NSHostingController(rootView: settingsView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Advanced Generation Settings"
        newWindow.styleMask = [.titled, .closable, .resizable]
        newWindow.setContentSize(NSSize(width: 520, height: 700))
        newWindow.minSize = NSSize(width: 420, height: 400)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
