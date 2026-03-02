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
    /// 0.5 keeps natural multi-step UI traversal in one intent span.
    static let navigatingClickDistance: CGFloat = 0.5

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
            from: timeline, excludingTimeRanges: excludedRanges,
            uiStateSamples: uiStateSamples
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
        // Use original keystroke time for focus position (before anticipation shift).
        // Prefer caret/cursor signal from nearest UI sample when available.
        let nearestSample = nearestUISample(at: start, in: uiStateSamples)
        let focusPos = typingFocusPosition(
            typingStart: start,
            timeline: timeline,
            nearestSample: nearestSample
        )
        let typingContext = inferTypingContext(
            typingStart: start,
            typingEnd: end,
            timeline: timeline,
            nearestSample: nearestSample
        )
        let confidence: Float = keyCount > 3 ? 0.9 : (keyCount > 1 ? 0.7 : 0.5)
        // Shift start time backward so the camera transition completes before
        // actual typing begins, giving a natural anticipation feel.
        let anticipatedStart = max(0, start - typingAnticipation)
        return IntentSpan(
            startTime: anticipatedStart,
            endTime: end,
            intent: .typing(context: typingContext),
            confidence: confidence,
            focusPosition: focusPos,
            focusElement: nearestSample?.elementInfo
        )
    }

    private static func nearestUISample(
        at time: TimeInterval,
        in samples: [UIStateSample]
    ) -> UIStateSample? {
        samples.min(by: { abs($0.timestamp - time) < abs($1.timestamp - time) })
    }

    private static func typingFocusPosition(
        typingStart: TimeInterval,
        timeline: EventTimeline,
        nearestSample: UIStateSample?
    ) -> NormalizedPoint {
        if let caret = nearestSample?.caretBounds,
           let normalizedCaret = normalizedFrameIfPossible(caret) {
            return NormalizedPoint(
                x: normalizedCaret.midX,
                y: normalizedCaret.midY
            )
        }
        if let sample = nearestSample {
            let cursor = sample.cursorPosition
            if (0...1).contains(cursor.x), (0...1).contains(cursor.y) {
                return NormalizedPoint(x: cursor.x, y: cursor.y)
            }
        }
        return timeline.lastMousePosition(before: typingStart)
            ?? NormalizedPoint(x: 0.5, y: 0.5)
    }

    private static func inferTypingContext(
        typingStart: TimeInterval,
        typingEnd: TimeInterval,
        timeline: EventTimeline,
        nearestSample: UIStateSample?
    ) -> TypingContext {
        let role = nearestSample?.elementInfo?.role.lowercased() ?? ""
        let subrole = nearestSample?.elementInfo?.subrole?.lowercased() ?? ""
        let appName = nearestSample?.elementInfo?.applicationName?.lowercased() ?? ""

        let rangeStart = max(0, typingStart - 0.5)
        let rangeEnd = min(timeline.duration, typingEnd + 0.5)
        let nearbyEvents = timeline.events(in: rangeStart...rangeEnd)
        let bundleID = nearbyEvents.first {
            $0.metadata.appBundleID != nil
        }?.metadata.appBundleID?.lowercased() ?? ""
        if role == "axtextfield" || role == "axsearchfield"
            || role == "axsecuretextfield" || role == "axcombobox" {
            return .textField
        }
        if containsAnyKeyword(
            in: [bundleID, appName],
            keywords: [
                "terminal", "iterm", "warp", "alacritty", "wezterm", "hyper"
            ]
        ) {
            return .terminal
        }
        if containsAnyKeyword(
            in: [bundleID, appName],
            keywords: [
                "xcode", "visual studio code", "vscode", "code", "codium",
                "cursor", "zed", "sublime", "nova", "jetbrains", "intellij",
                "pycharm", "goland", "clion", "rider"
            ]
        ) {
            return .codeEditor
        }
        if role == "axtextarea" {
            if containsAnyKeyword(
                in: [bundleID, appName, subrole],
                keywords: [
                    "word", "pages", "writer", "notes", "notion", "craft",
                    "obsidian", "rich", "document"
                ]
            ) {
                return .richTextEditor
            }
            return .codeEditor
        }
        return .textField
    }

    private static func normalizedFrameIfPossible(_ frame: CGRect) -> CGRect? {
        guard frame.maxX <= 1.1 && frame.maxY <= 1.1
            && frame.minX >= -0.1 && frame.minY >= -0.1 else {
            return nil
        }
        return frame
    }

    private static func containsAnyKeyword(
        in values: [String],
        keywords: [String]
    ) -> Bool {
        values.contains { value in
            keywords.contains { value.contains($0) }
        }
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
                } else if let start = scrollStart, event.time - scrollEnd > scrollMergeGap {
                    spans.append(IntentSpan(
                        startTime: start,
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
        excludingTimeRanges: [ClosedRange<TimeInterval>],
        uiStateSamples: [UIStateSample]
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
            guard let lastClick = group.last else { continue }
            let timeDelta = click.time - lastClick.time
            let distance = click.position.distance(to: lastClick.position)

            if timeDelta <= navigatingClickWindow
                && distance <= navigatingClickDistance {
                group.append(click)
            } else {
                spans.append(contentsOf: emitClickGroup(
                    group, uiStateSamples: uiStateSamples
                ))
                group = [click]
            }
        }
        spans.append(contentsOf: emitClickGroup(
            group, uiStateSamples: uiStateSamples
        ))

        return spans
    }

    private static func emitClickGroup(
        _ group: [UnifiedEvent],
        uiStateSamples: [UIStateSample]
    ) -> [IntentSpan] {
        guard !group.isEmpty else { return [] }

        if group.count >= navigatingMinClicks {
            guard let firstEvent = group.first, let lastEvent = group.last else { return [] }
            let avgX = group.map(\.position.x).reduce(0, +) / CGFloat(group.count)
            let avgY = group.map(\.position.y).reduce(0, +) / CGFloat(group.count)
            // Use last click's context change for the navigating span
            let change = detectPostClickChange(
                clickTime: lastEvent.time, uiStateSamples: uiStateSamples
            )
            var span = IntentSpan(
                startTime: firstEvent.time,
                endTime: lastEvent.time + pointSpanDuration,
                intent: .navigating,
                confidence: 0.8,
                focusPosition: NormalizedPoint(x: avgX, y: avgY),
                focusElement: lastEvent.metadata.elementInfo
            )
            span.contextChange = change
            return [span]
        } else {
            return group.map { event in
                let change = detectPostClickChange(
                    clickTime: event.time, uiStateSamples: uiStateSamples
                )
                var span = IntentSpan(
                    startTime: event.time,
                    endTime: event.time + pointSpanDuration,
                    intent: .clicking,
                    confidence: 0.9,
                    focusPosition: event.position,
                    focusElement: event.metadata.elementInfo
                )
                span.contextChange = change
                return span
            }
        }
    }

    /// Find nearest pre-click and post-click UI state samples and detect context change.
    private static func detectPostClickChange(
        clickTime: TimeInterval,
        uiStateSamples: [UIStateSample]
    ) -> UIStateSample.ContextChange? {
        guard !uiStateSamples.isEmpty else { return nil }

        // Find nearest sample before or at the click time
        let preSample = uiStateSamples
            .filter { $0.timestamp <= clickTime }
            .max(by: { $0.timestamp < $1.timestamp })

        // Find nearest sample after the click time (within 2 seconds)
        let postSample = uiStateSamples
            .filter { $0.timestamp > clickTime && $0.timestamp <= clickTime + 2.0 }
            .min(by: { $0.timestamp < $1.timestamp })

        guard let post = postSample else { return nil }

        let change = post.detectContextChange(from: preSample)
        if case .none = change { return nil }
        return change
    }

    // MARK: - Overlap Resolution

    private static func resolveOverlaps(_ spans: [IntentSpan]) -> [IntentSpan] {
        guard spans.count > 1 else { return spans }

        var result: [IntentSpan] = [spans[0]]
        for i in 1..<spans.count {
            let span = spans[i]
            guard let prev = result.last else { continue }
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
                        focusElement: span.focusElement,
                        contextChange: span.contextChange
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
                    let previousSpan = result[result.count - 1]
                    let lastPos = previousSpan.focusPosition
                    let nextPos = span.focusPosition
                    let distance = lastPos.distance(to: nextPos)
                    let compatible = intentsCompatibleForContinuation(
                        previous: previousSpan.intent,
                        next: span.intent
                    )
                    canContinue = compatible
                        && distance < continuationMaxDistance
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
                        focusElement: result[lastIdx].focusElement,
                        contextChange: result[lastIdx].contextChange
                    )
                } else {
                    let idleFocus = result.last?.focusPosition
                        ?? NormalizedPoint(x: 0.5, y: 0.5)
                    // Gap too large (temporal or spatial): insert idle span
                    result.append(makeIdleSpan(
                        start: gapStart, end: gapEnd,
                        focusPosition: idleFocus
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

    private static func intentsCompatibleForContinuation(
        previous: UserIntent,
        next: UserIntent
    ) -> Bool {
        switch (previous, next) {
        case (.typing(let lhsCtx), .typing(let rhsCtx)):
            return lhsCtx == rhsCtx
        case (.clicking, .clicking),
             (.clicking, .navigating),
             (.navigating, .clicking),
             (.navigating, .navigating):
            return true
        case (.dragging, .dragging),
             (.scrolling, .scrolling),
             (.reading, .reading):
            return true
        default:
            return false
        }
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
