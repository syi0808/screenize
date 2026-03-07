import SwiftUI

// MARK: - Sheet Header

/// Reusable header for sheet/dialog presentations.
/// Displays an icon, title, and optional close button.
struct SheetHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var iconColor: Color = DesignColors.accent
    var onDismiss: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)

            Text(title)
                .font(Typography.heading)

            Spacer()

            trailing()

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

extension SheetHeader where Trailing == EmptyView {
    init(
        icon: String,
        title: String,
        iconColor: Color = DesignColors.accent,
        onDismiss: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.onDismiss = onDismiss
        self.trailing = { EmptyView() }
    }
}
