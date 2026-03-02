import SwiftUI

// MARK: - Empty State View

/// Reusable empty/placeholder state view.
/// Used when no content is available (no selection, no source, no preview).
struct DesignEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String?
    var iconSize: CGFloat = 36
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)

            Text(title)
                .foregroundStyle(.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
