import SwiftUI

/// Badge showing the current status of a permission
struct PermissionStatusBadge: View {

    let status: PermissionsManager.PermissionStatus

    private var iconName: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .unknown: return "circle"
        case .restricted: return "slash.circle.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .unknown: return .yellow
        case .restricted: return .gray
        }
    }

    private var label: String {
        switch status {
        case .granted: return L10n.string("onboarding.permission.badge.granted", defaultValue: "Granted")
        case .denied: return L10n.string("onboarding.permission.badge.denied", defaultValue: "Denied")
        case .unknown: return L10n.string("onboarding.permission.badge.not_set", defaultValue: "Not Set")
        case .restricted: return L10n.string("onboarding.permission.badge.restricted", defaultValue: "Restricted")
        }
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(iconColor)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(iconColor.opacity(DesignOpacity.subtle))
        )
    }
}
