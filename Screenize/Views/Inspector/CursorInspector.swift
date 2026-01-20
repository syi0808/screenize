import SwiftUI

/// Cursor keyframe inspector
struct CursorInspector: View {

    // MARK: - Properties

    /// The keyframe being edited
    @Binding var keyframe: CursorStyleKeyframe

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
            VStack(alignment: .leading, spacing: 8) {
                Text("Cursor Style")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                CursorStylePicker(keyframe: $keyframe, onChange: onChange)

                // Preview
                CursorStylePreview(style: keyframe.style, scale: keyframe.scale)
                    .frame(height: 60)
            }

            Divider()

            // Options
            optionsSection

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
            Image(systemName: "cursorarrow")
                .foregroundColor(KeyframeColor.cursor)

            Text("Cursor Keyframe")
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
            HStack {
                Text("Position")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Position override toggle
                Toggle("Override", isOn: Binding(
                    get: { keyframe.position != nil },
                    set: { enabled in
                        if enabled {
                            keyframe.position = NormalizedPoint(x: 0.5, y: 0.5)
                        } else {
                            keyframe.position = nil
                        }
                        onChange?()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if let position = keyframe.position {
                // Visual position picker
                // SwiftUI uses a top-left origin while NormalizedPoint uses bottom-left, so invert Y
                PositionPicker(
                    x: Binding(
                        get: { position.x },
                        set: { keyframe.position = NormalizedPoint(x: $0, y: keyframe.position?.y ?? position.y) }
                    ),
                    y: Binding(
                        get: { 1 - position.y },
                        set: { keyframe.position = NormalizedPoint(x: keyframe.position?.x ?? position.x, y: 1 - $0) }
                    ),
                    color: KeyframeColor.cursor,
                    onChange: onChange
                )
                .frame(height: 100)

                // Numeric input
                VStack(spacing: 8) {
                    HStack {
                        Text("X")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 16)

                        Slider(
                            value: Binding(
                                get: { position.x },
                                set: { keyframe.position = NormalizedPoint(x: $0, y: position.y); onChange?() }
                            ),
                            in: 0...1
                        )

                        TextField("", value: Binding(
                            get: { Double(position.x) },
                            set: { keyframe.position = NormalizedPoint(x: CGFloat($0), y: position.y); onChange?() }
                        ), format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                    }

                    HStack {
                        Text("Y")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 16)

                        Slider(
                            value: Binding(
                                get: { position.y },
                                set: { keyframe.position = NormalizedPoint(x: position.x, y: $0); onChange?() }
                            ),
                            in: 0...1
                        )

                        TextField("", value: Binding(
                            get: { Double(position.y) },
                            set: { keyframe.position = NormalizedPoint(x: position.x, y: CGFloat($0)); onChange?() }
                        ), format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                    }
                }
            } else {
            // Indicator when using the original position
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.secondary)
                    Text("Using original mouse position")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Size
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scale")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(Int(keyframe.scale * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Slider(value: $keyframe.scale, in: 0.5...3.0, step: 0.1)

                    TextField("", value: Binding(
                        get: { Double(keyframe.scale) },
                        set: { keyframe.scale = CGFloat($0); onChange?() }
                    ), format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }

                // Preset button
                HStack(spacing: 8) {
                    ForEach([1.0, 1.5, 2.0, 2.5], id: \.self) { scale in
                        Button("\(Int(scale * 100))%") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                keyframe.scale = CGFloat(scale)
                            }
                            onChange?()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Visibility
            Toggle("Visible", isOn: Binding(
                get: { keyframe.visible },
                set: { keyframe.visible = $0; onChange?() }
            ))
                .toggleStyle(.switch)
                .controlSize(.small)
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

// MARK: - Cursor Style Picker

/// Cursor style picker
struct CursorStylePicker: View {

    @Binding var keyframe: CursorStyleKeyframe

    var onChange: (() -> Void)?

    // Available styles
    private let firstRowStyles: [CursorStyle] = [.arrow, .pointer, .iBeam]
    private let secondRowStyles: [CursorStyle] = [.crosshair, .openHand, .closedHand]

    var body: some View {
        VStack(spacing: 8) {
            // First row
            HStack(spacing: 8) {
                ForEach(firstRowStyles, id: \.self) { cursorStyle in
                    styleButton(for: cursorStyle)
                }
            }

            // Second row
            HStack(spacing: 8) {
                ForEach(secondRowStyles, id: \.self) { cursorStyle in
                    styleButton(for: cursorStyle)
                }
            }
        }
    }

    private func styleButton(for cursorStyle: CursorStyle) -> some View {
        let isSelected = keyframe.style == cursorStyle

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                keyframe.style = cursorStyle
            }
            onChange?()
        } label: {
            VStack(spacing: 4) {
                // Icon
                Image(systemName: iconName(for: cursorStyle))
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                // Name
                Text(cursorStyle.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func iconName(for style: CursorStyle) -> String {
        switch style {
        case .arrow:
            return "cursorarrow"
        case .pointer:
            return "hand.point.up.fill"
        case .iBeam:
            return "character.cursor.ibeam"
        case .crosshair:
            return "plus"
        case .openHand:
            return "hand.raised.fill"
        case .closedHand:
            return "hand.point.down.fill"
        case .contextMenu:
            return "contextualmenu.and.cursorarrow"
        }
    }
}

// MARK: - Cursor Style Preview

/// Cursor style preview
struct CursorStylePreview: View {

    let style: CursorStyle
    let scale: CGFloat

    @State private var position = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))

                // Cursor preview
                cursorView
                    .scaleEffect(scale)
                    .position(
                        x: position.x * size.width,
                        y: position.y * size.height
                    )
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    @ViewBuilder
    private var cursorView: some View {
        Image(systemName: iconName(for: style))
            .font(.system(size: 20))
            .foregroundColor(.primary)
    }

    private func iconName(for style: CursorStyle) -> String {
        switch style {
        case .arrow:
            return "cursorarrow"
        case .pointer:
            return "hand.point.up.fill"
        case .iBeam:
            return "character.cursor.ibeam"
        case .crosshair:
            return "plus"
        case .openHand:
            return "hand.raised.fill"
        case .closedHand:
            return "hand.point.down.fill"
        case .contextMenu:
            return "contextualmenu.and.cursorarrow"
        }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            position = CGPoint(x: 0.7, y: 0.6)
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var keyframe = CursorStyleKeyframe(
            time: 0,
            style: .arrow,
            visible: true,
            scale: 1.5
        )

        var body: some View {
            CursorInspector(keyframe: $keyframe) {
                print("Changed")
            }
            .frame(width: 280)
        }
    }

    return PreviewWrapper()
}
