import SwiftUI

/// Full-screen permission setup wizard shown on first launch
struct PermissionSetupWizardView: View {

    let onComplete: () -> Void

    @StateObject private var viewModel = PermissionWizardViewModel()

    var body: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

            header

            permissionList

            getStartedButton

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.xxxxl)
        .background(DesignColors.windowBackground)
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text(L10n.string("onboarding.title", defaultValue: "Welcome to Screenize"))
                .font(Typography.displayLarge)

            Text(L10n.string(
                "onboarding.subtitle",
                defaultValue: "A few permissions are needed to get started"
            ))
                .font(.title3)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Permission List

    private var permissionList: some View {
        VStack(spacing: 0) {
            ForEach(PermissionStep.allCases, id: \.rawValue) { step in
                permissionRow(step)
                if step != PermissionStep.allCases.last {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xxl)
                .fill(DesignColors.controlBackground)
        )
        .frame(maxWidth: 520)
    }

    private func permissionRow(_ step: PermissionStep) -> some View {
        let status = viewModel.status(for: step)

        return HStack(spacing: Spacing.md) {
            Image(systemName: step.icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(step.title)
                    .font(Typography.heading)
                Text(step.description)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                if step.requiresRestart && status != .granted {
                    Text(L10n.string(
                        "onboarding.permission.restart_required",
                        defaultValue: "May require restart after enabling"
                    ))
                        .font(Typography.footnote)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            if status == .granted {
                PermissionStatusBadge(status: status)
            } else {
                Button(L10n.string("onboarding.permission.grant", defaultValue: "Grant")) {
                    Task {
                        await viewModel.requestPermission(for: step)
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .motionSafeAnimation(AnimationTokens.standard, value: status == .granted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.permissionAccessibilityLabel(title: step.title, isGranted: status == .granted))
    }

    // MARK: - Get Started Button

    private var getStartedButton: some View {
        Button(L10n.string("onboarding.get_started", defaultValue: "Get Started")) {
            onComplete()
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.allPermissionsGranted)
    }
}
