import XCTest
@testable import Screenize

final class L10nTests: XCTestCase {

    func test_supportedLocaleResources_existForRequestedLanguages() {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let expectedResources = [
            "Screenize/fr.lproj/Localizable.strings",
            "Screenize/de.lproj/Localizable.strings",
            "Screenize/zh-Hans.lproj/Localizable.strings",
            "Screenize/ko.lproj/Localizable.strings",
            "Screenize/ja.lproj/Localizable.strings",
        ]

        for relativePath in expectedResources {
            let resourceURL = repositoryRoot.appendingPathComponent(relativePath)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: resourceURL.path),
                "Missing localized resource at \(relativePath)"
            )
        }
    }

    func test_commonErrorTitle_usesEnglishFallback() {
        XCTAssertEqual(L10n.commonErrorTitle, "Error")
    }

    func test_failedToOpenProject_formatsDetail() {
        XCTAssertEqual(
            L10n.failedToOpenProject(detail: "Disk full"),
            "Failed to open project: Disk full"
        )
    }

    func test_permissionAccessibilityLabel_usesGrantedStatusText() {
        XCTAssertEqual(
            L10n.permissionAccessibilityLabel(title: "Microphone", isGranted: true),
            "Microphone, granted"
        )
    }

    func test_failedToSaveProject_formatsDetail() {
        XCTAssertEqual(
            L10n.failedToSaveProject(detail: "Permission denied"),
            "Failed to save project: Permission denied"
        )
    }

    func test_exportStatusAccessibilityLabel_formatsStatus() {
        XCTAssertEqual(
            L10n.exportStatusAccessibilityLabel(status: "Encoding"),
            "Export status: Encoding"
        )
    }

    func test_previewRenderError_formatsFrameIndex() {
        XCTAssertEqual(
            L10n.previewRenderError(frameIndex: 42),
            "Render error at frame 42"
        )
    }

    func test_inspectorSelectedSegments_formatsCount() {
        XCTAssertEqual(
            L10n.inspectorSelectedSegments(count: 3),
            "3 Segments Selected"
        )
    }

    func test_inspectorDeleteSegments_formatsCount() {
        XCTAssertEqual(
            L10n.inspectorDeleteSegments(count: 3),
            "Delete 3 Segments"
        )
    }

    func test_editorWindowTitle_formatsFilename() {
        XCTAssertEqual(
            L10n.editorWindowTitle(filename: "demo.mp4"),
            "Screenize Editor - demo.mp4"
        )
    }

    func test_generatorGenerateSelected_formatsCount() {
        XCTAssertEqual(
            L10n.generatorGenerateSelected(count: 2),
            "Generate Selected (2)"
        )
    }

    func test_smartGenerationFailed_formatsDetail() {
        XCTAssertEqual(
            L10n.smartGenerationFailed(detail: "No mouse data"),
            "Failed to generate segments: No mouse data"
        )
    }

    func test_screenCapturePermissionRequired_usesEnglishFallback() {
        XCTAssertEqual(
            L10n.screenCapturePermissionRequired,
            "Screen capture permission required. Please enable it in System Settings > Privacy & Security > Screen Recording."
        )
    }

    func test_recordingRequiresMacOS15_usesEnglishFallback() {
        XCTAssertEqual(
            L10n.recordingRequiresMacOS15,
            "Recording requires macOS 15.0 or later"
        )
    }

    func test_failedToStartRecording_formatsDetail() {
        XCTAssertEqual(
            L10n.failedToStartRecording(detail: "Mic unavailable"),
            "Failed to start recording: Mic unavailable"
        )
    }

    func test_exportWidthMinimum_formatsLimit() {
        XCTAssertEqual(
            L10n.exportWidthMinimum(2),
            "Width must be at least 2"
        )
    }

    func test_exportFrameRateMaximum_formatsLimit() {
        XCTAssertEqual(
            L10n.exportFrameRateMaximum(240),
            "Frame rate cannot exceed 240"
        )
    }

    func test_projectFileNotFound_formatsFilename() {
        XCTAssertEqual(
            L10n.projectFileNotFound(filename: "demo.screenize"),
            "Project file not found: demo.screenize"
        )
    }

    func test_unsupportedProjectVersion_formatsVersion() {
        XCTAssertEqual(
            L10n.unsupportedProjectVersion(5),
            "Unsupported project version: 5. Please create a new project."
        )
    }

    func test_videoFileNotFound_formatsFilename() {
        XCTAssertEqual(
            L10n.videoFileNotFound(filename: "clip.mp4"),
            "Video file not found: clip.mp4"
        )
    }

    func test_captureFailed_formatsDetail() {
        XCTAssertEqual(
            L10n.captureFailed(detail: "Permission denied"),
            "Capture failed: Permission denied"
        )
    }

    func test_failedToStartWritingVideo_formatsDetail() {
        XCTAssertEqual(
            L10n.failedToStartWritingVideo(detail: "Disk full"),
            "Failed to start writing video: Disk full"
        )
    }

    func test_failedToStartAudioReader_formatsDetail() {
        XCTAssertEqual(
            L10n.failedToStartAudioReader(detail: "Format mismatch"),
            "Failed to start audio reader: Format mismatch"
        )
    }

    func test_outputResolutionCustom_formatsDimensions() {
        XCTAssertEqual(
            OutputResolution.custom(width: 1920, height: 1080).displayName,
            "Custom (1920x1080)"
        )
    }

    func test_exportProgressProcessing_formatsFrameCounts() {
        XCTAssertEqual(
            ExportProgress.processing(frame: 12, total: 48).statusText,
            "Processing frames... (12/48)"
        )
    }

    func test_analysisInvalidVideo_formatsMessage() {
        XCTAssertEqual(
            VideoFrameAnalyzer.AnalysisError.invalidVideo("Corrupted header").errorDescription,
            "Invalid video: Corrupted header"
        )
    }
}
