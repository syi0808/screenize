import Foundation
import CoreGraphics

/// Click-based cursor generator
/// Analyzes click events to auto-generate cursor keyframes
/// Synchronizes arrival time with zoom timing so the cursor reaches the click spot just before the click
final class ClickCursorGenerator: KeyframeGenerator {

    typealias Output = CursorTrack

    // MARK: - Properties

    let name = "Click Cursor"
    let description = "Generate cursor positions based on click events with zoom sync"

    // MARK: - Click Group

    /// Groups clicks belonging to the same object/area
    private struct ClickGroup {
        let clicks: [ClickEventData]

        var startTime: TimeInterval { clicks.first?.time ?? 0 }
        var endTime: TimeInterval { clicks.last?.time ?? 0 }
        var firstClick: ClickEventData? { clicks.first }
        var lastClick: ClickEventData? { clicks.last }
    }

    // MARK: - Generate

    func generate(from mouseData: MouseDataSource, settings: GeneratorSettings) -> CursorTrack {
        let cursorSettings = settings.clickCursor
        let clickSettings = settings.clickZoom
        let followSettings = settings.sameObjectFollow

        guard cursorSettings.enabled else {
            return createDefaultTrack()
        }

        var keyframes: [CursorStyleKeyframe] = []

        // Filter click events (only leftDown)
        let clicks = mouseData.clicks.filter { $0.clickType == .leftDown }

        guard !clicks.isEmpty else {
            return createDefaultTrack()
        }

        // First keyframe: start at the first click
        let firstClick = clicks[0]
        keyframes.append(CursorStyleKeyframe(
            time: 0,
            position: firstClick.position,
            style: .arrow,
            visible: true,
            scale: cursorSettings.cursorScale,
            velocity: 0,
            movementDirection: 0,
            easing: .linear
        ))

        // Group clicks (same logic as ClickZoomGenerator)
        let groups = groupClicks(clicks, clickSettings: clickSettings, followSettings: followSettings)

        // Generate keyframes for each group
        for (groupIndex, group) in groups.enumerated() {
            processClickGroup(
                group,
                groupIndex: groupIndex,
                keyframes: &keyframes,
                cursorSettings: cursorSettings,
                clickSettings: clickSettings,
                duration: mouseData.duration
            )
        }

        // Deduplicate and sort keyframes
        keyframes = removeDuplicates(keyframes)
        keyframes.sort { $0.time < $1.time }

        return CursorTrack(
            id: UUID(),
            name: "Cursor (Click-Based)",
            isEnabled: true,
            defaultStyle: .arrow,
            defaultScale: cursorSettings.cursorScale,
            defaultVisible: true,
            styleKeyframes: keyframes
        )
    }

    // MARK: - Click Grouping

    /// Group clicks by object/area
    private func groupClicks(
        _ clicks: [ClickEventData],
        clickSettings: ClickZoomSettings,
        followSettings: SameObjectFollowSettings
    ) -> [ClickGroup] {
        guard !clicks.isEmpty else { return [] }

        var groups: [ClickGroup] = []
        var currentGroupClicks: [ClickEventData] = []

        for click in clicks {
            if currentGroupClicks.isEmpty {
                currentGroupClicks.append(click)
            } else {
                let lastClick = currentGroupClicks.last!
                let timeSinceLastClick = click.time - lastClick.time

                let isSameContext = isSameObjectOrRegion(
                    click,
                    previousClick: lastClick,
                    followSettings: followSettings
                )

                if isSameContext {
                    currentGroupClicks.append(click)
                } else if timeSinceLastClick > clickSettings.idleTimeout {
                    groups.append(ClickGroup(clicks: currentGroupClicks))
                    currentGroupClicks = [click]
                } else {
                    groups.append(ClickGroup(clicks: currentGroupClicks))
                    currentGroupClicks = [click]
                }
            }
        }

        if !currentGroupClicks.isEmpty {
            groups.append(ClickGroup(clicks: currentGroupClicks))
        }

        return groups
    }

    /// Determine whether two clicks target the same object/area
    private func isSameObjectOrRegion(
        _ click: ClickEventData,
        previousClick: ClickEventData,
        followSettings: SameObjectFollowSettings
    ) -> Bool {
        if followSettings.sameAppOnly {
            if let currentApp = click.appBundleID,
               let previousApp = previousClick.appBundleID {
                return currentApp == previousApp
            }
        }

        let dx = click.x - previousClick.x
        let dy = click.y - previousClick.y
        let distance = sqrt(dx * dx + dy * dy)
        let proximityThreshold: CGFloat = 0.15
        return distance < proximityThreshold
    }

    // MARK: - Process Click Group

    /// Process click groups to generate cursor keyframes
    private func processClickGroup(
        _ group: ClickGroup,
        groupIndex: Int,
        keyframes: inout [CursorStyleKeyframe],
        cursorSettings: ClickCursorSettings,
        clickSettings: ClickZoomSettings,
        duration: TimeInterval
    ) {
        guard !group.clicks.isEmpty else { return }

        // Create keyframes for each click
        for (clickIndex, click) in group.clicks.enumerated() {
            let isFirstClickInGroup = clickIndex == 0

            if isFirstClickInGroup && groupIndex > 0 {
                // Move from the last click of the previous group to the current click
                if let lastKeyframe = keyframes.last {
                    createMovementKeyframes(
                        from: lastKeyframe,
                        to: click,
                        keyframes: &keyframes,
                        cursorSettings: cursorSettings,
                        clickSettings: clickSettings
                    )
                }
            } else if clickIndex > 0 {
                // Move from the previous group click to the current one
                let prevClick = group.clicks[clickIndex - 1]
                createInGroupMovementKeyframes(
                    from: prevClick,
                    to: click,
                    keyframes: &keyframes,
                    cursorSettings: cursorSettings
                )
            }

            // Click-time keyframe (arrival complete)
            keyframes.append(CursorStyleKeyframe(
                time: click.time,
                position: click.position,
                style: .arrow,
                visible: true,
                scale: cursorSettings.cursorScale,
                velocity: 0,
                movementDirection: 0,
                easing: cursorSettings.moveEasing
            ))

            // Hold keyframe after the click
            let holdEndTime = min(click.time + cursorSettings.holdTime, duration)
            if holdEndTime > click.time {
                keyframes.append(CursorStyleKeyframe(
                    time: holdEndTime,
                    position: click.position,
                    style: .arrow,
                    visible: true,
                    scale: cursorSettings.cursorScale,
                    velocity: 0,
                    movementDirection: 0,
                    easing: .linear
                ))
            }
        }
    }

    /// Generate inter-group movement keyframes (syncs with zoom timing)
    /// Uses the same easing pattern as the zoom movement for consistency
    private func createMovementKeyframes(
        from lastKeyframe: CursorStyleKeyframe,
        to click: ClickEventData,
        keyframes: inout [CursorStyleKeyframe],
        cursorSettings: ClickCursorSettings,
        clickSettings: ClickZoomSettings
    ) {
        guard let fromPosition = lastKeyframe.position else { return }

        // Compute arrival time (just before the click)
        let arrivalTime = click.time - cursorSettings.arrivalTime

        // Set the travel time to 0.2s to match zoom movement
        let moveDuration: TimeInterval = 0.2
        let moveStartTime = max(lastKeyframe.time, arrivalTime - moveDuration)

        guard moveStartTime < arrivalTime else { return }

        // Calculate distance and velocity
        let dx = click.x - fromPosition.x
        let dy = click.y - fromPosition.y
        let distance = sqrt(dx * dx + dy * dy)
        let actualMoveDuration = arrivalTime - moveStartTime
        let velocity = actualMoveDuration > 0 ? distance / CGFloat(actualMoveDuration) : 0
        let direction = atan2(dy, dx)

        // Start keyframe for movement – use the same easing as the zoom
        // KeyframeInterpolator applies easing, so only start/end keyframes are required
        keyframes.append(CursorStyleKeyframe(
            time: moveStartTime,
            position: fromPosition,
            style: .arrow,
            visible: true,
            scale: cursorSettings.cursorScale,
            velocity: velocity,
            movementDirection: direction,
            easing: cursorSettings.moveEasing
        ))

        // Arrival keyframe (velocity drops to zero)
        // Easing is applied when interpolating between the start and end keyframes
        keyframes.append(CursorStyleKeyframe(
            time: arrivalTime,
            position: click.position,
            style: .arrow,
            visible: true,
            scale: cursorSettings.cursorScale,
            velocity: 0,
            movementDirection: direction,
            easing: cursorSettings.moveEasing
        ))
    }

    /// Create intra-group movement keyframes for short distances
    /// Applies the same easing pattern as the zoom movement
    private func createInGroupMovementKeyframes(
        from prevClick: ClickEventData,
        to click: ClickEventData,
        keyframes: inout [CursorStyleKeyframe],
        cursorSettings: ClickCursorSettings
    ) {
        let dx = click.x - prevClick.x
        let dy = click.y - prevClick.y
        let distance = sqrt(dx * dx + dy * dy)

        // Short distances should move quickly
        guard distance > 0.02 else { return }

        // Use a 0.2s duration, matching the zoom move
        let moveDuration = min(0.2, click.time - prevClick.time - cursorSettings.holdTime)
        guard moveDuration > 0.05 else { return }

        let moveStartTime = click.time - moveDuration
        let velocity = distance / CGFloat(moveDuration)
        let direction = atan2(dy, dx)

        // Start keyframe for movement – use zoom easing
        keyframes.append(CursorStyleKeyframe(
            time: moveStartTime,
            position: prevClick.position,
            style: .arrow,
            visible: true,
            scale: cursorSettings.cursorScale,
            velocity: velocity,
            movementDirection: direction,
            easing: cursorSettings.moveEasing
        ))

        // Add the end keyframe at the arrival point
        // This lets KeyframeInterpolator apply easing between start and end
        keyframes.append(CursorStyleKeyframe(
            time: click.time - cursorSettings.holdTime,
            position: click.position,
            style: .arrow,
            visible: true,
            scale: cursorSettings.cursorScale,
            velocity: 0,
            movementDirection: direction,
            easing: cursorSettings.moveEasing
        ))
    }

    // MARK: - Helpers

    private func createDefaultTrack() -> CursorTrack {
        CursorTrack(
            id: UUID(),
            name: "Cursor (Click-Based)",
            isEnabled: true,
            defaultStyle: .arrow,
            defaultScale: 2.5,
            defaultVisible: true,
            styleKeyframes: nil
        )
    }

    /// Remove duplicate keyframes
    private func removeDuplicates(_ keyframes: [CursorStyleKeyframe]) -> [CursorStyleKeyframe] {
        var result: [CursorStyleKeyframe] = []
        var lastTime: TimeInterval = -1

        for keyframe in keyframes.sorted(by: { $0.time < $1.time }) {
            if abs(keyframe.time - lastTime) < 0.001 {
                result.removeLast()
            }
            result.append(keyframe)
            lastTime = keyframe.time
        }

        return result
    }
}

// MARK: - Statistics Extension

extension ClickCursorGenerator {

    /// Generate along with statistics
    func generateWithStatistics(
        from mouseData: MouseDataSource,
        settings: GeneratorSettings
    ) -> GeneratorResult<CursorTrack> {
        let startTime = Date()

        let track = generate(from: mouseData, settings: settings)

        let processingTime = Date().timeIntervalSince(startTime)
        let clicks = mouseData.clicks.filter { $0.clickType == .leftDown }

        let statistics = GeneratorStatistics(
            analyzedEvents: clicks.count,
            generatedKeyframes: track.styleKeyframes?.count ?? 0,
            processingTime: processingTime,
            additionalInfo: [
                "clickCount": clicks.count,
                "keyframeCount": track.styleKeyframes?.count ?? 0
            ]
        )

        return GeneratorResult(
            track: track,
            keyframeCount: track.styleKeyframes?.count ?? 0,
            statistics: statistics
        )
    }
}
