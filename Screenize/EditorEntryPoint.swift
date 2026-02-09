import SwiftUI

/// Editor entry point
/// Interface for opening the editor from the main app
@MainActor
struct EditorEntryPoint {

    // MARK: - Singleton

    static let shared = Self()

    private init() {}

    // MARK: - Open Editor

    /// Open the editor for a project
    /// - Parameter project: The project to open
    /// - Returns: The editor view
    func editorView(for project: ScreenizeProject) -> some View {
        EditorMainView(project: project)
    }

    /// Open the editor from a video file
    /// - Parameters:
    ///   - videoURL: Video file URL
    ///   - mouseDataURL: Mouse data URL (optional)
    /// - Returns: A view that hosts the editor
    func editorView(videoURL: URL, mouseDataURL: URL? = nil) -> some View {
        EditorLoaderView(videoURL: videoURL, mouseDataURL: mouseDataURL)
    }

    /// Open the editor for a recording result
    /// - Parameters:
    ///   - videoURL: Recorded video URL
    ///   - mouseDataURL: Mouse data URL
    ///   - captureMeta: Capture metadata
    /// - Returns: A view that hosts the editor
    func editorView(
        recordingResult videoURL: URL,
        mouseDataURL: URL,
        captureMeta: CaptureMeta
    ) -> some View {
        EditorLoaderView(
            videoURL: videoURL,
            mouseDataURL: mouseDataURL,
            captureMeta: captureMeta
        )
    }

    // MARK: - Open Window

    /// Open the editor in a new window
    /// - Parameter project: The project to open
    func openEditorWindow(for project: ScreenizeProject) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Screenize Editor - \(project.media.videoURL.lastPathComponent)"
        window.contentView = NSHostingView(rootView: EditorMainView(project: project))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Open the editor in a new window from a video file
    /// - Parameter videoURL: Video file URL
    func openEditorWindow(videoURL: URL, mouseDataURL: URL? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Screenize Editor"
        window.contentView = NSHostingView(
            rootView: EditorLoaderView(videoURL: videoURL, mouseDataURL: mouseDataURL)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Editor Loader View

/// View that loads a project from a video file and opens the editor
struct EditorLoaderView: View {

    // MARK: - Properties

    let videoURL: URL
    let mouseDataURL: URL?
    let captureMeta: CaptureMeta?

    // MARK: - State

    @State private var project: ScreenizeProject?
    @State private var isLoading = true
    @State private var errorMessage: String?

    // MARK: - Initialization

    init(videoURL: URL, mouseDataURL: URL? = nil, captureMeta: CaptureMeta? = nil) {
        self.videoURL = videoURL
        self.mouseDataURL = mouseDataURL
        self.captureMeta = captureMeta
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let project = project {
                EditorMainView(project: project)
            } else {
                errorView
            }
        }
        .task {
            await loadProject()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading project...")
                .font(.headline)

            Text(videoURL.lastPathComponent)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Failed to Load Project")
                .font(.headline)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Retry") {
                Task {
                    await loadProject()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load Project

    private func loadProject() async {
        isLoading = true
        errorMessage = nil

        do {
            // Check for an existing project file
            if let existingProjectURL = ProjectManager.shared.findExistingProject(for: videoURL) {
                let result = try await ProjectManager.shared.load(from: existingProjectURL)
                project = result.project
            } else {
                // Create a .screenize package and project
                let videoName = videoURL.deletingPathExtension().lastPathComponent
                let parentDirectory = videoURL.deletingLastPathComponent()
                let packageInfo = try ProjectManager.shared.createPackage(
                    name: videoName,
                    videoURL: videoURL,
                    mouseDataURL: mouseDataURL,
                    in: parentDirectory
                )

                if let captureMeta {
                    project = try await ProjectCreator.createFromRecording(
                        packageInfo: packageInfo,
                        captureMeta: captureMeta
                    )
                } else {
                    project = try await ProjectCreator.createFromVideo(
                        packageInfo: packageInfo
                    )
                }

                // Save the project into the package
                if let project {
                    try PackageManager.shared.save(project, to: packageInfo.packageURL)
                }
            }

            isLoading = false

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Open Editor Button

/// Button to open the editor from the main app
struct OpenEditorButton: View {

    let videoURL: URL
    let mouseDataURL: URL?
    let captureMeta: CaptureMeta?

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Edit in Timeline", systemImage: "timeline.selection")
        }
        .sheet(isPresented: $isPresented) {
            EditorLoaderView(
                videoURL: videoURL,
                mouseDataURL: mouseDataURL,
                captureMeta: captureMeta
            )
            .frame(minWidth: 1000, minHeight: 600)
        }
    }

    init(videoURL: URL, mouseDataURL: URL? = nil, captureMeta: CaptureMeta? = nil) {
        self.videoURL = videoURL
        self.mouseDataURL = mouseDataURL
        self.captureMeta = captureMeta
    }
}

// MARK: - Recent Projects View

/// Recent projects list view
struct RecentProjectsView: View {

    @ObservedObject var projectManager = ProjectManager.shared

    var onSelect: ((URL) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Projects")
                    .font(.headline)

                Spacer()

                if !projectManager.recentProjects.isEmpty {
                    Button("Clear") {
                        projectManager.clearRecentProjects()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
            }

            if projectManager.recentProjects.isEmpty {
                emptyState
            } else {
                projectList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.title)
                .foregroundColor(.secondary.opacity(0.5))

            Text("No recent projects")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var projectList: some View {
        VStack(spacing: 4) {
            ForEach(projectManager.recentProjects) { info in
                recentProjectRow(info)
            }
        }
    }

    private func recentProjectRow(_ info: RecentProjectInfo) -> some View {
        Button {
            Task {
                if let result = await projectManager.tryLoad(from: info.packageURL) {
                    onSelect?(result.packageURL)
                }
            }
        } label: {
            HStack {
                Image(systemName: "film")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .lineLimit(1)

                    HStack {
                        Text(info.formattedDuration)
                        Text("•")
                        Text(info.formattedDate)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from Recent") {
                projectManager.removeFromRecent(info.id)
            }

            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([info.packageURL])
            }
        }
    }
}

// MARK: - Preview

#Preview("Editor Loader") {
    EditorLoaderView(
        videoURL: URL(fileURLWithPath: "/test.mp4")
    )
    .frame(width: 1200, height: 800)
}

#Preview("Recent Projects") {
    RecentProjectsView { url in
        print("Selected: \(url)")
    }
    .frame(width: 300)
    .padding()
}
