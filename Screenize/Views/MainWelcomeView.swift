import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Welcome View (with Recording)

struct MainWelcomeView: View {

    var onStartRecording: (() -> Void)?
    var onOpenVideo: ((URL) -> Void)?
    var onOpenProject: ((URL) -> Void)?

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

            // Logo
            VStack(spacing: Spacing.lg) {
                Image(systemName: "film.stack")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("Screenize")
                    .font(Typography.displayLarge)

                Text("Screen Recording & Timeline Editing")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Primary action buttons
            HStack(spacing: Spacing.xxl) {
                // Record button
                ActionCard(
                    icon: "record.circle",
                    title: "Record",
                    description: "Record screen or window",
                    color: .red
                ) {
                    onStartRecording?()
                }

                // Open video button
                ActionCard(
                    icon: "film",
                    title: "Open Video",
                    description: "Edit existing video",
                    color: .blue
                ) {
                    openVideoPanel()
                }

                // Open project button
                ActionCard(
                    icon: "folder",
                    title: "Open Project",
                    description: "Continue editing",
                    color: .orange
                ) {
                    openProjectPanel()
                }
            }

            // Drop area
            dropZone

            // Recent projects
            RecentProjectsView { url in
                onOpenProject?(url)
            }
            .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignColors.windowBackground)
        .overlay(alignment: .topTrailing) {
            ShortcutHelpButton(context: .welcome)
                .padding(Spacing.lg)
        }
    }

    private var dropZone: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundColor(isDragging ? .accentColor : .secondary)

            Text("Drop video or project here")
                .font(Typography.heading)
                .foregroundColor(isDragging ? .accentColor : .secondary)

            Text(".mp4, .mov, .m4v, .screenize")
                .font(Typography.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 300, height: 100)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xxl)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.secondary.opacity(DesignOpacity.medium),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xxl)
                .fill(isDragging ? Color.accentColor.opacity(DesignOpacity.subtle) : Color.clear)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .accessibilityLabel("Drop zone")
        .accessibilityHint("Drop a video or project file here to open it")
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            let ext = url.pathExtension.lowercased()
            let videoExtensions = ["mp4", "mov", "m4v", "mpeg4"]

            if ext == ScreenizeProject.packageExtension {
                DispatchQueue.main.async {
                    onOpenProject?(url)
                }
            } else if videoExtensions.contains(ext) {
                DispatchQueue.main.async {
                    onOpenVideo?(url)
                }
            }
        }

        return true
    }

    private func openVideoPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            onOpenVideo?(url)
        }
    }

    private func openProjectPanel() {
        let panel = NSOpenPanel()
        let contentTypes = [UTType(filenameExtension: ScreenizeProject.packageExtension)!]
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            onOpenProject?(url)
        }
    }
}

// MARK: - Action Card

struct ActionCard: View {

    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)

                Text(title)
                    .font(Typography.heading)

                Text(description)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 140, height: 120)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xxl)
                    .fill(DesignColors.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xxl)
                    .stroke(isHovering ? color.opacity(DesignOpacity.prominent) : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withMotionSafeAnimation(AnimationTokens.quick) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(description)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openVideoFile = Notification.Name("openVideoFile")
    static let openProjectFile = Notification.Name("openProjectFile")
}
