import SwiftUI

// MARK: - Toolbar Icon Button Style

/// Consistent styling for toolbar icon buttons with hover highlight.
/// Replaces inline `.buttonStyle(.plain)` + `.help()` pattern.
struct ToolbarIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(AnimationTokens.quick, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.primary.opacity(DesignOpacity.light)
        } else if isHovered {
            return Color.primary.opacity(DesignOpacity.subtle)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Pill Button Style

/// Rounded pill-shaped buttons used in recording controls.
/// Provides a tinted background with the given color.
struct PillButtonStyle: ButtonStyle {
    var color: Color = DesignColors.accent
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.captionMedium)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                Capsule()
                    .fill(color.opacity(configuration.isPressed ? DesignOpacity.medium : DesignOpacity.light))
            )
            .foregroundStyle(color)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AnimationTokens.quick, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Destructive Button Style

/// Red-tinted button for destructive actions (delete segments, etc.)
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DesignColors.destructive)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(DesignColors.destructive.opacity(
                        configuration.isPressed ? DesignOpacity.light : DesignOpacity.subtle
                    ))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(AnimationTokens.quick, value: configuration.isPressed)
    }
}

// MARK: - Preset Chip Style

/// Small chip-style buttons for preset values (padding, corner radius, etc.)
struct PresetChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.caption)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Color.primary.opacity(
                        configuration.isPressed ? DesignOpacity.light : DesignOpacity.subtle
                    ))
            )
            .animation(AnimationTokens.quick, value: configuration.isPressed)
    }
}
