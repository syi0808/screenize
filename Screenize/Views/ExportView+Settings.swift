import SwiftUI

// MARK: - Settings Form

extension ExportSheetView {

    var settingsForm: some View {
        Form {
            // Preset
            Section(L10n.string("export.settings.preset", defaultValue: "Preset")) {
                PresetPickerView(settings: $renderSettings)
            }

            // Format
            Section(L10n.string("export.settings.format", defaultValue: "Format")) {
                Picker(L10n.string("export.settings.format", defaultValue: "Format"), selection: $renderSettings.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            if renderSettings.exportFormat == .video {
                // Resolution
                Section(L10n.string("export.settings.resolution", defaultValue: "Resolution")) {
                    Picker(L10n.string("export.settings.output_size", defaultValue: "Output Size"), selection: resolutionPickerBinding) {
                        ForEach(OutputResolution.allCases, id: \.self) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                        Text(L10n.string("export.settings.custom", defaultValue: "Custom"))
                            .tag(OutputResolution.custom(width: 0, height: 0))
                    }

                    if isCustomResolution {
                        HStack(spacing: 8) {
                            TextField(L10n.string("export.settings.width", defaultValue: "Width"), value: $customWidth, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: customWidth) { _ in applyCustomResolution() }

                            Text("\u{00d7}")
                                .foregroundColor(.secondary)

                            TextField(L10n.string("export.settings.height", defaultValue: "Height"), value: $customHeight, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: customHeight) { _ in applyCustomResolution() }
                        }

                        if let error = resolutionValidationError {
                            Text(error)
                                .font(Typography.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Frame rate
                Section(L10n.string("export.settings.frame_rate.section", defaultValue: "Frame Rate")) {
                    Picker(L10n.string("export.settings.frame_rate", defaultValue: "Frame Rate"), selection: frameRatePickerBinding) {
                        ForEach(OutputFrameRate.allCases, id: \.self) { rate in
                            Text(rate.displayName).tag(rate)
                        }
                        Text(L10n.string("export.settings.custom", defaultValue: "Custom")).tag(OutputFrameRate.fixed(-1))
                    }

                    if isCustomFrameRate {
                        HStack(spacing: 8) {
                            TextField(L10n.string("export.settings.fps", defaultValue: "fps"), value: $customFPS, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: customFPS) { _ in applyCustomFrameRate() }

                            Text(L10n.string("export.settings.fps", defaultValue: "fps"))
                                .foregroundColor(.secondary)
                        }

                        if let error = frameRateValidationError {
                            Text(error)
                                .font(Typography.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Codec
                Section(L10n.string("export.settings.codec", defaultValue: "Codec")) {
                    Picker(L10n.string("export.settings.video_codec", defaultValue: "Video Codec"), selection: $renderSettings.codec) {
                        ForEach(VideoCodec.allCases, id: \.self) { codec in
                            Text(codec.displayName).tag(codec)
                        }
                    }

                    Text(renderSettings.codec.displayName)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                // Quality
                Section(L10n.string("export.settings.quality", defaultValue: "Quality")) {
                    Picker(L10n.string("export.settings.quality", defaultValue: "Quality"), selection: $renderSettings.quality) {
                        ForEach(ExportQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }

                    // Estimated file size
                    estimatedVideoFileSize
                }

                // Color Space
                Section(L10n.string("export.settings.color_space", defaultValue: "Color Space")) {
                    Picker(
                        L10n.string("export.settings.color_space.label", defaultValue: "Color Space"),
                        selection: $renderSettings.outputColorSpace
                    ) {
                        ForEach(OutputColorSpace.allCases, id: \.self) { cs in
                            Text(cs.displayName).tag(cs)
                        }
                    }

                    if renderSettings.outputColorSpace.isWideGamut {
                        Text(L10n.string(
                            "export.settings.wide_gamut_hint",
                            defaultValue: "Wide gamut preserves colors outside sRGB range"
                        ))
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if renderSettings.exportFormat == .gif {
                // GIF Settings
                Section(L10n.string("export.settings.gif", defaultValue: "GIF Settings")) {
                    HStack {
                        Text(L10n.string("export.settings.frame_rate.section", defaultValue: "Frame Rate"))
                        Spacer()
                        Text(
                            "\(renderSettings.gifSettings.frameRate) \(L10n.string("export.settings.fps", defaultValue: "fps"))"
                        )
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: gifFrameRateBinding,
                        in: 5...30,
                        step: 1
                    )

                    Picker(
                        L10n.string("export.settings.max_width", defaultValue: "Max Width"),
                        selection: $renderSettings.gifSettings.maxWidth
                    ) {
                        Text(L10n.pixels(480)).tag(480)
                        Text(L10n.pixels(640)).tag(640)
                        Text(L10n.pixels(800)).tag(800)
                        Text(L10n.pixels(960)).tag(960)
                        Text(L10n.pixels(1280)).tag(1280)
                    }

                    Picker(L10n.string("export.settings.loop", defaultValue: "Loop"), selection: $renderSettings.gifSettings.loopCount) {
                        Text(L10n.string("export.settings.loop.infinite", defaultValue: "Infinite")).tag(0)
                        Text(L10n.string("export.settings.loop.once", defaultValue: "Once")).tag(1)
                        Text(L10n.string("export.settings.loop.twice", defaultValue: "Twice")).tag(2)
                        Text(L10n.string("export.settings.loop.three_times", defaultValue: "3 times")).tag(3)
                    }

                    // Estimated file size
                    gifEstimatedFileSize
                }

                if let warning = gifFileSizeWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Estimated File Size

    private var estimatedVideoFileSize: some View {
        let sourceSize = project.media.pixelSize
        let outputSize = renderSettings.outputResolution.size(sourceSize: sourceSize)
        let bitRate = renderSettings.quality.bitRate(for: outputSize)
        let estimatedBytes = Int64(Double(bitRate) * project.media.duration / 8)

        return HStack {
            Text(L10n.string("export.settings.estimated_size", defaultValue: "Estimated size:"))
                .foregroundColor(.secondary)

            Text(ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file))
                .fontWeight(.medium)
        }
        .font(Typography.caption)
    }

    // MARK: - GIF Helpers

    private var gifFrameRateBinding: Binding<Double> {
        Binding(
            get: { Double(renderSettings.gifSettings.frameRate) },
            set: { renderSettings.gifSettings.frameRate = Int($0) }
        )
    }

    private var gifEstimatedFileSize: some View {
        let duration = project.timeline.trimmedDuration
        let estimated = renderSettings.gifSettings.estimatedFileSize(duration: duration)

        return HStack {
            Text(L10n.string("export.settings.estimated_size", defaultValue: "Estimated size:"))
                .foregroundColor(.secondary)

            Text(ByteCountFormatter.string(fromByteCount: estimated, countStyle: .file))
                .fontWeight(.medium)
        }
        .font(Typography.caption)
    }

    private var gifFileSizeWarning: String? {
        let duration = project.timeline.trimmedDuration
        let estimated = renderSettings.gifSettings.estimatedFileSize(duration: duration)
        let estimatedMB = Double(estimated) / 1_048_576.0

        if duration > 30 {
            return L10n.format(
                "export.warning.duration",
                defaultValue: "Recording exceeds 30s. GIF files for long recordings will be very large (%.0f MB estimated).",
                estimatedMB
            )
        }
        if renderSettings.gifSettings.maxWidth > 960 {
            return L10n.format(
                "export.warning.max_width",
                defaultValue: "High resolution GIFs produce very large files (%.0f MB estimated). Consider reducing max width.",
                estimatedMB
            )
        }
        if estimatedMB > 50 {
            return L10n.string(
                "export.warning.file_size",
                defaultValue: "Estimated file size exceeds 50 MB. Consider reducing frame rate, max width, or trimming the recording."
            )
        }
        return nil
    }

    // MARK: - Picker Bindings

    var resolutionPickerBinding: Binding<OutputResolution> {
        Binding(
            get: {
                if isCustomResolution {
                    return .custom(width: 0, height: 0)
                }
                return renderSettings.outputResolution
            },
            set: { newValue in
                if case .custom = newValue {
                    isCustomResolution = true
                    applyCustomResolution()
                } else {
                    isCustomResolution = false
                    resolutionValidationError = nil
                    renderSettings.outputResolution = newValue
                }
            }
        )
    }

    var frameRatePickerBinding: Binding<OutputFrameRate> {
        Binding(
            get: {
                if isCustomFrameRate {
                    return .fixed(-1)
                }
                return renderSettings.outputFrameRate
            },
            set: { newValue in
                if case .fixed(-1) = newValue {
                    isCustomFrameRate = true
                    applyCustomFrameRate()
                } else {
                    isCustomFrameRate = false
                    frameRateValidationError = nil
                    renderSettings.outputFrameRate = newValue
                }
            }
        )
    }

    // MARK: - Validation

    var hasValidationError: Bool {
        resolutionValidationError != nil || frameRateValidationError != nil
    }

    func applyCustomResolution() {
        resolutionValidationError = nil

        guard customWidth >= 2 else {
            resolutionValidationError = L10n.exportWidthMinimum(2)
            return
        }
        guard customHeight >= 2 else {
            resolutionValidationError = L10n.exportHeightMinimum(2)
            return
        }
        guard customWidth <= 7680 else {
            resolutionValidationError = L10n.exportWidthMaximum(7680)
            return
        }
        guard customHeight <= 4320 else {
            resolutionValidationError = L10n.exportHeightMaximum(4320)
            return
        }

        // Ensure even dimensions for AVAssetWriter
        let w = customWidth.isMultiple(of: 2) ? customWidth : customWidth + 1
        let h = customHeight.isMultiple(of: 2) ? customHeight : customHeight + 1
        renderSettings.outputResolution = .custom(width: w, height: h)
    }

    func applyCustomFrameRate() {
        frameRateValidationError = nil

        guard customFPS >= 1 else {
            frameRateValidationError = L10n.exportFrameRateMinimum(1)
            return
        }
        guard customFPS <= 240 else {
            frameRateValidationError = L10n.exportFrameRateMaximum(240)
            return
        }

        renderSettings.outputFrameRate = .fixed(customFPS)
    }
}
