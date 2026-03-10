import Foundation
import CoreGraphics

// MARK: - Click State Evaluation (mouseDown/mouseUp event-based)

extension FrameEvaluator {

    /// Check whether any mouse button is pressed at the given time.
    /// Walks backward through sorted mouseButtonEvents to find the last event
    /// for each button type and determines current press state.
    func checkClickState(at time: TimeInterval) -> (isClicking: Bool, clickType: ClickType?) {
        guard !mouseButtonEvents.isEmpty else { return (false, nil) }

        // Track the last known state per button type
        var lastLeft: RenderMouseButtonEvent?
        var lastRight: RenderMouseButtonEvent?

        // Binary search for the last event at or before `time`
        var low = 0
        var high = mouseButtonEvents.count

        while low < high {
            let mid = (low + high) / 2
            if mouseButtonEvents[mid].timestamp <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        // low = index of first event after `time`; walk backward to find last events per type
        for i in stride(from: low - 1, through: 0, by: -1) {
            let event = mouseButtonEvents[i]
            switch event.clickType {
            case .left:
                if lastLeft == nil { lastLeft = event }
            case .right:
                if lastRight == nil { lastRight = event }
            }
            if lastLeft != nil && lastRight != nil { break }
        }

        // Check if any button is currently down
        if let left = lastLeft, left.isDown {
            return (true, .left)
        }
        if let right = lastRight, right.isDown {
            return (true, .right)
        }
        return (false, nil)
    }

    /// Compute the cursor scale modifier based on mouseDown/mouseUp events.
    /// Returns < 1.0 during press/hold, 1.0 when neutral, and may briefly
    /// exceed 1.0 during spring release overshoot.
    func computeClickScaleModifier(at time: TimeInterval) -> CGFloat {
        guard !mouseButtonEvents.isEmpty else { return 1.0 }

        let config = timeline.cursorTrackV2?
            .activeSegment(at: time)?.clickFeedback ?? .default

        let leftScale = computeScaleForButton(.left, at: time, config: config)
        let rightScale = computeScaleForButton(.right, at: time, config: config)

        // Pick the most extreme value (furthest from 1.0)
        return [leftScale, rightScale].max(by: {
            abs($0 - 1.0) < abs($1 - 1.0)
        }) ?? 1.0
    }

    // MARK: - Per-Button Scale Computation

    /// Compute cursor scale for a single button type at the given time.
    private func computeScaleForButton(
        _ buttonType: ClickType,
        at time: TimeInterval,
        config: ClickFeedbackConfig
    ) -> CGFloat {
        let pressDuration = config.mouseDownDuration
        let pressedScale = config.mouseDownScale
        let releaseDuration = config.mouseUpDuration

        // Find the last mouseDown and mouseUp of this button type at or before `time`
        var lastDown: TimeInterval?
        var lastUp: TimeInterval?

        // Binary search for last event at or before `time`
        var low = 0
        var high = mouseButtonEvents.count
        while low < high {
            let mid = (low + high) / 2
            if mouseButtonEvents[mid].timestamp <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }

        for i in stride(from: low - 1, through: 0, by: -1) {
            let event = mouseButtonEvents[i]
            guard event.clickType == buttonType else { continue }
            if event.isDown {
                if lastDown == nil { lastDown = event.timestamp }
            } else {
                if lastUp == nil { lastUp = event.timestamp }
            }
            if lastDown != nil && lastUp != nil { break }
        }

        guard let downTime = lastDown else { return 1.0 }

        let isPressed = lastUp == nil || downTime > lastUp!

        if isPressed {
            // Press or hold phase
            let elapsed = time - downTime
            if elapsed < pressDuration {
                // Animating press (shrink)
                let t = CGFloat(elapsed / pressDuration)
                return 1.0 + (pressedScale - 1.0) * easeOutQuad(t)
            } else {
                // Holding at pressed scale
                return pressedScale
            }
        } else {
            // Release phase or past it
            let upTime = lastUp!
            let elapsed = time - upTime
            if elapsed < releaseDuration {
                // Animating release (spring back)
                let t = elapsed / releaseDuration
                let eased = config.mouseUpSpring.applyUnclamped(
                    t,
                    duration: releaseDuration
                )
                return pressedScale + (1.0 - pressedScale) * CGFloat(eased)
            } else {
                // Fully released
                return 1.0
            }
        }
    }

    func easeOutQuad(_ t: CGFloat) -> CGFloat {
        let clamped = clamp(t, min: 0, max: 1)
        return 1 - (1 - clamped) * (1 - clamped)
    }
}
