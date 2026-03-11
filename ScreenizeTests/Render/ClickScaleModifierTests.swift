import XCTest
import CoreGraphics
@testable import Screenize

final class ClickScaleModifierTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvaluator(
        mouseButtonEvents: [RenderMouseButtonEvent] = [],
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
            mouseButtonEvents: mouseButtonEvents
        )
    }

    /// Create a pair of mouseDown + mouseUp events simulating a click
    private func makeClickEvents(
        at time: TimeInterval,
        duration: TimeInterval = 0.2,
        clickType: ClickType = .left
    ) -> [RenderMouseButtonEvent] {
        [
            RenderMouseButtonEvent(timestamp: time, isDown: true, clickType: clickType),
            RenderMouseButtonEvent(timestamp: time + duration, isDown: false, clickType: clickType)
        ]
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

    // MARK: - Zoom Normalization

    func testZoomNormalizedClickScale_preservesScaleAtUnitZoom() {
        let normalized = EffectCompositor.zoomNormalizedClickScale(
            rawClickScale: 0.75,
            zoomLevel: 1.0
        )

        XCTAssertEqual(normalized, 0.75, accuracy: 0.001)
    }

    func testZoomNormalizedClickScale_deepensPressAtHigherZoom() {
        let normalized = EffectCompositor.zoomNormalizedClickScale(
            rawClickScale: 0.75,
            zoomLevel: 1.44
        )

        XCTAssertLessThan(normalized, 0.75)
    }

    func testZoomNormalizedClickScale_clampsToSafeLowerBound() {
        let normalized = EffectCompositor.zoomNormalizedClickScale(
            rawClickScale: 0.10,
            zoomLevel: 9.0
        )

        XCTAssertGreaterThanOrEqual(normalized, 0.1)
    }

    func testDefaultClickFeedback_usesModeratePressScale() {
        XCTAssertEqual(ClickFeedbackConfig.default.mouseDownScale, 0.75, accuracy: 0.001)
    }

    func testCursorImageProvider_usesNextWholePixelInsteadOfFourPixelQuantization() throws {
        let provider = CursorImageProvider()
        let image = try XCTUnwrap(
            provider.cursorImage(style: .arrow, pixelHeight: 33.1)
        )

        XCTAssertEqual(image.extent.height, 34, accuracy: 0.001)
    }

    func testCursorRasterScale_preservesRequestedPixelHeight() {
        let rasterScale = EffectCompositor.cursorRasterScale(
            targetPixelHeight: 33.1,
            rasterizedPixelHeight: 34.0
        )

        XCTAssertEqual(34.0 * rasterScale, 33.1, accuracy: 0.001)
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
        let events = makeClickEvents(at: 1.0, duration: 0.5)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
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
        let events = makeClickEvents(at: 1.0, duration: 0.5)
        let segment = makeCursorSegment()
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
            cursorSegment: segment
        )

        // Right at the click start
        let scale = evaluator.computeClickScaleModifier(at: 1.0)
        XCTAssertEqual(scale, 1.0, accuracy: 0.01)
    }

    // MARK: - Hold Phase

    func testDuringHold_scaleStaysAtMouseDownScale() {
        let config = ClickFeedbackConfig.default
        let events = makeClickEvents(at: 1.0, duration: 0.5)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
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
        let events = makeClickEvents(at: 1.0, duration: 0.3)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
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
        let events = makeClickEvents(at: 1.0, duration: 0.5)
        let segment = makeCursorSegment(clickFeedback: customConfig)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
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
        let events = makeClickEvents(at: 1.0, duration: 0.3)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
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
        let events = makeClickEvents(at: 1.0, duration: 0.3)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
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
        let events = makeClickEvents(at: 1.0, duration: 0.5)
        // No cursor segment
        let evaluator = makeEvaluator(mouseButtonEvents: events)

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
        let events = makeClickEvents(at: 2.0, duration: 0.3)
        let segment = makeCursorSegment()
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
            cursorSegment: segment
        )

        let scale = evaluator.computeClickScaleModifier(at: 0.5)
        XCTAssertEqual(scale, 1.0, accuracy: 0.001)
    }

    // MARK: - Long Press (Drag)

    func testLongPress_scaleStaysSmallDuringHold() {
        let config = ClickFeedbackConfig.default
        // Simulate a 3-second drag: mouseDown at 1.0, mouseUp at 4.0
        let events = makeClickEvents(at: 1.0, duration: 3.0)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
            cursorSegment: segment
        )

        // During the drag (well after press animation ends)
        let midDrag = 2.5
        let scale = evaluator.computeClickScaleModifier(at: midDrag)
        XCTAssertEqual(
            scale, config.mouseDownScale, accuracy: 0.01,
            "During a long press/drag, cursor should stay at mouseDownScale"
        )
    }

    func testLongPress_releasesOnMouseUp() {
        let config = ClickFeedbackConfig.default
        let events = makeClickEvents(at: 1.0, duration: 3.0)
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
            cursorSegment: segment
        )

        // After mouseUp + release animation
        let settledTime = 4.0 + config.mouseUpDuration + 0.5
        let scale = evaluator.computeClickScaleModifier(at: settledTime)
        XCTAssertEqual(
            scale, 1.0, accuracy: 0.01,
            "After drag release settles, scale should return to 1.0"
        )
    }

    // MARK: - Multiple Clicks

    func testMultipleButtons_picksExtreme() {
        let config = ClickFeedbackConfig.default
        // Left click and right click at the same time
        let events = [
            RenderMouseButtonEvent(timestamp: 1.0, isDown: true, clickType: .left),
            RenderMouseButtonEvent(timestamp: 1.0, isDown: true, clickType: .right),
            RenderMouseButtonEvent(timestamp: 1.3, isDown: false, clickType: .left),
            RenderMouseButtonEvent(timestamp: 1.3, isDown: false, clickType: .right)
        ]
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
            cursorSegment: segment
        )

        // During press phase, should produce scale less than 1.0
        let midPress = 1.0 + config.mouseDownDuration * 0.5
        let scale = evaluator.computeClickScaleModifier(at: midPress)
        XCTAssertLessThan(
            scale, 1.0,
            "Simultaneous button presses should produce scale less than 1.0"
        )
    }

    // MARK: - Only MouseDown (no mouseUp yet)

    func testMouseDownOnly_staysPressed() {
        let config = ClickFeedbackConfig.default
        // Only a mouseDown event, no mouseUp
        let events = [
            RenderMouseButtonEvent(timestamp: 1.0, isDown: true, clickType: .left)
        ]
        let segment = makeCursorSegment(clickFeedback: config)
        let evaluator = makeEvaluator(
            mouseButtonEvents: events,
            cursorSegment: segment
        )

        // Well after press animation, should stay at mouseDownScale
        let holdTime = 5.0
        let scale = evaluator.computeClickScaleModifier(at: holdTime)
        XCTAssertEqual(
            scale, config.mouseDownScale, accuracy: 0.01,
            "Without mouseUp, cursor should stay pressed"
        )
    }
}
