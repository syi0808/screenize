import Foundation
import CoreGraphics

/// Converts raw scenario events into semantic scenario steps. Pure function — no side effects.
struct ScenarioGenerator {

    // MARK: - Public API

    /// Convert raw events to a semantic scenario.
    static func generate(from rawEvents: ScenarioRawEvents) -> Scenario {
        guard !rawEvents.events.isEmpty else {
            return Scenario(steps: [])
        }

        let actionSteps = convertToActionSteps(rawEvents.events, captureArea: rawEvents.captureArea)
        let stepsWithMoves = insertMouseMoves(between: actionSteps)
        let appContext = detectAppContext(rawEvents.events)

        return Scenario(version: 1, appContext: appContext, steps: stepsWithMoves)
    }

    // MARK: - Core Conversion

    private static func convertToActionSteps(_ events: [RawEvent], captureArea: CGRect) -> [ActionStep] {
        var result: [ActionStep] = []
        var index = 0

        while index < events.count {
            let event = events[index]

            switch event.type {
            case .mouseDown:
                let consumed = handleMouseDown(events: events, startIndex: index, captureArea: captureArea)
                result.append(contentsOf: consumed.steps)
                index = consumed.nextIndex

            case .scroll:
                let consumed = handleScroll(events: events, startIndex: index, captureArea: captureArea)
                result.append(contentsOf: consumed.steps)
                index = consumed.nextIndex

            case .keyDown:
                let consumed = handleKeyDown(events: events, startIndex: index)
                result.append(contentsOf: consumed.steps)
                index = consumed.nextIndex

            case .appActivated:
                let step = ScenarioStep(
                    type: .activateApp,
                    description: "Activate \(event.appName ?? "app")",
                    durationMs: 500,
                    app: event.bundleId
                )
                result.append(ActionStep(step: step, startMs: event.timeMs, endMs: event.timeMs))
                index += 1

            case .mouseMove, .mouseUp, .keyUp:
                // Consumed by their corresponding handlers
                index += 1
            }
        }

        return result
    }

    // MARK: - Mouse Down Handling

    private static func handleMouseDown(
        events: [RawEvent],
        startIndex: Int,
        captureArea: CGRect
    ) -> ConsumeResult {
        let downEvent = events[startIndex]
        let button = downEvent.button ?? "left"

        // Find matching mouseUp
        guard let upIndex = findMouseUp(events: events, after: startIndex, button: button) else {
            // No matching mouseUp found; skip
            return ConsumeResult(steps: [], nextIndex: startIndex + 1)
        }

        let upEvent = events[upIndex]

        // Check if this is a drag (distance > 5px between down and up)
        if isDrag(down: downEvent, up: upEvent, events: events, startIndex: startIndex, upIndex: upIndex) {
            return handleDrag(
                events: events, downIndex: startIndex, upIndex: upIndex, captureArea: captureArea
            )
        }

        // It's a click (or double-click or right-click)
        if button == "right" {
            let step = makeClickStep(
                type: .rightClick,
                downEvent: downEvent,
                upEvent: upEvent,
                captureArea: captureArea
            )
            return ConsumeResult(
                steps: [ActionStep(step: step, startMs: downEvent.timeMs, endMs: upEvent.timeMs)],
                nextIndex: upIndex + 1
            )
        }

        // Left click — check for double-click
        if let doubleResult = checkDoubleClick(
            events: events, firstDownIndex: startIndex, firstUpIndex: upIndex, captureArea: captureArea
        ) {
            return doubleResult
        }

        let step = makeClickStep(
            type: .click,
            downEvent: downEvent,
            upEvent: upEvent,
            captureArea: captureArea
        )
        return ConsumeResult(
            steps: [ActionStep(step: step, startMs: downEvent.timeMs, endMs: upEvent.timeMs)],
            nextIndex: upIndex + 1
        )
    }

    private static func checkDoubleClick(
        events: [RawEvent],
        firstDownIndex: Int,
        firstUpIndex: Int,
        captureArea: CGRect
    ) -> ConsumeResult? {
        let firstDown = events[firstDownIndex]
        let firstUp = events[firstUpIndex]

        // Look for a second mouseDown(left) after firstUp within 400ms of firstDown
        var searchIndex = firstUpIndex + 1
        while searchIndex < events.count {
            let candidate = events[searchIndex]
            // Skip mouse_move events between clicks
            if candidate.type == .mouseMove {
                searchIndex += 1
                continue
            }
            if candidate.type == .mouseDown && candidate.button == "left" {
                let timeSinceFirstDown = candidate.timeMs - firstDown.timeMs
                if timeSinceFirstDown <= 400 {
                    // Found second click start — find its mouseUp
                    if let secondUpIndex = findMouseUp(events: events, after: searchIndex, button: "left") {
                        let secondUp = events[secondUpIndex]
                        let step = makeClickStep(
                            type: .doubleClick,
                            downEvent: firstDown,
                            upEvent: secondUp,
                            captureArea: captureArea
                        )
                        return ConsumeResult(
                            steps: [ActionStep(step: step, startMs: firstDown.timeMs, endMs: secondUp.timeMs)],
                            nextIndex: secondUpIndex + 1
                        )
                    }
                }
                break
            }
            break
        }
        return nil
    }

    // MARK: - Drag Handling

    private static func isDrag(
        down: RawEvent, up: RawEvent,
        events: [RawEvent], startIndex: Int, upIndex: Int
    ) -> Bool {
        // Check if any mouse_move between down and up moved > 5px from down position
        guard let downX = down.x, let downY = down.y else { return false }
        for i in (startIndex + 1)..<upIndex {
            if events[i].type == .mouseMove, let mx = events[i].x, let my = events[i].y {
                let dist = hypot(mx - downX, my - downY)
                if dist > 5 { return true }
            }
        }
        // Also check down vs up distance
        if let upX = up.x, let upY = up.y {
            return hypot(upX - downX, upY - downY) > 5
        }
        return false
    }

    private static func handleDrag(
        events: [RawEvent],
        downIndex: Int,
        upIndex: Int,
        captureArea: CGRect
    ) -> ConsumeResult {
        let downEvent = events[downIndex]
        let upEvent = events[upIndex]
        var steps: [ActionStep] = []

        // mouse_down
        let downStep = ScenarioStep(
            type: .mouseDown,
            description: "Mouse down (drag start)",
            durationMs: 0,
            target: makeAXTarget(from: downEvent, captureArea: captureArea)
        )
        steps.append(ActionStep(step: downStep, startMs: downEvent.timeMs, endMs: downEvent.timeMs))

        // Collect drag mouse_move events
        for i in (downIndex + 1)..<upIndex where events[i].type == .mouseMove {
            let moveEvent = events[i]
            let prevTime = steps.last?.endMs ?? downEvent.timeMs
            let moveStep = ScenarioStep(
                type: .mouseMove,
                description: "Drag move",
                durationMs: moveEvent.timeMs - prevTime,
                path: .auto,
                rawTimeRange: TimeRange(startMs: prevTime, endMs: moveEvent.timeMs)
            )
            steps.append(ActionStep(step: moveStep, startMs: prevTime, endMs: moveEvent.timeMs))
        }

        // mouse_up
        let prevTime = steps.last?.endMs ?? downEvent.timeMs
        let upStep = ScenarioStep(
            type: .mouseUp,
            description: "Mouse up (drag end)",
            durationMs: upEvent.timeMs - prevTime,
            target: makeAXTarget(from: upEvent, captureArea: captureArea)
        )
        steps.append(ActionStep(step: upStep, startMs: prevTime, endMs: upEvent.timeMs))

        return ConsumeResult(steps: steps, nextIndex: upIndex + 1)
    }

    // MARK: - Scroll Handling

    private static func handleScroll(
        events: [RawEvent],
        startIndex: Int,
        captureArea: CGRect
    ) -> ConsumeResult {
        var totalDeltaY: Double = 0
        var totalDeltaX: Double = 0
        var endIndex = startIndex
        let firstEvent = events[startIndex]
        var lastTimeMs = firstEvent.timeMs

        // Merge consecutive scroll events within 100ms gaps
        var i = startIndex
        while i < events.count && events[i].type == .scroll {
            let event = events[i]
            if i > startIndex && (event.timeMs - lastTimeMs) > 100 {
                break
            }
            totalDeltaY += event.deltaY ?? 0
            totalDeltaX += event.deltaX ?? 0
            lastTimeMs = event.timeMs
            endIndex = i
            i += 1
        }

        let direction: ScenarioStep.ScrollDirection
        let amount: Int
        if abs(totalDeltaY) >= abs(totalDeltaX) {
            direction = totalDeltaY < 0 ? .down : .up
            amount = Int(abs(totalDeltaY))
        } else {
            direction = totalDeltaX < 0 ? .right : .left
            amount = Int(abs(totalDeltaX))
        }

        let step = ScenarioStep(
            type: .scroll,
            description: "Scroll \(direction.rawValue)",
            durationMs: lastTimeMs - firstEvent.timeMs,
            target: makeAXTarget(from: firstEvent, captureArea: captureArea),
            direction: direction,
            amount: amount
        )

        return ConsumeResult(
            steps: [ActionStep(step: step, startMs: firstEvent.timeMs, endMs: lastTimeMs)],
            nextIndex: endIndex + 1
        )
    }

    // MARK: - Key Handling

    private static func handleKeyDown(events: [RawEvent], startIndex: Int) -> ConsumeResult {
        let event = events[startIndex]
        let modifiers = event.modifiers ?? []
        // Non-shift modifiers indicate a keyboard combo
        let nonShiftModifiers = modifiers.filter { $0 != "shift" }

        if !nonShiftModifiers.isEmpty {
            return handleKeyboardCombo(events: events, startIndex: startIndex)
        }

        // No non-shift modifiers — this is text typing. Merge consecutive characters.
        return handleTypeText(events: events, startIndex: startIndex)
    }

    private static func handleKeyboardCombo(events: [RawEvent], startIndex: Int) -> ConsumeResult {
        let event = events[startIndex]
        let modifiers = (event.modifiers ?? []).sorted()
        let key = event.characters ?? ""
        let combo = (modifiers + [key]).joined(separator: "+")

        let step = ScenarioStep(
            type: .keyboard,
            description: "Press \(combo)",
            durationMs: 0,
            keyCombo: combo
        )

        // Skip past the matching keyUp
        var nextIdx = startIndex + 1
        while nextIdx < events.count {
            if events[nextIdx].type == .keyUp {
                nextIdx += 1
                break
            }
            nextIdx += 1
        }

        return ConsumeResult(
            steps: [ActionStep(step: step, startMs: event.timeMs, endMs: event.timeMs)],
            nextIndex: nextIdx
        )
    }

    private static func handleTypeText(events: [RawEvent], startIndex: Int) -> ConsumeResult {
        var text = ""
        var i = startIndex
        var lastTimeMs = events[startIndex].timeMs
        let firstTimeMs = events[startIndex].timeMs

        while i < events.count {
            let event = events[i]

            if event.type == .keyUp {
                i += 1
                continue
            }

            if event.type == .keyDown {
                let mods = event.modifiers ?? []
                let nonShiftMods = mods.filter { $0 != "shift" }
                if !nonShiftMods.isEmpty {
                    // Hit a combo key — stop merging
                    break
                }
                if let chars = event.characters, !chars.isEmpty {
                    text += chars
                    lastTimeMs = event.timeMs
                }
                i += 1
                continue
            }

            // Non-key event — stop merging
            break
        }

        let durationMs = lastTimeMs - firstTimeMs
        let step = ScenarioStep(
            type: .typeText,
            description: "Type \"\(text)\"",
            durationMs: durationMs,
            content: text,
            typingSpeedMs: text.isEmpty ? 50 : max(1, durationMs / text.count)
        )
        return ConsumeResult(
            steps: [ActionStep(step: step, startMs: firstTimeMs, endMs: lastTimeMs)],
            nextIndex: i
        )
    }

    // MARK: - mouse_move Insertion

    private static func insertMouseMoves(between actionSteps: [ActionStep]) -> [ScenarioStep] {
        guard !actionSteps.isEmpty else { return [] }

        var result: [ScenarioStep] = []

        for (i, action) in actionSteps.enumerated() {
            if i > 0 {
                let prevEnd = actionSteps[i - 1].endMs
                let currStart = action.startMs
                let gap = currStart - prevEnd

                if gap > 0 {
                    let moveStep = ScenarioStep(
                        type: .mouseMove,
                        description: "Move to next target",
                        durationMs: gap,
                        path: .auto,
                        rawTimeRange: TimeRange(startMs: prevEnd, endMs: currStart)
                    )
                    result.append(moveStep)
                }
            }
            result.append(action.step)
        }

        return result
    }

    // MARK: - App Context

    private static func detectAppContext(_ events: [RawEvent]) -> String? {
        var counts: [String: Int] = [:]
        for event in events where event.type == .appActivated {
            if let bundleId = event.bundleId {
                counts[bundleId, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Helpers

    private static func findMouseUp(events: [RawEvent], after startIndex: Int, button: String) -> Int? {
        for i in (startIndex + 1)..<events.count {
            if events[i].type == .mouseUp && (events[i].button ?? "left") == button {
                return i
            }
        }
        return nil
    }

    private static func makeClickStep(
        type: ScenarioStep.StepType,
        downEvent: RawEvent,
        upEvent: RawEvent,
        captureArea: CGRect
    ) -> ScenarioStep {
        let typeLabel: String
        switch type {
        case .click: typeLabel = "Click"
        case .doubleClick: typeLabel = "Double-click"
        case .rightClick: typeLabel = "Right-click"
        default: typeLabel = type.rawValue
        }
        let axTitle = downEvent.ax?.axTitle
        let description = axTitle.map { "\(typeLabel) \($0)" } ?? typeLabel

        return ScenarioStep(
            type: type,
            description: description,
            durationMs: upEvent.timeMs - downEvent.timeMs,
            target: makeAXTarget(from: downEvent, captureArea: captureArea)
        )
    }

    private static func makeAXTarget(from event: RawEvent, captureArea: CGRect) -> AXTarget? {
        // Coordinates are required; AX info is optional (async query may have failed/timed out)
        guard let absX = event.x, let absY = event.y else { return nil }

        let hintX = captureArea.width > 0 ? (absX - captureArea.origin.x) / captureArea.width : 0
        let hintY = captureArea.height > 0 ? (absY - captureArea.origin.y) / captureArea.height : 0

        return AXTarget(
            role: event.ax?.role ?? "unknown",
            axTitle: event.ax?.axTitle,
            axValue: event.ax?.axValue,
            path: event.ax?.path ?? [],
            positionHint: CGPoint(x: hintX, y: hintY),
            absoluteCoord: CGPoint(x: absX, y: absY)
        )
    }

    // MARK: - Internal Types

    /// Intermediate representation pairing a step with its raw event time range.
    private struct ActionStep {
        let step: ScenarioStep
        let startMs: Int
        let endMs: Int
    }

    /// Result of consuming one or more raw events.
    private struct ConsumeResult {
        let steps: [ActionStep]
        let nextIndex: Int
    }
}
