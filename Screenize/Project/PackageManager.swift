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
    /// Relative path to mic audio within the package (nil if no mic)
    let micAudioRelativePath: String?
    /// v4 interop block (nil for legacy v2 packages)
    let interop: InteropBlock?

    init(
        packageURL: URL,
        projectJSONURL: URL,
        videoURL: URL,
        mouseDataURL: URL,
        videoRelativePath: String,
        mouseDataRelativePath: String,
        micAudioRelativePath: String? = nil,
        interop: InteropBlock? = nil
    ) {
        self.packageURL = packageURL
        self.projectJSONURL = projectJSONURL
        self.videoURL = videoURL
        self.mouseDataURL = mouseDataURL
        self.videoRelativePath = videoRelativePath
        self.mouseDataRelativePath = mouseDataRelativePath
        self.micAudioRelativePath = micAudioRelativePath
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

    /// Canonical microphone audio filename
    static let canonicalMicAudioFilename = "recording_mic.m4a"

    // MARK: - Singleton

    static let shared = PackageManager()

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Package Creation

    /// Create a .screenize package from an imported video file (no event streams).
    func createPackageFromVideo(
        name: String,
        videoURL: URL,
        in parentDirectory: URL
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

        if fileManager.fileExists(atPath: videoURL.path),
           !fileManager.fileExists(atPath: destVideoURL.path) {
            try fileManager.moveItem(at: videoURL, to: destVideoURL)
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

    /// Create a .screenize package from a recording with event streams.
    func createPackageV4(
        name: String,
        videoURL: URL,
        mouseRecording: MouseRecording?,
        captureMeta: CaptureMeta,
        micAudioURL: URL? = nil,
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

        }

        // Move mic audio file into the package (if present)
        var micAudioRelativePath: String?
        if let micURL = micAudioURL,
           fileManager.fileExists(atPath: micURL.path) {
            let relPath = "\(Self.recordingDirectory)/\(Self.canonicalMicAudioFilename)"
            let destMicURL = packageURL.appendingPathComponent(relPath)
            try fileManager.moveItem(at: micURL, to: destMicURL)
            micAudioRelativePath = relPath
        }

        let interop = InteropBlock.forRecording(videoRelativePath: videoRelativePath)

        return PackageInfo(
            packageURL: packageURL,
            projectJSONURL: packageURL.appendingPathComponent(Self.projectFilename),
            videoURL: destVideoURL,
            mouseDataURL: destMouseDataURL,
            videoRelativePath: videoRelativePath,
            mouseDataRelativePath: mouseDataRelativePath,
            micAudioRelativePath: micAudioRelativePath,
            interop: interop
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

        guard project.version == 5 else {
            throw PackageManagerError.unsupportedProjectVersion(project.version)
        }

        // Resolve relative paths to absolute URLs using the package root
        project.media.resolveURLs(from: packageURL)

        // Recover interop for v4 projects saved without it
        if project.interop == nil {
            let metadataURL = packageURL.appendingPathComponent("recording/metadata.json")
            if fileManager.fileExists(atPath: metadataURL.path) {
                project.interop = InteropBlock.forRecording(
                    videoRelativePath: project.media.videoRelativePath
                )
            }
        }

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
    case unsupportedProjectVersion(Int)

    var errorDescription: String? {
        switch self {
        case .projectFileNotFound(let url):
            return "Project file not found: \(url.lastPathComponent)"
        case .videoFileNotFound(let url):
            return "Video file not found: \(url.lastPathComponent)"
        case .packageCreationFailed(let reason):
            return "Failed to create package: \(reason)"
        case .unsupportedProjectVersion(let version):
            return "Unsupported project version: \(version). Please create a new project."
        }
    }
}
