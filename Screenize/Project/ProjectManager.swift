import Foundation
import SwiftUI

/// Project manager
/// Handles saving, loading, and managing recent projects
@MainActor
final class ProjectManager: ObservableObject {

    // MARK: - Published Properties

    /// Recent project list
    @Published private(set) var recentProjects: [RecentProjectInfo] = []

    /// Loading indicator
    @Published private(set) var isLoading: Bool = false

    /// Error message
    @Published private(set) var errorMessage: String?

    // MARK: - Properties

    /// Project package extension
    static let projectExtension = ScreenizeProject.packageExtension

    /// Maximum number of recent projects
    private let maxRecentProjects = 10

    /// UserDefaults key
    private let recentProjectsKey = "RecentProjects"

    /// File manager
    private let fileManager = FileManager.default

    /// Package manager
    private let packageManager = PackageManager.shared

    // MARK: - Singleton

    static let shared = ProjectManager()

    private init() {
        loadRecentProjects()
    }

    // MARK: - Save

    /// Save a project to its .screenize package
    /// - Parameters:
    ///   - project: Project to save
    ///   - packageURL: The .screenize package directory URL
    /// - Returns: Package URL
    func save(_ project: ScreenizeProject, to packageURL: URL?) async throws -> URL {
        guard let packageURL else {
            throw ProjectManagerError.saveFailed
        }

        try packageManager.save(project, to: packageURL)

        // Add to recent projects
        await addToRecentProjects(project, packageURL: packageURL)

        return packageURL
    }

    // MARK: - Load

    /// Load a project from a .screenize package
    /// - Parameter url: Package URL (.screenize)
    /// - Returns: Loaded project and its package URL
    func load(from url: URL) async throws -> (project: ScreenizeProject, packageURL: URL) {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        guard PackageManager.isPackage(url) else {
            throw ProjectManagerError.invalidProjectFile
        }

        let project = try packageManager.load(from: url)

        // Add to recent projects
        await addToRecentProjects(project, packageURL: url)

        return (project, url)
    }

    /// Attempt to load from a URL (returns nil on failure)
    func tryLoad(from url: URL) async -> (project: ScreenizeProject, packageURL: URL)? {
        do {
            return try await load(from: url)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Recent Projects

    /// Add to recent projects
    private func addToRecentProjects(_ project: ScreenizeProject, packageURL: URL) async {
        let info = RecentProjectInfo(
            id: project.id,
            name: project.name,
            packageURL: packageURL,
            duration: project.media.duration,
            lastOpened: Date()
        )

        // Remove existing entries
        recentProjects.removeAll { $0.id == project.id || $0.packageURL == packageURL }

        // Insert at the front
        recentProjects.insert(info, at: 0)

        // Maintain the maximum count
        if recentProjects.count > maxRecentProjects {
            recentProjects = Array(recentProjects.prefix(maxRecentProjects))
        }

        // Save
        saveRecentProjects()
    }

    /// Save the recent project list
    private func saveRecentProjects() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(recentProjects) {
            UserDefaults.standard.set(data, forKey: recentProjectsKey)
        }
    }

    /// Load the recent project list
    private func loadRecentProjects() {
        guard let data = UserDefaults.standard.data(forKey: recentProjectsKey),
              let projects = try? JSONDecoder().decode([RecentProjectInfo].self, from: data) else {
            return
        }

        // Filter out projects that no longer exist
        recentProjects = projects.filter { info in
            fileManager.fileExists(atPath: info.packageURL.path)
        }
    }

    /// Remove a recent project
    func removeFromRecent(_ id: UUID) {
        recentProjects.removeAll { $0.id == id }
        saveRecentProjects()
    }

    /// Clear recent projects
    func clearRecentProjects() {
        recentProjects.removeAll()
        saveRecentProjects()
    }

    // MARK: - Delete

    /// Delete a project package
    func delete(at packageURL: URL) throws {
        try fileManager.removeItem(at: packageURL)

        // Also remove it from recent projects
        recentProjects.removeAll { $0.packageURL == packageURL }
        saveRecentProjects()
    }

    // MARK: - Utilities

    /// Check if the URL points to a .screenize project package
    static func isProjectFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == ScreenizeProject.packageExtension
    }

    /// Find an existing project for a video file
    func findExistingProject(for videoURL: URL) -> URL? {
        let projectName = videoURL.deletingPathExtension().lastPathComponent
        let directory = videoURL.deletingLastPathComponent()

        // Check for .screenize package
        let packageURL = directory.appendingPathComponent(projectName)
            .appendingPathExtension(ScreenizeProject.packageExtension)
        if fileManager.fileExists(atPath: packageURL.path) {
            return packageURL
        }

        return nil
    }
}

// MARK: - Recent Project Info

/// Recent project info
struct RecentProjectInfo: Codable, Identifiable {
    let id: UUID
    let name: String
    let packageURL: URL
    let duration: TimeInterval
    let lastOpened: Date

    /// Formatted date
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastOpened, relativeTo: Date())
    }

    /// Formatted duration
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Errors

enum ProjectManagerError: Error, LocalizedError {
    case videoFileNotFound(URL)
    case mouseDataNotFound(URL)
    case invalidProjectFile
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .videoFileNotFound(let url):
            return "Video file not found: \(url.lastPathComponent)"
        case .mouseDataNotFound(let url):
            return "Mouse data file not found: \(url.lastPathComponent)"
        case .invalidProjectFile:
            return "Invalid project file format"
        case .saveFailed:
            return "Failed to save project"
        }
    }
}
