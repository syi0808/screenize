import SwiftUI
import ScreenCaptureKit

/// Source picker view (select screen or window)
struct SourcePickerView: View {

    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: SourceTab = .displays

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Tabs
            tabPicker

            // Content
            if appState.availableDisplays.isEmpty && appState.availableWindows.isEmpty {
                emptyState
            } else {
                sourceList
            }

            Divider()

            // Bottom buttons
            footer
        }
        .frame(width: 600, height: 500)
        .task {
            await appState.refreshAvailableSources()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("Select Source")
                .font(Typography.heading)

            Spacer()

            Button {
                Task {
                    await appState.refreshAvailableSources()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Source Type", selection: $selectedTab) {
            Text("Displays (\(appState.availableDisplays.count))").tag(SourceTab.displays)
            Text("Windows (\(filteredWindows.count))").tag(SourceTab.windows)
        }
        .pickerStyle(.segmented)
        .padding(Spacing.lg)
    }

    /// Windows list filtered to exclude system UI
    private var filteredWindows: [SCWindow] {
        appState.availableWindows.filter { window in
            // Filter by application name
            let appName = window.owningApplication?.applicationName.lowercased() ?? ""
            let bundleID = window.owningApplication?.bundleIdentifier.lowercased() ?? ""

            // Apps to exclude
            let excludedApps = ["wallpaper", "underbelly", "dock", "windowserver", "window server"]
            if excludedApps.contains(where: { appName.contains($0) || bundleID.contains($0) }) {
                return false
            }

            // Filter by window title
            let title = window.title?.lowercased() ?? ""

            // Skip "Display N" desktop windows
            if title.hasPrefix("display ") {
                return false
            }

            // Exclude windows containing "Backstop"
            if title.contains("backstop") {
                return false
            }

            // Skip Finder desktop windows (empty title or "Desktop")
            if appName == "finder" && (title.isEmpty || title == "desktop") {
                return false
            }

            // Exclude windows without owning apps (system elements)
            if window.owningApplication == nil {
                return false
            }

            // Only show windows from regular (foreground) applications
            // This filters out daemons, agents, and background-only processes
            if let pid = window.owningApplication?.processID,
               let runningApp = NSRunningApplication(processIdentifier: pid),
               runningApp.activationPolicy != .regular {
                return false
            }

            // Exclude very small windows (likely system utilities)
            if window.frame.width < 100 || window.frame.height < 100 {
                return false
            }

            return true
        }
    }

    // MARK: - Source List

    private var sourceList: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
            ], spacing: 16) {
                switch selectedTab {
                case .displays:
                    ForEach(appState.availableDisplays, id: \.displayID) { display in
                        DisplayCard(
                            display: display,
                            isSelected: isSelected(display: display),
                            onSelect: { selectDisplay(display) }
                        )
                    }

                case .windows:
                    ForEach(filteredWindows, id: \.windowID) { window in
                        WindowCard(
                            window: window,
                            isSelected: isSelected(window: window),
                            onSelect: { selectWindow(window) }
                        )
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "rectangle.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Sources Available")
                .font(Typography.heading)
                .foregroundColor(.secondary)

            Text("Screen recording permission is required.\nPlease allow Screenize in System Settings.")
                .font(Typography.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.md) {
                Button("Open System Settings") {
                    openSystemPreferences()
                }
                .buttonStyle(.bordered)

                Button("Refresh") {
                    Task {
                        await appState.refreshAvailableSources()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Text("After enabling permission, click Refresh or restart the app")
                .font(Typography.footnote)
                .foregroundStyle(.quaternary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Select") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.selectedTarget == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding(Spacing.lg)
    }

    // MARK: - Helpers

    private func isSelected(display: SCDisplay) -> Bool {
        if case .display(let d) = appState.selectedTarget {
            return d.displayID == display.displayID
        }
        return false
    }

    private func isSelected(window: SCWindow) -> Bool {
        if case .window(let w) = appState.selectedTarget {
            return w.windowID == window.windowID
        }
        return false
    }

    private func selectDisplay(_ display: SCDisplay) {
        appState.selectedTarget = .display(display)
    }

    private func selectWindow(_ window: SCWindow) {
        appState.selectedTarget = .window(window)
    }

    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Source Tab

enum SourceTab {
    case displays
    case windows
}

// MARK: - Display Card

struct DisplayCard: View {

    let display: SCDisplay
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Spacing.sm) {
                // Preview area
                GeometryReader { geometry in
                    ZStack {
                        // Background
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(DesignColors.controlBackground)

                        // Thumbnail or placeholder
                        if let thumbnail = thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } else if isLoadingThumbnail {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "display")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                }
                .aspectRatio(16/10, contentMode: .fit)

                // Details
                VStack(spacing: Spacing.xxs) {
                    Text("Display \(display.displayID)")
                        .font(Typography.caption)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text("\(display.width) × \(display.height)")
                        .font(Typography.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xxl)
                    .fill(isSelected ? Color.accentColor.opacity(DesignOpacity.subtle) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Display \(display.displayID), \(display.width) by \(display.height)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard thumbnail == nil, !isLoadingThumbnail else { return }
        isLoadingThumbnail = true

        if #available(macOS 14.0, *) {
            do {
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                let displayAspect = CGFloat(display.width) / CGFloat(display.height)
                config.width = 320
                config.height = max(1, Int(320.0 / displayAspect))
                config.scalesToFit = true
                config.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            } catch {
                // Keep the default icon on failure
            }
        } else {
            // macOS 13: use CGDisplayCreateImage
            if let cgImage = CGDisplayCreateImage(display.displayID) {
                let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
                let targetSize = NSSize(width: 320, height: max(1, 320.0 / imageAspect))
                let resizedImage = NSImage(size: targetSize)
                resizedImage.lockFocus()
                NSGraphicsContext.current?.imageInterpolation = .high
                NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    .draw(in: NSRect(origin: .zero, size: targetSize),
                          from: .zero,
                          operation: .copy,
                          fraction: 1.0)
                resizedImage.unlockFocus()
                thumbnail = resizedImage
            }
        }

        isLoadingThumbnail = false
    }
}

// MARK: - Window Card

struct WindowCard: View {

    let window: SCWindow
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Spacing.sm) {
                // Preview area
                GeometryReader { geometry in
                    ZStack {
                        // Background
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(DesignColors.controlBackground)

                        // Thumbnail or placeholder
                        if let thumbnail = thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } else if isLoadingThumbnail {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            // Default icon shown before loading or on failure
                            VStack(spacing: Spacing.xs) {
                                if let appName = window.owningApplication?.applicationName {
                                    Text(String(appName.prefix(2)))
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Image(systemName: "macwindow")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                }
                .aspectRatio(16/10, contentMode: .fit)

                // Details
                VStack(spacing: Spacing.xxs) {
                    Text(window.owningApplication?.applicationName ?? "Unknown")
                        .font(Typography.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)

                    if let title = window.title, !title.isEmpty {
                        Text(title)
                            .font(Typography.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Text("\(Int(window.frame.width)) × \(Int(window.frame.height))")
                        .font(Typography.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xxl)
                    .fill(isSelected ? Color.accentColor.opacity(DesignOpacity.subtle) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(window.owningApplication?.applicationName ?? "Unknown") window\(window.title.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard thumbnail == nil, !isLoadingThumbnail else { return }
        isLoadingThumbnail = true

        if #available(macOS 14.0, *) {
            do {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                let windowAspect = window.frame.width / window.frame.height
                config.width = 320
                config.height = max(1, Int(320.0 / windowAspect))
                config.scalesToFit = true
                config.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            } catch {
                // Keep the default icon on failure
            }
        } else {
            // macOS 13: use CGWindowListCreateImage
            let windowID = window.windowID
            if let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
                let targetSize = NSSize(width: 320, height: max(1, 320.0 / imageAspect))
                let resizedImage = NSImage(size: targetSize)
                resizedImage.lockFocus()
                NSGraphicsContext.current?.imageInterpolation = .high
                NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    .draw(in: NSRect(origin: .zero, size: targetSize),
                          from: .zero,
                          operation: .copy,
                          fraction: 1.0)
                resizedImage.unlockFocus()
                thumbnail = resizedImage
            }
        }

        isLoadingThumbnail = false
    }
}

// MARK: - Preview

#Preview {
    SourcePickerView(appState: AppState.shared)
}
