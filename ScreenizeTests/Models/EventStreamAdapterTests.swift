import XCTest
@testable import Screenize

final class EventStreamAdapterTests: XCTestCase {

    // MARK: - Helpers

    /// Create a minimal metadata for testing.
    private func makeMetadata(
        widthPx: Int = 3024,
        heightPx: Int = 1964,
        scaleFactor: Double = 2.0,
        sessionStartMs: Int64 = 1000000
    ) -> PolyRecordingMetadata {
        PolyRecordingMetadata(
            formatVersion: 2,
            recorderName: "test",
            recorderVersion: "1.0",
            createdAt: "2026-01-01T00:00:00Z",
            processTimeStartMs: sessionStartMs,
            processTimeEndMs: sessionStartMs + 10000,
            unixTimeStartMs: 0,
            display: .init(
                widthPx: widthPx, heightPx: heightPx,
                scaleFactor: scaleFactor
            )
        )
    }

    private func makeMouseDown(
        at ms: Int64, x: Double, y: Double
    ) -> PolyMouseClickEvent {
        PolyMouseClickEvent(
            type: "mouseDown", processTimeMs: ms, unixTimeMs: 0,
            x: x, y: y, button: "left", cursorId: nil, activeModifiers: [],
            elementRole: nil,
            elementSubrole: nil,
            elementTitle: nil,
            elementAppName: nil,
            elementFrameX: nil,
            elementFrameY: nil,
            elementFrameW: nil,
            elementFrameH: nil,
            elementIsClickable: nil
        )
    }

    private func makeMouseUp(
        at ms: Int64, x: Double, y: Double
    ) -> PolyMouseClickEvent {
        PolyMouseClickEvent(
            type: "mouseUp", processTimeMs: ms, unixTimeMs: 0,
            x: x, y: y, button: "left", cursorId: nil, activeModifiers: [],
            elementRole: nil,
            elementSubrole: nil,
            elementTitle: nil,
            elementAppName: nil,
            elementFrameX: nil,
            elementFrameY: nil,
            elementFrameW: nil,
            elementFrameH: nil,
            elementIsClickable: nil
        )
    }

    private func makeMove(
        at ms: Int64, x: Double, y: Double
    ) -> PolyMouseMoveEvent {
        PolyMouseMoveEvent(
            type: "mouseMoved", processTimeMs: ms, unixTimeMs: 0,
            x: x, y: y, cursorId: nil, activeModifiers: [], button: nil
        )
    }

    private func makeAdapter(
        moves: [PolyMouseMoveEvent] = [],
        clicks: [PolyMouseClickEvent] = [],
        keystrokes: [PolyKeystrokeEvent] = [],
        metadata: PolyRecordingMetadata? = nil
    ) -> EventStreamAdapter {
        EventStreamAdapter(
            mouseMoves: moves,
            mouseClicks: clicks,
            keystrokes: keystrokes,
            metadata: metadata ?? makeMetadata(),
            duration: 10.0,
            frameRate: 60.0
        )
    }

    // MARK: - Keystroke keyCode Passthrough

    func test_keystrokeKeyCode_passedThrough() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        let keystrokes = [
            PolyKeystrokeEvent(
                type: "keyDown",
                processTimeMs: sessionStart + 1000,
                unixTimeMs: 0,
                keyCode: 19,
                character: "2",
                isARepeat: false,
                activeModifiers: ["command", "shift"]
            )
        ]

        let adapter = makeAdapter(keystrokes: keystrokes, metadata: meta)

        XCTAssertEqual(adapter.keyboardEvents.count, 1)
        XCTAssertEqual(adapter.keyboardEvents[0].keyCode, 19)
    }

    func test_keystrokeKeyCode_nilDefaultsToZero() {
        // Old recordings without keyCode field
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        let keystrokes = [
            PolyKeystrokeEvent(
                type: "keyDown",
                processTimeMs: sessionStart + 1000,
                unixTimeMs: 0,
                keyCode: nil,
                character: "a",
                isARepeat: false,
                activeModifiers: []
            )
        ]

        let adapter = makeAdapter(keystrokes: keystrokes, metadata: meta)

        XCTAssertEqual(adapter.keyboardEvents.count, 1)
        XCTAssertEqual(adapter.keyboardEvents[0].keyCode, 0)
    }

    func test_clickElementAppName_mappedToAppIdentifier() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)
        let clicks = [
            PolyMouseClickEvent(
                type: "mouseDown",
                processTimeMs: sessionStart + 1200,
                unixTimeMs: 0,
                x: 300,
                y: 400,
                button: "left",
                cursorId: nil,
                activeModifiers: [],
                elementRole: "AXButton",
                elementSubrole: nil,
                elementTitle: "Run",
                elementAppName: "  Xcode  ",
                elementFrameX: 100,
                elementFrameY: 100,
                elementFrameW: 60,
                elementFrameH: 24,
                elementIsClickable: true
            )
        ]

        let adapter = makeAdapter(clicks: clicks, metadata: meta)
        XCTAssertEqual(adapter.clicks.count, 1)
        XCTAssertEqual(adapter.clicks[0].appBundleID, "xcode")
    }

    // MARK: - Drag Inference: Basic Detection

    func test_dragInference_largeDisplacement_createsDragEvent() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        // mouseDown at (100, 100), mouse moves to (600, 600), mouseUp at (600, 600)
        // On 3024px display: displacement = 500/3024 ≈ 0.165 normalized — well above 0.02 threshold
        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 100, y: 100),
            makeMouseUp(at: sessionStart + 2000, x: 600, y: 600),
        ]
        let moves = [
            makeMove(at: sessionStart + 1100, x: 200, y: 200),
            makeMove(at: sessionStart + 1500, x: 400, y: 400),
            makeMove(at: sessionStart + 1900, x: 600, y: 600),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(adapter.dragEvents.count, 1, "Should detect one drag event")
        let drag = adapter.dragEvents[0]
        XCTAssertEqual(drag.startTime, 1.0, accuracy: 0.01)
        XCTAssertEqual(drag.endTime, 2.0, accuracy: 0.01)
        XCTAssertEqual(drag.dragType, .selection)
    }

    func test_dragInference_dragClicksRemovedFromClicks() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 100, y: 100),
            makeMouseUp(at: sessionStart + 2000, x: 600, y: 600),
        ]
        let moves = [
            makeMove(at: sessionStart + 1100, x: 200, y: 200),
            makeMove(at: sessionStart + 1500, x: 400, y: 400),
            makeMove(at: sessionStart + 1900, x: 600, y: 600),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(adapter.dragEvents.count, 1)
        XCTAssertEqual(
            adapter.clicks.count, 0,
            "mouseDown/mouseUp reclassified as drag should be removed from clicks"
        )
    }

    func test_dragInference_startAndEndPositions_normalized() {
        let sessionStart: Int64 = 1000000
        // 3024 x 1964 display
        let meta = makeMetadata(
            widthPx: 3024, heightPx: 1964, sessionStartMs: sessionStart
        )

        // mouseDown at (0, 0) — top-left in capture coords
        // mouseUp moves to (3024, 1964) — bottom-right
        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 0, y: 0),
            makeMouseUp(at: sessionStart + 2000, x: 3024, y: 1964),
        ]
        let moves = [
            makeMove(at: sessionStart + 1100, x: 1000, y: 500),
            makeMove(at: sessionStart + 1500, x: 2000, y: 1000),
            makeMove(at: sessionStart + 1900, x: 3024, y: 1964),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(adapter.dragEvents.count, 1)
        let drag = adapter.dragEvents[0]

        // Start: (0/3024, 1 - 0/1964) = (0, 1) — bottom-left origin
        XCTAssertEqual(drag.startPosition.x, 0.0, accuracy: 0.01)
        XCTAssertEqual(drag.startPosition.y, 1.0, accuracy: 0.01)

        // End: last move at (3024/3024, 1 - 1964/1964) = (1, 0)
        XCTAssertEqual(drag.endPosition.x, 1.0, accuracy: 0.01)
        XCTAssertEqual(drag.endPosition.y, 0.0, accuracy: 0.01)
    }

    // MARK: - Drag Inference: Below Threshold

    func test_dragInference_tinyDisplacement_notClassifiedAsDrag() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        // mouseDown and moves stay within ~10px on 3024px display
        // 10/3024 ≈ 0.003 — below 0.02 threshold
        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 500, y: 500),
            makeMouseUp(at: sessionStart + 2000, x: 510, y: 505),
        ]
        let moves = [
            makeMove(at: sessionStart + 1100, x: 502, y: 501),
            makeMove(at: sessionStart + 1500, x: 506, y: 503),
            makeMove(at: sessionStart + 1900, x: 510, y: 505),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(
            adapter.dragEvents.count, 0,
            "Tiny displacement should not be classified as drag"
        )
        XCTAssertEqual(
            adapter.clicks.count, 2,
            "mouseDown/mouseUp should remain as clicks"
        )
    }

    func test_dragInference_noMovesBetween_notClassifiedAsDrag() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        // mouseDown then mouseUp with no mouseMoves in between
        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 500, y: 500),
            makeMouseUp(at: sessionStart + 1100, x: 500, y: 500),
        ]

        let adapter = makeAdapter(moves: [], clicks: clicks, metadata: meta)

        XCTAssertEqual(adapter.dragEvents.count, 0)
        XCTAssertEqual(adapter.clicks.count, 2)
    }

    func test_dragInference_singleMoveBetween_notClassifiedAsDrag() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        // Only 1 move between down/up (need >= 2)
        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 500, y: 500),
            makeMouseUp(at: sessionStart + 2000, x: 800, y: 800),
        ]
        let moves = [
            makeMove(at: sessionStart + 1500, x: 700, y: 700),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(
            adapter.dragEvents.count, 0,
            "Single move between down/up should not be classified as drag"
        )
    }

    // MARK: - Drag Inference: Multiple Drags

    func test_dragInference_twoDrags_bothDetected() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        let clicks = [
            // First drag: 1s-2s
            makeMouseDown(at: sessionStart + 1000, x: 100, y: 100),
            makeMouseUp(at: sessionStart + 2000, x: 600, y: 600),
            // Second drag: 3s-4s
            makeMouseDown(at: sessionStart + 3000, x: 600, y: 600),
            makeMouseUp(at: sessionStart + 4000, x: 100, y: 100),
        ]
        let moves = [
            // First drag moves
            makeMove(at: sessionStart + 1200, x: 200, y: 200),
            makeMove(at: sessionStart + 1600, x: 400, y: 400),
            makeMove(at: sessionStart + 1800, x: 600, y: 600),
            // Second drag moves
            makeMove(at: sessionStart + 3200, x: 500, y: 500),
            makeMove(at: sessionStart + 3600, x: 300, y: 300),
            makeMove(at: sessionStart + 3800, x: 100, y: 100),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(adapter.dragEvents.count, 2)
        XCTAssertEqual(adapter.clicks.count, 0, "All clicks should be removed")

        XCTAssertEqual(adapter.dragEvents[0].startTime, 1.0, accuracy: 0.01)
        XCTAssertEqual(adapter.dragEvents[0].endTime, 2.0, accuracy: 0.01)
        XCTAssertEqual(adapter.dragEvents[1].startTime, 3.0, accuracy: 0.01)
        XCTAssertEqual(adapter.dragEvents[1].endTime, 4.0, accuracy: 0.01)
    }

    // MARK: - Drag Inference: Mixed Clicks and Drags

    func test_dragInference_mixedClicksAndDrags_correctClassification() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        let clicks = [
            // Normal click at 1s
            makeMouseDown(at: sessionStart + 1000, x: 500, y: 500),
            makeMouseUp(at: sessionStart + 1100, x: 500, y: 500),
            // Drag at 3s-4s
            makeMouseDown(at: sessionStart + 3000, x: 100, y: 100),
            makeMouseUp(at: sessionStart + 4000, x: 600, y: 600),
            // Normal click at 5s
            makeMouseDown(at: sessionStart + 5000, x: 800, y: 800),
            makeMouseUp(at: sessionStart + 5100, x: 800, y: 800),
        ]
        let moves = [
            // No significant moves during click at 1s
            makeMove(at: sessionStart + 1050, x: 501, y: 501),
            // Drag moves during 3-4s
            makeMove(at: sessionStart + 3200, x: 200, y: 200),
            makeMove(at: sessionStart + 3600, x: 400, y: 400),
            makeMove(at: sessionStart + 3800, x: 600, y: 600),
            // No significant moves during click at 5s
            makeMove(at: sessionStart + 5050, x: 801, y: 801),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(adapter.dragEvents.count, 1, "Only the 3-4s sequence is a drag")
        XCTAssertEqual(
            adapter.clicks.count, 4,
            "Two normal clicks (down+up each) should remain"
        )

        // Verify the drag is the correct one
        let drag = adapter.dragEvents[0]
        XCTAssertEqual(drag.startTime, 3.0, accuracy: 0.01)
        XCTAssertEqual(drag.endTime, 4.0, accuracy: 0.01)
    }

    // MARK: - Drag Inference: Right-Click Ignored

    func test_dragInference_rightClick_notProcessedAsDrag() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        let clicks = [
            PolyMouseClickEvent(
                type: "mouseDown", processTimeMs: sessionStart + 1000,
                unixTimeMs: 0, x: 100, y: 100, button: "right",
                cursorId: nil, activeModifiers: [],
                elementRole: nil,
                elementSubrole: nil,
                elementTitle: nil,
                elementAppName: nil,
                elementFrameX: nil,
                elementFrameY: nil,
                elementFrameW: nil,
                elementFrameH: nil,
                elementIsClickable: nil
            ),
            PolyMouseClickEvent(
                type: "mouseUp", processTimeMs: sessionStart + 2000,
                unixTimeMs: 0, x: 600, y: 600, button: "right",
                cursorId: nil, activeModifiers: [],
                elementRole: nil,
                elementSubrole: nil,
                elementTitle: nil,
                elementAppName: nil,
                elementFrameX: nil,
                elementFrameY: nil,
                elementFrameW: nil,
                elementFrameH: nil,
                elementIsClickable: nil
            ),
        ]
        let moves = [
            makeMove(at: sessionStart + 1200, x: 300, y: 300),
            makeMove(at: sessionStart + 1600, x: 500, y: 500),
            makeMove(at: sessionStart + 1800, x: 600, y: 600),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(
            adapter.dragEvents.count, 0,
            "Right-click sequences should not be classified as drags"
        )
        XCTAssertEqual(adapter.clicks.count, 2)
    }

    // MARK: - Drag Inference: Threshold Boundary

    func test_dragInference_exactlyAtThreshold_classifiedAsDrag() {
        let sessionStart: Int64 = 1000000
        // On 3024px display, 0.02 * 3024 ≈ 60.48px
        let meta = makeMetadata(
            widthPx: 3024, heightPx: 1964, sessionStartMs: sessionStart
        )

        // Move exactly ~61px horizontally (61/3024 ≈ 0.0202, just above 0.02)
        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 500, y: 500),
            makeMouseUp(at: sessionStart + 2000, x: 561, y: 500),
        ]
        let moves = [
            makeMove(at: sessionStart + 1200, x: 530, y: 500),
            makeMove(at: sessionStart + 1600, x: 561, y: 500),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(
            adapter.dragEvents.count, 1,
            "Displacement at threshold boundary should be classified as drag"
        )
    }

    func test_dragInference_justBelowThreshold_notClassifiedAsDrag() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(
            widthPx: 3024, heightPx: 1964, sessionStartMs: sessionStart
        )

        // Move ~55px horizontally (55/3024 ≈ 0.0182, below 0.02)
        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 500, y: 500),
            makeMouseUp(at: sessionStart + 2000, x: 555, y: 500),
        ]
        let moves = [
            makeMove(at: sessionStart + 1200, x: 520, y: 500),
            makeMove(at: sessionStart + 1600, x: 555, y: 500),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(
            adapter.dragEvents.count, 0,
            "Displacement below threshold should not be classified as drag"
        )
    }

    // MARK: - Drag Inference: End Position Uses Last Move

    func test_dragInference_endPosition_usesLastMoveNotMouseUp() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        // mouseUp at a different position than the last mouseMove
        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 100, y: 100),
            makeMouseUp(at: sessionStart + 2000, x: 700, y: 700),
        ]
        let moves = [
            makeMove(at: sessionStart + 1200, x: 200, y: 200),
            makeMove(at: sessionStart + 1500, x: 400, y: 400),
            // Last move is at (600, 600), not the mouseUp at (700, 700)
            makeMove(at: sessionStart + 1900, x: 600, y: 600),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(adapter.dragEvents.count, 1)
        let drag = adapter.dragEvents[0]

        // End position should be from last mouse move (600/3024, 1 - 600/1964)
        let expectedEndX = CGFloat(600.0 / 3024.0)
        let expectedEndY = CGFloat(1.0 - 600.0 / 1964.0)
        XCTAssertEqual(drag.endPosition.x, expectedEndX, accuracy: 0.001)
        XCTAssertEqual(drag.endPosition.y, expectedEndY, accuracy: 0.001)
    }

    // MARK: - Drag Inference: Unmatched MouseDown

    func test_dragInference_unmatchedMouseDown_nocrash() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        // mouseDown without a matching mouseUp
        let clicks = [
            makeMouseDown(at: sessionStart + 1000, x: 100, y: 100),
        ]
        let moves = [
            makeMove(at: sessionStart + 1200, x: 500, y: 500),
            makeMove(at: sessionStart + 1500, x: 800, y: 800),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        XCTAssertEqual(
            adapter.dragEvents.count, 0,
            "Unmatched mouseDown should not create a drag"
        )
        XCTAssertEqual(adapter.clicks.count, 1)
    }

    // MARK: - Drag Inference: Pipeline Integration

    func test_dragInference_pipelineIntegration_draggingIntentCreated() {
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        let clicks = [
            makeMouseDown(at: sessionStart + 2000, x: 100, y: 100),
            makeMouseUp(at: sessionStart + 3000, x: 600, y: 600),
        ]
        let moves = [
            makeMove(at: sessionStart + 500, x: 100, y: 100),
            makeMove(at: sessionStart + 2200, x: 200, y: 200),
            makeMove(at: sessionStart + 2600, x: 400, y: 400),
            makeMove(at: sessionStart + 2900, x: 600, y: 600),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)

        // Build timeline and classify intents
        let timeline = EventTimeline.build(from: adapter)
        let spans = IntentClassifier.classify(events: timeline, uiStateSamples: [])

        let draggingSpans = spans.filter {
            if case .dragging = $0.intent { return true }
            return false
        }
        let clickingSpans = spans.filter { $0.intent == .clicking }

        XCTAssertEqual(
            draggingSpans.count, 1,
            "Synthesized drag should produce a dragging intent span"
        )
        XCTAssertEqual(
            clickingSpans.count, 0,
            "Drag events should not also appear as clicking intents"
        )
    }

    func test_dragInference_pipelineIntegration_noDragZoomOscillation() {
        // Simulates the real-world scenario: click before drag, drag
        // Use large time gap to avoid continuation gap merging
        let sessionStart: Int64 = 1000000
        let meta = makeMetadata(sessionStartMs: sessionStart)

        let clicks = [
            // Normal click at 1s
            makeMouseDown(at: sessionStart + 1000, x: 500, y: 500),
            makeMouseUp(at: sessionStart + 1100, x: 500, y: 500),
            // Drag at 5-6s (far enough from click to not merge)
            makeMouseDown(at: sessionStart + 5000, x: 100, y: 100),
            makeMouseUp(at: sessionStart + 6000, x: 600, y: 600),
        ]
        let moves = [
            makeMove(at: sessionStart + 500, x: 500, y: 500),
            makeMove(at: sessionStart + 1050, x: 501, y: 501),
            makeMove(at: sessionStart + 5200, x: 200, y: 200),
            makeMove(at: sessionStart + 5500, x: 400, y: 400),
            makeMove(at: sessionStart + 5800, x: 600, y: 600),
        ]

        let adapter = makeAdapter(moves: moves, clicks: clicks, metadata: meta)
        let timeline = EventTimeline.build(from: adapter)
        let spans = IntentClassifier.classify(events: timeline, uiStateSamples: [])

        let draggingSpans = spans.filter {
            if case .dragging = $0.intent { return true }
            return false
        }
        let clickingSpans = spans.filter { $0.intent == .clicking }

        XCTAssertEqual(draggingSpans.count, 1, "The 5-6s sequence should be a drag")
        XCTAssertGreaterThanOrEqual(
            clickingSpans.count, 1,
            "The click at 1s should be a clicking intent"
        )

        // Verify the drag has correct timing
        let drag = draggingSpans[0]
        XCTAssertEqual(drag.startTime, 5.0, accuracy: 0.01)
        XCTAssertEqual(drag.endTime, 6.0, accuracy: 0.01)
    }
}
