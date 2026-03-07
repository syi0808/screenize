import SwiftUI

// MARK: - Settings Form

extension ExportSheetView {

    var settingsForm: some View {
        Form {
            // Preset
            Section("Preset") {
                PresetPickerView(settings: $renderSettings)
            }

            // Format
            Section("Format") {
                Picker("Format", selection: $renderSettings.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            if renderSettings.exportFormat == .video {
                // Resolution
                Section("Resolution") {
                    Picker("Output Size", selection: resolutionPickerBinding) {
                        ForEach(OutputResolution.allCases, id: \.self) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                        Text("Custom").tag(OutputResolution.custom(width: 0, height: 0))
                    }

                    if isCustomResolution {
                        HStack(spacing: 8) {
                            TextField("Width", value: $customWidth, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: customWidth) { _ in applyCustomResolution() }

                            Text("\u{00d7}")
                                .foregroundColor(.secondary)

                            TextField("Height", value: $customHeight, format: .number)
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
                Section("Frame Rate") {
                    Picker("Frame Rate", selection: frameRatePickerBinding) {
                        ForEach(OutputFrameRate.allCases, id: \.self) { rate in
                            Text(rate.displayName).tag(rate)
                        }
                        Text("Custom").tag(OutputFrameRate.fixed(-1))
                    }

                    if isCustomFrameRate {
                        HStack(spacing: 8) {
                            TextField("FPS", value: $customFPS, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: customFPS) { _ in applyCustomFrameRate() }

                            Text("fps")
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
                Section("Codec") {
                    Picker("Video Codec", selection: $renderSettings.codec) {
                        ForEach(VideoCodec.allCases, id: \.self) { codec in
                            Text(codec.displayName).tag(codec)
                        }
                    }

                    Text(renderSettings.codec.displayName)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                // Quality
                Section("Quality") {
                    Picker("Quality", selection: $renderSettings.quality) {
                        ForEach(ExportQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }

                    // Estimated file size
                    estimatedVideoFileSize
                }

                // Color Space
                Section("Color Space") {
                    Picker("Color Space", selection: $renderSettings.outputColorSpace) {
                        ForEach(OutputColorSpace.allCases, id: \.self) { cs in
                            Text(cs.displayName).tag(cs)
                        }
                    }

                    if renderSettings.outputColorSpace.isWideGamut {
                        Text("Wide gamut preserves colors outside sRGB range")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if renderSettings.exportFormat == .gif {
                // GIF Settings
                Section("GIF Settings") {
                    HStack {
                        Text("Frame Rate")
                        Spacer()
                        Text("\(renderSettings.gifSettings.frameRate) fps")
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: gifFrameRateBinding,
                        in: 5...30,
                        step: 1
                    )

                    Picker("Max Width", selection: $renderSettings.gifSettings.maxWidth) {
                        Text("480px").tag(480)
                        Text("640px").tag(640)
                        Text("800px").tag(800)
                        Text("960px").tag(960)
                        Text("1280px").tag(1280)
                    }

                    Picker("Loop", selection: $renderSettings.gifSettings.loopCount) {
                        Text("Infinite").tag(0)
                        Text("Once").tag(1)
                        Text("Twice").tag(2)
                        Text("3 times").tag(3)
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
            Text("Estimated size:")
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
            Text("Estimated size:")
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
            return "Recording exceeds 30s. GIF files for long recordings will be very large (\(String(format: "%.0f", estimatedMB)) MB estimated)."
        }
        if renderSettings.gifSettings.maxWidth > 960 {
            return "High resolution GIFs produce very large files (\(String(format: "%.0f", estimatedMB)) MB estimated). Consider reducing max width."
        }
        if estimatedMB > 50 {
            return "Estimated file size exceeds 50 MB. Consider reducing frame rate, max width, or trimming the recording."
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
            resolutionValidationError = "Width must be at least 2"
            return
        }
        guard customHeight >= 2 else {
            resolutionValidationError = "Height must be at least 2"
            return
        }
        guard customWidth <= 7680 else {
            resolutionValidationError = "Width cannot exceed 7680"
            return
        }
        guard customHeight <= 4320 else {
            resolutionValidationError = "Height cannot exceed 4320"
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
            frameRateValidationError = "Frame rate must be at least 1"
            return
        }
        guard customFPS <= 240 else {
            frameRateValidationError = "Frame rate cannot exceed 240"
            return
        }

        renderSettings.outputFrameRate = .fixed(customFPS)
    }
}
