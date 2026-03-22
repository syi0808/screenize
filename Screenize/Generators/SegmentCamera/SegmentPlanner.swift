import Foundation
import CoreGraphics

/// Converts intent spans into discrete, editable camera segments.
///
/// Pipeline:
/// 1. Convert IntentSpans to CameraScenes
/// 2. Merge short/similar scenes
/// 3. Plan shots via ShotPlanner
/// 4. Build chained CameraSegments (each start = previous end)
struct SegmentPlanner {

    /// Plan camera segments from classified intent spans.
    static func plan(
        intentSpans: [IntentSpan],
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        settings: ShotSettings,
        zoomIntensity: CGFloat = 1.0,
        mouseData: MouseDataSource? = nil
    ) -> [CameraSegment] {
        guard !intentSpans.isEmpty else { return [] }

        // Step 1: Convert IntentSpans to CameraScenes
        let scenes = intentSpans.map { span in
            CameraScene(
                startTime: span.startTime,
                endTime: span.endTime,
                primaryIntent: span.intent,
                focusRegions: makeFocusRegions(from: span),
                contextChange: span.contextChange
            )
        }

        // Step 1b: Absorb low-confidence scenes into neighbors
        let absorbed = absorbLowConfidenceScenes(scenes)

        // Step 2: Merge short/similar scenes
        let merged = mergeScenes(absorbed)

        // Step 3: Plan shots
        let shotPlans = ShotPlanner.plan(
            scenes: merged,
            screenBounds: screenBounds,
            eventTimeline: eventTimeline,
            frameAnalysis: frameAnalysis,
            settings: settings
        )

        // Step 4: Build chained camera segments
        let segments = buildSegments(from: shotPlans, zoomIntensity: zoomIntensity, mouseData: mouseData)

        // Step 5: Resolve transition styles between adjacent segments
        return TransitionResolver.resolve(segments, intentSpans: intentSpans)
    }

    // MARK: - Focus Regions

    private static func makeFocusRegions(from span: IntentSpan) -> [FocusRegion] {
        let midTime = (span.startTime + span.endTime) / 2
        let pos = span.focusPosition
        let pointSize: CGFloat = 0.01
        let region = CGRect(
            x: pos.x - pointSize / 2,
            y: pos.y - pointSize / 2,
            width: pointSize,
            height: pointSize
        )

        if let element = span.focusElement {
            return [
                FocusRegion(
                    time: midTime,
                    region: element.frame,
                    confidence: span.confidence,
                    source: .activeElement(element)
                )
            ]
        }

        return [
            FocusRegion(
                time: midTime,
                region: region,
                confidence: span.confidence,
                source: .cursorPosition
            )
        ]
    }

    // MARK: - Low-Confidence Absorption

    /// Absorb low-confidence scenes into their neighbors.
    ///
    /// Scenes where max focus region confidence falls in the `.none` band
    /// are removed: their time range is given to the preceding scene
    /// (extended endTime). If the first scene is low-confidence, it is
    /// replaced with an idle scene covering the same time range.
    static func absorbLowConfidenceScenes(
        _ scenes: [CameraScene]
    ) -> [CameraScene] {
        guard !scenes.isEmpty else { return scenes }

        var result: [CameraScene] = []

        for scene in scenes {
            let maxConfidence = scene.focusRegions.map(\.confidence).max() ?? 0
            let band = ConfidenceBands.band(for: maxConfidence)

            if band == .none {
                if result.isEmpty {
                    // First scene is low-confidence: replace with idle
                    let idle = CameraScene(
                        id: scene.id,
                        startTime: scene.startTime,
                        endTime: scene.endTime,
                        primaryIntent: .idle,
                        focusRegions: scene.focusRegions,
                        appContext: scene.appContext,
                        contextChange: scene.contextChange
                    )
                    result.append(idle)
                } else {
                    // Extend preceding scene to cover this time range
                    let previous = result[result.count - 1]
                    let extended = CameraScene(
                        id: previous.id,
                        startTime: previous.startTime,
                        endTime: scene.endTime,
                        primaryIntent: previous.primaryIntent,
                        focusRegions: previous.focusRegions,
                        appContext: previous.appContext,
                        contextChange: previous.contextChange
                    )
                    result[result.count - 1] = extended
                }
            } else {
                result.append(scene)
            }
        }

        return result
    }

    // MARK: - Scene Merging

    /// Merge scenes only when they target the same position within a short time gap.
    private static func mergeScenes(_ scenes: [CameraScene]) -> [CameraScene] {
        guard scenes.count > 1 else { return scenes }

        var result: [CameraScene] = [scenes[0]]

        for i in 1..<scenes.count {
            let current = scenes[i]
            let previous = result[result.count - 1]

            let shouldMerge: Bool = {
                // Only merge if positions are very close AND time gap is tiny
                let prevCenter = focusCenter(of: previous)
                let currCenter = focusCenter(of: current)
                let distance = prevCenter.distance(to: currCenter)
                let gap = current.startTime - previous.endTime

                return distance < 0.05 && gap < 0.5
            }()

            if shouldMerge {
                let merged = CameraScene(
                    id: previous.id,
                    startTime: previous.startTime,
                    endTime: current.endTime,
                    primaryIntent: previous.primaryIntent,
                    focusRegions: previous.focusRegions + current.focusRegions,
                    appContext: previous.appContext,
                    contextChange: current.contextChange ?? previous.contextChange
                )
                result[result.count - 1] = merged
            } else {
                result.append(current)
            }
        }

        return result
    }

    /// Compute the center of a scene's focus regions.
    private static func focusCenter(of scene: CameraScene) -> NormalizedPoint {
        guard !scene.focusRegions.isEmpty else {
            return NormalizedPoint(x: 0.5, y: 0.5)
        }
        let sumX = scene.focusRegions.reduce(CGFloat(0)) { $0 + $1.region.midX }
        let sumY = scene.focusRegions.reduce(CGFloat(0)) { $0 + $1.region.midY }
        let count = CGFloat(scene.focusRegions.count)
        return NormalizedPoint(x: sumX / count, y: sumY / count)
    }

    // MARK: - Cursor Travel Time

    private static let splitDistanceThreshold: CGFloat = 0.05
    private static let splitZoomThreshold: CGFloat = 0.1
    static let arrivalRadius: CGFloat = 0.08
    private static let minTransitionDuration: TimeInterval = 0.15
    private static let maxTransitionDuration: TimeInterval = 0.8
    private static let minHoldDuration: TimeInterval = 0.1
    private static let fallbackSpeedFactor: TimeInterval = 1.0

    /// Compute how long the cursor takes to arrive near the target position.
    static func cursorTravelTime(
        from startPosition: NormalizedPoint,
        to targetPosition: NormalizedPoint,
        mouseData: MouseDataSource,
        searchStart: TimeInterval,
        searchEnd: TimeInterval
    ) -> TimeInterval {
        let positions = mouseData.positions.filter {
            $0.time >= searchStart && $0.time <= searchEnd
        }

        for pos in positions {
            let dx = pos.position.x - targetPosition.x
            let dy = pos.position.y - targetPosition.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist <= arrivalRadius {
                let elapsed = pos.time - searchStart
                return min(max(elapsed, minTransitionDuration), maxTransitionDuration)
            }
        }

        let dx = targetPosition.x - startPosition.x
        let dy = targetPosition.y - startPosition.y
        let distance = sqrt(dx * dx + dy * dy)
        let fallback = Double(distance) * fallbackSpeedFactor
        return min(max(fallback, minTransitionDuration), maxTransitionDuration)
    }

    // MARK: - Segment Building

    /// Convert shot plans to chained CameraSegments.
    /// When mouseData is provided, splits segments into transition + hold
    /// when the camera needs to move a significant distance.
    private static func buildSegments(
        from plans: [ShotPlan],
        zoomIntensity: CGFloat,
        mouseData: MouseDataSource? = nil
    ) -> [CameraSegment] {
        guard !plans.isEmpty else { return [] }

        var segments: [CameraSegment] = []
        var previousEnd: TransformValue?

        for plan in plans {
            let rawZoom = plan.idealZoom
            let zoom = max(1.0, 1.0 + (rawZoom - 1.0) * zoomIntensity)
            let center = ShotPlanner.clampCenter(plan.idealCenter, zoom: zoom)
            let endTransform = TransformValue(zoom: zoom, center: center)

            let startTransform = previousEnd ?? endTransform
            let spanStart = plan.scene.startTime
            let spanEnd = plan.scene.endTime

            let needsSplit: Bool = {
                guard previousEnd != nil, mouseData != nil else { return false }
                let dx = startTransform.center.x - endTransform.center.x
                let dy = startTransform.center.y - endTransform.center.y
                let distance = sqrt(dx * dx + dy * dy)
                let zoomDiff = abs(startTransform.zoom - endTransform.zoom)
                return distance > splitDistanceThreshold || zoomDiff > splitZoomThreshold
            }()

            if needsSplit, let mouseData = mouseData {
                let travelTime = cursorTravelTime(
                    from: startTransform.center,
                    to: endTransform.center,
                    mouseData: mouseData,
                    searchStart: spanStart,
                    searchEnd: spanEnd
                )

                let transitionEnd = spanStart + travelTime
                let holdDuration = spanEnd - transitionEnd

                if holdDuration >= minHoldDuration {
                    let transition = CameraSegment(
                        startTime: spanStart,
                        endTime: transitionEnd,
                        kind: .manual(
                            startTransform: startTransform,
                            endTransform: endTransform
                        )
                    )
                    let hold = CameraSegment(
                        startTime: transitionEnd,
                        endTime: spanEnd,
                        kind: .manual(
                            startTransform: endTransform,
                            endTransform: endTransform
                        )
                    )
                    segments.append(transition)
                    segments.append(hold)
                } else {
                    let transition = CameraSegment(
                        startTime: spanStart,
                        endTime: spanEnd,
                        kind: .manual(
                            startTransform: startTransform,
                            endTransform: endTransform
                        )
                    )
                    segments.append(transition)
                }
            } else {
                let segment = CameraSegment(
                    startTime: spanStart,
                    endTime: spanEnd,
                    kind: .manual(
                        startTransform: startTransform,
                        endTransform: endTransform
                    )
                )
                segments.append(segment)
            }

            previousEnd = endTransform
        }

        // Ensure no segments overlap: clamp each segment's startTime to previous endTime
        for i in 1..<segments.count {
            if segments[i].startTime < segments[i - 1].endTime {
                segments[i].startTime = segments[i - 1].endTime
            }
            // Ensure valid duration after clamping
            if segments[i].endTime <= segments[i].startTime {
                segments[i].endTime = segments[i].startTime + 0.01
            }
        }

        return segments
    }

}
