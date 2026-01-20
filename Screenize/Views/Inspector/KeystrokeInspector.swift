import SwiftUI

/// Keystroke keyframe inspector
struct KeystrokeInspector: View {

    // MARK: - Properties

    /// Keyframe being edited
    @Binding var keyframe: KeystrokeKeyframe

    /// Change callback
    var onChange: (() -> Void)?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            header

            Divider()

            // Time
            timeSection

            Divider()

            // Display text
            textSection

            Divider()

            // Duration
            durationSection

            Divider()

            // Position
            positionSection

            Spacer()
        }
        .padding(12)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "keyboard")
                .foregroundColor(KeyframeColor.keystroke)

            Text("Keystroke Keyframe")
                .font(.headline)

            Spacer()
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            HStack {
                TextField("", value: $keyframe.time, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit { onChange?() }

                Text("s")
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Text")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            TextField("e.g. ⌘C", text: $keyframe.displayText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onChange?() }

            // Preview pill
            if !keyframe.displayText.isEmpty {
                HStack {
                    Spacer()
                    Text(keyframe.displayText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(white: 0.1, opacity: 0.75))
                        )
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Duration")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "%.1fs", keyframe.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack {
                Slider(value: $keyframe.duration, in: 0.5...5.0, step: 0.1)
                    .onChange(of: keyframe.duration) { _ in onChange?() }

                TextField("", value: Binding(
                    get: { Double(keyframe.duration) },
                    set: { keyframe.duration = $0; onChange?() }
                ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
            }

            // Fade durations
            VStack(spacing: 6) {
                HStack {
                    Text("Fade In")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Slider(value: $keyframe.fadeInDuration, in: 0...0.5, step: 0.05)
                        .onChange(of: keyframe.fadeInDuration) { _ in onChange?() }

                    Text(String(format: "%.2fs", keyframe.fadeInDuration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }

                HStack {
                    Text("Fade Out")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Slider(value: $keyframe.fadeOutDuration, in: 0...1.0, step: 0.05)
                        .onChange(of: keyframe.fadeOutDuration) { _ in onChange?() }

                    Text(String(format: "%.2fs", keyframe.fadeOutDuration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
            }
        }
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Visual position picker
            PositionPicker(
                x: Binding(
                    get: { keyframe.position.x },
                    set: { keyframe.position = NormalizedPoint(x: $0, y: keyframe.position.y); onChange?() }
                ),
                y: Binding(
                    get: { keyframe.position.y },
                    set: { keyframe.position = NormalizedPoint(x: keyframe.position.x, y: $0); onChange?() }
                ),
                color: KeyframeColor.keystroke,
                onChange: onChange
            )
            .frame(height: 100)

            // Numeric inputs
            VStack(spacing: 8) {
                HStack {
                    Text("X")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Slider(value: Binding(
                        get: { keyframe.position.x },
                        set: { keyframe.position = NormalizedPoint(x: $0, y: keyframe.position.y); onChange?() }
                    ), in: 0...1)

                    TextField("", value: Binding(
                        get: { Double(keyframe.position.x) },
                        set: { keyframe.position = NormalizedPoint(x: CGFloat($0), y: keyframe.position.y); onChange?() }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }

                HStack {
                    Text("Y")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Slider(value: Binding(
                        get: { keyframe.position.y },
                        set: { keyframe.position = NormalizedPoint(x: keyframe.position.x, y: $0); onChange?() }
                    ), in: 0...1)

                    TextField("", value: Binding(
                        get: { Double(keyframe.position.y) },
                        set: { keyframe.position = NormalizedPoint(x: keyframe.position.x, y: CGFloat($0)); onChange?() }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }
            }

            // Preset position buttons
            HStack(spacing: 6) {
                Button("Top") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        keyframe.position = NormalizedPoint(x: 0.5, y: 0.05)
                        onChange?()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Center") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        keyframe.position = NormalizedPoint(x: 0.5, y: 0.5)
                        onChange?()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Bottom") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        keyframe.position = NormalizedPoint(x: 0.5, y: 0.95)
                        onChange?()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

}
