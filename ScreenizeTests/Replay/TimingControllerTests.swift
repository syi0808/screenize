import XCTest
import CoreGraphics
@testable import Screenize

final class TimingControllerTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a ScenarioStep with just a type and durationMs.
    private func step(_ type: ScenarioStep.StepType, durationMs: Int = 100) -> ScenarioStep {
        ScenarioStep(type: type, description: "\(type)", durationMs: durationMs)
    }

    // MARK: - isDragGroupMember

    /// mouse_down at index 0, followed by mouse_move and mouse_up → member
    func test_isDragGroupMember_mouseDown_start() {
        let steps = [
            step(.mouseDown),
            step(.mouseMove),
            step(.mouseUp)
        ]
        XCTAssertTrue(TimingController.isDragGroupMember(steps: steps, index: 0))
    }

    /// mouse_move at index 1, between mouse_down and mouse_up → member
    func test_isDragGroupMember_mouseMove_middle() {
        let steps = [
            step(.mouseDown),
            step(.mouseMove),
            step(.mouseUp)
        ]
        XCTAssertTrue(TimingController.isDragGroupMember(steps: steps, index: 1))
    }

    /// mouse_up at index 2, after mouse_down and mouse_move → member
    func test_isDragGroupMember_mouseUp_end() {
        let steps = [
            step(.mouseDown),
            step(.mouseMove),
            step(.mouseUp)
        ]
        XCTAssertTrue(TimingController.isDragGroupMember(steps: steps, index: 2))
    }

    /// A standalone click step → not a drag group member
    func test_isDragGroupMember_standaloneClick_false() {
        let steps = [
            step(.click)
        ]
        XCTAssertFalse(TimingController.isDragGroupMember(steps: steps, index: 0))
    }

    /// mouse_down not followed by mouse_up (no termination) → not a drag group member
    func test_isDragGroupMember_loneMouseDown_false() {
        let steps = [
            step(.mouseDown),
            step(.mouseMove),
            step(.click)    // breaks the sequence — no mouse_up
        ]
        XCTAssertFalse(TimingController.isDragGroupMember(steps: steps, index: 0))
    }

    /// mouse_down with no following steps → not a drag group member (no mouse_up)
    func test_isDragGroupMember_mouseDown_noSuccessors_false() {
        let steps = [
            step(.mouseDown)
        ]
        XCTAssertFalse(TimingController.isDragGroupMember(steps: steps, index: 0))
    }

    /// mouse_down followed directly by mouse_up (no mouse_move) → both are members
    func test_isDragGroupMember_mouseDown_directMouseUp_true() {
        let steps = [
            step(.mouseDown),
            step(.mouseUp)
        ]
        XCTAssertTrue(TimingController.isDragGroupMember(steps: steps, index: 0))
        XCTAssertTrue(TimingController.isDragGroupMember(steps: steps, index: 1))
    }

    /// Multiple mouse_moves between mouse_down and mouse_up → all are members
    func test_isDragGroupMember_multipleMouseMoves_allTrue() {
        let steps = [
            step(.mouseDown),
            step(.mouseMove),
            step(.mouseMove),
            step(.mouseMove),
            step(.mouseUp)
        ]
        for i in 0..<steps.count {
            XCTAssertTrue(TimingController.isDragGroupMember(steps: steps, index: i), "Expected index \(i) to be a drag group member")
        }
    }

    // MARK: - interStepDelay

    /// Drag group members return 0 delay
    func test_interStepDelay_dragGroupMember_returnsZero() {
        let steps = [
            step(.mouseDown, durationMs: 50),
            step(.mouseMove, durationMs: 30),
            step(.mouseUp, durationMs: 20)
        ]
        XCTAssertEqual(TimingController.interStepDelay(steps: steps, index: 0), 0)
        XCTAssertEqual(TimingController.interStepDelay(steps: steps, index: 1), 0)
        XCTAssertEqual(TimingController.interStepDelay(steps: steps, index: 2), 0)
    }

    /// Normal step returns step.durationMs
    func test_interStepDelay_normalStep_returnsDurationMs() {
        let steps = [
            step(.click, durationMs: 200),
            step(.keyboard, durationMs: 150)
        ]
        XCTAssertEqual(TimingController.interStepDelay(steps: steps, index: 0), 200)
        XCTAssertEqual(TimingController.interStepDelay(steps: steps, index: 1), 150)
    }

    /// Non-drag sequence: mouse_down → click (not mouse_up) → normal delays apply
    func test_interStepDelay_brokenDragSequence_returnsDurationMs() {
        let steps = [
            step(.mouseDown, durationMs: 75),
            step(.click, durationMs: 100)
        ]
        // mouse_down here has no following mouse_up, so it is NOT a drag group member
        XCTAssertEqual(TimingController.interStepDelay(steps: steps, index: 0), 75)
        XCTAssertEqual(TimingController.interStepDelay(steps: steps, index: 1), 100)
    }

    // MARK: - delay

    /// delay(ms: 0) completes immediately (no sleep)
    func test_delay_zeroMs_completesImmediately() async {
        await TimingController.delay(ms: 0)
        // If we reach here without timing out, the test passes
    }

    /// delay(ms: negative) completes immediately (guard condition)
    func test_delay_negativeMs_completesImmediately() async {
        await TimingController.delay(ms: -100)
    }
}
