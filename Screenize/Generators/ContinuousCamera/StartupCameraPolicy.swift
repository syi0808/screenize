import Foundation

/// Resolved startup camera state before physics simulation begins.
struct ResolvedStartupCameraState {
    let initialCenter: NormalizedPoint
    let releaseTime: TimeInterval?
}

/// Startup camera policy that prefers a centered opening shot until meaningful action begins.
enum StartupCameraPolicy {

    static func resolve(
        cursorPositions: [MousePositionData],
        clickEvents: [ClickEventData],
        keyboardEvents: [KeyboardEventData],
        dragEvents: [DragEventData],
        intentSpans: [IntentSpan],
        settings: StartupCameraSettings
    ) -> ResolvedStartupCameraState {
        guard settings.enabled else {
            return ResolvedStartupCameraState(
                initialCenter: cursorPositions.first?.position ?? settings.initialCenter,
                releaseTime: 0
            )
        }

        let releaseCandidates: [TimeInterval?] = [
            clickEvents.map(\.time).min(),
            dragEvents.map(\.startTime).min(),
            earliestTypingTime(in: intentSpans),
            earliestKeyboardTime(in: keyboardEvents),
            earliestDeliberateMotionTime(
                in: cursorPositions,
                settings: settings
            )
        ]

        return ResolvedStartupCameraState(
            initialCenter: settings.initialCenter,
            releaseTime: releaseCandidates.compactMap { $0 }.min()
        )
    }

    private static func earliestTypingTime(in intentSpans: [IntentSpan]) -> TimeInterval? {
        intentSpans.compactMap { span in
            if case .typing = span.intent {
                return span.startTime
            }
            return nil
        }.min()
    }

    private static func earliestKeyboardTime(in keyboardEvents: [KeyboardEventData]) -> TimeInterval? {
        keyboardEvents.compactMap { event in
            guard event.eventType == .keyDown else { return nil }
            guard !event.modifiers.hasShortcutModifiers else { return nil }
            return event.time
        }.min()
    }

    private static func earliestDeliberateMotionTime(
        in cursorPositions: [MousePositionData],
        settings: StartupCameraSettings
    ) -> TimeInterval? {
        guard let anchor = cursorPositions.first else { return nil }
        let deadline = anchor.time + settings.deliberateMotionWindow

        for sample in cursorPositions where sample.time <= deadline {
            let distance = anchor.position.distance(to: sample.position)
            if distance <= settings.jitterDistance {
                continue
            }
            if distance >= settings.deliberateMotionDistance {
                return sample.time
            }
        }

        return nil
    }
}
