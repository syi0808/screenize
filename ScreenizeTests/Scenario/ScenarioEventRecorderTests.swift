import XCTest
@testable import Screenize

final class ScenarioEventRecorderTests: XCTestCase {

    // MARK: - calculateTimeMs

    func test_calculateTimeMs_basic() {
        let start = Date(timeIntervalSinceNow: -2.0)   // 2 seconds ago
        let result = ScenarioEventRecorder.calculateTimeMs(since: start, totalPauseMs: 0)
        XCTAssertTrue(result >= 1900 && result <= 2100, "Expected ~2000 ms, got \(result)")
    }

    func test_calculateTimeMs_withPause() {
        let start = Date(timeIntervalSinceNow: -3.0)   // 3 seconds ago, 1 second paused
        let result = ScenarioEventRecorder.calculateTimeMs(since: start, totalPauseMs: 1000)
        XCTAssertTrue(result >= 1900 && result <= 2100, "Expected ~2000 ms, got \(result)")
    }

    func test_calculateTimeMs_neverNegative() {
        let start = Date(timeIntervalSinceNow: -1.0)   // only 1 second elapsed
        let result = ScenarioEventRecorder.calculateTimeMs(since: start, totalPauseMs: 5000)
        XCTAssertEqual(result, 0, "Result must be clamped to 0 when pause exceeds elapsed time")
    }

    func test_calculateTimeMs_zeroPauseAndZeroElapsed() {
        // Start in the future to simulate near-zero elapsed time
        let start = Date()
        let result = ScenarioEventRecorder.calculateTimeMs(since: start, totalPauseMs: 0)
        XCTAssertGreaterThanOrEqual(result, 0)
    }

    func test_calculateTimeMs_largeElapsed() {
        let start = Date(timeIntervalSinceNow: -10.0)  // 10 seconds ago
        let result = ScenarioEventRecorder.calculateTimeMs(since: start, totalPauseMs: 0)
        XCTAssertTrue(result >= 9900 && result <= 10100, "Expected ~10000 ms, got \(result)")
    }

    func test_calculateTimeMs_pauseEqualsElapsed() {
        let start = Date(timeIntervalSinceNow: -2.0)
        // totalPauseMs is set to a large value covering the elapsed time
        let result = ScenarioEventRecorder.calculateTimeMs(since: start, totalPauseMs: 2000)
        // Result might be 0 or slightly positive depending on execution time
        XCTAssertGreaterThanOrEqual(result, 0)
    }

    // MARK: - shouldDebounceAX

    func test_debounce_withinThreshold() {
        // 20 ms since last query — well within 50 ms threshold
        XCTAssertTrue(
            ScenarioEventRecorder.shouldDebounceAX(currentTimeMs: 120, lastAXQueryTimeMs: 100),
            "20 ms < 50 ms should debounce"
        )
    }

    func test_debounce_outsideThreshold() {
        // 100 ms since last query — outside 50 ms threshold
        XCTAssertFalse(
            ScenarioEventRecorder.shouldDebounceAX(currentTimeMs: 200, lastAXQueryTimeMs: 100),
            "100 ms >= 50 ms should not debounce"
        )
    }

    func test_debounce_exactThreshold() {
        // Exactly 50 ms — boundary condition: not < 50 so should NOT debounce
        XCTAssertFalse(
            ScenarioEventRecorder.shouldDebounceAX(currentTimeMs: 150, lastAXQueryTimeMs: 100),
            "50 ms == 50 ms should not debounce (< 50 is the rule)"
        )
    }

    func test_debounce_zeroElapsed() {
        // Same timestamp — 0 ms < 50 ms, must debounce
        XCTAssertTrue(
            ScenarioEventRecorder.shouldDebounceAX(currentTimeMs: 100, lastAXQueryTimeMs: 100),
            "0 ms < 50 ms should debounce"
        )
    }

    func test_debounce_oneMillisecond() {
        XCTAssertTrue(
            ScenarioEventRecorder.shouldDebounceAX(currentTimeMs: 101, lastAXQueryTimeMs: 100),
            "1 ms < 50 ms should debounce"
        )
    }

    func test_debounce_fortyNineMilliseconds() {
        XCTAssertTrue(
            ScenarioEventRecorder.shouldDebounceAX(currentTimeMs: 149, lastAXQueryTimeMs: 100),
            "49 ms < 50 ms should debounce"
        )
    }

    func test_debounce_fiftyOneMilliseconds() {
        XCTAssertFalse(
            ScenarioEventRecorder.shouldDebounceAX(currentTimeMs: 151, lastAXQueryTimeMs: 100),
            "51 ms >= 50 ms should not debounce"
        )
    }

    func test_debounce_fromZero() {
        // First query: lastAXQueryTimeMs == 0, currentTimeMs == 0 → debounce
        XCTAssertTrue(
            ScenarioEventRecorder.shouldDebounceAX(currentTimeMs: 0, lastAXQueryTimeMs: 0)
        )
    }

    func test_debounce_firstQueryAfterStart() {
        // Very first event at 60 ms — should not debounce (60 ms >= 50 ms)
        XCTAssertFalse(
            ScenarioEventRecorder.shouldDebounceAX(currentTimeMs: 60, lastAXQueryTimeMs: 0)
        )
    }
}
