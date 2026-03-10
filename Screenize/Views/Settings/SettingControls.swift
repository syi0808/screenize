import SwiftUI

// MARK: - Collapsible Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(title, isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Slider with Reset

struct SettingSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let defaultValue: CGFloat
    var unit: String = ""
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 160, alignment: .leading)
                .font(.system(size: 11))

            Slider(value: $value, in: range)
                .frame(minWidth: 100)

            Text(formattedValue)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60, alignment: .trailing)

            Button {
                value = defaultValue
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .opacity(isHovering && value != defaultValue ? 1.0 : 0.0)
        }
        .onHover { isHovering = $0 }
    }

    private var formattedValue: String {
        if unit.isEmpty {
            return String(format: "%.3f", value)
        }
        return String(format: "%.2f", value) + unit
    }
}

// MARK: - Range Slider (Dual Value)

struct RangeSettingSlider: View {
    let label: String
    @Binding var min: CGFloat
    @Binding var max: CGFloat
    let range: ClosedRange<CGFloat>
    let defaultMin: CGFloat
    let defaultMax: CGFloat
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label)
                    .frame(width: 160, alignment: .leading)
                    .font(.system(size: 11))

                Text(String(format: "%.1f – %.1f", min, max))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    min = defaultMin
                    max = defaultMax
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .opacity(isHovering && (min != defaultMin || max != defaultMax) ? 1.0 : 0.0)
            }
            HStack(spacing: 8) {
                Text("Min")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                Slider(value: $min, in: range.lowerBound...max)
                    .frame(minWidth: 80)
                Text("Max")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 28)
                Slider(value: $max, in: min...range.upperBound)
                    .frame(minWidth: 80)
            }
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Stepper with Reset

struct SettingStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let defaultValue: Int
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 160, alignment: .leading)
                .font(.system(size: 11))

            Stepper(value: $value, in: range) {
                Text("\(value)")
                    .font(.system(size: 11, design: .monospaced))
            }

            Spacer()

            Button {
                value = defaultValue
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .opacity(isHovering && value != defaultValue ? 1.0 : 0.0)
        }
        .onHover { isHovering = $0 }
    }
}
