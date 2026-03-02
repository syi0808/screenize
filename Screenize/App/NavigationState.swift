import Foundation

/// UI navigation, project lifecycle, and editor state.
@MainActor
final class NavigationState: ObservableObject {

    // MARK: - UI State

    @Published var showEditor: Bool = false
    @Published var showExportSheet: Bool = false
    @Published var errorMessage: String?

    // MARK: - Current Project

    @Published var currentProject: ScreenizeProject?
    @Published var currentProjectURL: URL?

    // MARK: - Editor State (for menu commands)

    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    // MARK: - Capture Toolbar

    @Published var showCaptureToolbar: Bool = false

    // MARK: - Methods

    /// Close the current project and return to the welcome screen
    func closeProject() {
        currentProject = nil
        currentProjectURL = nil
    }
}
