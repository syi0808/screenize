import SwiftUI
import Sparkle

/// Screenize app entry point
@main
struct ScreenizeApp: App {

    // MARK: - State

    @StateObject private var projectManager = ProjectManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var sparkleController = SparkleController()

    // MARK: - Initialization

    init() {
        // Request screen recording access at launch
        _ = CGRequestScreenCaptureAccess()

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
        panel.allowedContentTypes = [.init(filenameExtension: ProjectManager.projectExtension)!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

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
    @State private var isCreatingProject: Bool = false

    var body: some View {
        Group {
            if let project = appState.currentProject {
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
    }

    private func openVideo(url: URL) async {
        do {
            // Create the project folder and move files
            let result = try projectManager.createProjectFolder(for: url)

            // Create a project from the moved files
            let project = try await ProjectCreator.createFromVideo(
                videoURL: result.videoURL,
                mouseDataURL: result.mouseDataURL
            )

            // Save the project
            let projectURL = projectManager.projectFileURL(in: result.projectFolderURL, name: project.name)
            let savedURL = try await projectManager.save(project, to: projectURL)

            appState.currentProjectURL = savedURL
            appState.currentProject = project
        } catch {
            print("Failed to create project: \(error)")
        }
    }

    private func openProject(url: URL) async {
        do {
            let project = try await projectManager.load(from: url)
            appState.currentProjectURL = url
            appState.currentProject = project
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
            // Create the project folder and move files
            let result = try projectManager.createProjectFolder(for: videoURL, mouseDataURL: mouseDataURL)

            // Create a project from the moved files
            guard let project = await appState.createProject(videoURL: result.videoURL, mouseDataURL: result.mouseDataURL) else {
                return
            }

            // Save the project
            let projectURL = projectManager.projectFileURL(in: result.projectFolderURL, name: project.name)
            let savedURL = try await projectManager.save(project, to: projectURL)

            appState.currentProjectURL = savedURL
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
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundColor(isDragging ? .accentColor : .secondary)

            Text("Drop video file here")
                .font(.headline)
                .foregroundColor(isDragging ? .accentColor : .secondary)

            Text(".mp4, .mov, .m4v")
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

            let validExtensions = ["mp4", "mov", "m4v", "mpeg4"]
            if validExtensions.contains(url.pathExtension.lowercased()) {
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
        panel.allowedContentTypes = [.init(filenameExtension: ProjectManager.projectExtension)!]
        panel.allowsMultipleSelection = false

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
