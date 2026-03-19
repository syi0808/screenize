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

    enum SettingsScope: CaseIterable {
        case appDefaults
        case thisProject

        var title: String {
            switch self {
            case .appDefaults:
                return L10n.string("generation_settings.scope.app_defaults", defaultValue: "App Defaults")
            case .thisProject:
                return L10n.string("generation_settings.scope.this_project", defaultValue: "This Project")
            }
        }
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
                    SettingsSection(
                        title: L10n.string("generation_settings.section.mode", defaultValue: "Generation Mode")
                    ) {
                        Picker(L10n.string("generation_settings.mode", defaultValue: "Mode"), selection: editingSettings.mode) {
                            Text(L10n.string("generation_settings.mode.continuous", defaultValue: "Continuous"))
                                .tag(GenerationMode.continuous)
                            Text(L10n.string("generation_settings.mode.segment_based", defaultValue: "Segment Based"))
                                .tag(GenerationMode.segmentBased)
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
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Menu {
                Button(L10n.string("generation_settings.menu.save_preset", defaultValue: "Save as Preset...")) {
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
                    Menu(L10n.string("generation_settings.menu.delete_preset", defaultValue: "Delete Preset")) {
                        ForEach(manager.presets) { preset in
                            Button(preset.name, role: .destructive) {
                                manager.deletePreset(preset.id)
                            }
                        }
                    }
                }
            } label: {
                Label(L10n.string("generation_settings.menu.presets", defaultValue: "Presets"), systemImage: "archivebox")
            }

            Spacer()

            Button(L10n.string("generation_settings.action.reset_all", defaultValue: "Reset All")) {
                resetAll()
            }

            Button {
                NotificationCenter.default.post(
                    name: .regenerateTimeline,
                    object: nil
                )
            } label: {
                Label(L10n.string("generation_settings.action.regenerate", defaultValue: "Regenerate"), systemImage: "arrow.clockwise")
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
        SettingsSection(title: L10n.string("generation_settings.section.camera_motion", defaultValue: "Camera Motion")) {
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.position_damping", defaultValue: "Position Damping"),
                value: editingSettings.cameraMotion.positionDampingRatio,
                range: 0.1...1.0, defaultValue: 0.90)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.position_response", defaultValue: "Position Response"),
                value: editingSettings.cameraMotion.positionResponse,
                range: 0.05...2.0, defaultValue: 0.35, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.zoom_damping", defaultValue: "Zoom Damping"),
                value: editingSettings.cameraMotion.zoomDampingRatio,
                range: 0.1...1.0, defaultValue: 0.90)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.zoom_response", defaultValue: "Zoom Response"),
                value: editingSettings.cameraMotion.zoomResponse,
                range: 0.05...2.0, defaultValue: 0.55, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.boundary_stiffness", defaultValue: "Boundary Stiffness"),
                value: editingSettings.cameraMotion.boundaryStiffness,
                range: 1.0...30.0, defaultValue: 12.0)
            SettingSlider(
                label: L10n.string(
                    "generation_settings.camera_motion.zoom_settle_threshold",
                    defaultValue: "Zoom Settle Threshold"
                ),
                value: editingSettings.cameraMotion.zoomSettleThreshold,
                range: 0.001...0.1, defaultValue: 0.02)

            Divider()
            Text(L10n.string("generation_settings.subsection.urgency_multipliers", defaultValue: "Urgency Multipliers"))
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.immediate", defaultValue: "Immediate"),
                value: editingSettings.cameraMotion.urgencyImmediateMultiplier,
                range: 0.01...1.0, defaultValue: 0.05)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.high", defaultValue: "High"),
                value: editingSettings.cameraMotion.urgencyHighMultiplier,
                range: 0.1...2.0, defaultValue: 0.5)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.normal", defaultValue: "Normal"),
                value: editingSettings.cameraMotion.urgencyNormalMultiplier,
                range: 0.5...3.0, defaultValue: 1.0)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.lazy", defaultValue: "Lazy"),
                value: editingSettings.cameraMotion.urgencyLazyMultiplier,
                range: 1.0...5.0, defaultValue: 2.0)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.blend_duration", defaultValue: "Blend Duration"),
                value: editingSettings.cameraMotion.urgencyBlendDuration,
                range: 0.1...2.0, defaultValue: 0.5, unit: "s")

            Divider()
            Text(L10n.string("generation_settings.subsection.dead_zone", defaultValue: "Dead Zone"))
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.safe_zone_fraction", defaultValue: "Safe Zone Fraction"),
                value: editingSettings.cameraMotion.safeZoneFraction,
                range: 0.3...1.0, defaultValue: 0.75)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.safe_zone_typing", defaultValue: "Safe Zone (Typing)"),
                value: editingSettings.cameraMotion.safeZoneFractionTyping,
                range: 0.3...1.0, defaultValue: 0.60)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.gradient_band_width", defaultValue: "Gradient Band Width"),
                value: editingSettings.cameraMotion.gradientBandWidth,
                range: 0.05...0.5, defaultValue: 0.25)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.correction_fraction", defaultValue: "Correction Fraction"),
                value: editingSettings.cameraMotion.correctionFraction,
                range: 0.1...1.0, defaultValue: 0.45)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.hysteresis_margin", defaultValue: "Hysteresis Margin"),
                value: editingSettings.cameraMotion.hysteresisMargin,
                range: 0.01...0.5, defaultValue: 0.15)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.correction_typing", defaultValue: "Correction (Typing)"),
                value: editingSettings.cameraMotion.correctionFractionTyping,
                range: 0.1...1.0, defaultValue: 0.80)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.min_response", defaultValue: "Min Response"),
                value: editingSettings.cameraMotion.deadZoneMinResponse,
                range: 0.05...1.0, defaultValue: 0.20, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.max_response", defaultValue: "Max Response"),
                value: editingSettings.cameraMotion.deadZoneMaxResponse,
                range: 0.1...2.0, defaultValue: 0.50, unit: "s")

            Divider()
            Text(L10n.string("generation_settings.subsection.micro_tracker", defaultValue: "Micro Tracker"))
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: L10n.string(
                    "generation_settings.camera_motion.idle_velocity_threshold",
                    defaultValue: "Idle Velocity Threshold"
                ),
                value: editingSettings.cameraMotion.idleVelocityThreshold,
                range: 0.001...0.1, defaultValue: 0.02)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.damping_ratio", defaultValue: "Damping Ratio"),
                value: editingSettings.cameraMotion.microTrackerDampingRatio,
                range: 0.1...2.0, defaultValue: 1.0)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.response", defaultValue: "Response"),
                value: editingSettings.cameraMotion.microTrackerResponse,
                range: 0.5...10.0, defaultValue: 3.0, unit: "s")
        }
    }

    // MARK: - Zoom Section

    var zoomSection: some View {
        SettingsSection(title: L10n.string("generation_settings.section.zoom_levels", defaultValue: "Zoom Levels")) {
            Text(L10n.string("generation_settings.subsection.per_activity_zoom_ranges", defaultValue: "Per-Activity Zoom Ranges"))
                .font(.caption).foregroundColor(.secondary)
            RangeSettingSlider(
                label: L10n.string("generation_settings.zoom.typing_code", defaultValue: "Typing (Code)"),
                min: editingSettings.zoom.typingCodeZoomMin,
                max: editingSettings.zoom.typingCodeZoomMax,
                range: 1.0...4.0, defaultMin: 2.0, defaultMax: 2.5)
            RangeSettingSlider(
                label: L10n.string("generation_settings.zoom.typing_text_field", defaultValue: "Typing (Text Field)"),
                min: editingSettings.zoom.typingTextFieldZoomMin,
                max: editingSettings.zoom.typingTextFieldZoomMax,
                range: 1.0...4.0, defaultMin: 2.2, defaultMax: 2.8)
            RangeSettingSlider(
                label: L10n.string("generation_settings.zoom.typing_terminal", defaultValue: "Typing (Terminal)"),
                min: editingSettings.zoom.typingTerminalZoomMin,
                max: editingSettings.zoom.typingTerminalZoomMax,
                range: 1.0...4.0, defaultMin: 1.6, defaultMax: 2.0)
            RangeSettingSlider(
                label: L10n.string("generation_settings.zoom.typing_rich_text", defaultValue: "Typing (Rich Text)"),
                min: editingSettings.zoom.typingRichTextZoomMin,
                max: editingSettings.zoom.typingRichTextZoomMax,
                range: 1.0...4.0, defaultMin: 1.8, defaultMax: 2.2)
            RangeSettingSlider(
                label: L10n.string("generation_settings.zoom.clicking", defaultValue: "Clicking"),
                min: editingSettings.zoom.clickingZoomMin,
                max: editingSettings.zoom.clickingZoomMax,
                range: 1.0...4.0, defaultMin: 1.5, defaultMax: 2.5)
            RangeSettingSlider(
                label: L10n.string("generation_settings.zoom.navigating", defaultValue: "Navigating"),
                min: editingSettings.zoom.navigatingZoomMin,
                max: editingSettings.zoom.navigatingZoomMax,
                range: 1.0...4.0, defaultMin: 1.5, defaultMax: 1.8)
            RangeSettingSlider(
                label: L10n.string("generation_settings.zoom.dragging", defaultValue: "Dragging"),
                min: editingSettings.zoom.draggingZoomMin,
                max: editingSettings.zoom.draggingZoomMax,
                range: 1.0...4.0, defaultMin: 1.3, defaultMax: 1.6)
            RangeSettingSlider(
                label: L10n.string("generation_settings.zoom.scrolling", defaultValue: "Scrolling"),
                min: editingSettings.zoom.scrollingZoomMin,
                max: editingSettings.zoom.scrollingZoomMax,
                range: 1.0...4.0, defaultMin: 1.3, defaultMax: 1.5)
            RangeSettingSlider(
                label: L10n.string("generation_settings.zoom.reading", defaultValue: "Reading"),
                min: editingSettings.zoom.readingZoomMin,
                max: editingSettings.zoom.readingZoomMax,
                range: 1.0...4.0, defaultMin: 1.0, defaultMax: 1.3)

            Divider()
            Text(L10n.string("generation_settings.subsection.fixed_zoom_levels", defaultValue: "Fixed Zoom Levels"))
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: L10n.string("generation_settings.zoom.switching", defaultValue: "Switching"),
                value: editingSettings.zoom.switchingZoom,
                range: 0.5...3.0, defaultValue: 1.0)
            SettingSlider(
                label: L10n.string("generation_settings.zoom.idle", defaultValue: "Idle"),
                value: editingSettings.zoom.idleZoom,
                range: 0.5...3.0, defaultValue: 1.0)

            Divider()
            Text(L10n.string("generation_settings.subsection.global_limits", defaultValue: "Global Limits"))
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: L10n.string("generation_settings.zoom.target_area_coverage", defaultValue: "Target Area Coverage"),
                value: editingSettings.zoom.targetAreaCoverage,
                range: 0.3...1.0, defaultValue: 0.7)
            SettingSlider(
                label: L10n.string("generation_settings.zoom.work_area_padding", defaultValue: "Work Area Padding"),
                value: editingSettings.zoom.workAreaPadding,
                range: 0.0...0.3, defaultValue: 0.08)
            SettingSlider(
                label: L10n.string("generation_settings.zoom.min_zoom", defaultValue: "Min Zoom"),
                value: editingSettings.zoom.minZoom,
                range: 0.5...2.0, defaultValue: 1.0)
            SettingSlider(
                label: L10n.string("generation_settings.zoom.max_zoom", defaultValue: "Max Zoom"),
                value: editingSettings.zoom.maxZoom,
                range: 1.5...5.0, defaultValue: 2.8)
            SettingSlider(
                label: L10n.string("generation_settings.zoom.idle_zoom_decay", defaultValue: "Idle Zoom Decay"),
                value: editingSettings.zoom.idleZoomDecay,
                range: 0.0...1.0, defaultValue: 0.5)
            SettingSlider(
                label: L10n.string("generation_settings.zoom.zoom_intensity", defaultValue: "Zoom Intensity"),
                value: editingSettings.zoom.zoomIntensity,
                range: 0.0...3.0, defaultValue: 1.0)
        }
    }

    // MARK: - Intent Classification Section

    var intentClassificationSection: some View {
        SettingsSection(
            title: L10n.string("generation_settings.section.intent_classification", defaultValue: "Intent Classification")
        ) {
            SettingSlider(
                label: L10n.string("generation_settings.intent.typing_session_timeout", defaultValue: "Typing Session Timeout"),
                value: editingSettings.intentClassification.typingSessionTimeout,
                range: 0.5...5.0, defaultValue: 1.5, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.intent.navigating_click_window", defaultValue: "Navigating Click Window"),
                value: editingSettings.intentClassification.navigatingClickWindow,
                range: 0.5...5.0, defaultValue: 2.0, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.intent.nav_click_distance", defaultValue: "Nav Click Distance"),
                value: editingSettings.intentClassification.navigatingClickDistance,
                range: 0.1...1.0, defaultValue: 0.5)
            SettingStepper(
                label: L10n.string("generation_settings.intent.nav_min_clicks", defaultValue: "Nav Min Clicks"),
                value: editingSettings.intentClassification.navigatingMinClicks,
                range: 1...10, defaultValue: 2)
            SettingSlider(
                label: L10n.string("generation_settings.intent.idle_threshold", defaultValue: "Idle Threshold"),
                value: editingSettings.intentClassification.idleThreshold,
                range: 1.0...15.0, defaultValue: 5.0, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.intent.continuation_gap", defaultValue: "Continuation Gap"),
                value: editingSettings.intentClassification.continuationGapThreshold,
                range: 0.5...5.0, defaultValue: 1.5, unit: "s")
            SettingSlider(
                label: L10n.string(
                    "generation_settings.intent.continuation_max_distance",
                    defaultValue: "Continuation Max Distance"
                ),
                value: editingSettings.intentClassification.continuationMaxDistance,
                range: 0.05...0.5, defaultValue: 0.20)
            SettingSlider(
                label: L10n.string("generation_settings.intent.scroll_merge_gap", defaultValue: "Scroll Merge Gap"),
                value: editingSettings.intentClassification.scrollMergeGap,
                range: 0.2...3.0, defaultValue: 1.0, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.intent.point_span_duration", defaultValue: "Point Span Duration"),
                value: editingSettings.intentClassification.pointSpanDuration,
                range: 0.1...2.0, defaultValue: 0.5, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.intent.context_change_window", defaultValue: "Context Change Window"),
                value: editingSettings.intentClassification.contextChangeWindow,
                range: 0.2...3.0, defaultValue: 0.8, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.intent.typing_anticipation", defaultValue: "Typing Anticipation"),
                value: editingSettings.intentClassification.typingAnticipation,
                range: 0.0...1.5, defaultValue: 0.4, unit: "s")
        }
    }

    // MARK: - Timing Section

    var timingSection: some View {
        SettingsSection(title: L10n.string("generation_settings.section.timing", defaultValue: "Timing")) {
            Text(L10n.string("generation_settings.subsection.lead_times", defaultValue: "Lead Times"))
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.immediate", defaultValue: "Immediate"),
                value: editingSettings.timing.leadTimeImmediate,
                range: 0.0...1.0, defaultValue: 0.24, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.high", defaultValue: "High"),
                value: editingSettings.timing.leadTimeHigh,
                range: 0.0...1.0, defaultValue: 0.16, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.normal", defaultValue: "Normal"),
                value: editingSettings.timing.leadTimeNormal,
                range: 0.0...1.0, defaultValue: 0.08, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.camera_motion.lazy", defaultValue: "Lazy"),
                value: editingSettings.timing.leadTimeLazy,
                range: 0.0...1.0, defaultValue: 0.0, unit: "s")

            Divider()
            Text(L10n.string("generation_settings.subsection.simulation", defaultValue: "Simulation"))
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: L10n.string("generation_settings.timing.tick_rate", defaultValue: "Tick Rate"),
                value: editingSettings.timing.tickRate,
                range: 24.0...120.0, defaultValue: 60.0, unit: "Hz")
            SettingSlider(
                label: L10n.string(
                    "generation_settings.timing.typing_detail_min_interval",
                    defaultValue: "Typing Detail Min Interval"
                ),
                value: editingSettings.timing.typingDetailMinInterval,
                range: 0.05...1.0, defaultValue: 0.2, unit: "s")
            SettingSlider(
                label: L10n.string(
                    "generation_settings.timing.typing_detail_min_distance",
                    defaultValue: "Typing Detail Min Distance"
                ),
                value: editingSettings.timing.typingDetailMinDistance,
                range: 0.005...0.1, defaultValue: 0.025)

            Divider()
            Text(L10n.string("generation_settings.subsection.response_thresholds", defaultValue: "Response Thresholds"))
                .font(.caption).foregroundColor(.secondary)
            SettingSlider(
                label: L10n.string("generation_settings.timing.fast_threshold", defaultValue: "Fast Threshold"),
                value: editingSettings.timing.responseFastThreshold,
                range: 0.1...2.0, defaultValue: 0.5, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.timing.slow_threshold", defaultValue: "Slow Threshold"),
                value: editingSettings.timing.responseSlowThreshold,
                range: 1.0...5.0, defaultValue: 2.0, unit: "s")
        }
    }

    // MARK: - Cursor & Keystroke Section

    var cursorKeystrokeSection: some View {
        SettingsSection(
            title: L10n.string("generation_settings.section.cursor_keystroke", defaultValue: "Cursor & Keystroke")
        ) {
            SettingSlider(
                label: L10n.string("generation_settings.cursor_keystroke.cursor_scale", defaultValue: "Cursor Scale"),
                value: editingSettings.cursorKeystroke.cursorScale,
                range: 0.5...5.0, defaultValue: 2.0, unit: "x")

            Divider()
            Text(L10n.string("generation_settings.subsection.keystroke_overlay", defaultValue: "Keystroke Overlay"))
                .font(.caption).foregroundColor(.secondary)
            Toggle(
                L10n.string("generation_settings.cursor_keystroke.enabled", defaultValue: "Enabled"),
                isOn: editingSettings.cursorKeystroke.keystrokeEnabled)
            Toggle(
                L10n.string("generation_settings.cursor_keystroke.shortcuts_only", defaultValue: "Shortcuts Only"),
                isOn: editingSettings.cursorKeystroke.shortcutsOnly)
            SettingSlider(
                label: L10n.string("generation_settings.cursor_keystroke.display_duration", defaultValue: "Display Duration"),
                value: editingSettings.cursorKeystroke.displayDuration,
                range: 0.5...5.0, defaultValue: 1.5, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.cursor_keystroke.fade_in", defaultValue: "Fade In"),
                value: editingSettings.cursorKeystroke.fadeInDuration,
                range: 0.0...1.0, defaultValue: 0.15, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.cursor_keystroke.fade_out", defaultValue: "Fade Out"),
                value: editingSettings.cursorKeystroke.fadeOutDuration,
                range: 0.0...1.0, defaultValue: 0.3, unit: "s")
            SettingSlider(
                label: L10n.string("generation_settings.cursor_keystroke.min_interval", defaultValue: "Min Interval"),
                value: editingSettings.cursorKeystroke.minInterval,
                range: 0.01...0.5, defaultValue: 0.05, unit: "s")
        }
    }

    // MARK: - Save Preset Sheet

    var savePresetSheet: some View {
        VStack(spacing: 16) {
            Text(L10n.string("generation_settings.sheet.save_preset", defaultValue: "Save Preset")).font(.headline)
            TextField(L10n.string("generation_settings.sheet.preset_name", defaultValue: "Preset Name"), text: $presetName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(L10n.string("generation_settings.sheet.cancel", defaultValue: "Cancel")) { showSavePresetSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("generation_settings.sheet.save", defaultValue: "Save")) {
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
