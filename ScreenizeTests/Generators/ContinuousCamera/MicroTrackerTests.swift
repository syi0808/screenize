import XCTest
import CoreGraphics
@testable import Screenize

final class MicroTrackerTests: XCTestCase {

    private let defaultSettings = MicroTrackerSettings()

    // MARK: - Dead Zone

    func test_cursorInDeadZone_offsetIsZero() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.5, y: 0.5)

        for _ in 0..<60 {
            tracker.update(cursorPosition: cursor, macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60)
        }

        XCTAssertEqual(tracker.offset.x, 0, accuracy: 0.001)
        XCTAssertEqual(tracker.offset.y, 0, accuracy: 0.001)
    }

    func test_cursorSlightlyOffCenter_stillInDeadZone() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let zoom: CGFloat = 2.0
        // At zoom 2.0, viewportHalf = 0.25, deadZone = 0.25 * 0.4 = 0.10
        // Cursor at 0.55 is 0.05 from center, within deadZone
        let cursor = NormalizedPoint(x: 0.55, y: 0.5)

        for _ in 0..<120 {
            tracker.update(cursorPosition: cursor, macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60)
        }

        XCTAssertEqual(tracker.offset.x, 0, accuracy: 0.005,
                       "Cursor within dead zone should not produce offset")
    }

    func test_cursorOutsideDeadZone_offsetMovesTowardCursor() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let zoom: CGFloat = 2.0
        // At zoom 2.0, viewportHalf = 0.25, deadZone = 0.10
        // Cursor at 0.7 is 0.2 away from center, exceeding deadZone by 0.1
        let cursor = NormalizedPoint(x: 0.7, y: 0.5)

        for _ in 0..<120 {
            tracker.update(cursorPosition: cursor, macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60)
        }

        XCTAssertGreaterThan(tracker.offset.x, 0.05,
                             "Offset should move toward cursor when outside dead zone")
    }

    // MARK: - Offset Limit

    func test_offset_clampedToMaxRatio() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.3, y: 0.5)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.9, y: 0.5)
        let viewportHalf = 0.5 / zoom
        let maxOffset = viewportHalf * defaultSettings.maxOffsetRatio

        for _ in 0..<300 {
            tracker.update(cursorPosition: cursor, macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60)
        }

        XCTAssertLessThanOrEqual(abs(tracker.offset.x), maxOffset + 0.01,
                                 "Offset should be clamped to max ratio")
    }

    // MARK: - Macro Transition Compensation

    func test_macroTransition_compensatesOffset() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.7, y: 0.5)
        let oldMacro = NormalizedPoint(x: 0.5, y: 0.5)

        for _ in 0..<120 {
            tracker.update(
                cursorPosition: cursor,
                macroCenter: oldMacro,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }
        let offsetBefore = tracker.offset
        let effectiveBefore = oldMacro.x + offsetBefore.x

        let newMacro = NormalizedPoint(x: 0.6, y: 0.5)
        tracker.compensateForMacroTransition(
            oldCenter: oldMacro,
            newCenter: newMacro
        )
        let effectiveAfter = newMacro.x + tracker.offset.x

        XCTAssertEqual(effectiveBefore, effectiveAfter, accuracy: 0.001,
                       "Effective center should not jump after macro transition")
    }

    // MARK: - Idle Returns to Zero

    func test_idle_offsetReturnsToZero() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let zoom: CGFloat = 2.0

        for _ in 0..<60 {
            tracker.update(
                cursorPosition: NormalizedPoint(x: 0.7, y: 0.5),
                macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60
            )
        }
        XCTAssertGreaterThan(abs(tracker.offset.x), 0.01)

        for _ in 0..<300 {
            tracker.update(
                cursorPosition: macroCenter,
                macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60,
                isIdle: true
            )
        }

        XCTAssertEqual(tracker.offset.x, 0, accuracy: 0.005,
                       "Offset should return to zero during idle")
    }

    // MARK: - Spring Smoothness

    func test_offset_changesGradually() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.8, y: 0.5)

        var offsets: [CGFloat] = []
        for _ in 0..<60 {
            tracker.update(cursorPosition: cursor, macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60)
            offsets.append(tracker.offset.x)
        }

        // No single-frame jump should exceed 0.04 (spring response is fast at 0.15s)
        for i in 1..<offsets.count {
            let jump = abs(offsets[i] - offsets[i - 1])
            XCTAssertLessThan(jump, 0.04,
                              "Offset should change smoothly frame to frame (jump=\(jump) at frame \(i))")
        }
    }
}
