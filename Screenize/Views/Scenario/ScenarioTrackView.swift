import SwiftUI

/// Represents a contiguous implicit drag sequence: mouse_down → mouse_move(s) → mouse_up.
private struct DragGroup {
    let startIndex: Int
    let endIndex: Int
}

/// Timeline track view that renders all ScenarioStep blocks horizontally on the time axis.
struct ScenarioTrackView: View {

    let scenario: Scenario
    let pixelsPerSecond: CGFloat
    let trimStart: TimeInterval
    @Binding var selectedStepId: UUID?

    var onStepSelect: ((UUID) -> Void)?
    var onStepDelete: ((UUID) -> Void)?
    var onStepDuplicate: ((UUID) -> Void)?
    /// Called when a step is moved; provides (stepId, fromIndex, toIndex).
    var onStepMove: ((UUID, Int, Int) -> Void)?
    /// Called when a step's duration is changed via edge drag; provides (stepId, newDurationMs).
    var onStepResize: ((UUID, Int) -> Void)?
    /// Called when a new step should be added after the given step index.
    var onStepAdd: ((ScenarioStep.StepType, Int) -> Void)?

    private let trackHeight: CGFloat = 36

    // MARK: - Drag Group Detection

    /// Scans `steps` and returns every implicit drag group (mouse_down → mouse_move* → mouse_up).
    private static func detectDragGroups(in steps: [ScenarioStep]) -> [DragGroup] {
        var groups: [DragGroup] = []
        var i = 0
        while i < steps.count {
            if steps[i].type == .mouseDown {
                var j = i + 1
                while j < steps.count && steps[j].type == .mouseMove {
                    j += 1
                }
                if j < steps.count && steps[j].type == .mouseUp {
                    groups.append(DragGroup(startIndex: i, endIndex: j))
                    i = j + 1
                    continue
                }
            }
            i += 1
        }
        return groups
    }

    var body: some View {
        let dragGroups = Self.detectDragGroups(in: scenario.steps)

        ZStack(alignment: .leading) {
            Color.clear

            // Drag group highlight backgrounds rendered behind individual step blocks.
            ForEach(dragGroups, id: \.startIndex) { group in
                let startX = CGFloat(scenario.startTime(forStepAt: group.startIndex)) * pixelsPerSecond
                let endStep = scenario.steps[group.endIndex]
                let endX = CGFloat(scenario.startTime(forStepAt: group.endIndex)) * pixelsPerSecond
                    + CGFloat(endStep.durationSeconds) * pixelsPerSecond

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX)
                    .allowsHitTesting(false)
            }

            ForEach(Array(scenario.steps.enumerated()), id: \.element.id) { index, step in
                let startTime = scenario.startTime(forStepAt: index)
                let blockWidth = max(20, CGFloat(step.durationSeconds) * pixelsPerSecond)
                let offsetX = CGFloat(startTime) * pixelsPerSecond
                let isSelected = selectedStepId == step.id

                ScenarioStepBlockView(
                    step: step,
                    isSelected: isSelected,
                    width: blockWidth,
                    pixelsPerSecond: pixelsPerSecond,
                    onResize: { newDurationMs in
                        onStepResize?(step.id, newDurationMs)
                    }
                )
                .offset(x: offsetX, y: 0)
                .onTapGesture {
                    onStepSelect?(step.id)
                }
                .contextMenu {
                    if index > 0 {
                        Button {
                            onStepMove?(step.id, index, index - 1)
                        } label: {
                            Label("Move Up", systemImage: "arrow.left")
                        }
                    }

                    if index < scenario.steps.count - 1 {
                        Button {
                            onStepMove?(step.id, index, index + 1)
                        } label: {
                            Label("Move Down", systemImage: "arrow.right")
                        }
                    }

                    Divider()

                    Menu {
                        ForEach(ScenarioStep.StepType.allCases, id: \.self) { stepType in
                            Button {
                                onStepAdd?(stepType, index + 1)
                            } label: {
                                Text(stepType.rawValue)
                            }
                        }
                    } label: {
                        Label("Add Step After", systemImage: "plus")
                    }

                    Divider()

                    Button {
                        onStepDuplicate?(step.id)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onStepDelete?(step.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .frame(height: trackHeight)
    }
}
