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

    /// Minimum scene duration. Scenes shorter than this are merged with neighbors.
    static let minimumSceneDuration: TimeInterval = 1.0

    /// Plan camera segments from classified intent spans.
    static func plan(
        intentSpans: [IntentSpan],
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        settings: ShotSettings,
        zoomIntensity: CGFloat = 1.0
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

        // Step 2: Merge short/similar scenes
        let merged = mergeScenes(scenes)

        // Step 3: Plan shots
        let shotPlans = ShotPlanner.plan(
            scenes: merged,
            screenBounds: screenBounds,
            eventTimeline: eventTimeline,
            frameAnalysis: frameAnalysis,
            settings: settings
        )

        // Step 4: Build chained camera segments
        return buildSegments(from: shotPlans, zoomIntensity: zoomIntensity)
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
                    confidence: 0.9,
                    source: .activeElement(element)
                )
            ]
        }

        return [
            FocusRegion(
                time: midTime,
                region: region,
                confidence: 0.7,
                source: .cursorPosition
            )
        ]
    }

    // MARK: - Scene Merging

    /// Merge scenes that are too short or have the same intent as their neighbor.
    private static func mergeScenes(_ scenes: [CameraScene]) -> [CameraScene] {
        guard scenes.count > 1 else { return scenes }

        var result: [CameraScene] = [scenes[0]]

        for i in 1..<scenes.count {
            let current = scenes[i]
            let previous = result[result.count - 1]

            let shouldMerge: Bool = {
                // Merge if current scene is too short
                let currentDuration = current.endTime - current.startTime
                if currentDuration < minimumSceneDuration {
                    return true
                }

                // Merge if same intent type as previous
                if intentKey(current.primaryIntent) == intentKey(previous.primaryIntent) {
                    return true
                }

                return false
            }()

            if shouldMerge {
                // Extend previous scene to cover current
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

    /// Intent classification key for merging. Groups similar intents.
    private static func intentKey(_ intent: UserIntent) -> String {
        switch intent {
        case .typing: return "typing"
        case .clicking: return "clicking"
        case .navigating: return "navigating"
        case .dragging: return "dragging"
        case .scrolling: return "scrolling"
        case .switching: return "switching"
        case .reading: return "reading"
        case .idle: return "idle"
        }
    }

    // MARK: - Segment Building

    /// Convert shot plans to chained CameraSegments.
    private static func buildSegments(
        from plans: [ShotPlan],
        zoomIntensity: CGFloat
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

            let easing = easingForIntent(plan.scene.primaryIntent)

            let segment = CameraSegment(
                startTime: plan.scene.startTime,
                endTime: plan.scene.endTime,
                startTransform: startTransform,
                endTransform: endTransform,
                interpolation: easing,
                mode: .manual,
                continuousTransforms: nil
            )

            segments.append(segment)
            previousEnd = endTransform
        }

        return segments
    }

    /// Choose easing curve based on intent type.
    private static func easingForIntent(_ intent: UserIntent) -> EasingCurve {
        switch intent {
        case .switching:
            return .easeInOut
        case .idle, .reading:
            return .easeOut
        default:
            return .easeInOut
        }
    }
}
