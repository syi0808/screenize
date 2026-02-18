import Foundation
import CoreGraphics

// MARK: - Intra-Session Moves Result

/// Result of generating intra-session center movement keyframes
struct IntraSessionMovesResult {
    let keyframes: [TransformKeyframe]
    let finalCenter: NormalizedPoint  // Center after the last movement (used in hold keyframes)
}

// MARK: - Session Center Resolver

/// Determine session centers and generate intra-session movement keyframes
struct SessionCenterResolver {

    /// Determine session centers (based on cursor/activity positions while ensuring the full target element fits in the viewport)
    static func determineSessionCenter(
        session: WorkSession,
        frameAnalysisArray: [VideoFrameAnalyzer.FrameAnalysis],
        settings: SmartZoomSettings
    ) -> NormalizedPoint {
        let typingActivities = session.activities.filter { $0.type == .typing }
        let hasTextElement = typingActivities.contains { activity in
            guard let info = activity.elementInfo else { return false }
            return UIElementInfo.textInputRoles.contains(info.role)
        }

        if hasTextElement && !typingActivities.isEmpty {
            // Use the cursor (typing location) as the center rather than the element's midpoint
            let cursorPosition = typingActivities.last?.position ?? session.center

            // Clamp the center so the entire element remains within the viewport
            var center = constrainCenterToShowElement(
                desiredCenter: cursorPosition,
                elementBounds: session.workArea,
                zoom: session.zoom
            )

            // Apply saliency blending lightly (cursor position takes priority during typing)
            if settings.saliencyEnabled {
                let midTime = (session.startTime + session.endTime) / 2
                if let analysis = ZoomLevelCalculator.lookupFrameAnalysis(at: midTime, in: frameAnalysisArray),
                   let saliencyCenter = analysis.saliencyCenter {
                    let saliencyPoint = NormalizedPoint(x: saliencyCenter.x, y: saliencyCenter.y)
                    let distance = center.distance(to: saliencyPoint)
                    if distance < settings.saliencyMaxDistance {
                        center = center.interpolated(to: saliencyPoint, amount: settings.saliencyBlendFactor * 0.3)
                    }
                }
            }

            return center.clamped()
        }

        // For clicks/drags: weighted average (give recent activity more weight)
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0
        var totalWeight: CGFloat = 0

        for (index, activity) in session.activities.enumerated() {
            let weight: CGFloat = 1.0 + CGFloat(index) * 0.5
            weightedX += activity.position.x * weight
            weightedY += activity.position.y * weight
            totalWeight += weight
        }

        var center = NormalizedPoint(
            x: weightedX / totalWeight,
            y: weightedY / totalWeight
        )

        // When an UI element is detected, restrict the center so the whole element remains visible
        let elementsWithInfo = session.activities.compactMap { $0.elementInfo }
        if let largestElement = elementsWithInfo.max(by: {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        }) {
            let frame = largestElement.frame
            if frame.width > 0.02 && frame.height > 0.02 && frame.width < 0.8 {
                let elementBounds = CGRect(
                    x: max(0, frame.minX - settings.workAreaPadding),
                    y: max(0, frame.minY - settings.workAreaPadding),
                    width: min(1.0, frame.width + settings.workAreaPadding * 2),
                    height: min(1.0, frame.height + settings.workAreaPadding * 2)
                )
                center = constrainCenterToShowElement(
                    desiredCenter: center,
                    elementBounds: elementBounds,
                    zoom: session.zoom
                )
            }
        }

        // Blend saliency scores
        if settings.saliencyEnabled {
            let midTime = (session.startTime + session.endTime) / 2
            if let analysis = ZoomLevelCalculator.lookupFrameAnalysis(at: midTime, in: frameAnalysisArray),
               let saliencyCenter = analysis.saliencyCenter {
                let saliencyPoint = NormalizedPoint(x: saliencyCenter.x, y: saliencyCenter.y)
                let distance = center.distance(to: saliencyPoint)
                if distance < settings.saliencyMaxDistance {
                    center = center.interpolated(to: saliencyPoint, amount: settings.saliencyBlendFactor)
                }
            }
        }

        return center.clamped()
    }

    /// Clamp the center so the entire target element fits within the viewport
    /// Adjust the center so the viewport [center - 0.5/zoom, center + 0.5/zoom] contains elementBounds
    static func constrainCenterToShowElement(
        desiredCenter: NormalizedPoint,
        elementBounds: CGRect,
        zoom: CGFloat
    ) -> NormalizedPoint {
        guard zoom > 1.0 else { return desiredCenter }

        let halfViewportW = 0.5 / zoom
        let halfViewportH = 0.5 / zoom

        // To include the element within the viewport:
        // center.x + halfViewport >= element.maxX  →  center.x >= element.maxX - halfViewport
        // center.x - halfViewport <= element.minX  →  center.x <= element.minX + halfViewport
        let minCenterX = elementBounds.maxX - halfViewportW
        let maxCenterX = elementBounds.minX + halfViewportW

        let minCenterY = elementBounds.maxY - halfViewportH
        let maxCenterY = elementBounds.minY + halfViewportH

        var constrainedX = desiredCenter.x
        var constrainedY = desiredCenter.y

        if minCenterX <= maxCenterX {
            // If the viewport is larger than the element, clamp to a valid range around the cursor
            constrainedX = max(minCenterX, min(maxCenterX, desiredCenter.x))
        } else {
            // If the viewport is smaller than the element (zoom too high), fall back to the element center
            constrainedX = elementBounds.midX
        }

        if minCenterY <= maxCenterY {
            constrainedY = max(minCenterY, min(maxCenterY, desiredCenter.y))
        } else {
            constrainedY = elementBounds.midY
        }

        return NormalizedPoint(x: constrainedX, y: constrainedY)
    }

    /// Generate intra-session center movement keyframes (only for significant shifts)
    /// - Returns: Generated keyframes and the final center position
    static func generateIntraSessionMoves(
        session: WorkSession,
        sessionCenter: NormalizedPoint,
        uiStateSamples: [UIStateSample],
        screenBounds: CGSize,
        settings: SmartZoomSettings
    ) -> IntraSessionMovesResult {
        var moves: [TransformKeyframe] = []

        // Check if this is a typing session
        let isTypingSession = session.activities.contains { $0.type == .typing }

        // Use caret-based movement logic for typing
        if isTypingSession {
            let caretMoves = generateCaretBasedMoves(
                session: session,
                sessionCenter: sessionCenter,
                uiStateSamples: uiStateSamples,
                screenBounds: screenBounds,
                settings: settings
            )
            if !caretMoves.keyframes.isEmpty {
                return caretMoves
            }
        }

        // No movement needed when the session has fewer than three activities
        guard session.activities.count >= 3 else {
            return IntraSessionMovesResult(keyframes: [], finalCenter: sessionCenter)
        }

        // Split the session into time-ordered subgroups
        var lastMoveCenter = sessionCenter
        var lastMoveTime = session.startTime

        for activity in session.activities {
            let distance = activity.position.distance(to: lastMoveCenter)
            let timeDelta = activity.time - lastMoveTime

            // Consider it a meaningful move when the distance is significant and enough time has passed
            if distance > 0.12 && timeDelta > 0.8 {
                let newCenter = lastMoveCenter.interpolated(to: activity.position, amount: 0.6)

                // Start moving
                moves.append(TransformKeyframe(
                    time: activity.time - 0.3,
                    zoom: session.zoom,
                    center: NormalizedPoint(x: lastMoveCenter.x, y: lastMoveCenter.y),
                    easing: settings.moveEasing
                ))

                // Complete the movement
                moves.append(TransformKeyframe(
                    time: activity.time,
                    zoom: session.zoom,
                    center: NormalizedPoint(x: newCenter.x, y: newCenter.y),
                    easing: settings.moveEasing
                ))

                lastMoveCenter = newCenter
                lastMoveTime = activity.time
            }
        }

        return IntraSessionMovesResult(keyframes: moves, finalCenter: lastMoveCenter)
    }

    /// Generate center movement keyframes when the caret leaves the viewport during a typing session
    static func generateCaretBasedMoves(
        session: WorkSession,
        sessionCenter: NormalizedPoint,
        uiStateSamples: [UIStateSample],
        screenBounds: CGSize,
        settings: SmartZoomSettings
    ) -> IntraSessionMovesResult {
        guard screenBounds.width > 0, screenBounds.height > 0 else {
            return IntraSessionMovesResult(keyframes: [], finalCenter: sessionCenter)
        }

        var moves: [TransformKeyframe] = []
        var currentCenter = sessionCenter
        var lastMoveTime = session.startTime

        // Filter UIStateSamples within the session time range
        let sessionSamples = uiStateSamples.filter {
            $0.timestamp >= session.startTime && $0.timestamp <= session.endTime
        }.sorted { $0.timestamp < $1.timestamp }

        // Minimum movement interval to avoid jittery adjustments
        let minMoveInterval: TimeInterval = 0.5
        // Viewport margin (leave padding near the edges)
        let viewportMargin: CGFloat = 0.08

        for sample in sessionSamples {
            // Process only samples that include a caret position
            guard let caretBounds = sample.caretBounds else { continue }

            // Convert the caret center to normalized coordinates
            let caretCenterX = (caretBounds.midX) / screenBounds.width
            let caretCenterY = (caretBounds.midY) / screenBounds.height
            let caretPosition = NormalizedPoint(x: caretCenterX, y: caretCenterY)

            // Check whether the caret is outside the current viewport
            let isOutside = caretPosition.isOutsideViewport(
                zoom: session.zoom,
                center: currentCenter,
                margin: viewportMargin
            )

                // Check the time interval
            let timeSinceLastMove = sample.timestamp - lastMoveTime

            if isOutside && timeSinceLastMove >= minMoveInterval {
                // Recompute a center that includes the caret
                let newCenter = caretPosition.centerToIncludeInViewport(
                    zoom: session.zoom,
                    currentCenter: currentCenter,
                    padding: viewportMargin
                )

                // Movement start keyframe (hold current position)
                let moveStartTime = sample.timestamp - 0.2
                if moveStartTime > lastMoveTime + 0.1 {
                    moves.append(TransformKeyframe(
                        time: moveStartTime,
                        zoom: session.zoom,
                        center: NormalizedPoint(x: currentCenter.x, y: currentCenter.y),
                        easing: settings.moveEasing
                    ))
                }

                // Movement completion keyframe
                moves.append(TransformKeyframe(
                    time: sample.timestamp,
                    zoom: session.zoom,
                    center: NormalizedPoint(x: newCenter.x, y: newCenter.y),
                    easing: settings.moveEasing
                ))

                currentCenter = newCenter
                lastMoveTime = sample.timestamp
            }
        }

        return IntraSessionMovesResult(keyframes: moves, finalCenter: currentCenter)
    }
}
