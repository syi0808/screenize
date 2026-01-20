import SwiftUI

/// Ripple keyframe inspector
struct RippleInspector: View {

    // MARK: - Properties

    /// Keyframe being edited
    @Binding var keyframe: RippleKeyframe

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

            // Position
            positionSection

            Divider()

            // Style
            styleSection

            Divider()

            // Easing
            easingSection

            Spacer()
        }
        .padding(12)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "circles.hexagonpath")
                .foregroundColor(KeyframeColor.ripple)

            Text("Ripple Keyframe")
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

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Visual position picker
            PositionPicker(
                x: $keyframe.x,
                y: $keyframe.y,
                color: keyframe.color.color,
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

                    Slider(value: $keyframe.x, in: 0...1)

                    TextField("", value: Binding(
                        get: { Double(keyframe.x) },
                        set: { keyframe.x = CGFloat($0); onChange?() }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }

                HStack {
                    Text("Y")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Slider(value: $keyframe.y, in: 0...1)

                    TextField("", value: Binding(
                        get: { Double(keyframe.y) },
                        set: { keyframe.y = CGFloat($0); onChange?() }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }
            }
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                RippleColorPicker(color: $keyframe.color, onChange: onChange)
            }

            // Intensity
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Intensity")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(Int(keyframe.intensity * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Slider(value: $keyframe.intensity, in: 0.1...1.0, step: 0.1)

                    TextField("", value: Binding(
                        get: { Double(keyframe.intensity) },
                        set: { keyframe.intensity = CGFloat($0); onChange?() }
                    ), format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }
            }

            // Duration
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Duration")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(String(format: "%.1f", keyframe.duration))s")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Slider(value: $keyframe.duration, in: 0.1...2.0, step: 0.1)

                    TextField("", value: $keyframe.duration, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .onSubmit { onChange?() }
                }
            }

            // Preview
            RipplePreview(
                color: keyframe.color.color,
                intensity: keyframe.intensity,
                duration: keyframe.duration
            )
            .frame(height: 60)
        }
    }

    private var easingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            EasingPicker(easing: Binding(
                get: { keyframe.easing },
                set: { keyframe.easing = $0; onChange?() }
            ))
        }
    }
}

// MARK: - Position Picker

/// Position picker
struct PositionPicker: View {

    @Binding var x: CGFloat
    @Binding var y: CGFloat

    var color: Color = .purple
    var onChange: (() -> Void)?

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                // Show position
                Circle()
                    .fill(color)
                    .frame(width: isDragging ? 20 : 16, height: isDragging ? 20 : 16)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: color.opacity(0.5), radius: isDragging ? 8 : 4)
                    .position(
                        x: x * size.width,
                        y: y * size.height
                    )
                    .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        x = max(0, min(1, value.location.x / size.width))
                        y = max(0, min(1, value.location.y / size.height))
                        onChange?()
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }
}

// MARK: - Ripple Color Picker

/// Ripple color picker
struct RippleColorPicker: View {

    @Binding var color: RippleColor

    var onChange: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RippleColor.presetColors, id: \.self) { rippleColor in
                colorButton(for: rippleColor)
            }
        }
    }

    private func colorButton(for rippleColor: RippleColor) -> some View {
        let isSelected = color == rippleColor

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                color = rippleColor
            }
            onChange?()
        } label: {
            Circle()
                .fill(rippleColor.color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? rippleColor.color : Color.clear, lineWidth: 1)
                        .padding(3)
                )
                .shadow(color: isSelected ? rippleColor.color.opacity(0.5) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ripple Preview

/// Ripple animation preview
struct RipplePreview: View {

    let color: Color
    let intensity: CGFloat
    let duration: TimeInterval

    /// Animation start time (reset when parameters change)
    @State private var animationStartDate = Date()

    var body: some View {
        SwiftUI.TimelineView(.animation) { timeline in
            let progress = calculateProgress(at: timeline.date)

            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let maxRadius = size / 2

                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))

                    // Ripple effect
                    Circle()
                        .stroke(color.opacity(Double((1 - progress) * intensity)), lineWidth: 2)
                        .frame(
                            width: maxRadius * 2 * progress,
                            height: maxRadius * 2 * progress
                        )
                }
            }
        }
        .onChange(of: color) { _ in resetAnimation() }
        .onChange(of: intensity) { _ in resetAnimation() }
        .onChange(of: duration) { _ in resetAnimation() }
    }

    /// Calculate progress at the given time (loops between 0 and 1)
    private func calculateProgress(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(animationStartDate)
        let cyclePosition = elapsed.truncatingRemainder(dividingBy: duration)
        return CGFloat(cyclePosition / duration)
    }

    /// Reset the animation
    private func resetAnimation() {
        animationStartDate = Date()
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var keyframe = RippleKeyframe(
            time: 1.5,
            x: 0.3,
            y: 0.4,
            intensity: 0.8,
            duration: 0.5,
            color: .leftClick
        )

        var body: some View {
            RippleInspector(keyframe: $keyframe) {
                print("Changed")
            }
            .frame(width: 280)
        }
    }

    return PreviewWrapper()
}
