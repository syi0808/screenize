import SwiftUI
import Sparkle
import UniformTypeIdentifiers

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        let ext = url.pathExtension.lowercased()
        if ext == ScreenizeProject.packageExtension {
            NotificationCenter.default.post(
                name: .openProjectFile,
                object: nil,
                userInfo: ["url": url]
            )
        } else {
            NotificationCenter.default.post(
                name: .openVideoFile,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }
}

/// Screenize app entry point
@main
struct ScreenizeApp: App {

    // MARK: - State

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var projectManager = ProjectManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var sparkleController = SparkleController()

    // MARK: - Initialization

    init() {
        // Screen recording permission is requested lazily when user starts recording
        // (via CaptureToolbarCoordinator → refreshAvailableSources).
        // Requesting here causes repeated dialogs because Xcode debug builds
        // change the code signature, invalidating previous TCC authorization.

        // Disable automatic window tabbing so Cmd+T is free for Duplicate
        NSWindow.allowsAutomaticWindowTabbing = false

        // Register a global hotkey (Cmd+Shift+2)
        GlobalHotkeyManager.shared.register {
            Task { @MainActor in
                await AppState.shared.toggleRecording()
            }
        }
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectManager)
                .environmentObject(appState)
        }
        .commands {
            // Add Check for Updates to the app menu
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(sparkleController: sparkleController)
            }

            CommandGroup(replacing: .undoRedo) {
                Button(L10n.string("app.menu.undo", defaultValue: "Undo")) {
                    NotificationCenter.default.post(name: .editorUndo, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appState.canUndo)

                Button(L10n.string("app.menu.redo", defaultValue: "Redo")) {
                    NotificationCenter.default.post(name: .editorRedo, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appState.canRedo)
            }

            CommandGroup(replacing: .pasteboard) {
                Button(L10n.string("app.menu.copy", defaultValue: "Copy")) {
                    if !NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) {
                        NotificationCenter.default.post(name: .editorCopy, object: nil)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)

                Button(L10n.string("app.menu.paste", defaultValue: "Paste")) {
                    if !NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) {
                        NotificationCenter.default.post(name: .editorPaste, object: nil)
                    }
                }
                .keyboardShortcut("v", modifiers: .command)

                Button(L10n.string("app.menu.cut", defaultValue: "Cut")) {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button(L10n.string("app.menu.select_all", defaultValue: "Select All")) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Divider()

                Button(L10n.string("app.menu.duplicate", defaultValue: "Duplicate")) {
                    NotificationCenter.default.post(name: .editorDuplicate, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button(
                    L10n.string(
                        "app.menu.advanced_generation_settings",
                        defaultValue: "Advanced Generation Settings..."
                    )
                ) {
                    GenerationSettingsWindowController.shared.showWindow()
                }
                .keyboardShortcut(",", modifiers: [.command, .option])
            }

            CommandGroup(replacing: .help) {
                Button(L10n.string("app.menu.keyboard_shortcuts", defaultValue: "Keyboard Shortcuts")) {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .newItem) {
                Button(L10n.string("app.menu.new_recording", defaultValue: "New Recording...")) {
                    Task { await appState.showCaptureToolbarFlow() }
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button(L10n.string("app.menu.open_video", defaultValue: "Open Video...")) {
                    openVideoFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(L10n.string("app.menu.open_project", defaultValue: "Open Project...")) {
                    openProjectFile()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button(
                    appState.isRecording
                        ? L10n.string("app.menu.stop_recording", defaultValue: "Stop Recording")
                        : L10n.string("app.menu.start_recording", defaultValue: "Start Recording")
                ) {
                    Task {
                        await appState.toggleRecording()
                    }
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                .disabled(!appState.isRecording && !appState.showCaptureToolbar)
            }
        }
    }

    // MARK: - File Opening

    private func openVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(
                name: .openVideoFile,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    private func openProjectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType("com.screenize.project")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(
                name: .openProjectFile,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }
}
