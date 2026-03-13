import SwiftUI

enum GenerationSettingsResetNotification: Equatable {
    case none
    case projectSettingsChanged(GenerationSettings)
}

struct GenerationSettingsView: View {
    @EnvironmentObject private var manager: GenerationSettingsManager
    @State private var showSavePresetSheet = false
    @State private var presetName = ""
    @State private var scope: SettingsScope = .appDefaults
    @State private var projectSettings: GenerationSettings?

    enum SettingsScope: String, CaseIterable {
        case appDefaults = "App Defaults"
        case thisProject = "This Project"
    }

    private var editingSettings: Binding<GenerationSettings> {
        switch scope {
        case .appDefaults:
            return $manager.settings
        case .thisProject:
            return Binding(
                get: { projectSettings ?? manager.settings },
                set: { newValue in
                    projectSettings = newValue
                    NotificationCenter.default.post(
                        name: .projectGenerationSettingsChanged,
                        object: nil,
                        userInfo: ["settings": newValue]
                    )
                }
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    // Generation Mode
                    SettingsSection(title: "Generation Mode") {
                        Picker("Mode", selection: editingSettings.mode) {
                            Text("Continuous").tag(GenerationMode.continuous)
                            Text("Segment Based").tag(GenerationMode.segmentBased)
                        }
                        .pickerStyle(.segmented)
                    }
                    cameraMotionSection
                    zoomSection
                    intentClassificationSection
                    timingSection
                    cursorKeystrokeSection
                }
                .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 400)
        .onChange(of: manager.settings) { _ in
            if scope == .appDefaults {
                manager.saveSettings()
            }
        }
        .onChange(of: scope) { newScope in
            if newScope == .thisProject {
                projectSettings = AppState.shared.currentProject?.generationSettings ?? manager.settings
            }
        }
        .sheet(isPresented: $showSavePresetSheet) {
            savePresetSheet
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Picker("", selection: $scope) {
                ForEach(SettingsScope.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Menu {
                Button("Save as Preset...") {
                    presetName = ""
                    showSavePresetSheet = true
                }
                if !manager.presets.isEmpty {
                    Divider()
                    ForEach(manager.presets) { preset in
                        Button(preset.name) {
                            manager.loadPreset(preset.id)
                        }
                    }
                    Divider()
                    Menu("Delete Preset") {
                        ForEach(manager.presets) { preset in
                            Button(preset.name, role: .destructive) {
                                manager.deletePreset(preset.id)
                            }
                        }
                    }
                }
            } label: {
                Label("Presets", systemImage: "archivebox")
            }

            Spacer()

            Button("Reset All") {
                resetAll()
            }

            Button {
                NotificationCenter.default.post(
                    name: .regenerateTimeline,
                    object: nil
                )
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func resetAll() {
        let notification = Self.resetAllState(
            scope: scope,
            appSettings: &manager.settings,
            projectSettings: &projectSettings
        )

        if case let .projectSettingsChanged(settings) = notification {
            NotificationCenter.default.post(
                name: .projectGenerationSettingsChanged,
                object: nil,
                userInfo: ["settings": settings]
            )
        }
    }

}

// MARK: - Section Views

extension GenerationSettingsView {

    static func resetAllState(
        scope: SettingsScope,
        appSettings: inout GenerationSettings,
        projectSettings: inout GenerationSettings?
    ) -> GenerationSettingsResetNotification {
        switch scope {
        case .appDefaults:
            appSettings = .default
            return .none
        case .thisProject:
            projectSettings = .default
            return .projectSettingsChanged(.default)
        }
    }

    // MARK: - Camera Motion Section

    var cameraMotionSection: some View {
        SettingsSection(title: "Camera Motion") {
            SettingSlider(
                label: "Position Damping",
                value: editingSettings.cameraMotion.positionDampingRatio,
                range: 0.1...1.0, defaultValue: 0.90)
            SettingSlider(
                label: "Position Response",
                value: editingSettings.cameraMotion.positionResponse,
                range: 0.05...2.0, defaultValue: 0.35, unit: "s")
            SettingSlider(
                label: "Zoom Damping",
                value: editingSettings.cameraMotion.zoomDampingRatio,
                range: 0.1...1.0, defaultValue: 0.90)
            SettingSlider(
                label: "Zoom Response",
                value: editingSettings.cameraMotion.zoomResponse,
                range: 0.05...2.0, defaultValue: 0.55, unit: "s")
            SettingSlider(
                label: "Boundary Stiffness",
                value: editingSettings.cameraMotion.boundaryStiffness,
                range: 1.0...30.0, defaultValue: 12.0)
            SettingSlider(
                label: "Zoom Settle Threshold",
                value: editingSettings.cameraMotion.zoomSettleThreshold,
                range: 0.001...0.1, defaultValue: 0.02)

            Divider()
            Text("Urgency Multipliers")
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: "Immediate",
                value: editingSettings.cameraMotion.urgencyImmediateMultiplier,
                range: 0.01...1.0, defaultValue: 0.05)
            SettingSlider(
                label: "High",
                value: editingSettings.cameraMotion.urgencyHighMultiplier,
                range: 0.1...2.0, defaultValue: 0.5)
            SettingSlider(
                label: "Normal",
                value: editingSettings.cameraMotion.urgencyNormalMultiplier,
                range: 0.5...3.0, defaultValue: 1.0)
            SettingSlider(
                label: "Lazy",
                value: editingSettings.cameraMotion.urgencyLazyMultiplier,
                range: 1.0...5.0, defaultValue: 2.0)
            SettingSlider(
                label: "Blend Duration",
                value: editingSettings.cameraMotion.urgencyBlendDuration,
                range: 0.1...2.0, defaultValue: 0.5, unit: "s")

            Divider()
            Text("Dead Zone")
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: "Safe Zone Fraction",
                value: editingSettings.cameraMotion.safeZoneFraction,
                range: 0.3...1.0, defaultValue: 0.75)
            SettingSlider(
                label: "Safe Zone (Typing)",
                value: editingSettings.cameraMotion.safeZoneFractionTyping,
                range: 0.3...1.0, defaultValue: 0.60)
            SettingSlider(
                label: "Gradient Band Width",
                value: editingSettings.cameraMotion.gradientBandWidth,
                range: 0.05...0.5, defaultValue: 0.25)
            SettingSlider(
                label: "Correction Fraction",
                value: editingSettings.cameraMotion.correctionFraction,
                range: 0.1...1.0, defaultValue: 0.45)
            SettingSlider(
                label: "Hysteresis Margin",
                value: editingSettings.cameraMotion.hysteresisMargin,
                range: 0.01...0.5, defaultValue: 0.15)
            SettingSlider(
                label: "Correction (Typing)",
                value: editingSettings.cameraMotion.correctionFractionTyping,
                range: 0.1...1.0, defaultValue: 0.80)
            SettingSlider(
                label: "Min Response",
                value: editingSettings.cameraMotion.deadZoneMinResponse,
                range: 0.05...1.0, defaultValue: 0.20, unit: "s")
            SettingSlider(
                label: "Max Response",
                value: editingSettings.cameraMotion.deadZoneMaxResponse,
                range: 0.1...2.0, defaultValue: 0.50, unit: "s")

            Divider()
            Text("Micro Tracker")
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: "Idle Velocity Threshold",
                value: editingSettings.cameraMotion.idleVelocityThreshold,
                range: 0.001...0.1, defaultValue: 0.02)
            SettingSlider(
                label: "Damping Ratio",
                value: editingSettings.cameraMotion.microTrackerDampingRatio,
                range: 0.1...2.0, defaultValue: 1.0)
            SettingSlider(
                label: "Response",
                value: editingSettings.cameraMotion.microTrackerResponse,
                range: 0.5...10.0, defaultValue: 3.0, unit: "s")
        }
    }

    // MARK: - Zoom Section

    var zoomSection: some View {
        SettingsSection(title: "Zoom Levels") {
            Text("Per-Activity Zoom Ranges")
                .font(.caption).foregroundColor(.secondary)
            RangeSettingSlider(
                label: "Typing (Code)",
                min: editingSettings.zoom.typingCodeZoomMin,
                max: editingSettings.zoom.typingCodeZoomMax,
                range: 1.0...4.0, defaultMin: 2.0, defaultMax: 2.5)
            RangeSettingSlider(
                label: "Typing (Text Field)",
                min: editingSettings.zoom.typingTextFieldZoomMin,
                max: editingSettings.zoom.typingTextFieldZoomMax,
                range: 1.0...4.0, defaultMin: 2.2, defaultMax: 2.8)
            RangeSettingSlider(
                label: "Typing (Terminal)",
                min: editingSettings.zoom.typingTerminalZoomMin,
                max: editingSettings.zoom.typingTerminalZoomMax,
                range: 1.0...4.0, defaultMin: 1.6, defaultMax: 2.0)
            RangeSettingSlider(
                label: "Typing (Rich Text)",
                min: editingSettings.zoom.typingRichTextZoomMin,
                max: editingSettings.zoom.typingRichTextZoomMax,
                range: 1.0...4.0, defaultMin: 1.8, defaultMax: 2.2)
            RangeSettingSlider(
                label: "Clicking",
                min: editingSettings.zoom.clickingZoomMin,
                max: editingSettings.zoom.clickingZoomMax,
                range: 1.0...4.0, defaultMin: 1.5, defaultMax: 2.5)
            RangeSettingSlider(
                label: "Navigating",
                min: editingSettings.zoom.navigatingZoomMin,
                max: editingSettings.zoom.navigatingZoomMax,
                range: 1.0...4.0, defaultMin: 1.5, defaultMax: 1.8)
            RangeSettingSlider(
                label: "Dragging",
                min: editingSettings.zoom.draggingZoomMin,
                max: editingSettings.zoom.draggingZoomMax,
                range: 1.0...4.0, defaultMin: 1.3, defaultMax: 1.6)
            RangeSettingSlider(
                label: "Scrolling",
                min: editingSettings.zoom.scrollingZoomMin,
                max: editingSettings.zoom.scrollingZoomMax,
                range: 1.0...4.0, defaultMin: 1.3, defaultMax: 1.5)
            RangeSettingSlider(
                label: "Reading",
                min: editingSettings.zoom.readingZoomMin,
                max: editingSettings.zoom.readingZoomMax,
                range: 1.0...4.0, defaultMin: 1.0, defaultMax: 1.3)

            Divider()
            Text("Fixed Zoom Levels")
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: "Switching",
                value: editingSettings.zoom.switchingZoom,
                range: 0.5...3.0, defaultValue: 1.0)
            SettingSlider(
                label: "Idle",
                value: editingSettings.zoom.idleZoom,
                range: 0.5...3.0, defaultValue: 1.0)

            Divider()
            Text("Global Limits")
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: "Target Area Coverage",
                value: editingSettings.zoom.targetAreaCoverage,
                range: 0.3...1.0, defaultValue: 0.7)
            SettingSlider(
                label: "Work Area Padding",
                value: editingSettings.zoom.workAreaPadding,
                range: 0.0...0.3, defaultValue: 0.08)
            SettingSlider(
                label: "Min Zoom",
                value: editingSettings.zoom.minZoom,
                range: 0.5...2.0, defaultValue: 1.0)
            SettingSlider(
                label: "Max Zoom",
                value: editingSettings.zoom.maxZoom,
                range: 1.5...5.0, defaultValue: 2.8)
            SettingSlider(
                label: "Idle Zoom Decay",
                value: editingSettings.zoom.idleZoomDecay,
                range: 0.0...1.0, defaultValue: 0.5)
            SettingSlider(
                label: "Zoom Intensity",
                value: editingSettings.zoom.zoomIntensity,
                range: 0.0...3.0, defaultValue: 1.0)
        }
    }

    // MARK: - Intent Classification Section

    var intentClassificationSection: some View {
        SettingsSection(title: "Intent Classification") {
            SettingSlider(
                label: "Typing Session Timeout",
                value: editingSettings.intentClassification.typingSessionTimeout,
                range: 0.5...5.0, defaultValue: 1.5, unit: "s")
            SettingSlider(
                label: "Navigating Click Window",
                value: editingSettings.intentClassification.navigatingClickWindow,
                range: 0.5...5.0, defaultValue: 2.0, unit: "s")
            SettingSlider(
                label: "Nav Click Distance",
                value: editingSettings.intentClassification.navigatingClickDistance,
                range: 0.1...1.0, defaultValue: 0.5)
            SettingStepper(
                label: "Nav Min Clicks",
                value: editingSettings.intentClassification.navigatingMinClicks,
                range: 1...10, defaultValue: 2)
            SettingSlider(
                label: "Idle Threshold",
                value: editingSettings.intentClassification.idleThreshold,
                range: 1.0...15.0, defaultValue: 5.0, unit: "s")
            SettingSlider(
                label: "Continuation Gap",
                value: editingSettings.intentClassification.continuationGapThreshold,
                range: 0.5...5.0, defaultValue: 1.5, unit: "s")
            SettingSlider(
                label: "Continuation Max Distance",
                value: editingSettings.intentClassification.continuationMaxDistance,
                range: 0.05...0.5, defaultValue: 0.20)
            SettingSlider(
                label: "Scroll Merge Gap",
                value: editingSettings.intentClassification.scrollMergeGap,
                range: 0.2...3.0, defaultValue: 1.0, unit: "s")
            SettingSlider(
                label: "Point Span Duration",
                value: editingSettings.intentClassification.pointSpanDuration,
                range: 0.1...2.0, defaultValue: 0.5, unit: "s")
            SettingSlider(
                label: "Context Change Window",
                value: editingSettings.intentClassification.contextChangeWindow,
                range: 0.2...3.0, defaultValue: 0.8, unit: "s")
            SettingSlider(
                label: "Typing Anticipation",
                value: editingSettings.intentClassification.typingAnticipation,
                range: 0.0...1.5, defaultValue: 0.4, unit: "s")
        }
    }

    // MARK: - Timing Section

    var timingSection: some View {
        SettingsSection(title: "Timing") {
            Text("Lead Times")
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: "Immediate",
                value: editingSettings.timing.leadTimeImmediate,
                range: 0.0...1.0, defaultValue: 0.24, unit: "s")
            SettingSlider(
                label: "High",
                value: editingSettings.timing.leadTimeHigh,
                range: 0.0...1.0, defaultValue: 0.16, unit: "s")
            SettingSlider(
                label: "Normal",
                value: editingSettings.timing.leadTimeNormal,
                range: 0.0...1.0, defaultValue: 0.08, unit: "s")
            SettingSlider(
                label: "Lazy",
                value: editingSettings.timing.leadTimeLazy,
                range: 0.0...1.0, defaultValue: 0.0, unit: "s")

            Divider()
            Text("Simulation")
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: "Tick Rate",
                value: editingSettings.timing.tickRate,
                range: 24.0...120.0, defaultValue: 60.0, unit: "Hz")
            SettingSlider(
                label: "Typing Detail Min Interval",
                value: editingSettings.timing.typingDetailMinInterval,
                range: 0.05...1.0, defaultValue: 0.2, unit: "s")
            SettingSlider(
                label: "Typing Detail Min Distance",
                value: editingSettings.timing.typingDetailMinDistance,
                range: 0.005...0.1, defaultValue: 0.025)

            Divider()
            Text("Response Thresholds")
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: "Fast Threshold",
                value: editingSettings.timing.responseFastThreshold,
                range: 0.1...2.0, defaultValue: 0.5, unit: "s")
            SettingSlider(
                label: "Slow Threshold",
                value: editingSettings.timing.responseSlowThreshold,
                range: 1.0...5.0, defaultValue: 2.0, unit: "s")
        }
    }

    // MARK: - Cursor & Keystroke Section

    var cursorKeystrokeSection: some View {
        SettingsSection(title: "Cursor & Keystroke") {
            SettingSlider(
                label: "Cursor Scale",
                value: editingSettings.cursorKeystroke.cursorScale,
                range: 0.5...5.0, defaultValue: 2.0, unit: "x")

            Divider()
            Text("Keystroke Overlay")
                .font(.caption).foregroundColor(.secondary)
            Toggle(
                "Enabled",
                isOn: editingSettings.cursorKeystroke.keystrokeEnabled)
            Toggle(
                "Shortcuts Only",
                isOn: editingSettings.cursorKeystroke.shortcutsOnly)
            SettingSlider(
                label: "Display Duration",
                value: editingSettings.cursorKeystroke.displayDuration,
                range: 0.5...5.0, defaultValue: 1.5, unit: "s")
            SettingSlider(
                label: "Fade In",
                value: editingSettings.cursorKeystroke.fadeInDuration,
                range: 0.0...1.0, defaultValue: 0.15, unit: "s")
            SettingSlider(
                label: "Fade Out",
                value: editingSettings.cursorKeystroke.fadeOutDuration,
                range: 0.0...1.0, defaultValue: 0.3, unit: "s")
            SettingSlider(
                label: "Min Interval",
                value: editingSettings.cursorKeystroke.minInterval,
                range: 0.01...0.5, defaultValue: 0.05, unit: "s")
        }
    }

    // MARK: - Save Preset Sheet

    var savePresetSheet: some View {
        VStack(spacing: 16) {
            Text("Save Preset").font(.headline)
            TextField("Preset Name", text: $presetName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showSavePresetSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard !presetName.isEmpty else { return }
                    manager.savePreset(name: presetName)
                    showSavePresetSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let regenerateTimeline = Notification.Name("regenerateTimeline")
    static let projectGenerationSettingsChanged = Notification.Name("projectGenerationSettingsChanged")
}
