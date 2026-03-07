import SwiftUI

/// Context determines which shortcuts are shown
enum ShortcutContext {
    case welcome
    case recording
    case editor
    case all
}

/// Keyboard shortcut help panel
struct KeyboardShortcutHelpView: View {

    @Environment(\.dismiss) private var dismiss

    let context: ShortcutContext

    init(context: ShortcutContext = .all) {
        self.context = context
    }

    /// Filtered categories based on context
    private var filteredCategories: [ShortcutCategory] {
        if context == .all {
            return Self.categories
        }
        return Self.categories.compactMap { category in
            let filtered = category.shortcuts.filter { $0.contexts.contains(context) }
            guard !filtered.isEmpty else { return nil }
            return ShortcutCategory(name: category.name, icon: category.icon, shortcuts: filtered)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                Text("Keyboard Shortcuts")
                    .font(.headline)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Shortcut list
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(filteredCategories) { category in
                        shortcutSection(category)
                    }
                }
                .padding()
            }
        }
        .frame(width: 380, height: 400)
    }

    // MARK: - Sections

    private func shortcutSection(_ category: ShortcutCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)

                Text(category.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            // Shortcuts
            VStack(spacing: 4) {
                ForEach(category.shortcuts) { shortcut in
                    shortcutRow(shortcut)
                }
            }
        }
    }

    private func shortcutRow(_ shortcut: ShortcutEntry) -> some View {
        HStack {
            Text(shortcut.description)
                .font(.system(size: 12))

            Spacer()

            keyCapsule(shortcut.keys)
        }
        .padding(.vertical, 2)
    }

    private func keyCapsule(_ keys: String) -> some View {
        Text(keys)
            .font(.system(size: 11, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Data Model

struct ShortcutCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let shortcuts: [ShortcutEntry]
}

struct ShortcutEntry: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
    let contexts: Set<ShortcutContext>
}

// MARK: - Shortcut Data

extension KeyboardShortcutHelpView {
    static let categories: [ShortcutCategory] = [
        ShortcutCategory(name: "General", icon: "globe", shortcuts: [
            ShortcutEntry(keys: "\u{2318}N", description: "New Recording", contexts: [.welcome]),
            ShortcutEntry(keys: "\u{2318}O", description: "Open Video", contexts: [.welcome]),
            ShortcutEntry(keys: "\u{21E7}\u{2318}O", description: "Open Project", contexts: [.welcome]),
            ShortcutEntry(keys: "\u{2318}S", description: "Save Project", contexts: [.editor]),
            ShortcutEntry(keys: "\u{21E7}\u{2318}2", description: "Start/Stop Recording", contexts: [.welcome, .recording]),
        ]),
        ShortcutCategory(name: "Editor", icon: "slider.horizontal.3", shortcuts: [
            ShortcutEntry(keys: "Space", description: "Play/Pause", contexts: [.editor]),
            ShortcutEntry(keys: "\u{232B}", description: "Delete Selected Segment(s)", contexts: [.editor]),
            ShortcutEntry(keys: "\u{2318}C", description: "Copy Selected Segment(s)", contexts: [.editor]),
            ShortcutEntry(keys: "\u{2318}V", description: "Paste Segment(s) at Playhead", contexts: [.editor]),
            ShortcutEntry(keys: "\u{2318}T", description: "Duplicate Selected Segment(s)", contexts: [.editor]),
            ShortcutEntry(keys: "\u{2318}Z", description: "Undo", contexts: [.editor]),
            ShortcutEntry(keys: "\u{21E7}\u{2318}Z", description: "Redo", contexts: [.editor]),
        ]),
        ShortcutCategory(name: "Help", icon: "questionmark.circle", shortcuts: [
            ShortcutEntry(keys: "\u{2318}?", description: "Keyboard Shortcuts", contexts: [.welcome, .recording, .editor]),
        ]),
    ]
}

// MARK: - Reusable Help Button

/// Reusable "?" button that shows keyboard shortcuts for a given context
struct ShortcutHelpButton: View {
    let context: ShortcutContext
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Keyboard Shortcuts")
        .sheet(isPresented: $showSheet) {
            KeyboardShortcutHelpView(context: context)
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
}
