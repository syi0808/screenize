import XCTest
@testable import Screenize

final class CursorFollowControllerTests: XCTestCase {

    private let defaultSettings = SimulationSettings()

    // MARK: - Start Position

    func test_simulate_startsAtShotPlanPosition() {
        let controller = CursorFollowController()
        let scene = makeScene(start: 0, end: 5, intent: .typing(context: .codeEditor))
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.4))
        let settings = makeSettings(events: [], screenBounds: CGSize(width: 1920, height: 1080))

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan,
            mouseData: EmptyMouseDataSource(), settings: settings
        )

        XCTAssertFalse(samples.isEmpty)
        XCTAssertEqual(samples[0].transform.zoom, 2.0, accuracy: 0.01)
        XCTAssertEqual(samples[0].transform.center.x, 0.3, accuracy: 0.01)
        XCTAssertEqual(samples[0].transform.center.y, 0.4, accuracy: 0.01)
    }

    // MARK: - Stationary Caret

    func test_simulate_stationaryCaret_holdsSteady() {
        let controller = CursorFollowController()
        // Caret stays at same position throughout
        let events = [
            makeUIStateEvent(time: 1.0, caretCenter: NormalizedPoint(x: 0.3, y: 0.4)),
            makeUIStateEvent(time: 2.0, caretCenter: NormalizedPoint(x: 0.3, y: 0.4)),
            makeUIStateEvent(time: 3.0, caretCenter: NormalizedPoint(x: 0.3, y: 0.4)),
        ]
        let scene = makeScene(start: 0, end: 5, intent: .typing(context: .codeEditor))
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.4))
        let settings = makeSettings(events: events, screenBounds: CGSize(width: 1920, height: 1080))

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan,
            mouseData: EmptyMouseDataSource(), settings: settings
        )

        // All samples should have same center (no panning)
        for sample in samples {
            XCTAssertEqual(sample.transform.center.x, 0.3, accuracy: 0.05)
            XCTAssertEqual(sample.transform.center.y, 0.4, accuracy: 0.05)
            XCTAssertEqual(sample.transform.zoom, 2.0, accuracy: 0.01)
        }
    }

    // MARK: - Caret Moves Outside Viewport

    func test_simulate_caretMovesOutsideViewport_pansToCaret() {
        let controller = CursorFollowController()
        // At zoom 2.0 centered at (0.3, 0.4), viewport is [0.05, 0.55] x [0.15, 0.65]
        // Caret at (0.8, 0.8) is outside → should trigger pan
        let events = [
            makeUIStateEvent(time: 1.0, caretCenter: NormalizedPoint(x: 0.3, y: 0.4)),
            makeUIStateEvent(time: 2.5, caretCenter: NormalizedPoint(x: 0.8, y: 0.8)),
        ]
        let scene = makeScene(start: 0, end: 5, intent: .typing(context: .codeEditor))
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.4))
        let settings = makeSettings(events: events, screenBounds: CGSize(width: 1920, height: 1080))

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan,
            mouseData: EmptyMouseDataSource(), settings: settings
        )

        // Should have more than 2 samples (start + end) due to pan
        XCTAssertGreaterThan(samples.count, 2)
        // Last sample should be near the new caret position
        let lastCenter = samples.last!.transform.center
        XCTAssertGreaterThan(lastCenter.x, 0.5, "Center should have moved toward caret at 0.8")
        XCTAssertGreaterThan(lastCenter.y, 0.5, "Center should have moved toward caret at 0.8")
    }

    // MARK: - Caret Within Viewport

    func test_simulate_caretWithinViewport_noMovement() {
        let controller = CursorFollowController()
        // At zoom 2.0 centered at (0.5, 0.5), viewport is [0.25, 0.75] x [0.25, 0.75]
        // Caret at (0.45, 0.55) is inside → no pan
        let events = [
            makeUIStateEvent(time: 1.0, caretCenter: NormalizedPoint(x: 0.5, y: 0.5)),
            makeUIStateEvent(time: 2.5, caretCenter: NormalizedPoint(x: 0.45, y: 0.55)),
        ]
        let scene = makeScene(start: 0, end: 5, intent: .typing(context: .codeEditor))
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        let settings = makeSettings(events: events, screenBounds: CGSize(width: 1920, height: 1080))

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan,
            mouseData: EmptyMouseDataSource(), settings: settings
        )

        // Should have exactly 2 samples (start + end) — no intermediate pans
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].transform.center.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(samples[1].transform.center.x, 0.5, accuracy: 0.01)
    }

    // MARK: - Multiple Pans

    func test_simulate_multiplePans_followsSequence() {
        let controller = CursorFollowController()
        // At zoom 2.0, viewport is 0.5 wide. Multiple caret jumps outside viewport.
        let events = [
            makeUIStateEvent(time: 0.5, caretCenter: NormalizedPoint(x: 0.3, y: 0.3)),
            // Jump far right at t=1.5 (outside viewport of center 0.3)
            makeUIStateEvent(time: 1.5, caretCenter: NormalizedPoint(x: 0.8, y: 0.3)),
            // Jump far down at t=3.0 (outside viewport of center ~0.8)
            makeUIStateEvent(time: 3.0, caretCenter: NormalizedPoint(x: 0.8, y: 0.8)),
        ]
        let scene = makeScene(start: 0, end: 5, intent: .typing(context: .codeEditor))
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let settings = makeSettings(events: events, screenBounds: CGSize(width: 1920, height: 1080))

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan,
            mouseData: EmptyMouseDataSource(), settings: settings
        )

        // Should have multiple pan keyframes
        XCTAssertGreaterThan(samples.count, 4, "Should produce keyframes for two pans")
    }

    // MARK: - Pan Clamped to Viewport

    func test_simulate_panClampedToViewport() {
        let controller = CursorFollowController()
        // Caret at extreme edge (0.99, 0.99) → center must be clamped
        let events = [
            makeUIStateEvent(time: 1.5, caretCenter: NormalizedPoint(x: 0.99, y: 0.99)),
        ]
        let scene = makeScene(start: 0, end: 5, intent: .typing(context: .codeEditor))
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        let settings = makeSettings(events: events, screenBounds: CGSize(width: 1920, height: 1080))

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan,
            mouseData: EmptyMouseDataSource(), settings: settings
        )

        // All centers should be within valid bounds: [halfCrop, 1-halfCrop]
        let halfCrop = 0.5 / 2.0 // = 0.25
        for sample in samples {
            XCTAssertGreaterThanOrEqual(sample.transform.center.x, halfCrop - 0.01)
            XCTAssertLessThanOrEqual(sample.transform.center.x, 1.0 - halfCrop + 0.01)
            XCTAssertGreaterThanOrEqual(sample.transform.center.y, halfCrop - 0.01)
            XCTAssertLessThanOrEqual(sample.transform.center.y, 1.0 - halfCrop + 0.01)
        }
    }

    // MARK: - Debounce

    func test_simulate_minimumPanInterval_debounce() {
        let controller = CursorFollowController()
        // Rapid caret jumps within 0.5s should be debounced
        let events = [
            makeUIStateEvent(time: 1.0, caretCenter: NormalizedPoint(x: 0.8, y: 0.3)),
            makeUIStateEvent(time: 1.1, caretCenter: NormalizedPoint(x: 0.2, y: 0.8)),
            makeUIStateEvent(time: 1.2, caretCenter: NormalizedPoint(x: 0.9, y: 0.2)),
        ]
        let scene = makeScene(start: 0, end: 5, intent: .typing(context: .codeEditor))
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        let settings = makeSettings(events: events, screenBounds: CGSize(width: 1920, height: 1080))

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan,
            mouseData: EmptyMouseDataSource(), settings: settings
        )

        // Should only trigger at most 1 pan (first one), the rest are debounced
        // Start + hold + pan end + scene end = 4 max
        // Or: start + pan-start + pan-end + end = 4
        XCTAssertLessThanOrEqual(samples.count, 4, "Rapid caret jumps should be debounced")
    }

    // MARK: - Fallback to Mouse

    func test_simulate_noCaretData_fallsBackToMouse() {
        let controller = CursorFollowController()
        // No caret data, but mouse events that move outside viewport
        let events = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.3, y: 0.3)),
            makeMouseMoveEvent(time: 2.0, position: NormalizedPoint(x: 0.85, y: 0.85)),
        ]
        let scene = makeScene(start: 0, end: 5, intent: .typing(context: .codeEditor))
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let settings = makeSettings(events: events, screenBounds: CGSize(width: 1920, height: 1080))

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan,
            mouseData: EmptyMouseDataSource(), settings: settings
        )

        // Should trigger a pan toward (0.85, 0.85)
        XCTAssertGreaterThan(samples.count, 2, "Should pan to follow mouse when no caret data")
        let lastCenter = samples.last!.transform.center
        XCTAssertGreaterThan(lastCenter.x, 0.5, "Should have followed mouse to the right")
    }

    // MARK: - Helpers

    private func makeScene(
        start: TimeInterval, end: TimeInterval, intent: UserIntent
    ) -> CameraScene {
        CameraScene(
            startTime: start, endTime: end,
            primaryIntent: intent,
            focusRegions: []
        )
    }

    private func makeShotPlan(
        scene: CameraScene, zoom: CGFloat, center: NormalizedPoint
    ) -> ShotPlan {
        ShotPlan(
            scene: scene,
            shotType: zoom > 2.0 ? .closeUp(zoom: zoom) : .medium(zoom: zoom),
            idealZoom: zoom,
            idealCenter: center
        )
    }

    private func makeSettings(
        events: [UnifiedEvent],
        screenBounds: CGSize
    ) -> SimulationSettings {
        let timeline = EventTimeline(events: events, duration: 10.0)
        return SimulationSettings(
            eventTimeline: timeline,
            screenBounds: screenBounds
        )
    }

    private func makeUIStateEvent(
        time: TimeInterval, caretCenter: NormalizedPoint
    ) -> UnifiedEvent {
        // Create caret bounds as a small rect centered at the given normalized point
        let caretRect = CGRect(
            x: caretCenter.x - 0.005, y: caretCenter.y - 0.01,
            width: 0.01, height: 0.02
        )
        return UnifiedEvent(
            time: time,
            kind: .mouseMove,
            position: caretCenter,
            metadata: EventMetadata(caretBounds: caretRect)
        )
    }

    private func makeMouseMoveEvent(
        time: TimeInterval, position: NormalizedPoint
    ) -> UnifiedEvent {
        UnifiedEvent(
            time: time,
            kind: .mouseMove,
            position: position,
            metadata: EventMetadata()
        )
    }
}

/// Minimal MouseDataSource for testing.
private struct EmptyMouseDataSource: MouseDataSource {
    var duration: TimeInterval { 10.0 }
    var frameRate: Double { 60.0 }
    var positions: [MousePositionData] { [] }
    var clicks: [ClickEventData] { [] }
    var keyboardEvents: [KeyboardEventData] { [] }
    var dragEvents: [DragEventData] { [] }
}
