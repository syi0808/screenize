import SwiftUI
import AppKit
import Combine

/// Manages the singleton Advanced Generation Settings window.
@MainActor
final class GenerationSettingsWindowController {

    static let shared = GenerationSettingsWindowController()

    private let languageManager = AppLanguageManager.shared
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        languageManager.$refreshID
            .sink { [weak self] _ in
                self?.updateWindowTitle()
            }
            .store(in: &cancellables)
    }

    func showWindow() {
        if let existing = window {
            updateWindowTitle()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = LocalizedRootView(languageManager: languageManager) {
            GenerationSettingsView()
                .environmentObject(GenerationSettingsManager.shared)
        }

        let hostingController = NSHostingController(rootView: settingsView)
        let newWindow = NSWindow(contentViewController: hostingController)
        self.window = newWindow
        updateWindowTitle()
        newWindow.styleMask = [.titled, .closable, .resizable]
        newWindow.setContentSize(NSSize(width: 520, height: 700))
        newWindow.minSize = NSSize(width: 420, height: 400)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateWindowTitle() {
        window?.title = L10n.string(
            "generation_settings.window.title",
            defaultValue: "Advanced Generation Settings"
        )
    }
}
