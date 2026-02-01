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
        VStack(alignment: .leading, spacing: 16) {
            // Presets
            PresetPickerView(settings: $settings, onChange: onChange)

            Divider()

            // Cursor settings
            cursorSettingsSection

            Divider()

            // Background header
            backgroundHeader

            Divider()

            // Background toggle
            backgroundToggle

            if settings.backgroundEnabled {
                Divider()

                // Background style
                backgroundStyleSection

                Divider()

                // Padding
                paddingSection

                Divider()

                // Window inset (border removal)
                windowInsetSection

                Divider()

                // Rounded corners
                cornerRadiusSection

                Divider()

                // Shadow
                shadowSection
            }

            Spacer()
        }
        .padding(12)
    }

    // MARK: - Sections

    // MARK: Cursor Settings

    private var cursorSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cursorarrow")
                    .foregroundColor(.orange)

                Text("Cursor")
                    .font(.headline)

                Spacer()
            }

            // Cursor scale
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cursor Scale")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(String(format: "%.1fx", cursorScale))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
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
                HStack(spacing: 8) {
                    ForEach([1.0, 1.5, 2.0, 2.5], id: \.self) { value in
                        Button(String(format: "%.1fx", value)) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                updateCursorScale(value)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var cursorScale: CGFloat {
        timeline.cursorTrack?.defaultScale ?? 2.5
    }

    private func updateCursorScale(_ newValue: CGFloat) {
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .cursor }),
              case .cursor(var track) = timeline.tracks[trackIndex] else {
            return
        }

        track = CursorTrack(
            id: track.id,
            name: track.name,
            isEnabled: track.isEnabled,
            defaultStyle: track.defaultStyle,
            defaultScale: newValue,
            defaultVisible: track.defaultVisible,
            styleKeyframes: track.styleKeyframes
        )
        timeline.tracks[trackIndex] = .cursor(track)
        onChange?()
    }

    // MARK: Background

    private var backgroundHeader: some View {
        HStack {
            Image(systemName: "rectangle.on.rectangle")
                .foregroundColor(.purple)

            Text("Background")
                .font(.headline)

            Spacer()
        }
    }

    private var backgroundToggle: some View {
        Toggle(isOn: $settings.backgroundEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Background")
                    .font(.system(size: 12, weight: .medium))
                Text("Add background behind window")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: settings.backgroundEnabled) { _ in
            onChange?()
        }
    }

    private var backgroundStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background Style")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Gradient presets
            VStack(alignment: .leading, spacing: 6) {
                Text("Gradient Presets")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Solid Color")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 8) {
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

                    // Custom color picker
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom Image")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 8) {
                    Button {
                        selectBackgroundImage()
                    } label: {
                        HStack(spacing: 4) {
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var paddingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Padding")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(settings.padding)) px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Slider(value: $settings.padding, in: 0...100, step: 4)
                    .onChange(of: settings.padding) { _ in
                        onChange?()
                    }

                TextField("", value: Binding(
                    get: { Double(settings.padding) },
                    set: { settings.padding = CGFloat($0); onChange?() }
                ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
            }

            // Preset buttons
            HStack(spacing: 8) {
                ForEach([0, 20, 40, 60], id: \.self) { value in
                    Button("\(value)") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.padding = CGFloat(value)
                        }
                        onChange?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var windowInsetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Window Inset")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(settings.windowInset)) px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text("Remove window border by cropping edges")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                Slider(value: $settings.windowInset, in: 0...30, step: 1)
                    .onChange(of: settings.windowInset) { _ in
                        onChange?()
                    }

                TextField("", value: Binding(
                    get: { Double(settings.windowInset) },
                    set: { settings.windowInset = CGFloat($0); onChange?() }
                ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
            }

            // Preset buttons
            HStack(spacing: 8) {
                ForEach([0, 8, 12, 16], id: \.self) { value in
                    Button("\(value)") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.windowInset = CGFloat(value)
                        }
                        onChange?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var cornerRadiusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Corner Radius")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(settings.cornerRadius)) px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Slider(value: $settings.cornerRadius, in: 0...40, step: 2)
                    .onChange(of: settings.cornerRadius) { _ in
                        onChange?()
                    }

                TextField("", value: Binding(
                    get: { Double(settings.cornerRadius) },
                    set: { settings.cornerRadius = CGFloat($0); onChange?() }
                ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
            }

            // Preset buttons
            HStack(spacing: 8) {
                ForEach([0, 8, 12, 20], id: \.self) { value in
                    Button("\(value)") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.cornerRadius = CGFloat(value)
                        }
                        onChange?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var shadowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shadow")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Shadow radius
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Radius")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text("\(Int(settings.shadowRadius)) px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Slider(value: $settings.shadowRadius, in: 0...50, step: 2)
                        .onChange(of: settings.shadowRadius) { _ in
                            onChange?()
                        }

                    TextField("", value: Binding(
                        get: { Double(settings.shadowRadius) },
                        set: { settings.shadowRadius = CGFloat($0); onChange?() }
                    ), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }
            }

            // Shadow opacity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text("\(Int(settings.shadowOpacity * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Slider(value: Binding(
                        get: { Double(settings.shadowOpacity) },
                        set: { settings.shadowOpacity = Float($0) }
                    ), in: 0...1, step: 0.05)
                        .onChange(of: settings.shadowOpacity) { _ in
                            onChange?()
                        }

                    TextField("", value: Binding(
                        get: { Double(settings.shadowOpacity) },
                        set: { settings.shadowOpacity = Float($0); onChange?() }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }
            }
        }
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
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: gradient.colors,
                        startPoint: gradient.startPoint,
                        endPoint: gradient.endPoint
                    )
                )
                .frame(height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
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
                        .stroke(color == .white ? Color.gray.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
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
                AnyTrack(CursorTrack(
                    id: UUID(),
                    name: "Cursor",
                    isEnabled: true,
                    defaultScale: 2.5
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
