import XCTest
@testable import Screenize

final class SceneSegmenterTests: XCTestCase {

    // MARK: - Empty / Trivial

    func test_segment_emptySpans_returnsEmpty() {
        let timeline = EventTimeline(events: [], duration: 10.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: [], eventTimeline: timeline, duration: 10.0
        )
        XCTAssertTrue(scenes.isEmpty)
    }

    func test_segment_singleSpan_returnsSingleScene() {
        let span = makeSpan(start: 0, end: 5, intent: .clicking)
        let timeline = EventTimeline(events: [], duration: 5.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: [span], eventTimeline: timeline, duration: 5.0
        )
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].startTime, 0)
        XCTAssertEqual(scenes[0].endTime, 5)
        XCTAssertEqual(scenes[0].primaryIntent, .clicking)
    }

    // MARK: - Scene Splitting

    func test_segment_intentChange_createsNewScene() {
        let spans = [
            makeSpan(start: 0, end: 3, intent: .typing(context: .codeEditor)),
            makeSpan(start: 3, end: 6, intent: .clicking)
        ]
        let timeline = EventTimeline(events: [], duration: 6.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 6.0
        )
        XCTAssertEqual(scenes.count, 2)
        XCTAssertEqual(scenes[0].primaryIntent, .typing(context: .codeEditor))
        XCTAssertEqual(scenes[1].primaryIntent, .clicking)
    }

    func test_segment_sameIntentMerges() {
        let spans = [
            makeSpan(start: 0, end: 2, intent: .clicking),
            makeSpan(start: 2, end: 5, intent: .clicking)
        ]
        let timeline = EventTimeline(events: [], duration: 5.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 5.0
        )
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].startTime, 0)
        XCTAssertEqual(scenes[0].endTime, 5)
    }

    func test_segment_switchingAlwaysCreatesNewScene() {
        let spans = [
            makeSpan(start: 0, end: 3, intent: .clicking),
            makeSpan(start: 3, end: 3.2, intent: .switching),
            makeSpan(start: 3.2, end: 6, intent: .clicking)
        ]
        let timeline = EventTimeline(events: [], duration: 6.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 6.0
        )
        // switching forces a split even though before and after are same intent
        XCTAssertGreaterThanOrEqual(scenes.count, 2)
        // The clicking scenes before and after switching should be separate
        let clickScenes = scenes.filter { $0.primaryIntent == .clicking }
        XCTAssertEqual(clickScenes.count, 2)
    }

    func test_segment_idleCreatesSceneBoundary() {
        let spans = [
            makeSpan(start: 0, end: 2, intent: .clicking),
            makeSpan(start: 2, end: 8, intent: .idle),
            makeSpan(start: 8, end: 12, intent: .clicking)
        ]
        let timeline = EventTimeline(events: [], duration: 12.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 12.0
        )
        // idle acts as scene boundary between the clicking scenes
        let clickScenes = scenes.filter { $0.primaryIntent == .clicking }
        XCTAssertEqual(clickScenes.count, 2)
    }

    // MARK: - Short Scene Absorption

    func test_segment_shortSceneAbsorbedIntoNeighbor() {
        let spans = [
            makeSpan(start: 0, end: 5, intent: .typing(context: .codeEditor)),
            makeSpan(start: 5, end: 5.5, intent: .clicking), // < 1s
            makeSpan(start: 5.5, end: 10, intent: .typing(context: .codeEditor))
        ]
        let timeline = EventTimeline(events: [], duration: 10.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 10.0
        )
        // The 0.5s clicking scene should be absorbed
        // Result could be 1 or 2 typing scenes, but no clicking scene
        let clickScenes = scenes.filter { $0.primaryIntent == .clicking }
        XCTAssertEqual(clickScenes.count, 0)
    }

    func test_segment_shortSceneNotAbsorbedIfOnlyScene() {
        let span = makeSpan(start: 0, end: 0.5, intent: .clicking)
        let timeline = EventTimeline(events: [], duration: 0.5)
        let scenes = SceneSegmenter.segment(
            intentSpans: [span], eventTimeline: timeline, duration: 0.5
        )
        // Single scene should not be removed even if short
        XCTAssertEqual(scenes.count, 1)
    }

    // MARK: - Primary Intent

    func test_segment_primaryIntentIsDominant() {
        // Two consecutive clicking spans should have clicking as primary intent
        let spans = [
            makeSpan(start: 0, end: 3, intent: .navigating),
            makeSpan(start: 3, end: 3.2, intent: .clicking),
            makeSpan(start: 3.2, end: 6, intent: .navigating)
        ]
        let timeline = EventTimeline(events: [], duration: 6.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 6.0
        )
        // The short clicking gets absorbed; navigating is dominant
        let navScenes = scenes.filter { $0.primaryIntent == .navigating }
        XCTAssertGreaterThanOrEqual(navScenes.count, 1)
    }

    // MARK: - Focus Regions

    func test_segment_focusRegionsPopulated() {
        let pos = NormalizedPoint(x: 0.3, y: 0.7)
        let span = IntentSpan(
            startTime: 0, endTime: 5, intent: .clicking,
            confidence: 0.9, focusPosition: pos, focusElement: nil
        )
        let timeline = EventTimeline(events: [], duration: 5.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: [span], eventTimeline: timeline, duration: 5.0
        )
        XCTAssertEqual(scenes.count, 1)
        XCTAssertFalse(scenes[0].focusRegions.isEmpty)
        let region = scenes[0].focusRegions[0]
        if case .cursorPosition = region.source {
            // expected
        } else {
            XCTFail("Expected .cursorPosition, got \(region.source)")
        }
    }

    func test_segment_focusRegionFromElement() {
        let elementInfo = UIElementInfo(
            role: "AXTextField",
            subrole: nil,
            frame: CGRect(x: 100, y: 200, width: 300, height: 30),
            title: "Search",
            isClickable: false,
            applicationName: nil
        )
        let span = IntentSpan(
            startTime: 0, endTime: 5,
            intent: .typing(context: .textField),
            confidence: 0.9,
            focusPosition: NormalizedPoint(x: 0.3, y: 0.5),
            focusElement: elementInfo
        )
        let timeline = EventTimeline(events: [], duration: 5.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: [span], eventTimeline: timeline, duration: 5.0
        )
        XCTAssertEqual(scenes.count, 1)
        let hasActiveElement = scenes[0].focusRegions.contains { region in
            if case .activeElement = region.source { return true }
            return false
        }
        XCTAssertTrue(hasActiveElement)
    }

    // MARK: - App Context

    func test_segment_appContextExtracted() {
        let event = UnifiedEvent(
            time: 1.0,
            kind: .click(ClickEventData(
                time: 1.0,
                position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown
            )),
            position: NormalizedPoint(x: 0.5, y: 0.5),
            metadata: EventMetadata(appBundleID: "com.apple.Xcode")
        )
        let span = makeSpan(start: 0, end: 5, intent: .clicking)
        let timeline = EventTimeline(events: [event], duration: 5.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: [span], eventTimeline: timeline, duration: 5.0
        )
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].appContext, "com.apple.Xcode")
    }

    // MARK: - Time Coverage

    func test_segment_scenesSpanFullDuration() {
        let spans = [
            makeSpan(start: 0, end: 3, intent: .clicking),
            makeSpan(start: 3, end: 6, intent: .typing(context: .codeEditor)),
            makeSpan(start: 6, end: 10, intent: .scrolling)
        ]
        let timeline = EventTimeline(events: [], duration: 10.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 10.0
        )
        XCTAssertFalse(scenes.isEmpty)
        XCTAssertEqual(scenes.first?.startTime, 0)
        XCTAssertEqual(scenes.last?.endTime, 10.0)
    }

    // MARK: - Typing Context Preservation

    func test_segment_typingContextPreserved() {
        let spans = [
            makeSpan(start: 0, end: 5, intent: .typing(context: .terminal)),
            makeSpan(start: 5, end: 10, intent: .typing(context: .codeEditor))
        ]
        let timeline = EventTimeline(events: [], duration: 10.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 10.0
        )
        // Different typing contexts should create different scenes
        XCTAssertEqual(scenes.count, 2)
        XCTAssertEqual(scenes[0].primaryIntent, .typing(context: .terminal))
        XCTAssertEqual(scenes[1].primaryIntent, .typing(context: .codeEditor))
    }

    func test_segment_sameTypingContextMerges() {
        let spans = [
            makeSpan(start: 0, end: 3, intent: .typing(context: .codeEditor)),
            makeSpan(start: 3, end: 6, intent: .typing(context: .codeEditor))
        ]
        let timeline = EventTimeline(events: [], duration: 6.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 6.0
        )
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].primaryIntent, .typing(context: .codeEditor))
    }

    // MARK: - Multiple Intent Types

    func test_segment_complexSequence() {
        let spans = [
            makeSpan(start: 0, end: 2, intent: .clicking),
            makeSpan(start: 2, end: 5, intent: .typing(context: .codeEditor)),
            makeSpan(start: 5, end: 5.1, intent: .switching),
            makeSpan(start: 5.1, end: 8, intent: .typing(context: .terminal)),
            makeSpan(start: 8, end: 14, intent: .idle),
            makeSpan(start: 14, end: 18, intent: .scrolling)
        ]
        let timeline = EventTimeline(events: [], duration: 18.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 18.0
        )
        // Should have at least: clicking, typing(code), switching, typing(terminal), idle, scrolling
        // switching and idle act as boundaries
        XCTAssertGreaterThanOrEqual(scenes.count, 4)
    }

    // MARK: - Helpers

    private func makeSpan(
        start: TimeInterval,
        end: TimeInterval,
        intent: UserIntent,
        position: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5)
    ) -> IntentSpan {
        IntentSpan(
            startTime: start,
            endTime: end,
            intent: intent,
            confidence: 0.9,
            focusPosition: position,
            focusElement: nil
        )
    }
}
