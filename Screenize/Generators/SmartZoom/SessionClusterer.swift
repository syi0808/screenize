import Foundation
import CoreGraphics

// MARK: - Work Session

/// Work session (a cluster of continuous activity)
struct WorkSession {
    let startTime: TimeInterval
    var endTime: TimeInterval
    var activities: [ActivityEvent]
    var workArea: CGRect            // Bounding box (normalized) containing all activity in the session
    var center: NormalizedPoint      // Center of the work area
    var zoom: CGFloat               // Zoom level for this session

    /// Update the work area when adding a new activity
    mutating func updateWorkArea(with position: NormalizedPoint, padding: CGFloat) {
        let positions = activities.map { $0.position }
        guard !positions.isEmpty else { return }

        var minX = positions.map(\.x).min()!
        var maxX = positions.map(\.x).max()!
        var minY = positions.map(\.y).min()!
        var maxY = positions.map(\.y).max()!

        // Apply padding
        minX = max(0, minX - padding)
        maxX = min(1, maxX + padding)
        minY = max(0, minY - padding)
        maxY = min(1, maxY + padding)

        workArea = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        center = NormalizedPoint(x: workArea.midX, y: workArea.midY)
    }
}

// MARK: - Session Clusterer

/// Utility to cluster activities into work sessions
struct SessionClusterer {

    /// Cluster activities into work sessions
    static func clusterActivitiesIntoSessions(
        activities: [ActivityEvent],
        settings: SmartZoomSettings
    ) -> [WorkSession] {
        guard !activities.isEmpty else { return [] }

        var sessions: [WorkSession] = []
        var currentSession = WorkSession(
            startTime: activities[0].time,
            endTime: activities[0].time,
            activities: [activities[0]],
            workArea: CGRect(
                x: activities[0].position.x - settings.workAreaPadding,
                y: activities[0].position.y - settings.workAreaPadding,
                width: settings.workAreaPadding * 2,
                height: settings.workAreaPadding * 2
            ),
            center: activities[0].position,
            zoom: settings.defaultZoom
        )

        for i in 1..<activities.count {
            let activity = activities[i]
            let timeDelta = activity.time - currentSession.endTime
            let spatialDistance = activity.position.distance(to: currentSession.center)

            // Check if the activities belong to the same app
            let sameApp = (activity.appBundleID != nil &&
                           activity.appBundleID == currentSession.activities.last?.appBundleID)

            // Determine if it is a continuous typing session (merge regardless of time when typing at the same spot)
            let lastActivity = currentSession.activities.last
            let isContinuousTyping = activity.type == .typing &&
                lastActivity?.type == .typing &&
                spatialDistance < settings.sessionMergeDistance

            // Merge conditions: continuous typing OR (close in time AND (close in space OR same app))
            let shouldMerge = isContinuousTyping ||
                (timeDelta < settings.sessionMergeInterval &&
                 (spatialDistance < settings.sessionMergeDistance || sameApp))

            if shouldMerge {
                // Add to the current session
                currentSession.activities.append(activity)
                currentSession.endTime = activity.time
                currentSession.updateWorkArea(with: activity.position, padding: settings.workAreaPadding)
            } else {
                // Close the current session and start a new one
                sessions.append(currentSession)
                currentSession = WorkSession(
                    startTime: activity.time,
                    endTime: activity.time,
                    activities: [activity],
                    workArea: CGRect(
                        x: activity.position.x - settings.workAreaPadding,
                        y: activity.position.y - settings.workAreaPadding,
                        width: settings.workAreaPadding * 2,
                        height: settings.workAreaPadding * 2
                    ),
                    center: activity.position,
                    zoom: settings.defaultZoom
                )
            }
        }

        // Append the final session
        sessions.append(currentSession)

        return sessions
    }

    /// Replace typing session work areas with the UI element (text field) frame
    static func applyTypingElementROI(
        sessions: inout [WorkSession],
        screenBounds: CGSize,
        settings: SmartZoomSettings
    ) {
        guard screenBounds.width > 0, screenBounds.height > 0 else { return }

        for i in sessions.indices {
            let session = sessions[i]

            // Find text input elements among typing activities within the session
            let typingActivities = session.activities.filter { $0.type == .typing }
            guard !typingActivities.isEmpty else { continue }

            // Filter for elements with a text input role
            let textElements = typingActivities.compactMap { activity -> UIElementInfo? in
                guard let info = activity.elementInfo,
                      ActivityCollector.textInputRoles.contains(info.role) else {
                    return nil
                }
                return info
            }

            guard let textElement = textElements.first,
                  textElement.frame.width > 0,
                  textElement.frame.height > 0 else {
                continue
            }

            // Convert pixel coordinates to normalized space
            let normalizedX = textElement.frame.origin.x / screenBounds.width
            let normalizedY = textElement.frame.origin.y / screenBounds.height
            let normalizedW = textElement.frame.width / screenBounds.width
            let normalizedH = textElement.frame.height / screenBounds.height

            // Apply padding
            let padding = settings.workAreaPadding
            let paddedX = max(0, normalizedX - padding)
            let paddedY = max(0, normalizedY - padding)
            let paddedW = min(1.0 - paddedX, normalizedW + padding * 2)
            let paddedH = min(1.0 - paddedY, normalizedH + padding * 2)

            let workArea = CGRect(x: paddedX, y: paddedY, width: paddedW, height: paddedH)

            sessions[i].workArea = workArea
            sessions[i].center = NormalizedPoint(x: workArea.midX, y: workArea.midY)
        }
    }
}
