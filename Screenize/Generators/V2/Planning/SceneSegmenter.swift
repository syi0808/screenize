import Foundation
import CoreGraphics

/// Segments intent spans into semantically meaningful camera scenes.
struct SceneSegmenter {

    /// Minimum scene duration; shorter scenes are absorbed into neighbors.
    static let minSceneDuration: TimeInterval = 0.3

    // MARK: - Public API

    /// Segment a sequence of intent spans into camera scenes.
    ///
    /// Rules:
    /// - Intent category change → new scene
    /// - `.switching` or `.idle` span → always starts a new scene
    /// - Consecutive spans of the same intent merge into one scene
    /// - Scenes shorter than `minSceneDuration` are absorbed into their longest neighbor
    static func segment(
        intentSpans: [IntentSpan],
        eventTimeline: EventTimeline,
        duration: TimeInterval
    ) -> [CameraScene] {
        guard !intentSpans.isEmpty else { return [] }

        // Phase 1: Build raw scenes by merging consecutive same-intent spans
        var rawScenes = buildRawScenes(from: intentSpans, eventTimeline: eventTimeline)

        // Phase 2: Absorb short scenes into neighbors
        rawScenes = absorbShortScenes(rawScenes)

        return rawScenes
    }

    // MARK: - Phase 1: Build Raw Scenes

    private static func buildRawScenes(
        from spans: [IntentSpan],
        eventTimeline: EventTimeline
    ) -> [CameraScene] {
        var scenes: [CameraScene] = []
        var currentSpans: [IntentSpan] = [spans[0]]

        for i in 1..<spans.count {
            let span = spans[i]
            let shouldSplit = shouldStartNewScene(
                current: currentSpans, next: span
            )

            if shouldSplit {
                scenes.append(
                    buildScene(from: currentSpans, eventTimeline: eventTimeline)
                )
                currentSpans = [span]
            } else {
                currentSpans.append(span)
            }
        }

        // Finalize the last group
        scenes.append(
            buildScene(from: currentSpans, eventTimeline: eventTimeline)
        )

        return scenes
    }

    private static func shouldStartNewScene(
        current: [IntentSpan],
        next: IntentSpan
    ) -> Bool {
        // Switching always forces a new scene
        if next.intent == .switching {
            return true
        }

        // If current group ends with switching, start fresh
        if current.last?.intent == .switching {
            return true
        }

        // Idle always forces a new scene
        if next.intent == .idle {
            return true
        }

        // If current group ends with idle, start fresh
        if current.last?.intent == .idle {
            return true
        }

        // Intent category change → new scene
        let currentIntent = dominantIntent(of: current)
        if !intentsSameCategory(currentIntent, next.intent) {
            return true
        }

        return false
    }

    /// Check if two intents belong to the same category for merging purposes.
    private static func intentsSameCategory(
        _ lhs: UserIntent, _ rhs: UserIntent
    ) -> Bool {
        switch (lhs, rhs) {
        case (.typing(let ctx1), .typing(let ctx2)):
            return ctx1 == ctx2
        case (.clicking, .clicking),
             (.navigating, .navigating),
             (.scrolling, .scrolling),
             (.reading, .reading):
            return true
        case (.dragging, .dragging):
            return true
        case (.switching, .switching):
            return true
        case (.idle, .idle):
            return true
        default:
            return false
        }
    }

    // MARK: - Build Single Scene

    private static func buildScene(
        from spans: [IntentSpan],
        eventTimeline: EventTimeline
    ) -> CameraScene {
        let startTime = spans.first!.startTime
        let endTime = spans.last!.endTime
        let primary = dominantIntent(of: spans)
        let focusRegions = buildFocusRegions(from: spans)
        let appContext = extractAppContext(
            from: eventTimeline, start: startTime, end: endTime
        )

        return CameraScene(
            startTime: startTime,
            endTime: endTime,
            primaryIntent: primary,
            focusRegions: focusRegions,
            appContext: appContext
        )
    }

    /// Determine the dominant intent from a group of spans (longest total duration wins).
    private static func dominantIntent(of spans: [IntentSpan]) -> UserIntent {
        guard !spans.isEmpty else { return .idle }

        var durationByIndex: [Int: TimeInterval] = [:]
        for (index, span) in spans.enumerated() {
            let duration = span.endTime - span.startTime
            // Group by intent equality
            if let existingIndex = spans.prefix(index).firstIndex(where: {
                $0.intent == span.intent
            }) {
                durationByIndex[existingIndex, default: 0] += duration
            } else {
                durationByIndex[index, default: 0] += duration
            }
        }

        let bestIndex = durationByIndex.max { $0.value < $1.value }?.key ?? 0
        return spans[bestIndex].intent
    }

    // MARK: - Focus Regions

    private static func buildFocusRegions(
        from spans: [IntentSpan]
    ) -> [FocusRegion] {
        var regions: [FocusRegion] = []

        for span in spans {
            // Scale cursor focus region based on intent type
            let (regionW, regionH) = cursorRegionSize(for: span.intent)
            let cursorRegion = FocusRegion(
                time: span.startTime,
                region: CGRect(
                    x: CGFloat(span.focusPosition.x) - regionW / 2,
                    y: CGFloat(span.focusPosition.y) - regionH / 2,
                    width: regionW,
                    height: regionH
                ),
                confidence: span.confidence,
                source: .cursorPosition
            )
            regions.append(cursorRegion)

            // Add element-based region if available
            if let element = span.focusElement {
                let elementRegion = FocusRegion(
                    time: span.startTime,
                    region: element.frame,
                    confidence: span.confidence,
                    source: .activeElement(element)
                )
                regions.append(elementRegion)
            }
        }

        return regions
    }

    /// Return (width, height) for cursor-based focus region scaled by intent type.
    private static func cursorRegionSize(for intent: UserIntent) -> (CGFloat, CGFloat) {
        switch intent {
        case .clicking, .navigating:
            return (0.1, 0.1)       // 10% — typical click target area
        case .typing:
            return (0.15, 0.05)     // Text line shape (wider than tall)
        case .dragging:
            return (0.1, 0.1)       // Drag start/end target area
        default:
            return (0.08, 0.08)     // Default for scrolling, reading, etc.
        }
    }

    // MARK: - App Context

    private static func extractAppContext(
        from eventTimeline: EventTimeline,
        start: TimeInterval,
        end: TimeInterval
    ) -> String? {
        guard start <= end else { return nil }
        let rangeEvents = eventTimeline.events(in: start...end)
        // Find the first event with an app bundle ID
        for event in rangeEvents {
            if let bundleID = event.metadata.appBundleID {
                return bundleID
            }
        }
        return nil
    }

    // MARK: - Phase 2: Absorb Short Scenes

    private static func absorbShortScenes(
        _ scenes: [CameraScene]
    ) -> [CameraScene] {
        guard scenes.count > 1 else { return scenes }

        // Identify which scenes are short
        var isShort = scenes.map { ($0.endTime - $0.startTime) < minSceneDuration }

        // Don't absorb if all scenes are short
        if isShort.allSatisfy({ $0 }) {
            return scenes
        }

        var result: [CameraScene] = []

        for (index, scene) in scenes.enumerated() {
            if isShort[index] {
                // Find the best neighbor to absorb into
                let prevLong = result.last.map { ($0.endTime - $0.startTime) >= minSceneDuration } ?? false
                let nextLong: Bool
                if index + 1 < scenes.count {
                    nextLong = !isShort[index + 1]
                } else {
                    nextLong = false
                }

                if prevLong, let last = result.last {
                    // Absorb into previous scene
                    result[result.count - 1] = extendScene(last, to: scene.endTime)
                } else if nextLong {
                    // Will be absorbed when the next scene is processed:
                    // Mark next scene to start earlier
                    // For simplicity, just skip this scene and extend the next
                    // We handle this by marking it for the next iteration
                    result.append(scene) // Temporarily add; will merge in cleanup
                } else if !result.isEmpty {
                    // Absorb into previous regardless
                    result[result.count - 1] = extendScene(result.last!, to: scene.endTime)
                } else {
                    result.append(scene)
                }
            } else {
                // Check if previous scene in result was short and pending absorption
                if let last = result.last,
                   (last.endTime - last.startTime) < minSceneDuration {
                    // Absorb the pending short scene into this one
                    result.removeLast()
                    let merged = CameraScene(
                        startTime: last.startTime,
                        endTime: scene.endTime,
                        primaryIntent: scene.primaryIntent,
                        focusRegions: last.focusRegions + scene.focusRegions,
                        appContext: scene.appContext ?? last.appContext
                    )
                    result.append(merged)
                } else {
                    result.append(scene)
                }
            }
        }

        return result
    }

    private static func extendScene(
        _ scene: CameraScene, to newEnd: TimeInterval
    ) -> CameraScene {
        CameraScene(
            id: scene.id,
            startTime: scene.startTime,
            endTime: newEnd,
            primaryIntent: scene.primaryIntent,
            focusRegions: scene.focusRegions,
            appContext: scene.appContext
        )
    }
}
