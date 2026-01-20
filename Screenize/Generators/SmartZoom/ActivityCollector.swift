import Foundation
import CoreGraphics

// MARK: - Activity Event

/// Activity events (aggregate all activities)
struct ActivityEvent: Comparable, Equatable {
    let time: TimeInterval
    let position: NormalizedPoint
    let type: ActivityType
    let elementInfo: UIElementInfo?
    let appBundleID: String?

    enum ActivityType: Equatable {
        case click
        case typing
        case dragStart
        case dragEnd
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.time < rhs.time
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.time == rhs.time && lhs.position == rhs.position && lhs.type == rhs.type
    }
}

// MARK: - Activity Collector

/// Collects activity events from mouse data
struct ActivityCollector {

    /// List of UI element roles that represent text input
    static let textInputRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField",
        "AXSecureTextField", "AXComboBox"
    ]

    /// Gather all activity events (include elementInfo from uiStateSamples when typing)
    static func collectActivities(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample]
    ) -> [ActivityEvent] {
        var activities: [ActivityEvent] = []

        // Handle click events
        for click in mouseData.clicks where click.clickType == .leftDown {
            activities.append(ActivityEvent(
                time: click.time,
                position: click.position,
                type: .click,
                elementInfo: click.elementInfo,
                appBundleID: click.appBundleID
            ))
        }

        // Handle drag events (selection, move, etc.)
        for drag in mouseData.dragEvents {
            activities.append(ActivityEvent(
                time: drag.startTime,
                position: drag.startPosition,
                type: .dragStart,
                elementInfo: nil,
                appBundleID: nil
            ))

            activities.append(ActivityEvent(
                time: drag.endTime,
                position: drag.endPosition,
                type: .dragEnd,
                elementInfo: nil,
                appBundleID: nil
            ))
        }

        // Handle keyboard events (detect typing sessions - pull elementInfo from UIStateSample)
        let typingSessions = detectTypingSessions(from: mouseData.keyboardEvents)
        for session in typingSessions {
            // Capture the cursor position
            guard let positionData = mouseData.positions.last(where: { $0.time <= session.startTime }) else {
                continue
            }

            // Query UIStateSample for elementInfo at the typing start
            // (MouseRecordingAdapter positions lack elementInfo, so use UIStateSample)
            let elementInfo: UIElementInfo?
            if !uiStateSamples.isEmpty {
                let closestSample = uiStateSamples.min { abs($0.timestamp - session.startTime) < abs($1.timestamp - session.startTime) }
                elementInfo = closestSample?.elementInfo
            } else {
                elementInfo = positionData.elementInfo
            }

            // Check whether the same element was clicked during typing
            // If so, use that click position to prevent camera drift
            let typingPosition: NormalizedPoint
            if let typingElement = elementInfo,
               let matchingClick = mouseData.clicks.last(where: { click in
                   guard click.clickType == .leftDown,
                         click.time < session.startTime,
                         let clickElement = click.elementInfo else {
                       return false
                   }
                   // Compare UI elements using frame locations
                   return clickElement.frame == typingElement.frame
               }) {
                // Use the matching click position to prevent drift
                typingPosition = matchingClick.position
            } else {
                // Fall back to the current cursor position when no click matches
                typingPosition = positionData.position
            }

            // Mark the start of a typing session
            activities.append(ActivityEvent(
                time: session.startTime,
                position: typingPosition,
                type: .typing,
                elementInfo: elementInfo,
                appBundleID: positionData.appBundleID
            ))

            // End the typing session (only if it was meaningful in length)
            if session.endTime > session.startTime + 0.5 {
                activities.append(ActivityEvent(
                    time: session.endTime,
                    position: typingPosition,
                    type: .typing,
                    elementInfo: elementInfo,
                    appBundleID: positionData.appBundleID
                ))
            }
        }

        return activities.sorted()
    }

    /// Detect typing sessions
    static func detectTypingSessions(from keyboardEvents: [KeyboardEventData]) -> [(startTime: TimeInterval, endTime: TimeInterval)] {
        var sessions: [(startTime: TimeInterval, endTime: TimeInterval)] = []

        let keyDownEvents = keyboardEvents.filter { $0.eventType == .keyDown && !$0.modifiers.hasShortcutModifiers }
        guard !keyDownEvents.isEmpty else { return [] }

        var sessionStart: TimeInterval?
        var lastKeyTime: TimeInterval = 0
        let sessionTimeout: TimeInterval = 1.5  // End the session if no input occurs for 1.5 seconds

        for event in keyDownEvents {
            if sessionStart == nil {
                sessionStart = event.time
            } else if event.time - lastKeyTime > sessionTimeout {
                sessions.append((startTime: sessionStart!, endTime: lastKeyTime))
                sessionStart = event.time
            }
            lastKeyTime = event.time
        }

        if let start = sessionStart {
            sessions.append((startTime: start, endTime: lastKeyTime))
        }

        return sessions
    }
}
