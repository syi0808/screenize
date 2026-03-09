import XCTest
@testable import Screenize

final class AdaptiveResponseTests: XCTestCase {

    func test_nextActionFarAway_slowResponse() {
        let settings = DeadZoneSettings()
        let response = AdaptiveResponse.compute(
            timeToNextAction: 3.0,
            settings: settings
        )
        XCTAssertEqual(response, settings.maxResponse, accuracy: 0.001)
    }

    func test_nextActionImminent_fastResponse() {
        let settings = DeadZoneSettings()
        let response = AdaptiveResponse.compute(
            timeToNextAction: 0.2,
            settings: settings
        )
        XCTAssertEqual(response, settings.minResponse, accuracy: 0.001)
    }

    func test_nextActionMidRange_interpolatedResponse() {
        let settings = DeadZoneSettings()
        let response = AdaptiveResponse.compute(
            timeToNextAction: 1.25,
            settings: settings
        )
        XCTAssertGreaterThan(response, settings.minResponse)
        XCTAssertLessThan(response, settings.maxResponse)
    }

    func test_noNextAction_slowResponse() {
        let settings = DeadZoneSettings()
        let response = AdaptiveResponse.compute(
            timeToNextAction: nil,
            settings: settings
        )
        XCTAssertEqual(response, settings.maxResponse, accuracy: 0.001)
    }

    func test_findNextActionTime_skipsIdleAndReading() {
        let spans = [
            makeSpan(start: 0, end: 2, intent: .idle),
            makeSpan(start: 2, end: 4, intent: .reading),
            makeSpan(start: 4, end: 6, intent: .clicking),
        ]
        let nextTime = AdaptiveResponse.findNextActionTime(
            after: 1.0,
            intentSpans: spans
        )
        XCTAssertEqual(nextTime!, 4.0, accuracy: 0.001)
    }

    func test_findNextActionTime_noFutureAction_returnsNil() {
        let spans = [
            makeSpan(start: 0, end: 2, intent: .clicking),
            makeSpan(start: 2, end: 5, intent: .idle),
        ]
        let nextTime = AdaptiveResponse.findNextActionTime(
            after: 3.0,
            intentSpans: spans
        )
        XCTAssertNil(nextTime)
    }

    func test_findNextActionTime_typingIsAction() {
        let spans = [
            makeSpan(start: 0, end: 2, intent: .idle),
            makeSpan(start: 2, end: 5, intent: .typing(context: .codeEditor)),
        ]
        let nextTime = AdaptiveResponse.findNextActionTime(
            after: 1.0,
            intentSpans: spans
        )
        XCTAssertEqual(nextTime!, 2.0, accuracy: 0.001)
    }

    private func makeSpan(
        start: TimeInterval, end: TimeInterval, intent: UserIntent
    ) -> IntentSpan {
        IntentSpan(
            startTime: start,
            endTime: end,
            intent: intent,
            confidence: 1.0,
            focusPosition: NormalizedPoint(x: 0.5, y: 0.5),
            focusElement: nil
        )
    }
}
