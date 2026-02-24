import Foundation
import CoreGraphics

// MARK: - Intent Classifier

/// Rule-based classifier that segments an event timeline into intent spans.
struct IntentClassifier {

    // MARK: - Configuration Constants

    /// Maximum gap between keyDown events within a typing session.
    static let typingSessionTimeout: TimeInterval = 1.5

    /// Maximum time between clicks to count as navigating.
    static let navigatingClickWindow: TimeInterval = 2.0

    /// Maximum spatial distance between clicks to count as navigating.
    /// 0.25 covers a quarter of the screen — clicks within this range during UI navigation are grouped.
    static let navigatingClickDistance: CGFloat = 0.25

    /// Minimum number of clicks for a navigating span.
    static let navigatingMinClicks: Int = 2

    /// Idle threshold (no actionable events for this duration).
    static let idleThreshold: TimeInterval = 5.0

    /// Max gap that extends the previous span (action continuation).
    /// Gaps larger than this insert an idle span instead.
    /// Set high enough to bridge natural pauses between clicks (1-2s).
    static let continuationGapThreshold: TimeInterval = 1.5

    /// Max spatial distance (normalized) for continuation gap merging.
    /// Prevents merging temporally close but spatially distant clicks.
    static let continuationMaxDistance: CGFloat = 0.20

    /// Maximum gap between scroll events to merge into one span.
    static let scrollMergeGap: TimeInterval = 1.0

    /// Brief span duration for point events (clicks, switching).
    /// Must be >= SceneSegmenter.minSceneDuration to avoid scene absorption.
    static let pointSpanDuration: TimeInterval = 0.5

    /// Anticipation time for typing scenes: camera arrives this much before the
    /// first keystroke so the transition completes before typing begins.
    static let typingAnticipation: TimeInterval = 0.4

    // MARK: - Classification

    /// Classify an event timeline into intent spans.
    static func classify(
        events timeline: EventTimeline,
        uiStateSamples: [UIStateSample]
    ) -> [IntentSpan] {
        guard timeline.duration > 0 else { return [] }

        // Filter actionable events (mouseMove and uiStateChange are context, not actions)
        let hasActionableEvents = timeline.events.contains { event in
            switch event.kind {
            case .mouseMove, .uiStateChange: return false
            default: return true
            }
        }

        guard hasActionableEvents else {
            return [makeIdleSpan(start: 0, end: timeline.duration)]
        }

        // Detect each intent type independently
        let typingSpans = detectTypingSpans(
            from: timeline, uiStateSamples: uiStateSamples
        )
        let draggingSpans = detectDraggingSpans(from: timeline)
        let scrollingSpans = detectScrollingSpans(from: timeline)
        let switchingSpans = detectSwitchingSpans(from: timeline)

        // Click/navigating detection excludes events already covered by typing/dragging
        let excludedRanges = (typingSpans + draggingSpans).map {
            $0.startTime...$0.endTime
        }
        let clickSpans = detectClickSpans(
            from: timeline, excludingTimeRanges: excludedRanges
        )

        // Merge all spans and sort by start time
        var allSpans = typingSpans + draggingSpans + scrollingSpans
            + switchingSpans + clickSpans
        allSpans.sort { $0.startTime < $1.startTime }

        // Resolve overlaps (earlier-detected spans win)
        allSpans = resolveOverlaps(allSpans)

        // Fill gaps with idle spans
        return fillGaps(spans: allSpans, duration: timeline.duration)
    }

    // MARK: - Typing Detection

    private static func detectTypingSpans(
        from timeline: EventTimeline,
        uiStateSamples: [UIStateSample]
    ) -> [IntentSpan] {
        let keyDownEvents = timeline.events.filter { event in
            if case .keyDown(let data) = event.kind {
                return !data.modifiers.hasShortcutModifiers
            }
            return false
        }
        guard !keyDownEvents.isEmpty else { return [] }

        var spans: [IntentSpan] = []
        var sessionStart = keyDownEvents[0].time
        var lastKeyTime = keyDownEvents[0].time
        var keyCount = 1

        for i in 1..<keyDownEvents.count {
            let event = keyDownEvents[i]
            if event.time - lastKeyTime > typingSessionTimeout {
                spans.append(makeTypingSpan(
                    start: sessionStart, end: lastKeyTime,
                    keyCount: keyCount, timeline: timeline,
                    uiStateSamples: uiStateSamples
                ))
                sessionStart = event.time
                keyCount = 1
            } else {
                keyCount += 1
            }
            lastKeyTime = event.time
        }

        spans.append(makeTypingSpan(
            start: sessionStart, end: lastKeyTime,
            keyCount: keyCount, timeline: timeline,
            uiStateSamples: uiStateSamples
        ))

        return spans
    }

    private static func makeTypingSpan(
        start: TimeInterval,
        end: TimeInterval,
        keyCount: Int,
        timeline: EventTimeline,
        uiStateSamples: [UIStateSample]
    ) -> IntentSpan {
        // Use original keystroke time for focus position (before anticipation shift)
        let focusPos = timeline.lastMousePosition(before: start)
            ?? NormalizedPoint(x: 0.5, y: 0.5)

        let nearestSample = uiStateSamples
            .min(by: { abs($0.timestamp - start) < abs($1.timestamp - start) })

        let confidence: Float = keyCount > 3 ? 0.9 : (keyCount > 1 ? 0.7 : 0.5)

        // Shift start time backward so the camera transition completes before
        // actual typing begins, giving a natural anticipation feel.
        let anticipatedStart = max(0, start - typingAnticipation)

        return IntentSpan(
            startTime: anticipatedStart,
            endTime: end,
            intent: .typing(context: .textField),
            confidence: confidence,
            focusPosition: focusPos,
            focusElement: nearestSample?.elementInfo
        )
    }

    // MARK: - Dragging Detection

    private static func detectDraggingSpans(
        from timeline: EventTimeline
    ) -> [IntentSpan] {
        var spans: [IntentSpan] = []

        for event in timeline.events {
            if case .dragStart(let data) = event.kind {
                let dragContext: DragContext
                switch data.dragType {
                case .selection: dragContext = .selection
                case .move: dragContext = .move
                case .resize: dragContext = .resize
                }

                spans.append(IntentSpan(
                    startTime: data.startTime,
                    endTime: data.endTime,
                    intent: .dragging(dragContext),
                    confidence: 0.95,
                    focusPosition: data.startPosition,
                    focusElement: nil
                ))
            }
        }

        return spans
    }

    // MARK: - Scrolling Detection

    private static func detectScrollingSpans(
        from timeline: EventTimeline
    ) -> [IntentSpan] {
        var spans: [IntentSpan] = []
        var scrollStart: TimeInterval?
        var scrollEnd: TimeInterval = 0
        var scrollPosition = NormalizedPoint(x: 0.5, y: 0.5)

        for event in timeline.events {
            if case .scroll = event.kind {
                if scrollStart == nil {
                    scrollStart = event.time
                    scrollPosition = event.position
                } else if event.time - scrollEnd > scrollMergeGap {
                    spans.append(IntentSpan(
                        startTime: scrollStart!,
                        endTime: scrollEnd,
                        intent: .scrolling,
                        confidence: 0.9,
                        focusPosition: scrollPosition,
                        focusElement: nil
                    ))
                    scrollStart = event.time
                    scrollPosition = event.position
                }
                scrollEnd = event.time
            }
        }

        if let start = scrollStart {
            spans.append(IntentSpan(
                startTime: start,
                endTime: scrollEnd,
                intent: .scrolling,
                confidence: 0.9,
                focusPosition: scrollPosition,
                focusElement: nil
            ))
        }

        return spans
    }

    // MARK: - Switching Detection

    private static func detectSwitchingSpans(
        from timeline: EventTimeline
    ) -> [IntentSpan] {
        var spans: [IntentSpan] = []
        var lastAppBundleID: String?

        for event in timeline.events {
            guard let currentApp = event.metadata.appBundleID else { continue }
            if let lastApp = lastAppBundleID, lastApp != currentApp {
                let switchTime = event.time
                spans.append(IntentSpan(
                    startTime: max(0, switchTime - pointSpanDuration),
                    endTime: switchTime + pointSpanDuration,
                    intent: .switching,
                    confidence: 0.85,
                    focusPosition: event.position,
                    focusElement: nil
                ))
            }
            lastAppBundleID = currentApp
        }

        return spans
    }

    // MARK: - Click / Navigating Detection

    private static func detectClickSpans(
        from timeline: EventTimeline,
        excludingTimeRanges: [ClosedRange<TimeInterval>]
    ) -> [IntentSpan] {
        let leftDownClicks = timeline.events.filter { event in
            if case .click(let data) = event.kind, data.clickType == .leftDown {
                return !excludingTimeRanges.contains { $0.contains(event.time) }
            }
            return false
        }
        guard !leftDownClicks.isEmpty else { return [] }

        var spans: [IntentSpan] = []
        var group: [UnifiedEvent] = [leftDownClicks[0]]

        for i in 1..<leftDownClicks.count {
            let click = leftDownClicks[i]
            let lastClick = group.last!
            let timeDelta = click.time - lastClick.time
            let distance = click.position.distance(to: lastClick.position)

            if timeDelta <= navigatingClickWindow
                && distance <= navigatingClickDistance {
                group.append(click)
            } else {
                spans.append(contentsOf: emitClickGroup(group))
                group = [click]
            }
        }
        spans.append(contentsOf: emitClickGroup(group))

        return spans
    }

    private static func emitClickGroup(_ group: [UnifiedEvent]) -> [IntentSpan] {
        guard !group.isEmpty else { return [] }

        if group.count >= navigatingMinClicks {
            let avgX = group.map(\.position.x).reduce(0, +) / CGFloat(group.count)
            let avgY = group.map(\.position.y).reduce(0, +) / CGFloat(group.count)
            return [IntentSpan(
                startTime: group.first!.time,
                endTime: group.last!.time + pointSpanDuration,
                intent: .navigating,
                confidence: 0.8,
                focusPosition: NormalizedPoint(x: avgX, y: avgY),
                focusElement: group.last?.metadata.elementInfo
            )]
        } else {
            return group.map { event in
                IntentSpan(
                    startTime: event.time,
                    endTime: event.time + pointSpanDuration,
                    intent: .clicking,
                    confidence: 0.9,
                    focusPosition: event.position,
                    focusElement: event.metadata.elementInfo
                )
            }
        }
    }

    // MARK: - Overlap Resolution

    private static func resolveOverlaps(_ spans: [IntentSpan]) -> [IntentSpan] {
        guard spans.count > 1 else { return spans }

        var result: [IntentSpan] = [spans[0]]
        for i in 1..<spans.count {
            let span = spans[i]
            let prev = result.last!
            if span.startTime < prev.endTime {
                // Trim the later span's start to after the earlier span's end
                let trimmedStart = prev.endTime
                if trimmedStart < span.endTime {
                    result.append(IntentSpan(
                        startTime: trimmedStart,
                        endTime: span.endTime,
                        intent: span.intent,
                        confidence: span.confidence,
                        focusPosition: span.focusPosition,
                        focusElement: span.focusElement
                    ))
                }
                // If trimming removes the span entirely, skip it
            } else {
                result.append(span)
            }
        }
        return result
    }

    // MARK: - Gap Filling

    private static func fillGaps(
        spans: [IntentSpan],
        duration: TimeInterval
    ) -> [IntentSpan] {
        guard !spans.isEmpty else {
            return [makeIdleSpan(start: 0, end: duration)]
        }

        var result: [IntentSpan] = []
        var currentTime: TimeInterval = 0

        for span in spans {
            let gapStart = currentTime
            let gapEnd = span.startTime

            if gapEnd - gapStart > 0.01 {
                let canContinue: Bool
                if gapEnd - gapStart <= continuationGapThreshold && !result.isEmpty {
                    let lastPos = result[result.count - 1].focusPosition
                    let nextPos = span.focusPosition
                    let distance = lastPos.distance(to: nextPos)
                    canContinue = distance < continuationMaxDistance
                } else {
                    canContinue = false
                }

                if canContinue {
                    // Nearby gap: extend previous span (same action continuation)
                    let lastIdx = result.count - 1
                    result[lastIdx] = IntentSpan(
                        startTime: result[lastIdx].startTime,
                        endTime: gapEnd,
                        intent: result[lastIdx].intent,
                        confidence: result[lastIdx].confidence,
                        focusPosition: result[lastIdx].focusPosition,
                        focusElement: result[lastIdx].focusElement
                    )
                } else {
                    // Gap too large (temporal or spatial): insert idle span
                    result.append(makeIdleSpan(
                        start: gapStart, end: gapEnd,
                        focusPosition: span.focusPosition
                    ))
                }
            }

            result.append(span)
            currentTime = span.endTime
        }

        // Trailing gap
        if duration - currentTime > 0.01 {
            let lastPos = result.last?.focusPosition
                ?? NormalizedPoint(x: 0.5, y: 0.5)
            result.append(makeIdleSpan(
                start: currentTime, end: duration, focusPosition: lastPos
            ))
        }

        return result
    }

    // MARK: - Helpers

    private static func makeIdleSpan(
        start: TimeInterval,
        end: TimeInterval,
        focusPosition: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5)
    ) -> IntentSpan {
        IntentSpan(
            startTime: start,
            endTime: end,
            intent: .idle,
            confidence: 0.8,
            focusPosition: focusPosition,
            focusElement: nil
        )
    }
}
