import Foundation

enum L10n {

    static let commonErrorTitle = string("common.error.title", defaultValue: "Error")
    static let commonOK = string("common.ok", defaultValue: "OK")

    static func string(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: defaultValue, comment: "")
    }

    static func format(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        let format = string(key, defaultValue: defaultValue)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static func failedToOpenVideo(detail: String) -> String {
        format("content.error.open_video", defaultValue: "Failed to open video: %@", detail)
    }

    static func failedToOpenProject(detail: String) -> String {
        format("content.error.open_project", defaultValue: "Failed to open project: %@", detail)
    }

    static func failedToCreateProject(detail: String) -> String {
        format("content.error.create_project", defaultValue: "Failed to create project: %@", detail)
    }

    static func failedToSaveProject(detail: String) -> String {
        format("editor.error.save_project", defaultValue: "Failed to save project: %@", detail)
    }

    static func exportFailed(detail: String) -> String {
        format("export.error.failed", defaultValue: "Export failed: %@", detail)
    }

    static func permissionAccessibilityLabel(title: String, isGranted: Bool) -> String {
        let status = isGranted
            ? string("onboarding.permission.accessibility.granted", defaultValue: "granted")
            : string("onboarding.permission.accessibility.not_granted", defaultValue: "not granted")
        return format(
            "onboarding.permission.accessibility.status",
            defaultValue: "%@, %@",
            title,
            status
        )
    }

    static func exportStatusAccessibilityLabel(status: String) -> String {
        format("export.progress.accessibility.status", defaultValue: "Export status: %@", status)
    }

    static func exportProcessingFPS(_ fps: Double) -> String {
        format("export.progress.processing_fps", defaultValue: "Processing: %.1f fps", fps)
    }

    static func exportRemaining(_ remaining: String) -> String {
        format("export.progress.remaining", defaultValue: "Remaining: %@", remaining)
    }

    static func previewRenderError(frameIndex: Int) -> String {
        format("preview.render_error", defaultValue: "Render error at frame %d", frameIndex)
    }

    static func inspectorSelectedSegments(count: Int) -> String {
        format("inspector.selection.count", defaultValue: "%d Segments Selected", count)
    }

    static func inspectorDeleteSegments(count: Int) -> String {
        format("inspector.selection.delete_count", defaultValue: "Delete %d Segments", count)
    }

    static func editorWindowTitle(filename: String) -> String {
        format("editor.window.title_with_file", defaultValue: "Screenize Editor - %@", filename)
    }

    static func generatorGenerateSelected(count: Int) -> String {
        format("generator.button.generate_selected", defaultValue: "Generate Selected (%d)", count)
    }

    static func smartGenerationFailed(detail: String) -> String {
        format("smart_generation.error.failed", defaultValue: "Failed to generate segments: %@", detail)
    }

    static let screenCapturePermissionRequired = string(
        "recording.error.screen_capture_permission",
        defaultValue: "Screen capture permission required. Please enable it in System Settings > Privacy & Security > Screen Recording."
    )

    static let recordingRequiresMacOS15 = string(
        "recording.error.requires_macos_15",
        defaultValue: "Recording requires macOS 15.0 or later"
    )

    static let failedToStopRecording = string(
        "recording.error.stop_failed",
        defaultValue: "Failed to stop recording"
    )

    static func failedToStartRecording(detail: String) -> String {
        format("recording.error.start_failed", defaultValue: "Failed to start recording: %@", detail)
    }

    static func exportWidthMinimum(_ value: Int) -> String {
        format("export.validation.width_minimum", defaultValue: "Width must be at least %d", value)
    }

    static func exportHeightMinimum(_ value: Int) -> String {
        format("export.validation.height_minimum", defaultValue: "Height must be at least %d", value)
    }

    static func exportWidthMaximum(_ value: Int) -> String {
        format("export.validation.width_maximum", defaultValue: "Width cannot exceed %d", value)
    }

    static func exportHeightMaximum(_ value: Int) -> String {
        format("export.validation.height_maximum", defaultValue: "Height cannot exceed %d", value)
    }

    static func exportFrameRateMinimum(_ value: Int) -> String {
        format("export.validation.frame_rate_minimum", defaultValue: "Frame rate must be at least %d", value)
    }

    static func exportFrameRateMaximum(_ value: Int) -> String {
        format("export.validation.frame_rate_maximum", defaultValue: "Frame rate cannot exceed %d", value)
    }

    static func projectFileNotFound(filename: String) -> String {
        format("project.error.project_file_not_found", defaultValue: "Project file not found: %@", filename)
    }

    static func videoFileNotFound(filename: String) -> String {
        format("project.error.video_file_not_found", defaultValue: "Video file not found: %@", filename)
    }

    static func packageCreationFailed(reason: String) -> String {
        format("project.error.package_creation_failed", defaultValue: "Failed to create package: %@", reason)
    }

    static func unsupportedProjectVersion(_ version: Int) -> String {
        format(
            "project.error.unsupported_project_version",
            defaultValue: "Unsupported project version: %d. Please create a new project.",
            version
        )
    }

    static let invalidProjectFile = string(
        "project.error.invalid_project_file",
        defaultValue: "Invalid project file format"
    )

    static let mouseDataFileNotFound = string(
        "project.error.mouse_data_file_not_found",
        defaultValue: "Mouse data file not found"
    )

    static func mouseDataFileNotFound(filename: String) -> String {
        format("project.error.mouse_data_file_not_found_with_name", defaultValue: "Mouse data file not found: %@", filename)
    }

    static let saveProjectFailed = string(
        "project.error.save_project_failed",
        defaultValue: "Failed to save project"
    )

    static let noVideoTrackFound = string(
        "project.error.no_video_track",
        defaultValue: "No video track found in the file"
    )

    static let invalidVideoFile = string(
        "project.error.invalid_video_file",
        defaultValue: "Invalid or corrupted video file"
    )

    static let alreadyRecording = string(
        "recording.error.already_recording",
        defaultValue: "Already recording"
    )

    static let notCurrentlyRecording = string(
        "recording.error.not_currently_recording",
        defaultValue: "Not currently recording"
    )

    static let recordingAlreadyInProgress = string(
        "recording.error.recording_already_in_progress",
        defaultValue: "Recording is already in progress"
    )

    static let noRecordingInProgress = string(
        "recording.error.no_recording_in_progress",
        defaultValue: "No recording in progress"
    )

    static let noCaptureTargetSelected = string(
        "recording.error.no_capture_target_selected",
        defaultValue: "No capture target selected"
    )

    static func captureFailed(detail: String) -> String {
        format("recording.error.capture_failed", defaultValue: "Capture failed: %@", detail)
    }

    static func writeFailed(detail: String) -> String {
        format("recording.error.write_failed", defaultValue: "Write failed: %@", detail)
    }

    static let captureAlreadyInProgress = string(
        "capture.error.already_in_progress",
        defaultValue: "Capture is already in progress"
    )

    static let noCaptureInProgress = string(
        "capture.error.not_in_progress",
        defaultValue: "No capture in progress"
    )

    static let captureTargetNotFound = string(
        "capture.error.target_not_found",
        defaultValue: "Capture target not found"
    )

    static let screenCapturePermissionDenied = string(
        "capture.error.permission_denied",
        defaultValue: "Screen capture permission denied"
    )

    static let failedToConfigureCapture = string(
        "capture.error.configuration_failed",
        defaultValue: "Failed to configure capture"
    )

    static let failedToConfigureVideoWriter = string(
        "recording.error.video_writer_configuration_failed",
        defaultValue: "Failed to configure the video writer"
    )

    static let noMicrophoneDeviceAvailable = string(
        "recording.error.no_microphone_device",
        defaultValue: "No microphone device available"
    )

    static let failedToConfigureMicrophoneInput = string(
        "recording.error.microphone_input_configuration_failed",
        defaultValue: "Failed to configure microphone input"
    )

    static let failedToConfigureAudioOutput = string(
        "recording.error.audio_output_configuration_failed",
        defaultValue: "Failed to configure audio output"
    )

    static func failedToStartAudioWriter(detail: String) -> String {
        format("recording.error.audio_writer_start_failed", defaultValue: "Failed to start audio writer: %@", detail)
    }

    static let failedToStartAudioWriter = string(
        "recording.error.audio_writer_start_failed_without_detail",
        defaultValue: "Failed to start audio writer"
    )

    static func failedToStartSystemAudioWriter(detail: String) -> String {
        format(
            "recording.error.system_audio_writer_start_failed",
            defaultValue: "Failed to start system audio writer: %@",
            detail
        )
    }

    static let failedToStartSystemAudioWriter = string(
        "recording.error.system_audio_writer_start_failed_without_detail",
        defaultValue: "Failed to start system audio writer"
    )

    static let videoWriterNotInitialized = string(
        "recording.error.video_writer_not_initialized",
        defaultValue: "Video writer not initialized"
    )

    static func failedToStartWriting(detail: String) -> String {
        format("recording.error.start_writing_failed", defaultValue: "Failed to start writing: %@", detail)
    }

    static func failedToFinishWriting(detail: String) -> String {
        format("recording.error.finish_writing_failed", defaultValue: "Failed to finish writing: %@", detail)
    }

    static let notCurrentlyWriting = string(
        "recording.error.not_currently_writing",
        defaultValue: "Not currently writing"
    )

    static let failedToConfigurePreviewEngine = string(
        "preview.error.setup_failed",
        defaultValue: "Failed to configure preview engine"
    )

    static let frameRenderingFailed = string(
        "preview.error.render_failed",
        defaultValue: "Frame rendering failed"
    )

    static let imageGeneratorNotReady = string(
        "render.error.image_generator_not_ready",
        defaultValue: "Image generator is not ready"
    )

    static let failedToExtractFrame = string(
        "render.error.frame_extraction_failed",
        defaultValue: "Failed to extract frame"
    )

    static let failedToCreateGIFDestination = string(
        "render.error.gif_destination_failed",
        defaultValue: "Failed to create GIF file destination"
    )

    static let failedToFinalizeGIF = string(
        "render.error.gif_finalize_failed",
        defaultValue: "Failed to finalize GIF file"
    )

    static let gifEncoderNotStarted = string(
        "render.error.gif_not_started",
        defaultValue: "GIF encoder has not been started"
    )

    static let exportAlreadyInProgress = string(
        "export.error.already_in_progress",
        defaultValue: "An export is already in progress"
    )

    static let failedToStartReadingVideo = string(
        "export.error.read_video_start_failed",
        defaultValue: "Failed to start reading video"
    )

    static func failedToStartWritingVideo(detail: String) -> String {
        format("export.error.write_video_start_failed", defaultValue: "Failed to start writing video: %@", detail)
    }

    static let failedToStartWritingVideo = string(
        "export.error.write_video_start_failed_without_detail",
        defaultValue: "Failed to start writing video"
    )

    static let failedToWriteVideo = string(
        "export.error.write_video_failed",
        defaultValue: "Failed to write video"
    )

    static let exportWasCancelled = string(
        "export.error.cancelled",
        defaultValue: "Export was cancelled"
    )

    static func failedToStartAudioReader(detail: String) -> String {
        format("export.error.audio_reader_start_failed", defaultValue: "Failed to start audio reader: %@", detail)
    }

    static let failedToStartAudioReader = string(
        "export.error.audio_reader_start_failed_without_detail",
        defaultValue: "Failed to start audio reader"
    )

    static let noAudioTrackFound = string(
        "export.error.no_audio_track",
        defaultValue: "No audio track found in source"
    )

    static let cannotAddReaderOutput = string(
        "render.error.cannot_add_reader_output",
        defaultValue: "Cannot add reader output"
    )

    static func failedToStartReading(detail: String) -> String {
        format("render.error.read_start_failed", defaultValue: "Failed to start reading: %@", detail)
    }

}
