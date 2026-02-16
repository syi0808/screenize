import SwiftUI

enum InspectorTab: String, CaseIterable {
    case settings = "Settings"
    case segment = "Segment"
}

/// Segment inspector view.
struct InspectorView: View {

    @Binding var timeline: Timeline
    @Binding var selectedKeyframeID: UUID?
    @Binding var selectedTrackType: TrackType?
    @Binding var renderSettings: RenderSettings
    var isWindowMode: Bool
    var onKeyframeChange: (() -> Void)?
    var onDeleteKeyframe: ((UUID, TrackType) -> Void)?

    @State private var selectedTab: InspectorTab = .segment

    var body: some View {
        VStack(spacing: 0) {
            if isWindowMode {
                Picker("Inspector Tab", selection: $selectedTab) {
                    ForEach(InspectorTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            if isWindowMode && selectedTab == .settings {
                ScrollView {
                    SettingsInspector(settings: $renderSettings, timeline: $timeline, onChange: onKeyframeChange)
                }
            } else {
                segmentInspector
            }
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var segmentInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Segment")
                    .font(.headline)

                if let id = selectedKeyframeID, let trackType = selectedTrackType {
                    LabeledContent("Track") {
                        Text(trackName(trackType))
                    }

                    LabeledContent("ID") {
                        Text(id.uuidString.prefix(8))
                            .font(.system(.caption, design: .monospaced))
                    }

                    Button(role: .destructive) {
                        onDeleteKeyframe?(id, trackType)
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Segment")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No Selection")
                            .foregroundStyle(.secondary)
                        Text("Select a segment on the timeline to inspect it.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                }
            }
            .padding(12)
        }
    }

    private func trackName(_ trackType: TrackType) -> String {
        switch trackType {
        case .transform:
            return "Camera"
        case .cursor:
            return "Cursor"
        case .keystroke:
            return "Keystroke"
        case .audio:
            return "Audio"
        }
    }
}
