import XCTest
import CoreGraphics
@testable import Screenize

final class ScenarioGeneratorTests: XCTestCase {

    // MARK: - Helpers

    private let captureArea = CGRect(x: 100, y: 50, width: 1920, height: 1080)

    private func makeRawEvents(_ events: [RawEvent]) -> ScenarioRawEvents {
        ScenarioRawEvents(
            startTimestamp: "2026-03-16T10:00:00Z",
            captureArea: captureArea,
            events: events
        )
    }

    private func axInfo(role: String = "AXButton", title: String? = "OK") -> RawAXInfo {
        RawAXInfo(
            role: role,
            axTitle: title,
            axValue: nil,
            axDescription: nil,
            path: ["AXWindow", role],
            frame: CGRect(x: 440, y: 102, width: 80, height: 30)
        )
    }

    /// Filter out mouse_move steps to inspect only action steps.
    private func actionSteps(_ scenario: Scenario) -> [ScenarioStep] {
        scenario.steps.filter { $0.type != .mouseMove }
    }

    // MARK: - 1. Click Detection

    func test_click_leftButton_samePosition() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 440, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 150, type: .mouseUp, x: 442, y: 103, button: "left")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].type, .click)
        XCTAssertNotNil(actions[0].target)
        XCTAssertEqual(actions[0].target?.role, "AXButton")
        XCTAssertEqual(actions[0].target?.axTitle, "OK")
        XCTAssertEqual(actions[0].durationMs, 50)
    }

    // MARK: - 2. Double-Click Detection

    func test_doubleClick_twoClicksWithin400ms() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 440, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 130, type: .mouseUp, x: 441, y: 102, button: "left"),
            RawEvent(timeMs: 200, type: .mouseDown, x: 441, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 230, type: .mouseUp, x: 442, y: 103, button: "left")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].type, .doubleClick)
        XCTAssertNotNil(actions[0].target)
    }

    // MARK: - 3. Right-Click Detection

    func test_rightClick_samePosition() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 440, y: 102, button: "right", ax: axInfo()),
            RawEvent(timeMs: 180, type: .mouseUp, x: 441, y: 103, button: "right")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].type, .rightClick)
        XCTAssertEqual(actions[0].durationMs, 80)
    }

    // MARK: - 4. Drag Detection

    func test_drag_producesMouseDownMoveUp() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 200, y: 200, button: "left", ax: axInfo()),
            RawEvent(timeMs: 200, type: .mouseMove, x: 250, y: 250),
            RawEvent(timeMs: 300, type: .mouseMove, x: 300, y: 300),
            RawEvent(timeMs: 400, type: .mouseUp, x: 300, y: 300, button: "left")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let allSteps = scenario.steps

        // Drag produces: mouse_down + mouse_move(s) + mouse_up
        let types = allSteps.map { $0.type }
        XCTAssertTrue(types.contains(.mouseDown))
        XCTAssertTrue(types.contains(.mouseMove))
        XCTAssertTrue(types.contains(.mouseUp))
        XCTAssertTrue(allSteps.count >= 3, "Expected at least mouse_down + mouse_move + mouse_up")
    }

    // MARK: - 5. Scroll Merging

    func test_scrollMerge_within100ms() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .scroll, x: 500, y: 400, deltaX: 0, deltaY: -30,
                     ax: axInfo(role: "AXScrollArea", title: nil)),
            RawEvent(timeMs: 140, type: .scroll, x: 500, y: 400, deltaX: 0, deltaY: -25),
            RawEvent(timeMs: 180, type: .scroll, x: 500, y: 400, deltaX: 0, deltaY: -20)
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].type, .scroll)
        XCTAssertEqual(actions[0].amount, 75) // 30+25+20
    }

    // MARK: - 6. Scroll Splitting

    func test_scrollSplit_moreThan100msGap() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .scroll, x: 500, y: 400, deltaX: 0, deltaY: -30),
            RawEvent(timeMs: 350, type: .scroll, x: 500, y: 400, deltaX: 0, deltaY: -20)
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].type, .scroll)
        XCTAssertEqual(actions[1].type, .scroll)
        XCTAssertEqual(actions[0].amount, 30)
        XCTAssertEqual(actions[1].amount, 20)
    }

    // MARK: - 7. Keyboard Combo

    func test_keyboardCombo_cmdC() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .keyDown, keyCode: 8, characters: "c", modifiers: ["cmd"]),
            RawEvent(timeMs: 150, type: .keyUp, keyCode: 8, characters: "c")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].type, .keyboard)
        XCTAssertEqual(actions[0].keyCombo, "cmd+c")
    }

    // MARK: - 8. Type Text

    func test_typeText_consecutiveCharacters() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .keyDown, keyCode: 4, characters: "h", modifiers: []),
            RawEvent(timeMs: 120, type: .keyUp, keyCode: 4, characters: "h"),
            RawEvent(timeMs: 200, type: .keyDown, keyCode: 34, characters: "i", modifiers: []),
            RawEvent(timeMs: 220, type: .keyUp, keyCode: 34, characters: "i"),
            RawEvent(timeMs: 300, type: .keyDown, keyCode: 1, characters: "!", modifiers: ["shift"]),
            RawEvent(timeMs: 320, type: .keyUp, keyCode: 1, characters: "!")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].type, .typeText)
        XCTAssertEqual(actions[0].content, "hi!")
    }

    // MARK: - 9. Activate App

    func test_activateApp() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .appActivated, bundleId: "com.apple.finder", appName: "Finder")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].type, .activateApp)
        XCTAssertEqual(actions[0].app, "com.apple.finder")
    }

    // MARK: - 10. Empty Events

    func test_emptyEvents_producesEmptySteps() {
        let raw = makeRawEvents([])
        let scenario = ScenarioGenerator.generate(from: raw)

        XCTAssertTrue(scenario.steps.isEmpty)
        XCTAssertEqual(scenario.version, 1)
    }

    // MARK: - 11. mouse_move Insertion

    func test_mouseMoveInsertion_betweenActionSteps() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 440, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 150, type: .mouseUp, x: 441, y: 103, button: "left"),
            RawEvent(timeMs: 600, type: .mouseDown, x: 800, y: 500, button: "left", ax: axInfo()),
            RawEvent(timeMs: 650, type: .mouseUp, x: 801, y: 501, button: "left")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)

        // Should have: click, mouse_move(auto), click
        XCTAssertEqual(scenario.steps.count, 3)
        XCTAssertEqual(scenario.steps[0].type, .click)
        XCTAssertEqual(scenario.steps[1].type, .mouseMove)
        XCTAssertEqual(scenario.steps[1].path, .auto)
        XCTAssertEqual(scenario.steps[2].type, .click)
    }

    // MARK: - 12. Timing / durationMs

    func test_timing_500msGap_reflectedInMouseMoveDuration() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 440, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 150, type: .mouseUp, x: 441, y: 103, button: "left"),
            RawEvent(timeMs: 650, type: .mouseDown, x: 800, y: 500, button: "left", ax: axInfo()),
            RawEvent(timeMs: 700, type: .mouseUp, x: 801, y: 501, button: "left")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)

        // mouse_move between two clicks should have durationMs = 650 - 150 = 500
        let moveSteps = scenario.steps.filter { $0.type == .mouseMove }
        XCTAssertEqual(moveSteps.count, 1)
        XCTAssertEqual(moveSteps[0].durationMs, 500)
    }

    // MARK: - 13. positionHint Calculation

    func test_positionHint_normalization() {
        // captureArea = (100, 50, 1920, 1080)
        // absolute coord = (440, 102)
        // positionHint.x = (440 - 100) / 1920 = 340/1920
        // positionHint.y = (102 - 50) / 1080 = 52/1080
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 440, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 150, type: .mouseUp, x: 441, y: 103, button: "left")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 1)
        guard let hint = actions[0].target?.positionHint else {
            XCTFail("Expected positionHint on target")
            return
        }
        XCTAssertEqual(hint.x, 340.0 / 1920.0, accuracy: 0.001)
        XCTAssertEqual(hint.y, 52.0 / 1080.0, accuracy: 0.001)
    }

    // MARK: - appContext Detection

    func test_appContext_mostFrequentBundleId() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .appActivated, bundleId: "com.apple.finder", appName: "Finder"),
            RawEvent(timeMs: 200, type: .appActivated, bundleId: "com.apple.safari", appName: "Safari"),
            RawEvent(timeMs: 300, type: .appActivated, bundleId: "com.apple.safari", appName: "Safari")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)

        XCTAssertEqual(scenario.appContext, "com.apple.safari")
    }

    func test_appContext_nil_whenNoAppEvents() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 440, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 150, type: .mouseUp, x: 441, y: 103, button: "left")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)

        XCTAssertNil(scenario.appContext)
    }

    // MARK: - mouse_move rawTimeRange

    func test_mouseMove_hasRawTimeRange() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 440, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 150, type: .mouseUp, x: 441, y: 103, button: "left"),
            RawEvent(timeMs: 700, type: .mouseDown, x: 800, y: 500, button: "left", ax: axInfo()),
            RawEvent(timeMs: 750, type: .mouseUp, x: 801, y: 501, button: "left")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)

        let moveSteps = scenario.steps.filter { $0.type == .mouseMove }
        XCTAssertEqual(moveSteps.count, 1)
        XCTAssertEqual(moveSteps[0].rawTimeRange?.startMs, 150)
        XCTAssertEqual(moveSteps[0].rawTimeRange?.endMs, 700)
    }

    // MARK: - Double-click not triggered when gap > 400ms

    func test_twoClicks_moreThan400msApart_areSeparateClicks() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .mouseDown, x: 440, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 130, type: .mouseUp, x: 441, y: 102, button: "left"),
            RawEvent(timeMs: 600, type: .mouseDown, x: 441, y: 102, button: "left", ax: axInfo()),
            RawEvent(timeMs: 630, type: .mouseUp, x: 442, y: 103, button: "left")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].type, .click)
        XCTAssertEqual(actions[1].type, .click)
    }

    // MARK: - Keyboard combo with multiple modifiers

    func test_keyboardCombo_cmdShiftS() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .keyDown, keyCode: 1, characters: "s", modifiers: ["cmd", "shift"]),
            RawEvent(timeMs: 150, type: .keyUp, keyCode: 1, characters: "s")
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].type, .keyboard)
        // Modifiers should be sorted for consistency
        XCTAssertTrue(actions[0].keyCombo == "cmd+shift+s" || actions[0].keyCombo == "shift+cmd+s",
                       "Expected combo with cmd and shift modifiers, got: \(actions[0].keyCombo ?? "nil")")
    }

    // MARK: - Scroll direction detection

    func test_scrollDirection_down_forNegativeDeltaY() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .scroll, x: 500, y: 400, deltaX: 0, deltaY: -50)
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions[0].direction, .down)
    }

    func test_scrollDirection_up_forPositiveDeltaY() {
        let raw = makeRawEvents([
            RawEvent(timeMs: 100, type: .scroll, x: 500, y: 400, deltaX: 0, deltaY: 50)
        ])
        let scenario = ScenarioGenerator.generate(from: raw)
        let actions = actionSteps(scenario)

        XCTAssertEqual(actions[0].direction, .up)
    }
}
