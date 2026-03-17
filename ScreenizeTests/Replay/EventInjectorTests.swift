import XCTest
import CoreGraphics
@testable import Screenize

final class EventInjectorTests: XCTestCase {

    // MARK: - createMouseMoveEvent

    func testCreateMouseMoveEvent_returnsNonNil() {
        let point = CGPoint(x: 100, y: 200)
        let event = EventInjector.createMouseMoveEvent(to: point)
        XCTAssertNotNil(event)
    }

    func testCreateMouseMoveEvent_positionMatchesTarget() {
        let point = CGPoint(x: 350, y: 450)
        guard let event = EventInjector.createMouseMoveEvent(to: point) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        let location = event.location
        XCTAssertEqual(location.x, point.x, accuracy: 0.001)
        XCTAssertEqual(location.y, point.y, accuracy: 0.001)
    }

    func testCreateMouseMoveEvent_typeIsMouseMoved() {
        let point = CGPoint(x: 100, y: 100)
        guard let event = EventInjector.createMouseMoveEvent(to: point) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertEqual(event.type, .mouseMoved)
    }

    // MARK: - createLeftClickEvents

    func testCreateLeftClickEvents_returnsTwoEvents() {
        let point = CGPoint(x: 200, y: 300)
        let events = EventInjector.createLeftClickEvents(at: point)
        XCTAssertEqual(events.count, 2)
    }

    func testCreateLeftClickEvents_firstEventIsMouseDown() {
        let point = CGPoint(x: 200, y: 300)
        let events = EventInjector.createLeftClickEvents(at: point)
        XCTAssertEqual(events[0].type, .leftMouseDown)
    }

    func testCreateLeftClickEvents_secondEventIsMouseUp() {
        let point = CGPoint(x: 200, y: 300)
        let events = EventInjector.createLeftClickEvents(at: point)
        XCTAssertEqual(events[1].type, .leftMouseUp)
    }

    func testCreateLeftClickEvents_positionsMatchTarget() {
        let point = CGPoint(x: 150, y: 250)
        let events = EventInjector.createLeftClickEvents(at: point)
        for event in events {
            XCTAssertEqual(event.location.x, point.x, accuracy: 0.001)
            XCTAssertEqual(event.location.y, point.y, accuracy: 0.001)
        }
    }

    func testCreateLeftClickEvents_defaultClickCountIsOne() {
        let point = CGPoint(x: 100, y: 100)
        let events = EventInjector.createLeftClickEvents(at: point)
        for event in events {
            let clickState = event.getIntegerValueField(.mouseEventClickState)
            XCTAssertEqual(clickState, 1)
        }
    }

    // MARK: - createLeftClickEvents doubleClick

    func testCreateLeftClickEvents_doubleClick_clickCountIsTwo() {
        let point = CGPoint(x: 100, y: 100)
        let events = EventInjector.createLeftClickEvents(at: point, clickCount: 2)
        XCTAssertEqual(events.count, 2)
        for event in events {
            let clickState = event.getIntegerValueField(.mouseEventClickState)
            XCTAssertEqual(clickState, 2)
        }
    }

    func testCreateLeftClickEvents_doubleClick_typesAreCorrect() {
        let point = CGPoint(x: 100, y: 100)
        let events = EventInjector.createLeftClickEvents(at: point, clickCount: 2)
        XCTAssertEqual(events[0].type, .leftMouseDown)
        XCTAssertEqual(events[1].type, .leftMouseUp)
    }

    // MARK: - createRightClickEvents

    func testCreateRightClickEvents_returnsTwoEvents() {
        let point = CGPoint(x: 300, y: 400)
        let events = EventInjector.createRightClickEvents(at: point)
        XCTAssertEqual(events.count, 2)
    }

    func testCreateRightClickEvents_firstEventIsRightMouseDown() {
        let point = CGPoint(x: 300, y: 400)
        let events = EventInjector.createRightClickEvents(at: point)
        XCTAssertEqual(events[0].type, .rightMouseDown)
    }

    func testCreateRightClickEvents_secondEventIsRightMouseUp() {
        let point = CGPoint(x: 300, y: 400)
        let events = EventInjector.createRightClickEvents(at: point)
        XCTAssertEqual(events[1].type, .rightMouseUp)
    }

    func testCreateRightClickEvents_positionsMatchTarget() {
        let point = CGPoint(x: 600, y: 800)
        let events = EventInjector.createRightClickEvents(at: point)
        for event in events {
            XCTAssertEqual(event.location.x, point.x, accuracy: 0.001)
            XCTAssertEqual(event.location.y, point.y, accuracy: 0.001)
        }
    }

    // MARK: - createKeyboardEvent

    func testCreateKeyboardEvent_returnsNonNil() {
        let event = EventInjector.createKeyboardEvent(keyCode: 8, flags: [], isDown: true)
        XCTAssertNotNil(event)
    }

    func testCreateKeyboardEvent_keyDown_typeIsKeyDown() {
        guard let event = EventInjector.createKeyboardEvent(keyCode: 8, flags: [], isDown: true) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertEqual(event.type, .keyDown)
    }

    func testCreateKeyboardEvent_keyUp_typeIsKeyUp() {
        guard let event = EventInjector.createKeyboardEvent(keyCode: 8, flags: [], isDown: false) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertEqual(event.type, .keyUp)
    }

    func testCreateKeyboardEvent_keyCodeIsSet() {
        let keyCode: UInt16 = 0  // 'a'
        guard let event = EventInjector.createKeyboardEvent(keyCode: keyCode, flags: [], isDown: true) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        let storedKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
        XCTAssertEqual(UInt16(storedKeyCode), keyCode)
    }

    func testCreateKeyboardEvent_flagsAreSet() {
        let flags: CGEventFlags = [.maskCommand]
        guard let event = EventInjector.createKeyboardEvent(keyCode: 8, flags: flags, isDown: true) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertTrue(event.flags.contains(.maskCommand))
    }

    func testCreateKeyboardEvent_multipleFlags() {
        let flags: CGEventFlags = [.maskCommand, .maskShift]
        guard let event = EventInjector.createKeyboardEvent(keyCode: 6, flags: flags, isDown: true) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertTrue(event.flags.contains(.maskCommand))
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    // MARK: - createScrollEvent

    func testCreateScrollEvent_returnsNonNil() {
        let event = EventInjector.createScrollEvent(deltaX: 0, deltaY: 10)
        XCTAssertNotNil(event)
    }

    func testCreateScrollEvent_typeIsScrollWheel() {
        guard let event = EventInjector.createScrollEvent(deltaX: 0, deltaY: 10) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertEqual(event.type, .scrollWheel)
    }

    func testCreateScrollEvent_deltaYIsSet() {
        let deltaY: Int32 = 20
        guard let event = EventInjector.createScrollEvent(deltaX: 0, deltaY: deltaY) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        let storedDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        XCTAssertEqual(Int32(storedDelta), deltaY)
    }

    func testCreateScrollEvent_deltaXIsSet() {
        let deltaX: Int32 = 15
        guard let event = EventInjector.createScrollEvent(deltaX: deltaX, deltaY: 0) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        let storedDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        XCTAssertEqual(Int32(storedDelta), deltaX)
    }

    func testCreateScrollEvent_zeroDelta_returnsNonNil() {
        let event = EventInjector.createScrollEvent(deltaX: 0, deltaY: 0)
        XCTAssertNotNil(event)
    }

    func testCreateScrollEvent_negativeDelta_returnsNonNil() {
        let event = EventInjector.createScrollEvent(deltaX: -5, deltaY: -10)
        XCTAssertNotNil(event)
    }

    // MARK: - createMouseDownEvent / createMouseUpEvent

    func testCreateMouseDownEvent_returnsNonNil() {
        let event = EventInjector.createMouseDownEvent(at: CGPoint(x: 100, y: 100))
        XCTAssertNotNil(event)
    }

    func testCreateMouseDownEvent_defaultButton_typeIsLeftMouseDown() {
        guard let event = EventInjector.createMouseDownEvent(at: CGPoint(x: 100, y: 100)) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertEqual(event.type, .leftMouseDown)
    }

    func testCreateMouseUpEvent_returnsNonNil() {
        let event = EventInjector.createMouseUpEvent(at: CGPoint(x: 100, y: 100))
        XCTAssertNotNil(event)
    }

    func testCreateMouseUpEvent_defaultButton_typeIsLeftMouseUp() {
        guard let event = EventInjector.createMouseUpEvent(at: CGPoint(x: 100, y: 100)) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertEqual(event.type, .leftMouseUp)
    }

    func testCreateMouseDownEvent_rightButton_typeIsRightMouseDown() {
        guard let event = EventInjector.createMouseDownEvent(at: CGPoint(x: 100, y: 100), button: .right) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertEqual(event.type, .rightMouseDown)
    }

    func testCreateMouseUpEvent_rightButton_typeIsRightMouseUp() {
        guard let event = EventInjector.createMouseUpEvent(at: CGPoint(x: 100, y: 100), button: .right) else {
            XCTFail("Expected non-nil CGEvent")
            return
        }
        XCTAssertEqual(event.type, .rightMouseUp)
    }
}
