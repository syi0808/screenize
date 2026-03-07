import Foundation
import CoreGraphics

// MARK: - Click State Evaluation

extension FrameEvaluator {

    func checkClickState(at time: TimeInterval) -> (isClicking: Bool, clickType: ClickType?) {
        guard !clickEvents.isEmpty else { return (false, nil) }

        // Binary search for first click whose endTimestamp >= time
        var low = 0
        var high = clickEvents.count

        while low < high {
            let mid = (low + high) / 2
            if clickEvents[mid].endTimestamp < time {
                low = mid + 1
            } else {
                high = mid
            }
        }

        // Scan forward from the found position (clicks are sorted by timestamp)
        for i in low..<clickEvents.count {
            let click = clickEvents[i]
            if click.timestamp > time { break }
            if click.isActive(at: time) {
                return (true, click.clickType)
            }
        }
        return (false, nil)
    }

    func computeClickScaleModifier(at time: TimeInterval) -> CGFloat {
        guard !clickEvents.isEmpty else { return 1.0 }

        let pressDuration: TimeInterval = 0.08
        let pressedScale: CGFloat = 0.8
        let settleDuration: TimeInterval = 0.08

        // Binary search for first click whose effect window reaches time
        // A click affects time if: timestamp <= time <= endTimestamp + settleDuration
        var low = 0
        var high = clickEvents.count

        while low < high {
            let mid = (low + high) / 2
            if clickEvents[mid].endTimestamp + settleDuration < time {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var candidates: [CGFloat] = []

        for i in low..<clickEvents.count {
            let click = clickEvents[i]
            let downTime = click.timestamp
            if downTime > time { break }
            let upTime = click.endTimestamp

            let clickModifier: CGFloat
            if time < downTime || time > upTime + settleDuration {
                continue
            } else if time <= downTime + pressDuration {
                let t = CGFloat((time - downTime) / pressDuration)
                clickModifier = 1.0 + (pressedScale - 1.0) * easeOutQuad(t)
            } else if time <= upTime {
                clickModifier = pressedScale
            } else {
                let t = CGFloat((time - upTime) / settleDuration)
                clickModifier = pressedScale + (1.0 - pressedScale) * easeOutQuad(t)
            }

            candidates.append(clickModifier)
        }

        guard !candidates.isEmpty else { return 1.0 }
        if let minimum = candidates.min(), minimum < 1.0 {
            return minimum
        }
        return candidates.max() ?? 1.0
    }

    func easeOutQuad(_ t: CGFloat) -> CGFloat {
        let clamped = clamp(t, min: 0, max: 1)
        return 1 - (1 - clamped) * (1 - clamped)
    }
}
