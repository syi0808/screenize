import SwiftUI
import Sparkle
import UniformTypeIdentifiers

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        let ext = url.pathExtension.lowercased()
        if ext == ScreenizeProject.packageExtension
            || ext == ScreenizeProject.legacyFileExtension {
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

            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .newItem) {
                Button("New Recording...") {
                    appState.showSourcePicker = true
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
                .disabled(appState.selectedTarget == nil && !appState.isRecording && !appState.isCountingDown)
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
        var contentTypes = [UTType(filenameExtension: ScreenizeProject.packageExtension)!]
        // MARK: - Legacy (remove in next minor version)
        if let legacyType = UTType(filenameExtension: ScreenizeProject.legacyFileExtension) {
            contentTypes.append(legacyType)
        }
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
        } else if appState.isRecording || appState.selectedTarget != nil || appState.showSourcePicker {
            return .recording
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
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
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
            } else if appState.isRecording || appState.selectedTarget != nil || appState.showSourcePicker {
                // Recording in progress or source selected → show recording view
                RecordingView(appState: appState)
            } else {
                // Initial state → welcome view
                MainWelcomeView(
                    onStartRecording: {
                        appState.showSourcePicker = true
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
            // Create .screenize package and move files
            let videoName = url.deletingPathExtension().lastPathComponent
            let parentDirectory = url.deletingLastPathComponent()
            let packageInfo = try projectManager.createPackage(
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
            print("Failed to create project: \(error)")
        }
    }

    private func openProject(url: URL) async {
        do {
            let result = try await projectManager.load(from: url)
            appState.currentProjectURL = result.packageURL
            appState.currentProject = result.project
        } catch {
            print("Failed to load project: \(error)")
        }
    }

    private func createProjectFromRecording() async {
        guard let videoURL = appState.lastRecordingURL,
              let mouseDataURL = appState.lastMouseDataURL else {
            return
        }

        do {
            // Create .screenize package and move files
            let videoName = videoURL.deletingPathExtension().lastPathComponent
            let parentDirectory = videoURL.deletingLastPathComponent()
            let packageInfo = try projectManager.createPackage(
                name: videoName,
                videoURL: videoURL,
                mouseDataURL: mouseDataURL,
                in: parentDirectory
            )

            // Create a project using AppState's capture metadata
            guard let project = await appState.createProject(packageInfo: packageInfo) else {
                return
            }

            // Save the project into the package
            let packageURL = try await projectManager.save(project, to: packageInfo.packageURL)

            appState.currentProjectURL = packageURL
            appState.currentProject = project
        } catch {
            print("Failed to create project from recording: \(error)")
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
        VStack(spacing: 32) {
            Spacer()

            // Logo
            VStack(spacing: 16) {
                Image(systemName: "film.stack")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("Screenize")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Screen Recording & Timeline Editing")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Primary action buttons
            HStack(spacing: 24) {
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
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topTrailing) {
            ShortcutHelpButton(context: .welcome)
                .padding()
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundColor(isDragging ? .accentColor : .secondary)

            Text("Drop video or project here")
                .font(.headline)
                .foregroundColor(isDragging ? .accentColor : .secondary)

            Text(".mp4, .mov, .m4v, .screenize")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 300, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
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
            // MARK: - Legacy (remove in next minor version)
            } else if ext == ScreenizeProject.legacyFileExtension {
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
        var contentTypes = [UTType(filenameExtension: ScreenizeProject.packageExtension)!]
        // MARK: - Legacy (remove in next minor version)
        if let legacyType = UTType(filenameExtension: ScreenizeProject.legacyFileExtension) {
            contentTypes.append(legacyType)
        }
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
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)

                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 140, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering ? color.opacity(0.5) : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openVideoFile = Notification.Name("openVideoFile")
    static let openProjectFile = Notification.Name("openProjectFile")
}
