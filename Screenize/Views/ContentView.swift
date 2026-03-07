import SwiftUI

// MARK: - Content View

struct ContentView: View {

    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var appState: AppState
    @AppStorage("hasCompletedPermissionSetup") private var hasCompletedSetup: Bool = false
    @State private var isCreatingProject: Bool = false
    @State private var showKeyboardShortcuts = false
    @State private var showErrorAlert = false
    @State private var errorAlertMessage = ""

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
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlertMessage)
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
            errorAlertMessage = "Failed to open video: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func openProject(url: URL) async {
        do {
            let result = try await projectManager.load(from: url)
            appState.currentProjectURL = result.packageURL
            appState.currentProject = result.project
        } catch {
            Log.project.error("Failed to load project: \(error)")
            errorAlertMessage = "Failed to open project: \(error.localizedDescription)"
            showErrorAlert = true
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
            errorAlertMessage = "Failed to create project: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}
