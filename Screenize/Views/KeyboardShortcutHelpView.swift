import SwiftUI

/// Keyboard shortcut help panel
struct KeyboardShortcutHelpView: View {

    @Environment(\.dismiss) private var dismiss

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
                    ForEach(Self.categories) { category in
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
}

// MARK: - Shortcut Data

extension KeyboardShortcutHelpView {
    static let categories: [ShortcutCategory] = [
        ShortcutCategory(name: "General", icon: "globe", shortcuts: [
            ShortcutEntry(keys: "\u{2318}N", description: "New Recording"),
            ShortcutEntry(keys: "\u{2318}O", description: "Open Video"),
            ShortcutEntry(keys: "\u{21E7}\u{2318}O", description: "Open Project"),
            ShortcutEntry(keys: "\u{2318}S", description: "Save Project"),
            ShortcutEntry(keys: "\u{21E7}\u{2318}2", description: "Start/Stop Recording"),
        ]),
        ShortcutCategory(name: "Editor", icon: "slider.horizontal.3", shortcuts: [
            ShortcutEntry(keys: "Space", description: "Play/Pause"),
            ShortcutEntry(keys: "\u{232B}", description: "Delete Selected Keyframe"),
            ShortcutEntry(keys: "\u{2318}Z", description: "Undo"),
            ShortcutEntry(keys: "\u{21E7}\u{2318}Z", description: "Redo"),
        ]),
        ShortcutCategory(name: "Help", icon: "questionmark.circle", shortcuts: [
            ShortcutEntry(keys: "\u{2318}?", description: "Keyboard Shortcuts"),
        ]),
    ]
}

// MARK: - Notification

extension Notification.Name {
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
}
