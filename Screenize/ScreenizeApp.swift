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
        // Only request screen recording at launch if permission setup is already completed
        if UserDefaults.standard.bool(forKey: "hasCompletedPermissionSetup") {
            _ = CGRequestScreenCaptureAccess()
        }

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
                Button("Undo") {
                    NotificationCenter.default.post(name: .editorUndo, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appState.canUndo)

                Button("Redo") {
                    NotificationCenter.default.post(name: .editorRedo, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appState.canRedo)
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    if !NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) {
                        NotificationCenter.default.post(name: .editorCopy, object: nil)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    if !NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) {
                        NotificationCenter.default.post(name: .editorPaste, object: nil)
                    }
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Divider()

                Button("Duplicate") {
                    NotificationCenter.default.post(name: .editorDuplicate, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .newItem) {
                Button("New Recording...") {
                    Task { await appState.showCaptureToolbarFlow() }
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Open Video...") {
                    openVideoFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Project...") {
                    openProjectFile()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
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
        let contentTypes = [UTType(filenameExtension: ScreenizeProject.packageExtension)!]
        panel.allowedContentTypes = contentTypes
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
