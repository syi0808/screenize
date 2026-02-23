import SwiftUI

// MARK: - Slider With Field

/// Reusable control combining a label, slider, text field, and optional preset buttons.
/// Replaces the repeated pattern in SettingsInspector (padding, corner radius, etc.)
struct SliderWithField: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    var unit: String = ""
    var fractionDigits: Int = 0
    var presets: [(String, Double)]?
    var description: String?
    var onChange: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Label + value
            SubSectionLabel(
                label: label,
                value: formattedValue
            )

            // Description
            if let description {
                Text(description)
                    .font(Typography.monoSmall)
                    .foregroundStyle(.tertiary)
            }

            // Slider + text field
            HStack(spacing: Spacing.md) {
                Slider(value: $value, in: range, step: step)
                    .onChange(of: value) { _ in
                        onChange?()
                    }

                TextField("", value: $value, format: .number.precision(
                    .fractionLength(fractionDigits)
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .onChange(of: value) { _ in
                    onChange?()
                }
            }

            // Preset buttons
            if let presets, !presets.isEmpty {
                HStack(spacing: Spacing.sm) {
                    ForEach(presets, id: \.1) { preset in
                        Button(preset.0) {
                            withAnimation(AnimationTokens.standard) {
                                value = preset.1
                            }
                            onChange?()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var formattedValue: String {
        if fractionDigits == 0 {
            return "\(Int(value))\(unit.isEmpty ? "" : " \(unit)")"
        } else {
            return String(format: "%.\(fractionDigits)f\(unit)", value)
        }
    }
}

// MARK: - Binding Helpers

extension Binding where Value == CGFloat {
    /// Bridge CGFloat binding to Double for use with SliderWithField
    var asDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = CGFloat($0) }
        )
    }
}

extension Binding where Value == Float {
    /// Bridge Float binding to Double for use with SliderWithField
    var asDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = Float($0) }
        )
    }
}
