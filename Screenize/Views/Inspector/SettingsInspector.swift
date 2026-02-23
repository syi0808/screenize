import SwiftUI

/// Settings inspector
/// Configure background, padding, rounded corners, shadows, and cursor size
struct SettingsInspector: View {

    // MARK: - Properties

    /// Render settings binding
    @Binding var settings: RenderSettings

    /// Timeline binding (for cursor configuration)
    @Binding var timeline: Timeline

    /// Change callback
    var onChange: (() -> Void)?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Presets
            PresetPickerView(settings: $settings, onChange: onChange)

            Divider()

            // Cursor settings
            cursorSettingsSection

            Divider()

            // Background
            SectionHeader(title: "Background", icon: "rectangle.on.rectangle", iconColor: DesignColors.sectionBackground)

            Divider()

            backgroundToggle

            if settings.backgroundEnabled {
                Divider()
                backgroundStyleSection
            }

            Divider()

            // Padding
            SliderWithField(
                label: "Padding",
                value: $settings.padding.asDouble,
                range: 0...100,
                step: 4,
                unit: "px",
                presets: [("0", 0), ("20", 20), ("40", 40), ("60", 60)],
                onChange: onChange
            )

            Divider()

            // Window inset
            SliderWithField(
                label: "Window Inset",
                value: $settings.windowInset.asDouble,
                range: 0...30,
                step: 1,
                unit: "px",
                presets: [("0", 0), ("8", 8), ("12", 12), ("16", 16)],
                description: "Remove window border by cropping edges",
                onChange: onChange
            )

            Divider()

            // Corner radius
            SliderWithField(
                label: "Corner Radius",
                value: $settings.cornerRadius.asDouble,
                range: 0...40,
                step: 2,
                unit: "px",
                presets: [("0", 0), ("8", 8), ("12", 12), ("20", 20)],
                onChange: onChange
            )

            Divider()

            // Shadow
            shadowSection

            Spacer()
        }
        .padding(Spacing.md)
    }

    // MARK: - Cursor Settings

    private var cursorSettingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Cursor", icon: "cursorarrow", iconColor: DesignColors.sectionCursor)

            // Cursor scale
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SubSectionLabel(
                    label: "Cursor Scale",
                    value: String(format: "%.1fx", cursorScale)
                )

                HStack(spacing: Spacing.md) {
                    Slider(value: Binding(
                        get: { Double(cursorScale) },
                        set: { updateCursorScale(CGFloat($0)) }
                    ), in: 0.5...5.0, step: 0.1)

                    TextField("", value: Binding(
                        get: { Double(cursorScale) },
                        set: { updateCursorScale(CGFloat($0)) }
                    ), format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }

                // Preset buttons
                HStack(spacing: Spacing.sm) {
                    ForEach([1.0, 1.5, 2.0, 2.5], id: \.self) { value in
                        Button(String(format: "%.1fx", value)) {
                            withAnimation(AnimationTokens.standard) {
                                updateCursorScale(value)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Smooth cursor interpolation
            Toggle(isOn: smoothCursorBinding) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Smooth Cursor")
                        .font(Typography.bodyMedium)
                    Text("Interpolate cursor movement between data points")
                        .font(Typography.monoSmall)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var smoothCursorBinding: Binding<Bool> {
        Binding(
            get: { timeline.cursorTrackV2?.useSmoothCursor ?? true },
            set: { newValue in
                guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .cursor }),
                      case .cursor(var track) = timeline.tracks[trackIndex] else { return }
                track.useSmoothCursor = newValue
                timeline.tracks[trackIndex] = .cursor(track)
                onChange?()
            }
        )
    }

    private var cursorScale: CGFloat {
        timeline.cursorTrackV2?.segments.first?.scale ?? 2.5
    }

    private func updateCursorScale(_ newValue: CGFloat) {
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .cursor }),
              case .cursor(var track) = timeline.tracks[trackIndex] else {
            return
        }

        track.segments = track.segments.map {
            var segment = $0
            segment.scale = newValue
            return segment
        }
        timeline.tracks[trackIndex] = .cursor(track)
        onChange?()
    }

    // MARK: - Background

    private var backgroundToggle: some View {
        Toggle(isOn: $settings.backgroundEnabled) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Background")
                    .font(Typography.bodyMedium)
                Text("Add background behind window")
                    .font(Typography.monoSmall)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: settings.backgroundEnabled) { _ in
            onChange?()
        }
    }

    private var backgroundStyleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SubSectionLabel(label: "Background Style")

            // Gradient presets
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Gradient Presets")
                    .font(Typography.monoSmall)
                    .foregroundStyle(.tertiary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Spacing.sm) {
                    ForEach(0..<GradientStyle.presets.count, id: \.self) { index in
                        let gradient = GradientStyle.presets[index]
                        GradientPresetButton(
                            gradient: gradient,
                            isSelected: isGradientSelected(gradient),
                            onSelect: {
                                settings.backgroundStyle = .gradient(gradient)
                                onChange?()
                            }
                        )
                    }
                }
            }

            // Solid color selection
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Solid Color")
                    .font(Typography.monoSmall)
                    .foregroundStyle(.tertiary)

                HStack(spacing: Spacing.sm) {
                    ForEach(solidColorPresets, id: \.self) { color in
                        SolidColorButton(
                            color: color,
                            isSelected: isSolidColorSelected(color),
                            onSelect: {
                                settings.backgroundStyle = .solid(color)
                                onChange?()
                            }
                        )
                    }

                    ColorPicker("", selection: Binding(
                        get: { currentSolidColor },
                        set: { newColor in
                            settings.backgroundStyle = .solid(newColor)
                            onChange?()
                        }
                    ))
                    .labelsHidden()
                    .frame(width: 24, height: 24)
                }
            }

            // Custom image
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Custom Image")
                    .font(Typography.monoSmall)
                    .foregroundStyle(.tertiary)

                HStack(spacing: Spacing.sm) {
                    Button {
                        selectBackgroundImage()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "photo")
                            Text(isBackgroundImageSelected ? "Change Image" : "Select Image")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if isBackgroundImageSelected {
                        Button {
                            settings.backgroundStyle = .gradient(.defaultGradient)
                            onChange?()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove background image")
                    }
                }
            }

            // Current selection preview
            currentBackgroundPreview
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        }
    }

    // MARK: - Shadow

    private var shadowSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SubSectionLabel(label: "Shadow")

            // Shadow radius
            SliderWithField(
                label: "Radius",
                value: $settings.shadowRadius.asDouble,
                range: 0...50,
                step: 2,
                unit: "px",
                onChange: onChange
            )

            // Shadow opacity
            SliderWithField(
                label: "Opacity",
                value: shadowOpacityBinding,
                range: 0...1,
                step: 0.05,
                unit: "%",
                fractionDigits: 0,
                onChange: onChange
            )
        }
    }

    private var shadowOpacityBinding: Binding<Double> {
        Binding(
            get: { Double(settings.shadowOpacity) },
            set: { settings.shadowOpacity = Float($0) }
        )
    }

    // MARK: - Helpers

    private var solidColorPresets: [Color] {
        [.black, .white, Color(hex: "#1a1a2e")!, Color(hex: "#f5f5f5")!]
    }

    private var currentSolidColor: Color {
        if case .solid(let color) = settings.backgroundStyle {
            return color
        }
        return .black
    }

    private func isGradientSelected(_ gradient: GradientStyle) -> Bool {
        if case .gradient(let current) = settings.backgroundStyle {
            return current == gradient
        }
        return false
    }

    private func isSolidColorSelected(_ color: Color) -> Bool {
        if case .solid(let current) = settings.backgroundStyle {
            return current.hexString == color.hexString
        }
        return false
    }

    private var isBackgroundImageSelected: Bool {
        if case .image = settings.backgroundStyle { return true }
        return false
    }

    private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a background image"

        if panel.runModal() == .OK, let url = panel.url {
            settings.backgroundStyle = .image(url)
            onChange?()
        }
    }

    @ViewBuilder
    private var currentBackgroundPreview: some View {
        switch settings.backgroundStyle {
        case .solid(let color):
            Rectangle()
                .fill(color)

        case .gradient(let gradient):
            LinearGradient(
                colors: gradient.colors,
                startPoint: gradient.startPoint,
                endPoint: gradient.endPoint
            )

        case .image(let url):
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray
            }
        }
    }
}

// MARK: - Gradient Preset Button

private struct GradientPresetButton: View {
    let gradient: GradientStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(
                    LinearGradient(
                        colors: gradient.colors,
                        startPoint: gradient.startPoint,
                        endPoint: gradient.endPoint
                    )
                )
                .frame(height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(isSelected ? DesignColors.accent : Color.clear, lineWidth: 2)
                )
                .overlay(
                    isSelected ?
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                    : nil
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Solid Color Button

private struct SolidColorButton: View {
    let color: Color
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(color == .white ? Color.gray.opacity(DesignOpacity.medium) : Color.clear, lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? DesignColors.accent : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var settings = RenderSettings()
        @State private var timeline = Timeline(
            tracks: [
                AnySegmentTrack.cursor(CursorTrackV2(
                    id: UUID(),
                    name: "Cursor",
                    isEnabled: true,
                    segments: [
                        CursorSegment(startTime: 0, endTime: 10, scale: 2.5),
                    ]
                ))
            ],
            duration: 10
        )

        var body: some View {
            SettingsInspector(
                settings: $settings,
                timeline: $timeline
            ) {
                print("Settings changed")
            }
            .frame(width: 280)
            .onAppear {
                settings.backgroundEnabled = true
            }
        }
    }

    return PreviewWrapper()
}
