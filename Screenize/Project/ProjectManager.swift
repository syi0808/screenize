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

    /// Project file extension
    static let projectExtension = "fsproj"

    /// Maximum number of recent projects
    private let maxRecentProjects = 10

    /// UserDefaults key
    private let recentProjectsKey = "RecentProjects"

    /// File manager
    private let fileManager = FileManager.default

    // MARK: - Singleton

    static let shared = ProjectManager()

    private init() {
        loadRecentProjects()
    }

    // MARK: - Project Folder

    /// Create the project folder and move media files
    /// - Parameters:
    ///   - videoURL: Original video file URL
    ///   - mouseDataURL: Mouse data file URL (optional)
    /// - Returns: (moved video URL, moved mouse data URL, project folder URL)
    func createProjectFolder(
        for videoURL: URL,
        mouseDataURL: URL? = nil
    ) throws -> (videoURL: URL, mouseDataURL: URL, projectFolderURL: URL) {
        let videoName = videoURL.deletingPathExtension().lastPathComponent
        let parentDirectory = videoURL.deletingLastPathComponent()
        let projectFolderURL = parentDirectory.appendingPathComponent(videoName)

        // Create the project folder
        if !fileManager.fileExists(atPath: projectFolderURL.path) {
            try fileManager.createDirectory(at: projectFolderURL, withIntermediateDirectories: true)
        }

        // Move the video file
        let newVideoURL = projectFolderURL.appendingPathComponent(videoURL.lastPathComponent)
        if !fileManager.fileExists(atPath: newVideoURL.path) {
            if fileManager.fileExists(atPath: videoURL.path) {
                try fileManager.moveItem(at: videoURL, to: newVideoURL)
            }
        }

        // Move the mouse data file
        let mouseURL = mouseDataURL ?? findMouseDataURL(for: videoURL)
        let newMouseURL = projectFolderURL.appendingPathComponent(mouseURL.lastPathComponent)
        if !fileManager.fileExists(atPath: newMouseURL.path) {
            if fileManager.fileExists(atPath: mouseURL.path) {
                try fileManager.moveItem(at: mouseURL, to: newMouseURL)
            }
        }

        return (newVideoURL, newMouseURL, projectFolderURL)
    }

    /// Path to the .fsproj file inside the project folder
    func projectFileURL(in projectFolderURL: URL, name: String) -> URL {
        return projectFolderURL.appendingPathComponent("\(name).\(Self.projectExtension)")
    }

    /// Find the mouse data file associated with a video
    private func findMouseDataURL(for videoURL: URL) -> URL {
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let directory = videoURL.deletingLastPathComponent()

        let candidates = [
            "\(baseName).mouse.json",
            "\(baseName)_mouse.json",
            "mouse.json"
        ]

        for candidate in candidates {
            let candidateURL = directory.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directory.appendingPathComponent("\(baseName).mouse.json")
    }

    // MARK: - Save

    /// Save a project
    /// - Parameters:
    ///   - project: Project to save
    ///   - url: Save location (nil uses existing path or prompts)
    /// - Returns: Saved file URL
    func save(_ project: ScreenizeProject, to url: URL? = nil) async throws -> URL {
        let saveURL: URL

        if let url = url {
            saveURL = url
        } else {
            // Default save location: same directory as the video file
            let videoDirectory = project.media.videoURL.deletingLastPathComponent()
            let projectName = project.media.videoURL.deletingPathExtension().lastPathComponent
            saveURL = videoDirectory.appendingPathComponent("\(projectName).\(Self.projectExtension)")
        }

        // JSON encoding
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(project)

        // Write the file
        try data.write(to: saveURL, options: .atomic)

        // Add to recent projects
        await addToRecentProjects(project, url: saveURL)

        return saveURL
    }

    // MARK: - Load

    /// Load a project
    /// - Parameter url: Project file URL
    /// - Returns: Loaded project
    func load(from url: URL) async throws -> ScreenizeProject {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Read the file
        let data = try Data(contentsOf: url)

        // JSON decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let project = try decoder.decode(ScreenizeProject.self, from: data)

        // Ensure the media file exists
        guard fileManager.fileExists(atPath: project.media.videoURL.path) else {
            throw ProjectManagerError.videoFileNotFound(project.media.videoURL)
        }

        // Add to recent projects
        await addToRecentProjects(project, url: url)

        return project
    }

    /// Attempt to load from a URL (returns nil on failure)
    func tryLoad(from url: URL) async -> ScreenizeProject? {
        do {
            return try await load(from: url)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Recent Projects

    /// Add to recent projects
    private func addToRecentProjects(_ project: ScreenizeProject, url: URL) async {
        let info = RecentProjectInfo(
            id: project.id,
            name: project.media.videoURL.deletingPathExtension().lastPathComponent,
            projectURL: url,
            videoURL: project.media.videoURL,
            duration: project.media.duration,
            lastOpened: Date()
        )

        // Remove existing entries
        recentProjects.removeAll { $0.id == project.id || $0.projectURL == url }

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
            fileManager.fileExists(atPath: info.projectURL.path)
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

    /// Delete a project file
    func delete(at url: URL) throws {
        try fileManager.removeItem(at: url)

        // Also remove it from recent projects
        recentProjects.removeAll { $0.projectURL == url }
        saveRecentProjects()
    }

    // MARK: - Utilities

    /// Check if the URL points to a project file
    static func isProjectFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == projectExtension
    }

    /// Find the project file in the same directory as the video
    func findExistingProject(for videoURL: URL) -> URL? {
        let projectName = videoURL.deletingPathExtension().lastPathComponent
        let directory = videoURL.deletingLastPathComponent()
        let projectURL = directory.appendingPathComponent("\(projectName).\(Self.projectExtension)")

        if fileManager.fileExists(atPath: projectURL.path) {
            return projectURL
        }

        return nil
    }
}

// MARK: - Recent Project Info

/// Recent project info
struct RecentProjectInfo: Codable, Identifiable {
    let id: UUID
    let name: String
    let projectURL: URL
    let videoURL: URL
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
