import SwiftUI

/// Inspector panel for a single ScenarioStep, showing type-specific editing controls.
struct ScenarioInspectorView: View {

    @Binding var step: ScenarioStep

    /// Whether raw recording events are available (shows "Generate from recording" button).
    var hasRawEvents: Bool = false

    /// Called when the user requests waypoint generation; passes (stepId, hz).
    var onGenerateWaypoints: ((UUID, Int) -> Void)?

    @State private var selectedHz: Int = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                commonSection

                Divider()

                typeSpecificSection

                Divider()

                timingSection
            }
            .padding(12)
        }
    }

    // MARK: - Type-Specific Dispatch

    @ViewBuilder
    private var typeSpecificSection: some View {
        switch step.type {
        case .mouseMove:
            mouseMoveSection
        case .click, .doubleClick, .rightClick:
            clickSection
        case .keyboard:
            keyboardSection
        case .typeText:
            typeTextSection
        case .scroll:
            scrollSection
        case .activateApp:
            activateAppSection
        case .wait:
            EmptyView()
        case .mouseDown, .mouseUp:
            mouseDownUpSection
        }
    }

    // MARK: - Common Section

    private var commonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Type") {
                Picker("", selection: $step.type) {
                    ForEach(ScenarioStep.StepType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .frame(width: 140)
            }
            .onChange(of: step.type) { newType in
                clearFieldsForType(newType)
            }

            LabeledContent("Description") {
                TextField("Description", text: $step.description)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
        }
    }

    /// Clear type-specific fields that do not apply to the new step type.
    private func clearFieldsForType(_ newType: ScenarioStep.StepType) {
        let usesTarget: Set<ScenarioStep.StepType> = [
            .click, .doubleClick, .rightClick, .scroll, .mouseDown, .mouseUp
        ]
        if !usesTarget.contains(newType) {
            step.target = nil
        }
        if newType != .mouseMove {
            step.path = nil
        }
        if newType != .keyboard {
            step.keyCombo = nil
        }
        if newType != .typeText {
            step.content = nil
            step.typingSpeedMs = nil
        }
        if newType != .activateApp {
            step.app = nil
        }
        if newType != .scroll {
            step.direction = nil
            step.amount = nil
        }
    }

    // MARK: - Mouse Move Section

    private var mouseMoveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            pathModePicker

            if case .waypoints(let points)? = step.path {
                Text("Waypoints: \(points.count) points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hasRawEvents, step.rawTimeRange != nil {
                HStack {
                    Button("Generate from recording") {
                        onGenerateWaypoints?(step.id, selectedHz)
                    }
                    .font(.caption)

                    Picker("Hz", selection: $selectedHz) {
                        ForEach([1, 2, 5, 10, 15, 30], id: \.self) { hz in
                            Text("\(hz)").tag(hz)
                        }
                    }
                    .frame(width: 60)
                }
            }
        }
    }

    private var pathModePicker: some View {
        Picker("Path", selection: Binding(
            get: {
                if case .waypoints = step.path { return 1 }
                return 0
            },
            set: { newValue in
                if newValue == 0 {
                    step.path = .auto
                } else {
                    step.path = .waypoints(points: [])
                }
            }
        )) {
            Text("Auto (Bezier)").tag(0)
            Text("Waypoints").tag(1)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Click Section (click, double_click, right_click)

    private var clickSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let target = step.target {
                Text("Target").font(.caption.weight(.medium))

                LabeledContent("Role") {
                    Text(target.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let title = target.axTitle {
                    LabeledContent("Title") {
                        Text(title).font(.caption)
                    }
                }

                LabeledContent("Path") {
                    Text(target.path.joined(separator: " > "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Position") {
                    Text("(\(String(format: "%.2f", target.positionHint.x)), \(String(format: "%.2f", target.positionHint.y)))")
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    // MARK: - Keyboard Section

    private var keyboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keys").font(.caption.weight(.medium))

            LabeledContent("Combo") {
                TextField("Key combo", text: Binding(
                    get: { step.keyCombo ?? "" },
                    set: { step.keyCombo = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospacedDigit())
            }
        }
    }

    // MARK: - Type Text Section

    private var typeTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text").font(.caption.weight(.medium))

            LabeledContent("Content") {
                TextField("Text", text: Binding(
                    get: { step.content ?? "" },
                    set: { step.content = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            }

            LabeledContent("Typing speed") {
                HStack {
                    TextField("ms/char", value: Binding(
                        get: { step.typingSpeedMs ?? 50 },
                        set: { step.typingSpeedMs = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)

                    Text("ms/char")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Scroll Section

    private var scrollSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scroll").font(.caption.weight(.medium))

            LabeledContent("Direction") {
                Picker("", selection: Binding(
                    get: { step.direction ?? .down },
                    set: { step.direction = $0 }
                )) {
                    ForEach([
                        ScenarioStep.ScrollDirection.up,
                        .down,
                        .left,
                        .right
                    ], id: \.self) { dir in
                        Text(dir.rawValue).tag(dir)
                    }
                }
                .frame(width: 80)
            }

            LabeledContent("Amount") {
                HStack {
                    TextField("px", value: Binding(
                        get: { step.amount ?? 0 },
                        set: { step.amount = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)

                    Text("px")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let target = step.target {
                Text("Target").font(.caption.weight(.medium)).padding(.top, 4)

                LabeledContent("Role") {
                    Text(target.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Activate App Section

    private var activateAppSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Bundle ID") {
                Text(step.app ?? "unknown")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Mouse Down/Up Section

    private var mouseDownUpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let target = step.target {
                LabeledContent("Position") {
                    Text("(\(String(format: "%.2f", target.positionHint.x)), \(String(format: "%.2f", target.positionHint.y)))")
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    // MARK: - Timing Section

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timing").font(.caption.weight(.medium))

            LabeledContent("Duration") {
                HStack {
                    TextField("ms", value: $step.durationMs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)

                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
