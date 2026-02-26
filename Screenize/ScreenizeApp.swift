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

// MARK: - Content View

struct ContentView: View {

    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var appState: AppState
    @AppStorage("hasCompletedPermissionSetup") private var hasCompletedSetup: Bool = false
    @State private var isCreatingProject: Bool = false
    @State private var showKeyboardShortcuts = false

    /// Determine current shortcut context based on active screen
    private var currentShortcutContext: ShortcutContext {
        if appState.currentProject != nil {
            return .editor
        } else {
            return .welcome
        }
    }

    var body: some View {
        Group {
            if !hasCompletedSetup {
                PermissionSetupWizardView(onComplete: {
                    hasCompletedSetup = true
                })
            } else if let project = appState.currentProject {
                // Show the editor when a project exists
                EditorMainView(project: project, projectURL: appState.currentProjectURL)
                    .id(project.id) // Force view rebuild when the project changes
            } else if appState.showEditor || isCreatingProject {
                // Display loader while creating project after recording
                VStack {
                    ProgressView()
                    Text("Creating project...")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, Spacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    if appState.showEditor && !isCreatingProject {
                        appState.showEditor = false
                        isCreatingProject = true
                        Task {
                            await createProjectFromRecording()
                            isCreatingProject = false
                        }
                    }
                }
            } else {
                // Initial state → welcome view
                MainWelcomeView(
                    onStartRecording: {
                        Task { await appState.showCaptureToolbarFlow() }
                    },
                    onOpenVideo: { url in
                        Task {
                            await openVideo(url: url)
                        }
                    },
                    onOpenProject: { url in
                        Task {
                            await openProject(url: url)
                        }
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVideoFile)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                Task {
                    await openVideo(url: url)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProjectFile)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                Task {
                    await openProject(url: url)
                }
            }
        }
        .onChange(of: appState.showEditor) { showEditor in
            if showEditor && !isCreatingProject {
                appState.showEditor = false
                isCreatingProject = true
                Task {
                    await createProjectFromRecording()
                    isCreatingProject = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
            showKeyboardShortcuts = true
        }
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutHelpView(context: currentShortcutContext)
        }
    }

    private func openVideo(url: URL) async {
        do {
            // Create .screenize package from imported video
            let videoName = url.deletingPathExtension().lastPathComponent
            let parentDirectory = url.deletingLastPathComponent()
            let packageInfo = try PackageManager.shared.createPackageFromVideo(
                name: videoName,
                videoURL: url,
                in: parentDirectory
            )

            // Create a project from the package
            let project = try await ProjectCreator.createFromVideo(packageInfo: packageInfo)

            // Save the project into the package
            let packageURL = try await projectManager.save(project, to: packageInfo.packageURL)

            appState.currentProjectURL = packageURL
            appState.currentProject = project
        } catch {
            Log.project.error("Failed to create project: \(error)")
        }
    }

    private func openProject(url: URL) async {
        do {
            let result = try await projectManager.load(from: url)
            appState.currentProjectURL = result.packageURL
            appState.currentProject = result.project
        } catch {
            Log.project.error("Failed to load project: \(error)")
        }
    }

    private func createProjectFromRecording() async {
        guard let videoURL = appState.lastRecordingURL else {
            return
        }

        do {
            let videoName = videoURL.deletingPathExtension().lastPathComponent
            let parentDirectory = videoURL.deletingLastPathComponent()
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

            // Create project using AppState's capture metadata (computes captureMeta from selectedTarget)
            // First get a temporary PackageInfo to create the project
            guard let captureMeta = await appState.buildCaptureMeta(videoURL: videoURL) else {
                return
            }

            let packageInfo = try PackageManager.shared.createPackageV4(
                name: videoName,
                videoURL: videoURL,
                mouseRecording: appState.lastMouseRecording,
                captureMeta: captureMeta,
                micAudioURL: appState.lastMicAudioURL,
                systemAudioURL: appState.lastSystemAudioURL,
                in: parentDirectory,
                recordingStartDate: appState.lastRecordingStartDate ?? Date(),
                processTimeStartMs: appState.lastProcessTimeStartMs,
                appVersion: appVersion
            )

            appState.lastMouseRecording = nil
            appState.lastMicAudioURL = nil
            appState.lastSystemAudioURL = nil

            guard let project = await appState.createProject(packageInfo: packageInfo) else {
                return
            }

            let packageURL = try await projectManager.save(project, to: packageInfo.packageURL)

            appState.currentProjectURL = packageURL
            appState.currentProject = project
        } catch {
            Log.project.error("Failed to create project from recording: \(error)")
        }
    }
}

// MARK: - Main Welcome View (with Recording)

struct MainWelcomeView: View {

    var onStartRecording: (() -> Void)?
    var onOpenVideo: ((URL) -> Void)?
    var onOpenProject: ((URL) -> Void)?

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

            // Logo
            VStack(spacing: Spacing.lg) {
                Image(systemName: "film.stack")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("Screenize")
                    .font(Typography.displayLarge)

                Text("Screen Recording & Timeline Editing")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Primary action buttons
            HStack(spacing: Spacing.xxl) {
                // Record button
                ActionCard(
                    icon: "record.circle",
                    title: "Record",
                    description: "Record screen or window",
                    color: .red
                ) {
                    onStartRecording?()
                }

                // Open video button
                ActionCard(
                    icon: "film",
                    title: "Open Video",
                    description: "Edit existing video",
                    color: .blue
                ) {
                    openVideoPanel()
                }

                // Open project button
                ActionCard(
                    icon: "folder",
                    title: "Open Project",
                    description: "Continue editing",
                    color: .orange
                ) {
                    openProjectPanel()
                }
            }

            // Drop area
            dropZone

            // Recent projects
            RecentProjectsView { url in
                onOpenProject?(url)
            }
            .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignColors.windowBackground)
        .overlay(alignment: .topTrailing) {
            ShortcutHelpButton(context: .welcome)
                .padding(Spacing.lg)
        }
    }

    private var dropZone: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundColor(isDragging ? .accentColor : .secondary)

            Text("Drop video or project here")
                .font(Typography.heading)
                .foregroundColor(isDragging ? .accentColor : .secondary)

            Text(".mp4, .mov, .m4v, .screenize")
                .font(Typography.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 300, height: 100)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xxl)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.secondary.opacity(DesignOpacity.medium),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xxl)
                .fill(isDragging ? Color.accentColor.opacity(DesignOpacity.subtle) : Color.clear)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .accessibilityLabel("Drop zone")
        .accessibilityHint("Drop a video or project file here to open it")
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            let ext = url.pathExtension.lowercased()
            let videoExtensions = ["mp4", "mov", "m4v", "mpeg4"]

            if ext == ScreenizeProject.packageExtension {
                DispatchQueue.main.async {
                    onOpenProject?(url)
                }
            } else if videoExtensions.contains(ext) {
                DispatchQueue.main.async {
                    onOpenVideo?(url)
                }
            }
        }

        return true
    }

    private func openVideoPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            onOpenVideo?(url)
        }
    }

    private func openProjectPanel() {
        let panel = NSOpenPanel()
        let contentTypes = [UTType(filenameExtension: ScreenizeProject.packageExtension)!]
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            onOpenProject?(url)
        }
    }
}

// MARK: - Action Card

struct ActionCard: View {

    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)

                Text(title)
                    .font(Typography.heading)

                Text(description)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 140, height: 120)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xxl)
                    .fill(DesignColors.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xxl)
                    .stroke(isHovering ? color.opacity(DesignOpacity.prominent) : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withMotionSafeAnimation(AnimationTokens.quick) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(description)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openVideoFile = Notification.Name("openVideoFile")
    static let openProjectFile = Notification.Name("openProjectFile")
}
