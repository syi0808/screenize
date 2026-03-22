import XCTest
import CoreGraphics
@testable import Screenize

final class ScenarioModelsTests: XCTestCase {

    // MARK: - Helpers

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private let decoder = JSONDecoder()

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - MousePath Codable

    func test_mousePath_auto_roundTrip() throws {
        let path = MousePath.auto
        let decoded = try roundTrip(path)
        XCTAssertEqual(decoded, path)
    }

    func test_mousePath_auto_encodesAsString() throws {
        let path = MousePath.auto
        let plainEncoder = JSONEncoder()
        let data = try plainEncoder.encode(path)
        // Top-level string — compare raw JSON bytes directly
        let jsonString = String(data: data, encoding: .utf8)
        XCTAssertEqual(jsonString, "\"auto\"")
    }

    func test_mousePath_waypoints_roundTrip() throws {
        let points = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.5, y: 0.7)]
        let path = MousePath.waypoints(points: points)
        let decoded = try roundTrip(path)
        XCTAssertEqual(decoded, path)
    }

    func test_mousePath_waypoints_encodesAsObject() throws {
        let path = MousePath.waypoints(points: [CGPoint(x: 0.3, y: 0.4)])
        let data = try encoder.encode(path)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "waypoints")
        XCTAssertNotNil(obj?["points"])
    }

    func test_mousePath_auto_decodesFromStringLiteral() throws {
        let json = "\"auto\"".data(using: .utf8)!
        let decoded = try decoder.decode(MousePath.self, from: json)
        XCTAssertEqual(decoded, .auto)
    }

    // MARK: - TimeRange Codable

    func test_timeRange_roundTrip() throws {
        let range = TimeRange(startMs: 0, endMs: 5000)
        let decoded = try roundTrip(range)
        XCTAssertEqual(decoded, range)
    }

    // MARK: - AXTarget Codable

    func test_axTarget_roundTrip() throws {
        let target = AXTarget(
            role: "AXButton",
            axTitle: "Save",
            axValue: nil,
            path: ["AXWindow", "AXToolbar", "AXButton"],
            positionHint: CGPoint(x: 0.5, y: 0.1),
            absoluteCoord: CGPoint(x: 800, y: 100)
        )
        let decoded = try roundTrip(target)
        XCTAssertEqual(decoded, target)
    }

    func test_axTarget_nilFields_roundTrip() throws {
        let target = AXTarget(
            role: "AXTextField",
            axTitle: nil,
            axValue: nil,
            path: [],
            positionHint: CGPoint(x: 0.0, y: 0.0),
            absoluteCoord: CGPoint(x: 0, y: 0)
        )
        let decoded = try roundTrip(target)
        XCTAssertEqual(decoded, target)
    }

    // MARK: - ScenarioStep Codable

    func test_scenarioStep_click_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            type: .click,
            description: "Click Save button",
            durationMs: 200,
            target: AXTarget(
                role: "AXButton",
                axTitle: "Save",
                axValue: nil,
                path: ["AXWindow", "AXButton"],
                positionHint: CGPoint(x: 0.8, y: 0.05),
                absoluteCoord: CGPoint(x: 1200, y: 40)
            )
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_mouseMove_auto_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789013")!,
            type: .mouseMove,
            description: "Move to button",
            durationMs: 500,
            path: .auto
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_mouseMove_waypoints_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789014")!,
            type: .mouseMove,
            description: "Move along path",
            durationMs: 800,
            path: .waypoints(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5)])
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_mouseMove_withRawTimeRange_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789015")!,
            type: .mouseMove,
            description: "Generated from recording",
            durationMs: 1200,
            path: .auto,
            rawTimeRange: TimeRange(startMs: 0, endMs: 1200)
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_keyboard_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789016")!,
            type: .keyboard,
            description: "Press Cmd+S",
            durationMs: 100,
            keyCombo: "cmd+s"
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_typeText_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789017")!,
            type: .typeText,
            description: "Type filename",
            durationMs: 2000,
            content: "my-recording.mp4",
            typingSpeedMs: 80
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_scroll_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789018")!,
            type: .scroll,
            description: "Scroll down",
            durationMs: 300,
            direction: .down,
            amount: 200
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_activateApp_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789019")!,
            type: .activateApp,
            description: "Switch to Finder",
            durationMs: 500,
            app: "com.apple.finder"
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_wait_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789020")!,
            type: .wait,
            description: "Wait for animation",
            durationMs: 1000
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_doubleClick_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789021")!,
            type: .doubleClick,
            description: "Double-click file",
            durationMs: 150,
            target: AXTarget(
                role: "AXCell",
                axTitle: "myfile.txt",
                axValue: nil,
                path: ["AXWindow", "AXList", "AXCell"],
                positionHint: CGPoint(x: 0.3, y: 0.4),
                absoluteCoord: CGPoint(x: 400, y: 300)
            )
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
    }

    func test_scenarioStep_durationSeconds_computation() {
        let step = ScenarioStep(
            id: UUID(),
            type: .wait,
            description: "Wait",
            durationMs: 2500
        )
        XCTAssertEqual(step.durationSeconds, 2.5, accuracy: 0.001)
    }

    // MARK: - Scenario Codable

    func test_scenario_roundTrip_mixedSteps() throws {
        let scenario = Scenario(
            appContext: "com.example.app",
            steps: [
                ScenarioStep(
                    id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                    type: .click,
                    description: "Click button",
                    durationMs: 200,
                    target: AXTarget(
                        role: "AXButton",
                        axTitle: "OK",
                        axValue: nil,
                        path: ["AXWindow", "AXButton"],
                        positionHint: CGPoint(x: 0.5, y: 0.5),
                        absoluteCoord: CGPoint(x: 600, y: 400)
                    )
                ),
                ScenarioStep(
                    id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                    type: .mouseMove,
                    description: "Move to field",
                    durationMs: 400,
                    path: .auto
                ),
                ScenarioStep(
                    id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                    type: .typeText,
                    description: "Enter text",
                    durationMs: 1500,
                    content: "Hello, world!",
                    typingSpeedMs: 60
                ),
                ScenarioStep(
                    id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                    type: .keyboard,
                    description: "Submit",
                    durationMs: 50,
                    keyCombo: "return"
                ),
                ScenarioStep(
                    id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
                    type: .scroll,
                    description: "Scroll to result",
                    durationMs: 600,
                    direction: .up,
                    amount: 300
                ),
                ScenarioStep(
                    id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
                    type: .activateApp,
                    description: "Bring Safari to front",
                    durationMs: 300,
                    app: "com.apple.safari"
                ),
                ScenarioStep(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    type: .wait,
                    description: "Pause",
                    durationMs: 1000
                )
            ]
        )
        let decoded = try roundTrip(scenario)
        XCTAssertEqual(decoded, scenario)
    }

    func test_scenario_version_defaultsToOne() {
        let scenario = Scenario(steps: [])
        XCTAssertEqual(scenario.version, 1)
    }

    func test_scenario_appContext_canBeNil() {
        let scenario = Scenario(steps: [])
        XCTAssertNil(scenario.appContext)
    }

    // MARK: - Scenario.totalDuration

    func test_totalDuration_sumOfSteps() {
        let steps = [
            ScenarioStep(id: UUID(), type: .wait, description: "A", durationMs: 1000),
            ScenarioStep(id: UUID(), type: .wait, description: "B", durationMs: 2000),
            ScenarioStep(id: UUID(), type: .wait, description: "C", durationMs: 500)
        ]
        let scenario = Scenario(steps: steps)
        XCTAssertEqual(scenario.totalDuration, 3.5, accuracy: 0.001)
    }

    func test_totalDuration_emptySteps_isZero() {
        let scenario = Scenario(steps: [])
        XCTAssertEqual(scenario.totalDuration, 0.0)
    }

    func test_totalDuration_singleStep() {
        let steps = [ScenarioStep(id: UUID(), type: .wait, description: "A", durationMs: 750)]
        let scenario = Scenario(steps: steps)
        XCTAssertEqual(scenario.totalDuration, 0.75, accuracy: 0.001)
    }

    // MARK: - Scenario.startTime(forStepAt:)

    func test_startTime_firstStep_isZero() {
        let steps = [
            ScenarioStep(id: UUID(), type: .wait, description: "A", durationMs: 1000),
            ScenarioStep(id: UUID(), type: .wait, description: "B", durationMs: 2000)
        ]
        let scenario = Scenario(steps: steps)
        XCTAssertEqual(scenario.startTime(forStepAt: 0), 0.0, accuracy: 0.001)
    }

    func test_startTime_secondStep_equalsFirstDuration() {
        let steps = [
            ScenarioStep(id: UUID(), type: .wait, description: "A", durationMs: 1000),
            ScenarioStep(id: UUID(), type: .wait, description: "B", durationMs: 2000),
            ScenarioStep(id: UUID(), type: .wait, description: "C", durationMs: 500)
        ]
        let scenario = Scenario(steps: steps)
        XCTAssertEqual(scenario.startTime(forStepAt: 1), 1.0, accuracy: 0.001)
        XCTAssertEqual(scenario.startTime(forStepAt: 2), 3.0, accuracy: 0.001)
    }

    func test_startTime_beyondBounds_returnsTotalDuration() {
        let steps = [
            ScenarioStep(id: UUID(), type: .wait, description: "A", durationMs: 1000)
        ]
        let scenario = Scenario(steps: steps)
        // Out-of-bounds index returns total duration (clamps)
        let result = scenario.startTime(forStepAt: 5)
        XCTAssertEqual(result, scenario.totalDuration, accuracy: 0.001)
    }

    // MARK: - Scenario.step(at:)

    func test_stepAt_returnsCorrectStep() {
        let stepA = ScenarioStep(id: UUID(), type: .wait, description: "A", durationMs: 1000)
        let stepB = ScenarioStep(id: UUID(), type: .wait, description: "B", durationMs: 2000)
        let stepC = ScenarioStep(id: UUID(), type: .wait, description: "C", durationMs: 500)
        let scenario = Scenario(steps: [stepA, stepB, stepC])

        XCTAssertEqual(scenario.step(at: 0.0)?.id, stepA.id)
        XCTAssertEqual(scenario.step(at: 0.5)?.id, stepA.id)
        XCTAssertEqual(scenario.step(at: 1.0)?.id, stepB.id)  // boundary: start of B
        XCTAssertEqual(scenario.step(at: 2.0)?.id, stepB.id)
        XCTAssertEqual(scenario.step(at: 3.0)?.id, stepC.id)  // boundary: start of C
        XCTAssertEqual(scenario.step(at: 3.4)?.id, stepC.id)
    }

    func test_stepAt_beyondTotalDuration_returnsNil() {
        let steps = [ScenarioStep(id: UUID(), type: .wait, description: "A", durationMs: 1000)]
        let scenario = Scenario(steps: steps)
        XCTAssertNil(scenario.step(at: 1.5))
    }

    func test_stepAt_negativeTime_returnsNil() {
        let steps = [ScenarioStep(id: UUID(), type: .wait, description: "A", durationMs: 1000)]
        let scenario = Scenario(steps: steps)
        XCTAssertNil(scenario.step(at: -0.1))
    }

    func test_stepAt_emptySteps_returnsNil() {
        let scenario = Scenario(steps: [])
        XCTAssertNil(scenario.step(at: 0.0))
    }

    // MARK: - ScenarioRawEvents Codable

    func test_rawEvents_roundTrip_mixedEvents() throws {
        let rawEvents = ScenarioRawEvents(
            startTimestamp: "2026-03-16T10:00:00Z",
            captureArea: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            events: [
                RawEvent(
                    timeMs: 0,
                    type: .mouseMove,
                    x: 0.5,
                    y: 0.3
                ),
                RawEvent(
                    timeMs: 100,
                    type: .mouseDown,
                    x: 0.5,
                    y: 0.3,
                    button: "left",
                    ax: RawAXInfo(
                        role: "AXButton",
                        axTitle: "OK",
                        axValue: nil,
                        axDescription: "Confirm action",
                        path: ["AXWindow", "AXButton"],
                        frame: CGRect(x: 480, y: 320, width: 80, height: 30)
                    )
                ),
                RawEvent(timeMs: 150, type: .mouseUp, x: 0.5, y: 0.3, button: "left"),
                RawEvent(
                    timeMs: 200,
                    type: .keyDown,
                    keyCode: 36,
                    characters: "\r",
                    modifiers: ["cmd"]
                ),
                RawEvent(timeMs: 250, type: .keyUp, keyCode: 36, characters: "\r"),
                RawEvent(
                    timeMs: 300,
                    type: .scroll,
                    x: 0.5,
                    y: 0.5,
                    deltaX: 0.0,
                    deltaY: -100.0
                ),
                RawEvent(
                    timeMs: 400,
                    type: .appActivated,
                    bundleId: "com.apple.finder",
                    appName: "Finder"
                )
            ]
        )

        let decoded = try roundTrip(rawEvents)
        XCTAssertEqual(decoded, rawEvents)
    }

    func test_rawEvents_version_defaultsToOne() {
        let rawEvents = ScenarioRawEvents(
            startTimestamp: "2026-03-16T10:00:00Z",
            captureArea: CGRect.zero,
            events: []
        )
        XCTAssertEqual(rawEvents.version, 1)
    }

    // MARK: - RawAXInfo Codable

    func test_rawAXInfo_roundTrip() throws {
        let info = RawAXInfo(
            role: "AXTextField",
            axTitle: "Name field",
            axValue: "John",
            axDescription: "Enter your name",
            path: ["AXWindow", "AXGroup", "AXTextField"],
            frame: CGRect(x: 100, y: 200, width: 300, height: 28)
        )
        let decoded = try roundTrip(info)
        XCTAssertEqual(decoded, info)
    }

    // MARK: - Edge Cases

    func test_scenario_emptySteps_nocrash() throws {
        let scenario = Scenario(steps: [])
        let decoded = try roundTrip(scenario)
        XCTAssertEqual(decoded.steps.count, 0)
        XCTAssertEqual(decoded.totalDuration, 0.0)
        XCTAssertNil(decoded.step(at: 0.0))
    }

    func test_scenarioStep_allOptionalFieldsNil_roundTrip() throws {
        let step = ScenarioStep(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAB")!,
            type: .wait,
            description: "Minimal step",
            durationMs: 100
        )
        let decoded = try roundTrip(step)
        XCTAssertEqual(decoded, step)
        XCTAssertNil(decoded.target)
        XCTAssertNil(decoded.path)
        XCTAssertNil(decoded.rawTimeRange)
        XCTAssertNil(decoded.app)
        XCTAssertNil(decoded.keyCombo)
        XCTAssertNil(decoded.content)
        XCTAssertNil(decoded.typingSpeedMs)
        XCTAssertNil(decoded.direction)
        XCTAssertNil(decoded.amount)
    }

    func test_stepType_rawValues_matchSpec() {
        XCTAssertEqual(ScenarioStep.StepType.mouseMove.rawValue, "mouse_move")
        XCTAssertEqual(ScenarioStep.StepType.activateApp.rawValue, "activate_app")
        XCTAssertEqual(ScenarioStep.StepType.click.rawValue, "click")
        XCTAssertEqual(ScenarioStep.StepType.doubleClick.rawValue, "double_click")
        XCTAssertEqual(ScenarioStep.StepType.rightClick.rawValue, "right_click")
        XCTAssertEqual(ScenarioStep.StepType.mouseDown.rawValue, "mouse_down")
        XCTAssertEqual(ScenarioStep.StepType.mouseUp.rawValue, "mouse_up")
        XCTAssertEqual(ScenarioStep.StepType.scroll.rawValue, "scroll")
        XCTAssertEqual(ScenarioStep.StepType.keyboard.rawValue, "keyboard")
        XCTAssertEqual(ScenarioStep.StepType.typeText.rawValue, "type_text")
        XCTAssertEqual(ScenarioStep.StepType.wait.rawValue, "wait")
    }

    func test_scrollDirection_rawValues_matchSpec() {
        XCTAssertEqual(ScenarioStep.ScrollDirection.up.rawValue, "up")
        XCTAssertEqual(ScenarioStep.ScrollDirection.down.rawValue, "down")
        XCTAssertEqual(ScenarioStep.ScrollDirection.left.rawValue, "left")
        XCTAssertEqual(ScenarioStep.ScrollDirection.right.rawValue, "right")
    }

    func test_rawEventType_rawValues_matchSpec() {
        XCTAssertEqual(RawEvent.RawEventType.mouseMove.rawValue, "mouse_move")
        XCTAssertEqual(RawEvent.RawEventType.mouseDown.rawValue, "mouse_down")
        XCTAssertEqual(RawEvent.RawEventType.mouseUp.rawValue, "mouse_up")
        XCTAssertEqual(RawEvent.RawEventType.scroll.rawValue, "scroll")
        XCTAssertEqual(RawEvent.RawEventType.keyDown.rawValue, "key_down")
        XCTAssertEqual(RawEvent.RawEventType.keyUp.rawValue, "key_up")
        XCTAssertEqual(RawEvent.RawEventType.appActivated.rawValue, "app_activated")
    }
}
