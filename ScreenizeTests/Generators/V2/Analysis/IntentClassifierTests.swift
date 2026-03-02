import XCTest
import CoreGraphics
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

    private func firstTypingContext(in spans: [IntentSpan]) -> TypingContext? {
        for span in spans {
            if case .typing(let context) = span.intent {
                return context
            }
        }
        return nil
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
        // First keystroke at 1.0, with anticipation offset the start is shifted earlier
        let anticipation = IntentClassifier.typingAnticipation
        XCTAssertEqual(typingSpans[0].startTime, 1.0 - anticipation, accuracy: 0.01)
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

    func test_classify_typingWithCodeEditorElement_classifiesCodeEditor() {
        let keys = [makeKeyDown(at: 1.0), makeKeyDown(at: 1.2)]
        let positions = [
            MousePositionData(
                time: 0.9,
                position: NormalizedPoint(x: 0.4, y: 0.6),
                appBundleID: "com.apple.dt.Xcode"
            ),
            MousePositionData(
                time: 1.1,
                position: NormalizedPoint(x: 0.42, y: 0.62),
                appBundleID: "com.apple.dt.Xcode"
            )
        ]
        let sample = UIStateSample(
            timestamp: 1.0,
            cursorPosition: CGPoint(x: 0.4, y: 0.6),
            elementInfo: UIElementInfo(
                role: "AXTextArea",
                subrole: nil,
                frame: CGRect(x: 0.35, y: 0.55, width: 0.3, height: 0.2),
                title: nil,
                isClickable: true,
                applicationName: "Xcode"
            ),
            caretBounds: CGRect(x: 0.41, y: 0.61, width: 0.01, height: 0.02)
        )
        let mouseData = MockMouseDataSource(
            duration: 5.0,
            positions: positions,
            keyboardEvents: keys
        )

        let timeline = EventTimeline.build(
            from: mouseData,
            uiStateSamples: [sample]
        )
        let spans = IntentClassifier.classify(
            events: timeline,
            uiStateSamples: [sample]
        )

        XCTAssertEqual(firstTypingContext(in: spans), .codeEditor)
    }

    func test_classify_typingWithTerminalBundleID_classifiesTerminal() {
        let keys = [makeKeyDown(at: 1.0), makeKeyDown(at: 1.2)]
        let positions = [
            MousePositionData(
                time: 0.9,
                position: NormalizedPoint(x: 0.55, y: 0.45),
                appBundleID: "com.googlecode.iterm2"
            ),
            MousePositionData(
                time: 1.1,
                position: NormalizedPoint(x: 0.56, y: 0.46),
                appBundleID: "com.googlecode.iterm2"
            )
        ]
        let mouseData = MockMouseDataSource(
            duration: 5.0,
            positions: positions,
            keyboardEvents: keys
        )
        let timeline = EventTimeline.build(from: mouseData)
        let spans = IntentClassifier.classify(events: timeline, uiStateSamples: [])

        XCTAssertEqual(firstTypingContext(in: spans), .terminal)
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

    func test_classify_twoClicksModeratelyFar_stillNavigating() {
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.2, y: 0.3)),
            makeClick(at: 2.2, position: NormalizedPoint(x: 0.55, y: 0.3)),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let spans = classify(mouseData)

        let navigatingSpans = spans.filter { $0.intent == .navigating }
        XCTAssertEqual(
            navigatingSpans.count,
            1,
            "Natural UI traversal clicks should remain in one navigating span"
        )
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

    func test_classify_navigatingFocus_biasedTowardRecentClicks() {
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.20, y: 0.50)),
            makeClick(at: 1.5, position: NormalizedPoint(x: 0.35, y: 0.50)),
            makeClick(at: 1.9, position: NormalizedPoint(x: 0.50, y: 0.50)),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let spans = classify(mouseData)

        guard let navigating = spans.first(where: { $0.intent == .navigating }) else {
            XCTFail("Expected navigating span")
            return
        }

        let simpleAverageX = (0.20 + 0.35 + 0.50) / 3.0
        XCTAssertGreaterThan(
            navigating.focusPosition.x,
            simpleAverageX,
            "Navigating focus should bias toward recent clicks"
        )
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
        // Use distant positions so clicks don't group as navigating (distance > 0.3)
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.1, y: 0.1), appBundleID: "com.app.one"),
            makeClick(at: 3.0, position: NormalizedPoint(x: 0.9, y: 0.9), appBundleID: "com.app.two"),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let spans = classify(mouseData)

        let switchingSpans = spans.filter { $0.intent == .switching }
        XCTAssertGreaterThanOrEqual(switchingSpans.count, 1)
    }

    func test_classify_sameAppAlias_doesNotProduceSwitchingSpan() {
        let positions = [
            MousePositionData(
                time: 0.9,
                position: NormalizedPoint(x: 0.4, y: 0.6),
                appBundleID: "com.apple.dt.xcode"
            ),
            MousePositionData(
                time: 1.1,
                position: NormalizedPoint(x: 0.42, y: 0.62),
                appBundleID: "com.apple.dt.xcode"
            )
        ]
        let uiStates = [
            UIStateSample(
                timestamp: 1.0,
                cursorPosition: CGPoint(x: 0.4, y: 0.6),
                elementInfo: UIElementInfo(
                    role: "AXTextArea",
                    subrole: nil,
                    frame: CGRect(x: 0.35, y: 0.55, width: 0.3, height: 0.2),
                    title: nil,
                    isClickable: true,
                    applicationName: "Xcode"
                )
            )
        ]

        let mouseData = MockMouseDataSource(duration: 3.0, positions: positions)
        let timeline = EventTimeline.build(from: mouseData, uiStateSamples: uiStates)
        let spans = IntentClassifier.classify(events: timeline, uiStateSamples: uiStates)

        let switchingSpans = spans.filter { $0.intent == .switching }
        XCTAssertEqual(
            switchingSpans.count,
            0,
            "Bundle ID and app name aliases for the same app must not trigger switching"
        )
    }

    func test_classify_uiStateApplicationChange_producesSwitchingSpan() {
        let clicks = [
            makeClick(at: 0.8, position: NormalizedPoint(x: 0.2, y: 0.3)),
            makeClick(at: 2.8, position: NormalizedPoint(x: 0.8, y: 0.7)),
        ]
        let positions = [
            MousePositionData(
                time: 0.6,
                position: NormalizedPoint(x: 0.2, y: 0.3)
            ),
            MousePositionData(
                time: 1.8,
                position: NormalizedPoint(x: 0.5, y: 0.5)
            ),
            MousePositionData(
                time: 2.8,
                position: NormalizedPoint(x: 0.8, y: 0.7)
            )
        ]
        let uiStates = [
            UIStateSample(
                timestamp: 1.0,
                cursorPosition: CGPoint(x: 0.2, y: 0.3),
                elementInfo: UIElementInfo(
                    role: "AXTextArea",
                    subrole: nil,
                    frame: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.2),
                    title: nil,
                    isClickable: true,
                    applicationName: "Xcode"
                )
            ),
            UIStateSample(
                timestamp: 2.0,
                cursorPosition: CGPoint(x: 0.8, y: 0.7),
                elementInfo: UIElementInfo(
                    role: "AXButton",
                    subrole: nil,
                    frame: CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.1),
                    title: nil,
                    isClickable: true,
                    applicationName: "Safari"
                )
            )
        ]

        let mouseData = MockMouseDataSource(
            duration: 5.0,
            positions: positions,
            clicks: clicks
        )
        let timeline = EventTimeline.build(
            from: mouseData,
            uiStateSamples: uiStates
        )
        let spans = IntentClassifier.classify(
            events: timeline,
            uiStateSamples: uiStates
        )

        let switchingSpans = spans.filter { $0.intent == .switching }
        XCTAssertGreaterThanOrEqual(
            switchingSpans.count,
            1,
            "App changes in UI state samples should produce switching spans"
        )
    }

    // MARK: - Click Context Change

    func test_classify_clickContextChange_ignoresLateSample() {
        let clicks = [makeClick(at: 1.0, position: NormalizedPoint(x: 0.3, y: 0.4))]
        let mouseData = MockMouseDataSource(duration: 4.0, clicks: clicks)
        let uiStates = [
            UIStateSample(
                timestamp: 0.9,
                cursorPosition: CGPoint(x: 0.3, y: 0.4),
                elementInfo: UIElementInfo(
                    role: "AXTextField",
                    subrole: nil,
                    frame: CGRect(x: 0.2, y: 0.3, width: 0.1, height: 0.05),
                    title: nil,
                    isClickable: true,
                    applicationName: "Xcode"
                )
            ),
            UIStateSample(
                timestamp: 1.95,
                cursorPosition: CGPoint(x: 0.3, y: 0.4),
                elementInfo: UIElementInfo(
                    role: "AXTextArea",
                    subrole: nil,
                    frame: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                    title: nil,
                    isClickable: true,
                    applicationName: "Xcode"
                )
            )
        ]

        let timeline = EventTimeline.build(from: mouseData, uiStateSamples: uiStates)
        let spans = IntentClassifier.classify(events: timeline, uiStateSamples: uiStates)

        guard let clicking = spans.first(where: { $0.intent == .clicking }) else {
            XCTFail("Expected clicking span")
            return
        }
        XCTAssertNil(
            clicking.contextChange,
            "UI sample outside context-change window should be ignored"
        )
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

    // MARK: - Gap Filling

    func test_classify_mediumGap_insertsIdleSpan() {
        // Two clicks far apart in time — should have an idle span between them
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.2, y: 0.2)),
            makeClick(at: 4.0, position: NormalizedPoint(x: 0.8, y: 0.8)),
        ]
        let mouseData = MockMouseDataSource(duration: 6.0, clicks: clicks)
        let spans = classify(mouseData)

        let idleSpans = spans.filter { $0.intent == .idle }
        // Gap between click spans should produce an idle span
        let idleBetweenClicks = idleSpans.filter { $0.startTime >= 1.0 && $0.endTime <= 4.5 }
        XCTAssertGreaterThanOrEqual(
            idleBetweenClicks.count, 1,
            "Large gap between clicks should insert idle span. " +
            "All spans: \(spans.map { "[\(String(format: "%.2f", $0.startTime))-\(String(format: "%.2f", $0.endTime))] \($0.intent)" })"
        )
    }

    func test_classify_insertedIdleFocus_keepsPreviousContext() {
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.2, y: 0.2)),
            makeClick(at: 4.0, position: NormalizedPoint(x: 0.8, y: 0.8)),
        ]
        let mouseData = MockMouseDataSource(duration: 6.0, clicks: clicks)
        let spans = classify(mouseData)

        guard let idle = spans.first(where: {
            $0.intent == .idle && $0.startTime >= 1.4 && $0.endTime <= 4.0
        }) else {
            XCTFail("Expected an idle span between click actions")
            return
        }

        XCTAssertEqual(idle.focusPosition.x, 0.2, accuracy: 0.01)
        XCTAssertEqual(idle.focusPosition.y, 0.2, accuracy: 0.01)
    }

    func test_classify_gapFillingDoesNotExtendSpanBeyond300ms() {
        // Click at 1.0s, then another at 5.0s — large gap
        // First click span ends around 1.5s (pointSpanDuration=0.5)
        // The first span should NOT be extended to 5.0s
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.2, y: 0.2)),
            makeClick(at: 5.0, position: NormalizedPoint(x: 0.8, y: 0.8)),
        ]
        let mouseData = MockMouseDataSource(duration: 7.0, clicks: clicks)
        let spans = classify(mouseData)

        let clickingSpans = spans.filter { $0.intent == .clicking }
        XCTAssertGreaterThanOrEqual(clickingSpans.count, 1)
        // First clicking span should NOT extend to cover the large gap
        let firstClick = clickingSpans[0]
        XCTAssertLessThan(
            firstClick.endTime, 3.0,
            "First click span should not be extended across a large gap. Span end: \(firstClick.endTime)"
        )
    }

    func test_classify_realisticSequence_producesMultipleIntentSpans() {
        // Realistic sequence: click, type, click, type with ~1s gaps
        let clicks = [
            makeClick(at: 0.5, position: NormalizedPoint(x: 0.3, y: 0.3)),
            makeClick(at: 5.0, position: NormalizedPoint(x: 0.7, y: 0.7)),
        ]
        let keys = [
            makeKeyDown(at: 2.0), makeKeyDown(at: 2.2), makeKeyDown(at: 2.4),
            makeKeyDown(at: 6.5), makeKeyDown(at: 6.7), makeKeyDown(at: 6.9),
        ]
        let mouseData = MockMouseDataSource(duration: 10.0, clicks: clicks, keyboardEvents: keys)
        let spans = classify(mouseData)

        let actionSpans = spans.filter { $0.intent != .idle }
        XCTAssertGreaterThanOrEqual(
            actionSpans.count, 4,
            "click, type, click, type should produce at least 4 action spans. " +
            "Got: \(spans.map { "[\(String(format: "%.2f", $0.startTime))-\(String(format: "%.2f", $0.endTime))] \($0.intent)" })"
        )
    }

    func test_classify_thenSegment_realisticRecording_producesMultipleScenes() {
        // 15s recording: clicks at 0.5, 4.0, 10.0; typing at 1.5-2.3, 5.0-6.2
        let clicks = [
            makeClick(at: 0.5, position: NormalizedPoint(x: 0.3, y: 0.3)),
            makeClick(at: 4.0, position: NormalizedPoint(x: 0.7, y: 0.7)),
            makeClick(at: 10.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let keys = [
            makeKeyDown(at: 1.5), makeKeyDown(at: 1.7), makeKeyDown(at: 1.9),
            makeKeyDown(at: 2.1), makeKeyDown(at: 2.3),
            makeKeyDown(at: 5.0), makeKeyDown(at: 5.2), makeKeyDown(at: 5.4),
            makeKeyDown(at: 5.6), makeKeyDown(at: 5.8), makeKeyDown(at: 6.0),
            makeKeyDown(at: 6.2),
        ]
        let mouseData = MockMouseDataSource(
            duration: 15.0, clicks: clicks, keyboardEvents: keys
        )
        let timeline = EventTimeline.build(from: mouseData)
        let intentSpans = IntentClassifier.classify(
            events: timeline, uiStateSamples: []
        )
        let scenes = SceneSegmenter.segment(
            intentSpans: intentSpans, eventTimeline: timeline, duration: 15.0
        )

        // Should produce at least 3 distinct scenes (click, type, click, type, click)
        XCTAssertGreaterThanOrEqual(
            scenes.count, 3,
            "Realistic recording should produce >= 3 scenes. " +
            "Got \(scenes.count): \(scenes.map { "[\(String(format: "%.1f", $0.startTime))-\(String(format: "%.1f", $0.endTime))] \($0.primaryIntent)" })"
        )
    }

    func test_classify_shortGapUnder300ms_extendsPreviousSpan() {
        // Two clicks 0.2s apart at same position — gap < 0.3s should NOT insert idle
        // (continuation of same action)
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            makeClick(at: 1.3, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, clicks: clicks)
        let spans = classify(mouseData)

        // The gap between the two clicks is tiny (~0.2s: first ends at 1.1, second starts at 1.3)
        // No idle span should be inserted in this range
        let idleBetweenClicks = spans.filter { $0.intent == .idle && $0.startTime > 1.0 && $0.endTime < 1.3 }
        XCTAssertEqual(
            idleBetweenClicks.count, 0,
            "Very short gap (<0.3s) should not insert idle span"
        )
    }

    func test_classify_shortGapDifferentIntents_insertsIdleSpan() {
        // Clicking and typing with a short spatially-close gap should still insert idle
        // because they are different intent families.
        let clicks = [
            makeClick(at: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5))
        ]
        let keys = [
            makeKeyDown(at: 2.2, character: "a"),
            makeKeyDown(at: 2.4, character: "b")
        ]
        let mouseData = MockMouseDataSource(
            duration: 6.0,
            positions: [
                MousePositionData(
                    time: 1.0,
                    position: NormalizedPoint(x: 0.5, y: 0.5)
                ),
                MousePositionData(
                    time: 2.2,
                    position: NormalizedPoint(x: 0.5, y: 0.5)
                )
            ],
            clicks: clicks,
            keyboardEvents: keys
        )
        let spans = classify(mouseData)
        let idleSpans = spans.filter { span in
            if case .idle = span.intent { return true }
            return false
        }
        let idleBetweenClickAndTyping = idleSpans.contains {
            $0.startTime >= 1.45 && $0.endTime <= 1.85
        }
        XCTAssertTrue(
            idleBetweenClickAndTyping,
            "Different intents should not be merged across short gaps"
        )
    }

    // MARK: - Typing Anticipation

    func test_classify_typingSpan_startTimeShiftedByAnticipation() {
        let keys = [
            makeKeyDown(at: 3.0, character: "h"),
            makeKeyDown(at: 3.2, character: "e"),
            makeKeyDown(at: 3.4, character: "l"),
            makeKeyDown(at: 3.6, character: "l"),
            makeKeyDown(at: 3.8, character: "o"),
        ]
        let mouseData = MockMouseDataSource(keyboardEvents: keys)
        let spans = classify(mouseData)

        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        XCTAssertEqual(typingSpans.count, 1)

        // First keystroke at 3.0s, anticipation = 0.4s → span starts at 2.6s
        let anticipation = IntentClassifier.typingAnticipation
        XCTAssertEqual(
            typingSpans[0].startTime, 3.0 - anticipation, accuracy: 0.01,
            "Typing span should start \(anticipation)s before first keystroke"
        )
        // End time should not be affected
        XCTAssertEqual(typingSpans[0].endTime, 3.8, accuracy: 0.01)
    }

    func test_classify_typingAnticipation_clampedToZero() {
        // Typing starts very early — anticipation should not go below 0
        let keys = [
            makeKeyDown(at: 0.1, character: "a"),
            makeKeyDown(at: 0.3, character: "b"),
        ]
        let mouseData = MockMouseDataSource(keyboardEvents: keys)
        let spans = classify(mouseData)

        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        XCTAssertEqual(typingSpans.count, 1)
        XCTAssertGreaterThanOrEqual(
            typingSpans[0].startTime, 0,
            "Typing span start should never be negative"
        )
    }

    func test_classify_typingAnticipation_focusPositionUsesOriginalTime() {
        // Mouse at (0.2, 0.3) before typing, then moves to (0.8, 0.9) after
        // Focus should use position before the first keystroke (not the anticipated start)
        let positions = [
            MousePositionData(
                time: 2.0, position: NormalizedPoint(x: 0.2, y: 0.3)
            ),
            MousePositionData(
                time: 2.5, position: NormalizedPoint(x: 0.5, y: 0.5)
            ),
            MousePositionData(
                time: 4.0, position: NormalizedPoint(x: 0.8, y: 0.9)
            ),
        ]
        let keys = [
            makeKeyDown(at: 3.0, character: "a"),
            makeKeyDown(at: 3.2, character: "b"),
            makeKeyDown(at: 3.4, character: "c"),
            makeKeyDown(at: 3.6, character: "d"),
        ]
        let mouseData = MockMouseDataSource(
            positions: positions, keyboardEvents: keys
        )
        let spans = classify(mouseData)

        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        XCTAssertEqual(typingSpans.count, 1)

        // Focus should be the mouse position before t=3.0 (the actual keystroke time)
        // That's (0.5, 0.5) at t=2.5
        XCTAssertEqual(typingSpans[0].focusPosition.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(typingSpans[0].focusPosition.y, 0.5, accuracy: 0.01)
    }

    func test_classify_typingAnticipation_doesNotOverlapPreviousSpan() {
        // Click at 2.5s, typing at 3.0s — the anticipation (0.4s) would push
        // typing start to 2.6s, which overlaps the click span.
        // The overlap resolver should trim the typing span's start.
        let clicks = [makeClick(at: 2.5)]
        let keys = [
            makeKeyDown(at: 3.0, character: "a"),
            makeKeyDown(at: 3.2, character: "b"),
            makeKeyDown(at: 3.4, character: "c"),
            makeKeyDown(at: 3.6, character: "d"),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks, keyboardEvents: keys)
        let spans = classify(mouseData)

        // Verify no overlaps exist in the classified spans
        for i in 0..<spans.count - 1 {
            XCTAssertLessThanOrEqual(
                spans[i].endTime, spans[i + 1].startTime + 0.01,
                "Span \(i) end \(spans[i].endTime) should not overlap " +
                "span \(i + 1) start \(spans[i + 1].startTime)"
            )
        }
    }

    func test_classify_twoTypingSessions_bothHaveAnticipation() {
        let keys = [
            // First session
            makeKeyDown(at: 2.0, character: "a"),
            makeKeyDown(at: 2.2, character: "b"),
            makeKeyDown(at: 2.4, character: "c"),
            // Gap > 1.5s
            // Second session
            makeKeyDown(at: 5.0, character: "x"),
            makeKeyDown(at: 5.2, character: "y"),
            makeKeyDown(at: 5.4, character: "z"),
        ]
        let mouseData = MockMouseDataSource(keyboardEvents: keys)
        let spans = classify(mouseData)

        let typingSpans = spans.filter {
            if case .typing = $0.intent { return true }
            return false
        }
        XCTAssertEqual(typingSpans.count, 2)

        let anticipation = IntentClassifier.typingAnticipation
        XCTAssertEqual(
            typingSpans[0].startTime, 2.0 - anticipation, accuracy: 0.01
        )
        XCTAssertEqual(
            typingSpans[1].startTime, 5.0 - anticipation, accuracy: 0.01
        )
    }
}
