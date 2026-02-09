import Foundation

/// Information about a created .screenize package
struct PackageInfo {
    /// The .screenize package directory URL
    let packageURL: URL
    /// The project.json file URL inside the package
    let projectJSONURL: URL
    /// Absolute video file URL inside the package
    let videoURL: URL
    /// Absolute mouse data file URL inside the package
    let mouseDataURL: URL
    /// Relative path to video within the package
    let videoRelativePath: String
    /// Relative path to mouse data within the package
    let mouseDataRelativePath: String
    /// v4 interop block (nil for legacy v2 packages)
    let interop: InteropBlock?

    init(
        packageURL: URL,
        projectJSONURL: URL,
        videoURL: URL,
        mouseDataURL: URL,
        videoRelativePath: String,
        mouseDataRelativePath: String,
        interop: InteropBlock? = nil
    ) {
        self.packageURL = packageURL
        self.projectJSONURL = projectJSONURL
        self.videoURL = videoURL
        self.mouseDataURL = mouseDataURL
        self.videoRelativePath = videoRelativePath
        self.mouseDataRelativePath = mouseDataRelativePath
        self.interop = interop
    }
}

/// Manages .screenize package operations
/// Handles creating, saving, and loading package-format projects
@MainActor
final class PackageManager {

    // MARK: - Constants

    /// Package file extension
    static let packageExtension = "screenize"

    /// Internal project filename
    static let projectFilename = "project.json"

    /// Internal recording subdirectory
    static let recordingDirectory = "recording"

    /// Canonical video base name (extension preserved from original)
    static let canonicalVideoBaseName = "recording"

    /// Canonical mouse data filename
    static let canonicalMouseDataFilename = "recording.mouse.json"

    // MARK: - Singleton

    static let shared = PackageManager()

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Package Creation (v4)

    /// Create a v4 .screenize package from a recording with event streams.
    /// Writes both polyrecorder-compatible event streams and legacy recording.mouse.json.
    func createPackageV4(
        name: String,
        videoURL: URL,
        mouseRecording: MouseRecording?,
        captureMeta: CaptureMeta,
        in parentDirectory: URL,
        recordingStartDate: Date,
        processTimeStartMs: Int64,
        appVersion: String
    ) throws -> PackageInfo {
        let packageURL = parentDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(Self.packageExtension)

        let recordingDir = packageURL.appendingPathComponent(Self.recordingDirectory)
        try fileManager.createDirectory(at: recordingDir, withIntermediateDirectories: true)

        let videoExtension = videoURL.pathExtension
        let canonicalVideoFilename = "\(Self.canonicalVideoBaseName).\(videoExtension)"
        let videoRelativePath = "\(Self.recordingDirectory)/\(canonicalVideoFilename)"
        let mouseDataRelativePath = "\(Self.recordingDirectory)/\(Self.canonicalMouseDataFilename)"

        let destVideoURL = packageURL.appendingPathComponent(videoRelativePath)
        let destMouseDataURL = packageURL.appendingPathComponent(mouseDataRelativePath)

        // Move video file into the package
        if fileManager.fileExists(atPath: videoURL.path),
           !fileManager.fileExists(atPath: destVideoURL.path) {
            try fileManager.moveItem(at: videoURL, to: destVideoURL)
        }

        if let recording = mouseRecording {
            // Write v4 event streams
            try EventStreamWriter.write(
                recording: recording,
                to: recordingDir,
                captureMeta: captureMeta,
                recordingStartDate: recordingStartDate,
                processTimeStartMs: processTimeStartMs,
                appVersion: appVersion
            )

            // MARK: - Legacy v2 (remove in next minor version)
            // Also write legacy mouse data for backward compatibility
            try recording.save(to: destMouseDataURL)
        }

        let interop = InteropBlock.forRecording(videoRelativePath: videoRelativePath)

        return PackageInfo(
            packageURL: packageURL,
            projectJSONURL: packageURL.appendingPathComponent(Self.projectFilename),
            videoURL: destVideoURL,
            mouseDataURL: destMouseDataURL,
            videoRelativePath: videoRelativePath,
            mouseDataRelativePath: mouseDataRelativePath,
            interop: interop
        )
    }

    // MARK: - Legacy v2 (remove in next minor version)

    /// Create a .screenize package from video and mouse data files
    /// - Parameters:
    ///   - name: Project name (used as package directory name)
    ///   - videoURL: Source video file URL
    ///   - mouseDataURL: Source mouse data file URL (optional)
    ///   - parentDirectory: Directory where the package will be created
    /// - Returns: PackageInfo with all resolved URLs
    func createPackage(
        name: String,
        videoURL: URL,
        mouseDataURL: URL?,
        in parentDirectory: URL
    ) throws -> PackageInfo {
        let packageURL = parentDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(Self.packageExtension)

        let recordingDir = packageURL.appendingPathComponent(Self.recordingDirectory)

        // Create package and recording directories
        try fileManager.createDirectory(at: recordingDir, withIntermediateDirectories: true)

        // Determine canonical video filename (preserve original extension)
        let videoExtension = videoURL.pathExtension
        let canonicalVideoFilename = "\(Self.canonicalVideoBaseName).\(videoExtension)"
        let videoRelativePath = "\(Self.recordingDirectory)/\(canonicalVideoFilename)"
        let mouseDataRelativePath = "\(Self.recordingDirectory)/\(Self.canonicalMouseDataFilename)"

        let destVideoURL = packageURL.appendingPathComponent(videoRelativePath)
        let destMouseDataURL = packageURL.appendingPathComponent(mouseDataRelativePath)

        // Move video file into the package
        if fileManager.fileExists(atPath: videoURL.path) {
            if !fileManager.fileExists(atPath: destVideoURL.path) {
                try fileManager.moveItem(at: videoURL, to: destVideoURL)
            }
        }

        // Move mouse data file into the package
        if let mouseDataURL, fileManager.fileExists(atPath: mouseDataURL.path) {
            if !fileManager.fileExists(atPath: destMouseDataURL.path) {
                try fileManager.moveItem(at: mouseDataURL, to: destMouseDataURL)
            }
        }

        return PackageInfo(
            packageURL: packageURL,
            projectJSONURL: packageURL.appendingPathComponent(Self.projectFilename),
            videoURL: destVideoURL,
            mouseDataURL: destMouseDataURL,
            videoRelativePath: videoRelativePath,
            mouseDataRelativePath: mouseDataRelativePath
        )
    }

    // MARK: - Save

    /// Save a project into an existing .screenize package
    /// - Parameters:
    ///   - project: The project to save
    ///   - packageURL: The .screenize package directory URL
    func save(_ project: ScreenizeProject, to packageURL: URL) throws {
        let projectJSONURL = packageURL.appendingPathComponent(Self.projectFilename)
        let data = try project.encodeToJSON()
        try data.write(to: projectJSONURL, options: .atomic)
    }

    // MARK: - Load

    /// Load a project from a .screenize package
    /// - Parameter packageURL: The .screenize package directory URL
    /// - Returns: The loaded project with resolved absolute URLs
    func load(from packageURL: URL) throws -> ScreenizeProject {
        let projectJSONURL = packageURL.appendingPathComponent(Self.projectFilename)

        guard fileManager.fileExists(atPath: projectJSONURL.path) else {
            throw PackageManagerError.projectFileNotFound(projectJSONURL)
        }

        let data = try Data(contentsOf: projectJSONURL)
        var project = try ScreenizeProject.decodeFromJSON(data)

        // Resolve relative paths to absolute URLs using the package root
        project.media.resolveURLs(from: packageURL)

        // Validate video file exists
        guard project.media.videoExists else {
            throw PackageManagerError.videoFileNotFound(project.media.videoURL)
        }

        return project
    }

    // MARK: - Utilities

    /// Check if a URL points to a .screenize package
    static func isPackage(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == packageExtension
    }

    /// Get the project.json URL within a package
    static func projectJSONURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(projectFilename)
    }
}

// MARK: - Errors

enum PackageManagerError: Error, LocalizedError {
    case projectFileNotFound(URL)
    case videoFileNotFound(URL)
    case packageCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .projectFileNotFound(let url):
            return "Project file not found: \(url.lastPathComponent)"
        case .videoFileNotFound(let url):
            return "Video file not found: \(url.lastPathComponent)"
        case .packageCreationFailed(let reason):
            return "Failed to create package: \(reason)"
        }
    }
}
