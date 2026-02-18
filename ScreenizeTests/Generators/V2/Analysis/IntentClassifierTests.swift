import XCTest
@testable import Screenize

final class IntentClassifierTests: XCTestCase {

    // MARK: - Helpers

    private func makeKeyDown(
        at time: TimeInterval,
        character: String = "a",
        modifiers: KeyboardEventData.ModifierFlags = KeyboardEventData.ModifierFlags(rawValue: 0)
    ) -> KeyboardEventData {
        KeyboardEventData(
            time: time, keyCode: 0, eventType: .keyDown,
            modifiers: modifiers, character: character
        )
    }

    private func makeClick(
        at time: TimeInterval,
        position: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5),
        clickType: ClickEventData.ClickType = .leftDown,
        appBundleID: String? = nil
    ) -> ClickEventData {
        ClickEventData(
            time: time, position: position,
            clickType: clickType, appBundleID: appBundleID, elementInfo: nil
        )
    }

    private func classify(_ mouseData: MockMouseDataSource) -> [IntentSpan] {
        let timeline = EventTimeline.build(from: mouseData)
        return IntentClassifier.classify(events: timeline, uiStateSamples: [])
    }

    // MARK: - Empty Input

    func test_classify_emptyTimeline_producesIdleSpan() {
        let mouseData = MockMouseDataSource(duration: 10.0)
        let spans = classify(mouseData)

        // Should produce at least an idle span covering the duration
        XCTAssertFalse(spans.isEmpty)
        XCTAssertEqual(spans.first?.intent, .idle)
    }

    // MARK: - Typing Detection

    func test_classify_keyDownSequence_producesTypingSpan() {
        let keys = [
            makeKeyDown(at: 1.0, character: "h"),
            makeKeyDown(at: 1.2, character: "e"),
            makeKeyDown(at: 1.4, character: "l"),
            makeKeyDown(at: 1.6, character: "l"),
            makeKeyDown(at: 1.8, character: "o"),
        ]
        let mouseData = MockMouseDataSource(keyboardEvents: keys)
        let spans = classify(mouseData)

        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        XCTAssertEqual(typingSpans.count, 1)
        XCTAssertEqual(typingSpans[0].startTime, 1.0, accuracy: 0.01)
        XCTAssertEqual(typingSpans[0].endTime, 1.8, accuracy: 0.01)
    }

    func test_classify_keyDownWithShortcutModifiers_notTyping() {
        let keys = [
            KeyboardEventData(
                time: 1.0, keyCode: 0, eventType: .keyDown,
                modifiers: .command, character: "c"
            ),
            KeyboardEventData(
                time: 2.0, keyCode: 0, eventType: .keyDown,
                modifiers: .control, character: "a"
            ),
        ]
        let mouseData = MockMouseDataSource(keyboardEvents: keys)
        let spans = classify(mouseData)

        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        XCTAssertEqual(typingSpans.count, 0, "Shortcut-modified keys should not produce typing spans")
    }

    func test_classify_typingSessionGapOver1_5s_splitIntoTwoSpans() {
        let keys = [
            makeKeyDown(at: 1.0),
            makeKeyDown(at: 1.2),
            makeKeyDown(at: 1.4),
            // Gap > 1.5s
            makeKeyDown(at: 4.0),
            makeKeyDown(at: 4.2),
        ]
        let mouseData = MockMouseDataSource(keyboardEvents: keys)
        let spans = classify(mouseData)

        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        XCTAssertEqual(typingSpans.count, 2)
    }

    func test_classify_singleKeyDown_producesTypingSpan() {
        let keys = [makeKeyDown(at: 3.0)]
        let mouseData = MockMouseDataSource(keyboardEvents: keys)
        let spans = classify(mouseData)

        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        XCTAssertEqual(typingSpans.count, 1)
    }

    func test_classify_typingConfidence_higherWithMoreKeystrokes() {
        // Single keystroke
        let singleKey = MockMouseDataSource(keyboardEvents: [makeKeyDown(at: 1.0)])
        let singleSpans = classify(singleKey).filter {
            if case .typing = $0.intent { return true }
            return false
        }

        // Many keystrokes
        let manyKeys = MockMouseDataSource(keyboardEvents: [
            makeKeyDown(at: 1.0), makeKeyDown(at: 1.1),
            makeKeyDown(at: 1.2), makeKeyDown(at: 1.3),
            makeKeyDown(at: 1.4),
        ])
        let manySpans = classify(manyKeys).filter {
            if case .typing = $0.intent { return true }
            return false
        }

        XCTAssertFalse(singleSpans.isEmpty)
        XCTAssertFalse(manySpans.isEmpty)
        XCTAssertGreaterThan(manySpans[0].confidence, singleSpans[0].confidence)
    }

    // MARK: - Clicking Detection

    func test_classify_singleLeftDownClick_producesClickingSpan() {
        let clicks = [makeClick(at: 2.0)]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let spans = classify(mouseData)

        let clickingSpans = spans.filter { $0.intent == .clicking }
        XCTAssertEqual(clickingSpans.count, 1)
    }

    // MARK: - Navigating Detection

    func test_classify_twoClicksWithin2s_producesNavigatingSpan() {
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.3, y: 0.5)),
            makeClick(at: 2.0, position: NormalizedPoint(x: 0.4, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let spans = classify(mouseData)

        let navigatingSpans = spans.filter { $0.intent == .navigating }
        XCTAssertEqual(navigatingSpans.count, 1)
    }

    func test_classify_twoClicksFarApart_producesSeparateClickingSpans() {
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.1, y: 0.1)),
            makeClick(at: 2.0, position: NormalizedPoint(x: 0.9, y: 0.9)),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let spans = classify(mouseData)

        let clickingSpans = spans.filter { $0.intent == .clicking }
        XCTAssertEqual(clickingSpans.count, 2, "Clicks > 0.3 apart should be separate clicking spans")
    }

    func test_classify_threeRapidClicks_singleNavigatingSpan() {
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            makeClick(at: 1.3, position: NormalizedPoint(x: 0.5, y: 0.5)),
            makeClick(at: 1.6, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let spans = classify(mouseData)

        let navigatingSpans = spans.filter { $0.intent == .navigating }
        XCTAssertEqual(navigatingSpans.count, 1)
    }

    // MARK: - Dragging Detection

    func test_classify_dragStartEnd_producesDraggingSpan() {
        let drags = [
            DragEventData(
                startTime: 2.0, endTime: 3.5,
                startPosition: NormalizedPoint(x: 0.2, y: 0.3),
                endPosition: NormalizedPoint(x: 0.8, y: 0.7),
                dragType: .selection
            ),
        ]
        let mouseData = MockMouseDataSource(dragEvents: drags)
        let spans = classify(mouseData)

        let draggingSpans = spans.filter {
            if case .dragging = $0.intent { return true }
            return false
        }
        XCTAssertEqual(draggingSpans.count, 1)
    }

    func test_classify_dragSpan_timeMatchesDragDuration() {
        let drags = [
            DragEventData(
                startTime: 2.0, endTime: 3.5,
                startPosition: NormalizedPoint(x: 0.2, y: 0.3),
                endPosition: NormalizedPoint(x: 0.8, y: 0.7),
                dragType: .move
            ),
        ]
        let mouseData = MockMouseDataSource(dragEvents: drags)
        let spans = classify(mouseData)

        let draggingSpans = spans.filter {
            if case .dragging = $0.intent { return true }
            return false
        }
        XCTAssertEqual(draggingSpans[0].startTime, 2.0, accuracy: 0.01)
        XCTAssertEqual(draggingSpans[0].endTime, 3.5, accuracy: 0.01)
    }

    // MARK: - Switching Detection

    func test_classify_appBundleIDChange_producesSwitchingSpan() {
        let clicks = [
            makeClick(at: 1.0, appBundleID: "com.app.one"),
            makeClick(at: 3.0, appBundleID: "com.app.two"),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let spans = classify(mouseData)

        let switchingSpans = spans.filter { $0.intent == .switching }
        XCTAssertGreaterThanOrEqual(switchingSpans.count, 1)
    }

    // MARK: - Idle Detection

    func test_classify_noEventsFor5Seconds_producesIdleSpan() {
        // Click at 1s, then nothing until 8s, then click at 8s
        let clicks = [
            makeClick(at: 1.0),
            makeClick(at: 8.0),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let spans = classify(mouseData)

        let idleSpans = spans.filter { $0.intent == .idle }
        // The gap between ~1.1s and ~8.0s (~6.9s) exceeds the 5s idle threshold
        XCTAssertGreaterThanOrEqual(idleSpans.count, 1)
    }

    // MARK: - Span Ordering and Coverage

    func test_classify_spansAreSortedByTime() {
        let keys = [makeKeyDown(at: 5.0), makeKeyDown(at: 5.2)]
        let clicks = [makeClick(at: 1.0)]
        let mouseData = MockMouseDataSource(clicks: clicks, keyboardEvents: keys)
        let spans = classify(mouseData)

        let startTimes = spans.map(\.startTime)
        XCTAssertEqual(startTimes, startTimes.sorted())
    }

    func test_classify_spansDoNotOverlap() {
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            makeClick(at: 1.5, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let keys = [makeKeyDown(at: 3.0), makeKeyDown(at: 3.2)]
        let mouseData = MockMouseDataSource(clicks: clicks, keyboardEvents: keys)
        let spans = classify(mouseData)

        for i in 0..<spans.count - 1 {
            XCTAssertLessThanOrEqual(
                spans[i].endTime, spans[i + 1].startTime + 0.01,
                "Span \(i) (end: \(spans[i].endTime)) overlaps with span \(i + 1) (start: \(spans[i + 1].startTime))"
            )
        }
    }

    func test_classify_spansCoverFullDuration() {
        let clicks = [makeClick(at: 2.0), makeClick(at: 7.0)]
        let mouseData = MockMouseDataSource(duration: 10.0, clicks: clicks)
        let spans = classify(mouseData)

        guard let firstSpan = spans.first, let lastSpan = spans.last else {
            XCTFail("Expected at least one span")
            return
        }

        // First span should start at or near 0
        XCTAssertLessThanOrEqual(firstSpan.startTime, 0.5)
        // Last span should end at or near duration
        XCTAssertGreaterThanOrEqual(lastSpan.endTime, 9.5)
    }

    // MARK: - Mixed Scenarios

    func test_classify_clickThenTyping_twoSeparateIntents() {
        let clicks = [makeClick(at: 1.0)]
        let keys = [
            makeKeyDown(at: 3.0),
            makeKeyDown(at: 3.2),
            makeKeyDown(at: 3.4),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks, keyboardEvents: keys)
        let spans = classify(mouseData)

        let clickingSpans = spans.filter { $0.intent == .clicking }
        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        XCTAssertEqual(clickingSpans.count, 1)
        XCTAssertEqual(typingSpans.count, 1)
        // Click should come before typing
        XCTAssertLessThan(clickingSpans[0].startTime, typingSpans[0].startTime)
    }

    func test_classify_typingInterruptedByClick_threeSpans() {
        let keys = [
            makeKeyDown(at: 1.0), makeKeyDown(at: 1.2), makeKeyDown(at: 1.4),
            // Click interrupts at 3.0
            // Then more typing at 5.0
            makeKeyDown(at: 5.0), makeKeyDown(at: 5.2),
        ]
        let clicks = [makeClick(at: 3.0)]
        let mouseData = MockMouseDataSource(clicks: clicks, keyboardEvents: keys)
        let spans = classify(mouseData)

        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        let clickingSpans = spans.filter { $0.intent == .clicking }

        XCTAssertEqual(typingSpans.count, 2)
        XCTAssertEqual(clickingSpans.count, 1)
    }
}
