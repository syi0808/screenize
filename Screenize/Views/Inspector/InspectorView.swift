import SwiftUI

/// Inspector tab types
enum InspectorTab: String, CaseIterable {
    case settings = "Settings"
    case keyframe = "Keyframe"
}

/// Inspector main view
/// Edit properties of the selected keyframe or track
struct InspectorView: View {

    // MARK: - Properties

    /// Timeline (for editing keyframes)
    @Binding var timeline: Timeline

    /// Selected keyframe ID
    @Binding var selectedKeyframeID: UUID?

    /// Selected track type
    @Binding var selectedTrackType: TrackType?

    /// Render settings (for window styling)
    @Binding var renderSettings: RenderSettings

    /// Window mode flag
    var isWindowMode: Bool

    /// Change callback
    var onKeyframeChange: (() -> Void)?

    /// Keyframe deletion callback
    var onDeleteKeyframe: ((UUID, TrackType) -> Void)?

    /// Currently selected tab
    @State private var selectedTab: InspectorTab = .keyframe

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Tab selection (window mode only)
            if isWindowMode {
                tabPicker
                Divider()
            }

            // Content per tab
            if isWindowMode && selectedTab == .settings {
                ScrollView {
                    SettingsInspector(
                        settings: $renderSettings,
                        timeline: $timeline,
                        onChange: onKeyframeChange
                    )
                }
            } else {
                // Inspector content (keyframe editing)
                inspectorContent
            }
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Inspector Tab", selection: $selectedTab) {
            ForEach(InspectorTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var inspectorContent: some View {
        if let keyframeID = selectedKeyframeID,
           let trackType = selectedTrackType {
            // When a keyframe is selected
            keyframeInspector(for: keyframeID, trackType: trackType)
        } else if let trackType = selectedTrackType {
            // When only a track is selected
            trackInfo(for: trackType)
        } else {
            // When nothing is selected
            emptyState
        }
    }

    // MARK: - Keyframe Inspector

    @ViewBuilder
    private func keyframeInspector(for keyframeID: UUID, trackType: TrackType) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                switch trackType {
                case .transform:
                    if let binding = transformKeyframeBinding(for: keyframeID) {
                        TransformInspector(
                            keyframe: binding,
                            onChange: onKeyframeChange
                        )
                    } else {
                        keyframeNotFound
                    }

                case .ripple:
                    if let binding = rippleKeyframeBinding(for: keyframeID) {
                        RippleInspector(
                            keyframe: binding,
                            onChange: onKeyframeChange
                        )
                    } else {
                        keyframeNotFound
                    }

                case .cursor:
                    if let binding = cursorKeyframeBinding(for: keyframeID) {
                        CursorInspector(
                            keyframe: binding,
                            onChange: onKeyframeChange
                        )
                    } else {
                        keyframeNotFound
                    }

                case .keystroke:
                    if let binding = keystrokeKeyframeBinding(for: keyframeID) {
                        KeystrokeInspector(
                            keyframe: binding,
                            onChange: onKeyframeChange
                        )
                    } else {
                        keyframeNotFound
                    }

                case .audio:
                    // Implement when audio tracks are supported in the future
                    emptyState
                }

                Divider()
                    .padding(.vertical, 8)

                // Delete button
                deleteButton(for: keyframeID, trackType: trackType)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Track Info

    private func trackInfo(for trackType: TrackType) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: trackIcon(for: trackType))
                .font(.system(size: 40))
                .foregroundColor(KeyframeColor.color(for: trackType).opacity(0.5))

            Text(trackName(for: trackType))
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Select a keyframe to edit its properties")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // Track statistics
            trackStatistics(for: trackType)
                .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    private func trackStatistics(for trackType: TrackType) -> some View {
        let count = keyframeCount(for: trackType)

        return VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(KeyframeColor.color(for: trackType))

            Text(count == 1 ? "Keyframe" : "Keyframes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(KeyframeColor.color(for: trackType).opacity(0.1))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sidebar.right")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Selection")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Select a track or keyframe to view and edit its properties")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Keyframe Not Found

    private var keyframeNotFound: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange.opacity(0.5))

            Text("Keyframe Not Found")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("The selected keyframe could not be found")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Delete Button

    private func deleteButton(for keyframeID: UUID, trackType: TrackType) -> some View {
        Button(role: .destructive) {
            onDeleteKeyframe?(keyframeID, trackType)
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Keyframe")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    // MARK: - Helpers

    private func trackIcon(for type: TrackType) -> String {
        switch type {
        case .transform:
            return "arrow.up.left.and.arrow.down.right"
        case .ripple:
            return "circles.hexagonpath"
        case .cursor:
            return "cursorarrow"
        case .keystroke:
            return "keyboard"
        case .audio:
            return "waveform"
        }
    }

    private func trackName(for type: TrackType) -> String {
        switch type {
        case .transform:
            return "Transform Track"
        case .ripple:
            return "Ripple Track"
        case .cursor:
            return "Cursor Track"
        case .keystroke:
            return "Keystroke Track"
        case .audio:
            return "Audio Track"
        }
    }

    private func keyframeCount(for type: TrackType) -> Int {
        switch type {
        case .transform:
            return timeline.transformTrack?.keyframes.count ?? 0
        case .ripple:
            return timeline.rippleTrack?.keyframes.count ?? 0
        case .cursor:
            return timeline.cursorTrack?.styleKeyframes?.count ?? 0
        case .keystroke:
            return timeline.keystrokeTrack?.keyframes.count ?? 0
        case .audio:
            return 0  // Implement once audio track support exists
        }
    }

    // MARK: - Keyframe Bindings

    private func transformKeyframeBinding(for id: UUID) -> Binding<TransformKeyframe>? {
        // Initial validation (ensure the keyframe exists)
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .transform }),
              case .transform(let track) = timeline.tracks[trackIndex],
              track.keyframes.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                // Re-find the index by ID each time
                if case .transform(let track) = self.timeline.tracks[trackIndex],
                   let keyframeIndex = track.keyframes.firstIndex(where: { $0.id == id }) {
                    return track.keyframes[keyframeIndex]
                }
                return TransformKeyframe(time: 0, zoom: 1.0, centerX: 0.5, centerY: 0.5)
            },
            set: { newValue in
                // Re-find the index by ID each time
                if case .transform(var track) = self.timeline.tracks[trackIndex],
                   let keyframeIndex = track.keyframes.firstIndex(where: { $0.id == id }) {
                    track.keyframes[keyframeIndex] = newValue
                    self.timeline.tracks[trackIndex] = .transform(track)
                }
            }
        )
    }

    private func rippleKeyframeBinding(for id: UUID) -> Binding<RippleKeyframe>? {
        // Initial validation (ensure the keyframe exists)
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .ripple }),
              case .ripple(let track) = timeline.tracks[trackIndex],
              track.keyframes.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                // Re-find the index by ID each time
                if case .ripple(let track) = self.timeline.tracks[trackIndex],
                   let keyframeIndex = track.keyframes.firstIndex(where: { $0.id == id }) {
                    return track.keyframes[keyframeIndex]
                }
                return RippleKeyframe(time: 0, x: 0.5, y: 0.5)
            },
            set: { newValue in
                // Re-find the index by ID each time
                if case .ripple(var track) = self.timeline.tracks[trackIndex],
                   let keyframeIndex = track.keyframes.firstIndex(where: { $0.id == id }) {
                    track.keyframes[keyframeIndex] = newValue
                    self.timeline.tracks[trackIndex] = .ripple(track)
                }
            }
        )
    }

    private func cursorKeyframeBinding(for id: UUID) -> Binding<CursorStyleKeyframe>? {
        // Initial validation (ensure the keyframe exists)
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .cursor }),
              case .cursor(let track) = timeline.tracks[trackIndex],
              let keyframes = track.styleKeyframes,
              keyframes.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                // Re-find the index by ID each time
                if case .cursor(let track) = self.timeline.tracks[trackIndex],
                   let keyframes = track.styleKeyframes,
                   let keyframeIndex = keyframes.firstIndex(where: { $0.id == id }) {
                    return keyframes[keyframeIndex]
                }
                return CursorStyleKeyframe(time: 0, style: .arrow, visible: true, scale: 1.0)
            },
            set: { newValue in
                // Re-find the index by ID each time
                if case .cursor(var track) = self.timeline.tracks[trackIndex],
                   var keyframes = track.styleKeyframes,
                   let keyframeIndex = keyframes.firstIndex(where: { $0.id == id }) {
                    keyframes[keyframeIndex] = newValue
                    track = CursorTrack(
                        id: track.id,
                        name: track.name,
                        isEnabled: track.isEnabled,
                        defaultStyle: track.defaultStyle,
                        defaultScale: track.defaultScale,
                        defaultVisible: track.defaultVisible,
                        styleKeyframes: keyframes
                    )
                    self.timeline.tracks[trackIndex] = .cursor(track)
                }
            }
        )
    }

    private func keystrokeKeyframeBinding(for id: UUID) -> Binding<KeystrokeKeyframe>? {
        // Initial validation (ensure the keyframe exists)
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }),
              case .keystroke(let track) = timeline.tracks[trackIndex],
              track.keyframes.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                // Re-find the index by ID each time
                if case .keystroke(let track) = self.timeline.tracks[trackIndex],
                   let keyframeIndex = track.keyframes.firstIndex(where: { $0.id == id }) {
                    return track.keyframes[keyframeIndex]
                }
                return KeystrokeKeyframe(time: 0, displayText: "")
            },
            set: { newValue in
                // Re-find the index by ID each time
                if case .keystroke(var track) = self.timeline.tracks[trackIndex],
                   let keyframeIndex = track.keyframes.firstIndex(where: { $0.id == id }) {
                    track.keyframes[keyframeIndex] = newValue
                    self.timeline.tracks[trackIndex] = .keystroke(track)
                }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var timeline = Timeline(
            tracks: [
                AnyTrack(TransformTrack(
                    id: UUID(),
                    name: "Transform",
                    isEnabled: true,
                    keyframes: [
                        TransformKeyframe(time: 0, zoom: 1.0, centerX: 0.5, centerY: 0.5),
                        TransformKeyframe(time: 2, zoom: 2.0, centerX: 0.3, centerY: 0.4),
                    ]
                )),
                AnyTrack(RippleTrack(
                    id: UUID(),
                    name: "Ripple",
                    isEnabled: true,
                    keyframes: [
                        RippleKeyframe(time: 1, x: 0.3, y: 0.4),
                    ]
                )),
                AnyTrack(CursorTrack(
                    id: UUID(),
                    name: "Cursor",
                    isEnabled: true
                )),
            ],
            duration: 10
        )

        @State private var selectedKeyframeID: UUID?
        @State private var selectedTrackType: TrackType? = .transform
        @State private var renderSettings = RenderSettings()

        var body: some View {
            HStack(spacing: 0) {
                // Selection buttons
                VStack {
                    Button("Select Transform KF") {
                        selectedTrackType = .transform
                        if let track = timeline.transformTrack {
                            selectedKeyframeID = track.keyframes.first?.id
                        }
                    }

                    Button("Select Ripple KF") {
                        selectedTrackType = .ripple
                        if let track = timeline.rippleTrack {
                            selectedKeyframeID = track.keyframes.first?.id
                        }
                    }

                    Button("Select Track Only") {
                        selectedTrackType = .cursor
                        selectedKeyframeID = nil
                    }

                    Button("Clear Selection") {
                        selectedTrackType = nil
                        selectedKeyframeID = nil
                    }

                    Divider()

                    Toggle("Window Mode", isOn: .constant(true))
                }
                .padding()

                Divider()

                // Inspector
                InspectorView(
                    timeline: $timeline,
                    selectedKeyframeID: $selectedKeyframeID,
                    selectedTrackType: $selectedTrackType,
                    renderSettings: $renderSettings,
                    isWindowMode: true,
                    onKeyframeChange: {
                        print("Keyframe changed")
                    },
                    onDeleteKeyframe: { id, type in
                        print("Delete keyframe \(id) from \(type)")
                    }
                )
            }
            .frame(width: 500, height: 600)
        }
    }

    return PreviewWrapper()
}
