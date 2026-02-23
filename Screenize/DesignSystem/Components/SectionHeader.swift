import SwiftUI

// MARK: - Section Header

/// Reusable section header with optional icon.
/// Used in inspector panels and settings views.
struct SectionHeader: View {
    let title: String
    var icon: String?
    var iconColor: Color?

    var body: some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .foregroundColor(iconColor ?? DesignColors.accent)
            }

            Text(title)
                .font(Typography.heading)

            Spacer()
        }
    }
}

// MARK: - Sub-section Label

/// Smaller label for sub-sections within an inspector section.
/// Displays label + optional value on opposite sides.
struct SubSectionLabel: View {
    let label: String
    var value: String?
    var style: LabelStyle = .standard

    enum LabelStyle {
        case standard   // 11pt medium, secondary
        case compact    // 10pt, tertiary
    }

    var body: some View {
        HStack {
            Text(label)
                .font(style == .standard ? Typography.timelineLabel : Typography.monoSmall)
                .foregroundStyle(style == .standard ? .secondary : .tertiary)

            Spacer()

            if let value {
                Text(value)
                    .font(style == .standard ? Typography.mono : Typography.monoSmall)
                    .foregroundStyle(style == .standard ? .secondary : .tertiary)
            }
        }
    }
}
