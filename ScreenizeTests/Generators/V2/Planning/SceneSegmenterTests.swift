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
            makeSpan(start: 5, end: 5.2, intent: .clicking), // 0.2s < minSceneDuration (0.3)
            makeSpan(start: 5.2, end: 10, intent: .typing(context: .codeEditor))
        ]
        let timeline = EventTimeline(events: [], duration: 10.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 10.0
        )
        // The 0.2s clicking scene should be absorbed
        // Result could be 1 or 2 typing scenes, but no clicking scene
        let clickScenes = scenes.filter { $0.primaryIntent == .clicking }
        XCTAssertEqual(clickScenes.count, 0)
    }

    func test_segment_clickSceneOf500ms_notAbsorbed() {
        let spans = [
            makeSpan(start: 0, end: 5, intent: .typing(context: .codeEditor)),
            makeSpan(start: 5, end: 5.5, intent: .clicking), // 0.5s >= minSceneDuration (0.3)
            makeSpan(start: 5.5, end: 10, intent: .typing(context: .codeEditor))
        ]
        let timeline = EventTimeline(events: [], duration: 10.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 10.0
        )
        // The 0.5s clicking scene should survive (>= 0.3s)
        let clickScenes = scenes.filter { $0.primaryIntent == .clicking }
        XCTAssertEqual(clickScenes.count, 1)
    }

    func test_segment_veryShortScene100ms_absorbed() {
        let spans = [
            makeSpan(start: 0, end: 5, intent: .typing(context: .codeEditor)),
            makeSpan(start: 5, end: 5.1, intent: .clicking), // 0.1s < minSceneDuration (0.3)
            makeSpan(start: 5.1, end: 10, intent: .typing(context: .codeEditor))
        ]
        let timeline = EventTimeline(events: [], duration: 10.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 10.0
        )
        // The 0.1s clicking scene should be absorbed
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

    // MARK: - Focus Region Size by Intent

    func test_segment_clickingIntent_largerRegion() {
        let span = makeSpan(start: 0, end: 5, intent: .clicking,
                            position: NormalizedPoint(x: 0.5, y: 0.5))
        let timeline = EventTimeline(events: [], duration: 5.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: [span], eventTimeline: timeline, duration: 5.0
        )
        let cursorRegion = scenes[0].focusRegions.first {
            if case .cursorPosition = $0.source { return true }
            return false
        }!
        // Clicking should have 0.1x0.1 region (10%), not 0.02x0.02 (2%)
        XCTAssertGreaterThan(cursorRegion.region.width, 0.05,
                             "Clicking region should be larger than 2%")
        XCTAssertGreaterThan(cursorRegion.region.height, 0.05,
                             "Clicking region should be larger than 2%")
    }

    func test_segment_typingIntent_textLineShape() {
        let span = makeSpan(start: 0, end: 5,
                            intent: .typing(context: .codeEditor),
                            position: NormalizedPoint(x: 0.5, y: 0.5))
        let timeline = EventTimeline(events: [], duration: 5.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: [span], eventTimeline: timeline, duration: 5.0
        )
        let cursorRegion = scenes[0].focusRegions.first {
            if case .cursorPosition = $0.source { return true }
            return false
        }!
        // Typing should have wider-than-tall shape (text line)
        XCTAssertGreaterThan(cursorRegion.region.width, cursorRegion.region.height,
                             "Typing region should be wider than tall")
        XCTAssertGreaterThan(cursorRegion.region.width, 0.05,
                             "Typing region should be wider than 5%")
    }

    func test_segment_navigatingIntent_largerRegion() {
        let span = makeSpan(start: 0, end: 5, intent: .navigating,
                            position: NormalizedPoint(x: 0.5, y: 0.5))
        let timeline = EventTimeline(events: [], duration: 5.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: [span], eventTimeline: timeline, duration: 5.0
        )
        let cursorRegion = scenes[0].focusRegions.first {
            if case .cursorPosition = $0.source { return true }
            return false
        }!
        XCTAssertGreaterThan(cursorRegion.region.width, 0.05,
                             "Navigating region should be larger than 2%")
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

    // MARK: - Absorption Preserves Focus Regions

    func test_segment_absorbShortScene_preservesFocusRegionsFromBothScenes() {
        // Long typing → short clicking (absorbed) → long typing
        // Both short scene's focus regions should be preserved in the merged result
        let shortPos = NormalizedPoint(x: 0.7, y: 0.3)
        let spans = [
            makeSpan(start: 0, end: 5, intent: .typing(context: .codeEditor),
                     position: NormalizedPoint(x: 0.3, y: 0.5)),
            makeSpan(start: 5, end: 5.2, intent: .clicking, position: shortPos),
            makeSpan(start: 5.2, end: 10, intent: .typing(context: .codeEditor),
                     position: NormalizedPoint(x: 0.4, y: 0.6)),
        ]
        let timeline = EventTimeline(events: [], duration: 10.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 10.0
        )
        // The 0.2s clicking scene is absorbed
        let clickScenes = scenes.filter { $0.primaryIntent == .clicking }
        XCTAssertEqual(clickScenes.count, 0, "Short clicking scene should be absorbed")

        // The absorbed scene's focus regions should be preserved in the merged scene
        let allRegions = scenes.flatMap(\.focusRegions)
        let hasShortSceneRegion = allRegions.contains { region in
            abs(region.region.midX - shortPos.x) < 0.1
                && abs(region.region.midY - shortPos.y) < 0.1
        }
        XCTAssertTrue(hasShortSceneRegion,
                       "Absorbed scene's focus region at (0.7, 0.3) should be preserved")
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

    // MARK: - Spatial Segmentation

    func test_segment_sameIntent_farApart_splits() {
        // Two clicking spans at opposite corners (distance 0.6 > threshold 0.25)
        let spans = [
            makeSpan(start: 0, end: 3, intent: .clicking,
                     position: NormalizedPoint(x: 0.2, y: 0.2)),
            makeSpan(start: 3, end: 6, intent: .clicking,
                     position: NormalizedPoint(x: 0.8, y: 0.8))
        ]
        let timeline = EventTimeline(events: [], duration: 6.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 6.0
        )
        XCTAssertEqual(scenes.count, 2,
                       "Spatially distant same-intent spans should split")
    }

    func test_segment_sameIntent_closeBy_merges() {
        // Two clicking spans nearby (distance 0.1 < threshold 0.25)
        let spans = [
            makeSpan(start: 0, end: 3, intent: .clicking,
                     position: NormalizedPoint(x: 0.4, y: 0.5)),
            makeSpan(start: 3, end: 6, intent: .clicking,
                     position: NormalizedPoint(x: 0.5, y: 0.5))
        ]
        let timeline = EventTimeline(events: [], duration: 6.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 6.0
        )
        XCTAssertEqual(scenes.count, 1,
                       "Spatially close same-intent spans should still merge")
    }

    func test_segment_typing_farApart_doesNotSplit() {
        // Two typing spans far apart — typing is exempt from spatial splitting
        let spans = [
            makeSpan(start: 0, end: 3, intent: .typing(context: .codeEditor),
                     position: NormalizedPoint(x: 0.1, y: 0.1)),
            makeSpan(start: 3, end: 6, intent: .typing(context: .codeEditor),
                     position: NormalizedPoint(x: 0.9, y: 0.9))
        ]
        let timeline = EventTimeline(events: [], duration: 6.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 6.0
        )
        XCTAssertEqual(scenes.count, 1,
                       "Typing spans should NOT split spatially (CursorFollowController handles it)")
    }

    func test_segment_dragging_farApart_doesNotSplit() {
        // Two dragging spans far apart — dragging is exempt from spatial splitting
        let spans = [
            makeSpan(start: 0, end: 3, intent: .dragging(.selection),
                     position: NormalizedPoint(x: 0.1, y: 0.1)),
            makeSpan(start: 3, end: 6, intent: .dragging(.selection),
                     position: NormalizedPoint(x: 0.9, y: 0.9))
        ]
        let timeline = EventTimeline(events: [], duration: 6.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 6.0
        )
        XCTAssertEqual(scenes.count, 1,
                       "Dragging spans should NOT split spatially (CursorFollowController handles it)")
    }

    func test_segment_threeClicks_splitAfterSecond() {
        // 1st and 2nd close, 3rd far from group — splits after 2nd
        let spans = [
            makeSpan(start: 0, end: 2, intent: .clicking,
                     position: NormalizedPoint(x: 0.3, y: 0.3)),
            makeSpan(start: 2, end: 4, intent: .clicking,
                     position: NormalizedPoint(x: 0.35, y: 0.35)),
            makeSpan(start: 4, end: 6, intent: .clicking,
                     position: NormalizedPoint(x: 0.8, y: 0.8))
        ]
        let timeline = EventTimeline(events: [], duration: 6.0)
        let scenes = SceneSegmenter.segment(
            intentSpans: spans, eventTimeline: timeline, duration: 6.0
        )
        XCTAssertEqual(scenes.count, 2,
                       "Should split when 3rd click is far from group centroid")
        XCTAssertEqual(scenes[0].primaryIntent, .clicking)
        XCTAssertEqual(scenes[1].primaryIntent, .clicking)
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
