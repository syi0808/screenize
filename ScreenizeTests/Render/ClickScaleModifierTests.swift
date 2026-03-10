import XCTest
import CoreGraphics
@testable import Screenize

final class ClickScaleModifierTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvaluator(
        clickEvents: [RenderClickEvent] = [],
        cursorSegment: CursorSegment? = nil,
        duration: TimeInterval = 10.0
    ) -> FrameEvaluator {
        var tracks: [AnySegmentTrack] = []

        if let segment = cursorSegment {
            let cursorTrack = CursorTrackV2(segments: [segment])
            tracks.append(.cursor(cursorTrack))
        }

        let timeline = Timeline(
            tracks: tracks,
            duration: duration
        )

        return FrameEvaluator(
            timeline: timeline,
            clickEvents: clickEvents
        )
    }

    private func makeClick(
        at time: TimeInterval,
        duration: TimeInterval = 0.2
    ) -> RenderClickEvent {
        RenderClickEvent(
            timestamp: time,
            duration: duration,
            x: 0.5,
            y: 0.5,
            clickType: .left
        )
    }

    private func makeCursorSegment(
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 10,
        clickFeedback: ClickFeedbackConfig = .default
    ) -> CursorSegment {
        CursorSegment(
            startTime: startTime,
            endTime: endTime,
            clickFeedback: clickFeedback
        )
    }

    // MARK: - No Clicks

    func testNoClicks_returnsOne() {
        let evaluator = makeEvaluator()
        let scale = evaluator.computeClickScaleModifier(at: 1.0)
        XCTAssertEqual(scale, 1.0, accuracy: 0.001)
    }

    // MARK: - Press Phase

    func testDuringPress_scaleDecreasesToConfigValue() {
        let config = ClickFeedbackConfig.default
        let click = makeClick(at: 1.0, duration: 0.5)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            clickEvents: [click],
            cursorSegment: segment
        )

        // At the end of the press phase
        let pressEnd = 1.0 + config.mouseDownDuration
        let scale = evaluator.computeClickScaleModifier(at: pressEnd)
        XCTAssertEqual(
            scale, config.mouseDownScale, accuracy: 0.01,
            "At end of press phase, scale should reach mouseDownScale"
        )
    }

    func testDuringPress_scaleStartsAtOne() {
        let click = makeClick(at: 1.0, duration: 0.5)
        let segment = makeCursorSegment()
        let evaluator = makeEvaluator(
            clickEvents: [click],
            cursorSegment: segment
        )

        // Right at the click start
        let scale = evaluator.computeClickScaleModifier(at: 1.0)
        XCTAssertEqual(scale, 1.0, accuracy: 0.01)
    }

    // MARK: - Hold Phase

    func testDuringHold_scaleStaysAtMouseDownScale() {
        let config = ClickFeedbackConfig.default
        let click = makeClick(at: 1.0, duration: 0.5)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            clickEvents: [click],
            cursorSegment: segment
        )

        // Mid-hold: after press but before release
        let holdTime = 1.0 + config.mouseDownDuration + 0.1
        let scale = evaluator.computeClickScaleModifier(at: holdTime)
        XCTAssertEqual(
            scale, config.mouseDownScale, accuracy: 0.01,
            "During hold, scale stays at mouseDownScale"
        )
    }

    // MARK: - Release Phase

    func testAfterReleaseSettles_scaleReturnsToOne() {
        let config = ClickFeedbackConfig.default
        let click = makeClick(at: 1.0, duration: 0.3)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            clickEvents: [click],
            cursorSegment: segment
        )

        // Well after release settles
        let settledTime = 1.3 + config.mouseUpDuration + 0.5
        let scale = evaluator.computeClickScaleModifier(at: settledTime)
        XCTAssertEqual(
            scale, 1.0, accuracy: 0.01,
            "After release settles, scale returns to 1.0"
        )
    }

    // MARK: - Custom Config

    func testCustomConfig_usesCustomScale() {
        let customConfig = ClickFeedbackConfig(
            mouseDownScale: 0.5,
            mouseDownDuration: 0.2,
            mouseUpDuration: 0.3,
            mouseUpSpring: .spring(dampingRatio: 0.6, response: 0.3)
        )
        let click = makeClick(at: 1.0, duration: 0.5)
        let segment = makeCursorSegment(clickFeedback: customConfig)
        let evaluator = makeEvaluator(
            clickEvents: [click],
            cursorSegment: segment
        )

        // At end of press phase
        let pressEnd = 1.0 + customConfig.mouseDownDuration
        let scale = evaluator.computeClickScaleModifier(at: pressEnd)
        XCTAssertEqual(
            scale, 0.5, accuracy: 0.02,
            "Custom config mouseDownScale of 0.5 should be used"
        )

        // During hold
        let holdTime = 1.0 + customConfig.mouseDownDuration + 0.1
        let holdScale = evaluator.computeClickScaleModifier(
            at: holdTime
        )
        XCTAssertEqual(
            holdScale, 0.5, accuracy: 0.02,
            "Hold should use custom mouseDownScale"
        )
    }

    // MARK: - Spring Release Easing

    func testReleaseUsesSpringEasing() {
        let config = ClickFeedbackConfig(
            mouseDownScale: 0.7,
            mouseDownDuration: 0.1,
            mouseUpDuration: 0.4,
            mouseUpSpring: .spring(dampingRatio: 0.4, response: 0.3)
        )
        let click = makeClick(at: 1.0, duration: 0.3)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            clickEvents: [click],
            cursorSegment: segment
        )

        let upTime = 1.3
        // Sample during release phase
        let releaseStart = evaluator.computeClickScaleModifier(
            at: upTime + 0.01
        )
        // Scale should be increasing from mouseDownScale toward 1.0
        XCTAssertGreaterThan(
            releaseStart, config.mouseDownScale,
            "Release should start moving scale back toward 1.0"
        )
    }

    func testReleaseRespectsConfiguredDuration() {
        let config = ClickFeedbackConfig.default
        let click = makeClick(at: 1.0, duration: 0.3)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            clickEvents: [click],
            cursorSegment: segment
        )

        let upTime = 1.3
        let quarterRelease = upTime + config.mouseUpDuration * 0.25
        let scale = evaluator.computeClickScaleModifier(at: quarterRelease)

        XCTAssertLessThan(
            scale, 0.95,
            "Release should still be visibly animating at 25% progress"
        )
        XCTAssertGreaterThan(
            scale, config.mouseDownScale,
            "Release should move back toward the resting scale"
        )
    }

    // MARK: - Fallback to Default Config

    func testNoSegment_usesDefaultConfig() {
        let defaultConfig = ClickFeedbackConfig.default
        let click = makeClick(at: 1.0, duration: 0.5)
        // No cursor segment
        let evaluator = makeEvaluator(clickEvents: [click])

        // At end of press phase with default config
        let pressEnd = 1.0 + defaultConfig.mouseDownDuration
        let scale = evaluator.computeClickScaleModifier(at: pressEnd)
        XCTAssertEqual(
            scale, defaultConfig.mouseDownScale, accuracy: 0.02,
            "Without segment, should fall back to default config"
        )
    }

    // MARK: - Before Click

    func testBeforeClick_returnsOne() {
        let click = makeClick(at: 2.0, duration: 0.3)
        let segment = makeCursorSegment()
        let evaluator = makeEvaluator(
            clickEvents: [click],
            cursorSegment: segment
        )

        let scale = evaluator.computeClickScaleModifier(at: 0.5)
        XCTAssertEqual(scale, 1.0, accuracy: 0.001)
    }

    // MARK: - Multiple Clicks

    func testMultipleClicks_picksExtreme() {
        let config = ClickFeedbackConfig.default
        let clicks = [
            makeClick(at: 1.0, duration: 0.3),
            makeClick(at: 1.05, duration: 0.3)
        ]
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            clickEvents: clicks,
            cursorSegment: segment
        )

        // During overlapping press phases, should pick most extreme
        let midPress = 1.0 + config.mouseDownDuration * 0.5
        let scale = evaluator.computeClickScaleModifier(at: midPress)
        XCTAssertLessThan(
            scale, 1.0,
            "Overlapping clicks should produce scale less than 1.0"
        )
    }
}
