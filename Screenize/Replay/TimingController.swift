import Foundation

/// Controls timing and inter-step delays during scenario replay.
struct TimingController {

    /// Async delay for the specified milliseconds.
    static func delay(ms: Int) async {
        guard ms > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    /// Check if step at index is part of a drag group (mouse_down → mouse_move(s) → mouse_up).
    ///
    /// A drag group is a contiguous sequence: one `mouse_down`, zero or more `mouse_move`, one `mouse_up`.
    /// A step is a member if it belongs to such a complete sequence.
    static func isDragGroupMember(steps: [ScenarioStep], index: Int) -> Bool {
        guard index >= 0, index < steps.count else { return false }
        let step = steps[index]
        guard step.type == .mouseDown || step.type == .mouseMove || step.type == .mouseUp else {
            return false
        }

        // Find the mouse_down that starts a potential drag group containing this index.
        // Walk backward to find the mouse_down anchor.
        var downIndex: Int?
        switch step.type {
        case .mouseDown:
            downIndex = index
        case .mouseMove, .mouseUp:
            // Walk backward past any mouse_move to find a mouse_down
            var i = index - 1
            while i >= 0 {
                let t = steps[i].type
                if t == .mouseDown {
                    downIndex = i
                    break
                } else if t == .mouseMove {
                    i -= 1
                } else {
                    // Non-drag type interrupts the group — not a drag group member
                    return false
                }
            }
        default:
            return false
        }

        guard let start = downIndex else { return false }

        // Validate the sequence from start: mouse_down → mouse_move* → mouse_up
        var i = start + 1
        while i < steps.count {
            let t = steps[i].type
            if t == .mouseMove {
                i += 1
            } else if t == .mouseUp {
                // Valid drag group found — check that our index is within [start, i]
                return index >= start && index <= i
            } else {
                // Sequence broken before mouse_up
                return false
            }
        }

        // No mouse_up found — incomplete sequence, not a drag group
        return false
    }

    /// Get inter-step delay in ms. Returns 0 for drag group members (continuous execution).
    static func interStepDelay(steps: [ScenarioStep], index: Int) -> Int {
        if isDragGroupMember(steps: steps, index: index) {
            return 0
        }
        guard index >= 0, index < steps.count else { return 0 }
        return steps[index].durationMs
    }
}
