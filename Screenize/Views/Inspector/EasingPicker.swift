import SwiftUI

/// Easing curve picker
struct EasingPicker: View {

    // MARK: - Properties

    @Binding var easing: EasingCurve

    /// Compact mode (icons only)
    var compact: Bool = false

    // MARK: - Body

    var body: some View {
        if compact {
            compactPicker
        } else {
            fullPicker
        }
    }

    // MARK: - Full Picker

    private var fullPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Easing")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 4) {
                    ForEach(EasingOption.allCases) { option in
                        easingButton(for: option)
                    }
                }
            }
        }
    }

    // MARK: - Compact Picker

    private var compactPicker: some View {
        Menu {
            ForEach(EasingOption.allCases) { option in
                Button {
                    easing = option.curve
                } label: {
                    HStack {
                        option.icon
                        Text(option.name)

                        if option.curve == easing {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                currentOption.icon
                    .font(.system(size: 10))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Easing Button

    private func easingButton(for option: EasingOption) -> some View {
        let isSelected = option.curve == easing

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                easing = option.curve
            }
        } label: {
            VStack(spacing: 4) {
                // Curve preview
                EasingCurvePreview(curve: option.curve)
                    .frame(width: 40, height: 24)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(option.shortName)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help(option.name)
    }

    // MARK: - Computed Properties

    private var currentOption: EasingOption {
        EasingOption.allCases.first { $0.curve == easing } ?? .linear
    }
}

// MARK: - Easing Option

private enum EasingOption: CaseIterable, Identifiable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case spring
    case springBouncy
    case springSmooth

    var id: String { name }

    // Display in two rows
    static var firstRow: [Self] {
        [.linear, .easeIn, .easeOut, .easeInOut]
    }

    static var secondRow: [Self] {
        [.spring, .springBouncy, .springSmooth]
    }

    var name: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In Out"
        case .spring: return "Spring"
        case .springBouncy: return "Spring Bouncy"
        case .springSmooth: return "Spring Smooth"
        }
    }

    var shortName: String {
        switch self {
        case .linear: return "Lin"
        case .easeIn: return "In"
        case .easeOut: return "Out"
        case .easeInOut: return "InOut"
        case .spring: return "Spr"
        case .springBouncy: return "Bnc"
        case .springSmooth: return "Smo"
        }
    }

    var curve: EasingCurve {
        switch self {
        case .linear: return .linear
        case .easeIn: return .easeIn
        case .easeOut: return .easeOut
        case .easeInOut: return .easeInOut
        case .spring: return .springDefault
        case .springBouncy: return .springBouncy
        case .springSmooth: return .springSmooth
        }
    }

    var icon: some View {
        EasingCurvePreview(curve: curve)
            .frame(width: 16, height: 12)
    }
}

// MARK: - Easing Curve Preview

/// Mini easing curve preview
struct EasingCurvePreview: View {

    let curve: EasingCurve

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let padding: CGFloat = 2

                let drawWidth = width - padding * 2
                let drawHeight = height - padding * 2

                path.move(to: CGPoint(x: padding, y: height - padding))

                let steps = 20
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let easedT = curve.apply(t)

                    let x = padding + drawWidth * t
                    let y = height - padding - drawHeight * easedT

                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, lineWidth: 1.5)
        }
    }
}

// MARK: - Larger Easing Preview (for Inspector)

/// Large easing curve preview
struct LargeEasingCurvePreview: View {

    let curve: EasingCurve

    /// Animation duration (seconds)
    private let animationDuration: TimeInterval = 2.0

    var body: some View {
        VStack(spacing: 8) {
            // Curve graph
            SwiftUI.TimelineView(.animation) { timeline in
                let progress = calculateProgress(at: timeline.date)

                ZStack {
                    // Background grid
                    gridBackground

                    // Curve
                    EasingCurvePreview(curve: curve)

                    // Animated dot
                    animatedDot(progress: progress)
                }
            }
            .frame(height: 80)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    /// Calculate progress that oscillates between 0 and 1 based on the current time
    private func calculateProgress(at date: Date) -> CGFloat {
        let totalElapsed = date.timeIntervalSinceReferenceDate
        let cyclePosition = totalElapsed.truncatingRemainder(dividingBy: animationDuration * 2)

        // Cycle from 0 to 1 and back
        if cyclePosition < animationDuration {
            return CGFloat(cyclePosition / animationDuration)
        } else {
            return CGFloat(1.0 - (cyclePosition - animationDuration) / animationDuration)
        }
    }

    private var gridBackground: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                // Horizontal grid lines
                for i in 1..<4 {
                    let y = height * CGFloat(i) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }

                // Vertical grid lines
                for i in 1..<4 {
                    let x = width * CGFloat(i) / 4
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
            }
            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        }
    }

    private func animatedDot(progress: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let padding: CGFloat = 4

            let easedProgress = curve.apply(progress)
            let x = padding + (width - padding * 2) * progress
            let y = height - padding - (height - padding * 2) * easedProgress

            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .position(x: x, y: y)
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var easing: EasingCurve = .easeOut

        var body: some View {
            VStack(spacing: 20) {
                // Full picker
                EasingPicker(easing: $easing)

                Divider()

                // Compact picker
                HStack {
                    Text("Compact:")
                    EasingPicker(easing: $easing, compact: true)
                }

                Divider()

                // Large preview
                LargeEasingCurvePreview(curve: easing)
                    .frame(width: 200)
            }
            .padding()
            .frame(width: 300)
        }
    }

    return PreviewWrapper()
}
