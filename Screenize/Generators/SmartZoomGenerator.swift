import Foundation
import CoreGraphics

/// Session-based Smart Zoom generator
/// Groups continuous activity into work sessions and applies zoom per session for smooth transitions
final class SmartZoomGenerator {

    // MARK: - Types

    /// Zoom states
    enum ZoomState {
        case idle                           // No zoom applied
        case zoomed(session: WorkSession)   // Zoomed into a session state
    }

    // MARK: - Properties

    let name = "Smart Zoom"
    let description = "Session-based intelligent auto-zoom for smooth, natural transitions"

    // MARK: - Generate

    /// Generate session-based camera track
    func generate(
        from mouseData: MouseDataSource,
        frameAnalysisArray: [VideoFrameAnalyzer.FrameAnalysis],
        uiStateSamples: [UIStateSample],
        screenBounds: CGSize,
        settings: SmartZoomSettings
    ) -> CameraTrack {
        var keyframes: [TransformKeyframe] = []

        // Add an initial keyframe representing the base state
        keyframes.append(TransformKeyframe(
            time: 0,
            zoom: settings.minZoom,
            center: NormalizedPoint(x: 0.5, y: 0.5),
            easing: .linear
        ))

        // Collect and sort activity events (include elementInfo for typing from uiStateSamples)
        let activities = ActivityCollector.collectActivities(from: mouseData, uiStateSamples: uiStateSamples)

        guard !activities.isEmpty else {
            return createEmptyTrack()
        }

        // Cluster activities into sessions
        var sessions = SessionClusterer.clusterActivitiesIntoSessions(
            activities: activities,
            settings: settings
        )

        // Replace typing session ROIs with the UI element frame
        SessionClusterer.applyTypingElementROI(
            sessions: &sessions,
            screenBounds: screenBounds,
            settings: settings
        )

        // Calculate zoom level for each session
        let zoomedSessions = sessions.map { session -> WorkSession in
            var s = session
            s.zoom = ZoomLevelCalculator.calculateSessionZoom(workArea: s.workArea, settings: settings)
            return s
        }

        // Generate keyframes for each session
        var lastSessionEndTime: TimeInterval = 0

        for (index, session) in zoomedSessions.enumerated() {
            // Check for zoom-out conditions (use frame analysis to decide)
            let shouldForceZoomOut = ZoomLevelCalculator.checkForceZoomOut(
                session: session,
                frameAnalysisArray: frameAnalysisArray,
                uiStateSamples: uiStateSamples,
                settings: settings
            )

            if shouldForceZoomOut {
                continue  // Skip zooming this session (e.g., when a modal opens)
            }

            // Determine the session center (leverage saliency and UI info)
            let sessionCenter = SessionCenterResolver.determineSessionCenter(
                session: session,
                frameAnalysisArray: frameAnalysisArray,
                settings: settings
            )

            // Create zoom-in keyframes
            let zoomInKeyframes = generateZoomInKeyframes(
                session: session,
                sessionCenter: sessionCenter,
                lastSessionEndTime: lastSessionEndTime,
                settings: settings,
                existingKeyframes: keyframes
            )
            keyframes.append(contentsOf: zoomInKeyframes)

            // Handle cases where the center must move within the session (large position change or caret leaving the viewport)
            let intraSessionResult = SessionCenterResolver.generateIntraSessionMoves(
                session: session,
                sessionCenter: sessionCenter,
                uiStateSamples: uiStateSamples,
                screenBounds: screenBounds,
                settings: settings
            )
            keyframes.append(contentsOf: intraSessionResult.keyframes)

            // Subsequent keyframes use the final center from the intra-session move
            let effectiveCenter = intraSessionResult.finalCenter

            // Generate zoom-out/transition keyframes
            let transitionResult = generateZoomOutOrTransitionKeyframes(
                session: session,
                effectiveCenter: effectiveCenter,
                index: index,
                zoomedSessions: zoomedSessions,
                mouseData: mouseData,
                frameAnalysisArray: frameAnalysisArray,
                settings: settings,
                existingKeyframes: keyframes
            )
            keyframes.append(contentsOf: transitionResult.keyframes)
            lastSessionEndTime = transitionResult.lastSessionEndTime
        }

        // Clamp keyframe centers to match the zoom level (prevents asymmetric boundaries)
        keyframes = clampKeyframeCenters(keyframes)

        // Remove duplicates and sort
        keyframes = optimizeKeyframes(keyframes)

        return convertToSegments(keyframes: keyframes, duration: mouseData.duration)
    }

    // MARK: - Zoom In Keyframes

    private func generateZoomInKeyframes(
        session: WorkSession,
        sessionCenter: NormalizedPoint,
        lastSessionEndTime: TimeInterval,
        settings: SmartZoomSettings,
        existingKeyframes: [TransformKeyframe]
    ) -> [TransformKeyframe] {
        var keyframes: [TransformKeyframe] = []

        // Generate zoom-in keyframes
        // Skip zoom-in when a direct transition kept zoom from the previous session
        let zoomInStartTime = max(lastSessionEndTime + 0.1, session.startTime - settings.focusingDuration)
        let zoomInEndTime = session.startTime
        let needsZoomIn = zoomInStartTime < zoomInEndTime

        if needsZoomIn {
            // Start the zoom-in while maintaining the current state
            // When zoom equals minZoom, keep the center at (0.5, 0.5)
            // Maintains consistency with the previous zoom-out keyframe (prevents drift in window mode)
            if zoomInStartTime > (existingKeyframes.last?.time ?? 0) + 0.05 {
                keyframes.append(TransformKeyframe(
                    time: zoomInStartTime,
                    zoom: settings.minZoom,
                    center: NormalizedPoint(x: 0.5, y: 0.5),
                    easing: settings.zoomInEasing
                ))
            }

            // Finish zooming in
            keyframes.append(TransformKeyframe(
                time: zoomInEndTime,
                zoom: session.zoom,
                center: NormalizedPoint(x: sessionCenter.x, y: sessionCenter.y),
                easing: settings.zoomInEasing
            ))
        }

        return keyframes
    }

    // MARK: - Zoom Out / Transition Keyframes

    private struct TransitionResult {
        let keyframes: [TransformKeyframe]
        let lastSessionEndTime: TimeInterval
    }

    private func generateZoomOutOrTransitionKeyframes(
        session: WorkSession,
        effectiveCenter: NormalizedPoint,
        index: Int,
        zoomedSessions: [WorkSession],
        mouseData: MouseDataSource,
        frameAnalysisArray: [VideoFrameAnalyzer.FrameAnalysis],
        settings: SmartZoomSettings,
        existingKeyframes: [TransformKeyframe]
    ) -> TransitionResult {
        var keyframes: [TransformKeyframe] = []

        // Determine when to start zooming out
        let holdEndTime = session.endTime + settings.idleTimeout
        let nextSessionStart = (index + 1 < zoomedSessions.count)
            ? zoomedSessions[index + 1].startTime
            : mouseData.duration

        // When the next session is nearby, skip zoom-out and transition directly
        let timeBetweenSessions = nextSessionStart - session.endTime
        let shouldTransitionDirectly = timeBetweenSessions < settings.idleTimeout + settings.transitionDuration

        if shouldTransitionDirectly && (index + 1 < zoomedSessions.count) {
            // Jump directly to the next session (keep zoom, only shift center)
            let nextSession = zoomedSessions[index + 1]
            let nextCenter = SessionCenterResolver.determineSessionCenter(
                session: nextSession,
                frameAnalysisArray: frameAnalysisArray,
                settings: settings
            )

            // Hold briefly at the end of the current session (use the final center)
            let moveStartTime = session.endTime + min(1.0, timeBetweenSessions * 0.3)
            keyframes.append(TransformKeyframe(
                time: moveStartTime,
                zoom: session.zoom,
                center: NormalizedPoint(x: effectiveCenter.x, y: effectiveCenter.y),
                easing: settings.moveEasing
            ))

            // Transition to the next session's zoom level and center
            let moveEndTime = nextSession.startTime - 0.05
            if moveEndTime > moveStartTime + 0.1 {
                keyframes.append(TransformKeyframe(
                    time: moveEndTime,
                    zoom: nextSession.zoom,
                    center: NormalizedPoint(x: nextCenter.x, y: nextCenter.y),
                    easing: settings.moveEasing
                ))
            }

            return TransitionResult(keyframes: keyframes, lastSessionEndTime: moveEndTime)
        } else {
            // Perform a zoom-out
            let isLastSession = (index + 1 >= zoomedSessions.count)

            // For the final session, reserve transitionDuration before the end of the video
            let zoomOutEndTime: TimeInterval
            let zoomOutStartTime: TimeInterval

            if isLastSession {
                // Complete zoom-out 0.1 seconds before the video ends
                zoomOutEndTime = mouseData.duration - 0.1
                // Start zoom-out transitionDuration seconds before completion
                zoomOutStartTime = zoomOutEndTime - settings.transitionDuration
            } else {
                zoomOutStartTime = min(holdEndTime, nextSessionStart - settings.transitionDuration - 0.1)
                zoomOutEndTime = zoomOutStartTime + settings.transitionDuration
            }

            // If the zoom-out start precedes the last keyframe, adjust those keyframes
            var allKeyframes = existingKeyframes + keyframes
            let lastKfTime = allKeyframes.last?.time ?? 0
            if isLastSession && zoomOutStartTime < lastKfTime {
                // Replace the last keyframe with the zoom-out start point
                while let last = allKeyframes.last, last.time > zoomOutStartTime - 0.1 && allKeyframes.count > 1 {
                    allKeyframes.removeLast()
                }
                // Reflecting adjusted keyframes is complicated, so just append new ones
            }

            // Hold before zoom-out (use final center to avoid jumps)
            let combinedLastTime = (existingKeyframes + keyframes).last?.time ?? 0
            if zoomOutStartTime > combinedLastTime + 0.1 {
                keyframes.append(TransformKeyframe(
                    time: zoomOutStartTime,
                    zoom: session.zoom,
                    center: NormalizedPoint(x: effectiveCenter.x, y: effectiveCenter.y),
                    easing: settings.zoomOutEasing
                ))
            }

            // Finish zoom-out (center moves to screen center)
            let zoomOutCenter = NormalizedPoint(x: 0.5, y: 0.5)

            keyframes.append(TransformKeyframe(
                time: zoomOutEndTime,
                zoom: settings.minZoom,
                center: zoomOutCenter,
                easing: settings.zoomOutEasing
            ))

            return TransitionResult(keyframes: keyframes, lastSessionEndTime: zoomOutEndTime)
        }
    }

    // MARK: - Helpers

    /// Clamp keyframe centers to the appropriate zoom level
    private func clampKeyframeCenters(_ keyframes: [TransformKeyframe]) -> [TransformKeyframe] {
        keyframes.map { kf in
            guard kf.zoom > 1.0 else { return kf }
            let halfCropRatio = 0.5 / kf.zoom
            let clampedX = max(halfCropRatio, min(1.0 - halfCropRatio, kf.center.x))
            let clampedY = max(halfCropRatio, min(1.0 - halfCropRatio, kf.center.y))
            return TransformKeyframe(
                id: kf.id,
                time: kf.time,
                zoom: kf.zoom,
                center: NormalizedPoint(x: clampedX, y: clampedY),
                easing: kf.easing
            )
        }
    }

    /// Optimize keyframes (remove duplicates, sort)
    private func optimizeKeyframes(_ keyframes: [TransformKeyframe]) -> [TransformKeyframe] {
        var result: [TransformKeyframe] = []
        var lastTime: TimeInterval = -1

        let sorted = keyframes.sorted { $0.time < $1.time }

        for keyframe in sorted {
            if abs(keyframe.time - lastTime) < 0.01 {
                if !result.isEmpty {
                    result.removeLast()
                }
            }
            result.append(keyframe)
            lastTime = keyframe.time
        }

        return result
    }

    private func createEmptyTrack() -> CameraTrack {
        let kf = TransformKeyframe(time: 0, zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        return convertToSegments(keyframes: [kf], duration: 0)
    }

    /// Convert internal keyframes to CameraTrack segments.
    private func convertToSegments(
        keyframes: [TransformKeyframe],
        duration: TimeInterval
    ) -> CameraTrack {
        let sorted = keyframes.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else {
            return CameraTrack(name: "Camera (Smart Zoom)", segments: [])
        }

        var segments: [CameraSegment] = []
        for index in 0..<sorted.count {
            let current = sorted[index]
            let nextTime = index + 1 < sorted.count ? sorted[index + 1].time : duration
            let endTime = max(current.time + 0.001, nextTime)
            segments.append(
                CameraSegment(
                    startTime: current.time,
                    endTime: min(duration, endTime),
                    startTransform: current.value,
                    endTransform: index + 1 < sorted.count ? sorted[index + 1].value : current.value,
                    interpolation: current.easing
                )
            )
        }

        return CameraTrack(name: "Camera (Smart Zoom)", segments: segments)
    }
}
