// Legacy migration support - remove this entire file in next minor version
//
// Migrates old .fsproj projects to .screenize package format.
// After the next minor version, this file can be safely deleted.

import Foundation

// MARK: - Legacy (remove in next minor version)

/// Migrates old .fsproj projects to .screenize package format
struct LegacyProjectMigrator {

    private static let fileManager = FileManager.default

    /// Check whether a URL points to a legacy .fsproj file
    static func isLegacyProject(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == ScreenizeProject.legacyFileExtension
    }

    /// Migrate a .fsproj project to .screenize package format
    /// - Parameter fsprojURL: URL to the legacy .fsproj file
    /// - Returns: Migrated project and the new .screenize package URL
    static func migrate(from fsprojURL: URL) throws -> (project: ScreenizeProject, packageURL: URL) {
        // 1. Load legacy project
        let data = try Data(contentsOf: fsprojURL)
        var project = try ScreenizeProject.decodeFromJSON(data)

        // 2. Get the source directory (where .fsproj and media files live)
        let sourceDirectory = fsprojURL.deletingLastPathComponent()
        let parentDirectory = sourceDirectory.deletingLastPathComponent()

        // 3. Determine the video file extension
        let videoExtension = project.media.videoURL.pathExtension.isEmpty
            ? "mp4" : project.media.videoURL.pathExtension

        // 4. Create the .screenize package directory
        let packageName = project.name
        let packageURL = parentDirectory
            .appendingPathComponent(packageName)
            .appendingPathExtension(ScreenizeProject.packageExtension)
        let recordingDir = packageURL.appendingPathComponent(PackageManager.recordingDirectory)

        try fileManager.createDirectory(at: recordingDir, withIntermediateDirectories: true)

        // 5. Set up canonical paths
        let canonicalVideoFilename = "\(PackageManager.canonicalVideoBaseName).\(videoExtension)"
        let videoRelativePath = "\(PackageManager.recordingDirectory)/\(canonicalVideoFilename)"
        let mouseDataRelativePath = "\(PackageManager.recordingDirectory)/\(PackageManager.canonicalMouseDataFilename)"

        let destVideoURL = packageURL.appendingPathComponent(videoRelativePath)
        let destMouseDataURL = packageURL.appendingPathComponent(mouseDataRelativePath)

        // 6. Move media files from old location into the package
        let sourceVideoURL = project.media.videoURL
        if fileManager.fileExists(atPath: sourceVideoURL.path) {
            if !fileManager.fileExists(atPath: destVideoURL.path) {
                try fileManager.moveItem(at: sourceVideoURL, to: destVideoURL)
            }
        } else {
            throw LegacyMigrationError.videoFileNotFound(sourceVideoURL)
        }

        let sourceMouseDataURL = project.media.mouseDataURL
        if fileManager.fileExists(atPath: sourceMouseDataURL.path) {
            if !fileManager.fileExists(atPath: destMouseDataURL.path) {
                try fileManager.moveItem(at: sourceMouseDataURL, to: destMouseDataURL)
            }
        }

        // 7. Update project to v2 format
        project.version = 2
        project.media = MediaAsset(
            videoRelativePath: videoRelativePath,
            mouseDataRelativePath: mouseDataRelativePath,
            packageRootURL: packageURL,
            pixelSize: project.media.pixelSize,
            frameRate: project.media.frameRate,
            duration: project.media.duration
        )

        // 8. Save project.json into the package
        let projectJSONURL = packageURL.appendingPathComponent(PackageManager.projectFilename)
        let projectData = try project.encodeToJSON()
        try projectData.write(to: projectJSONURL, options: .atomic)

        return (project, packageURL)
    }
}

// MARK: - Legacy Migration Errors (remove in next minor version)

enum LegacyMigrationError: Error, LocalizedError {
    case videoFileNotFound(URL)
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .videoFileNotFound(let url):
            return "Legacy migration failed: video file not found at \(url.path)"
        case .migrationFailed(let reason):
            return "Legacy migration failed: \(reason)"
        }
    }
}
