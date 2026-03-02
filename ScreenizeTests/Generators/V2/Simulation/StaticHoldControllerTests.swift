import XCTest
@testable import Screenize

final class StaticHoldControllerTests: XCTestCase {

    private let controller = StaticHoldController()
    private let defaultSettings = SimulationSettings()

    func test_simulate_producesAtLeastTwoSamples() {
        let scene = makeScene(start: 0, end: 5)
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.7))
        let mockData = MockMouseDataSource(duration: 5.0)

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan, mouseData: mockData, settings: defaultSettings
        )
        XCTAssertGreaterThanOrEqual(samples.count, 2)
    }

    func test_simulate_samplesSpanSceneDuration() {
        let scene = makeScene(start: 2, end: 8)
        let shotPlan = makeShotPlan(scene: scene, zoom: 1.5, center: NormalizedPoint(x: 0.5, y: 0.5))
        let mockData = MockMouseDataSource(duration: 10.0)

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan, mouseData: mockData, settings: defaultSettings
        )
        XCTAssertEqual(samples.first?.time, 2.0)
        XCTAssertEqual(samples.last?.time, 8.0)
    }

    func test_simulate_transformMatchesShotPlan() {
        let center = NormalizedPoint(x: 0.4, y: 0.6)
        let scene = makeScene(start: 0, end: 5)
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.2, center: center)
        let mockData = MockMouseDataSource(duration: 5.0)

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan, mouseData: mockData, settings: defaultSettings
        )
        for sample in samples {
            XCTAssertEqual(sample.transform.zoom, 2.2, accuracy: 0.001)
            XCTAssertEqual(sample.transform.center.x, center.x, accuracy: 0.001)
            XCTAssertEqual(sample.transform.center.y, center.y, accuracy: 0.001)
        }
    }

    func test_simulate_allSamplesHaveConstantTransform() {
        let scene = makeScene(start: 0, end: 10)
        let shotPlan = makeShotPlan(scene: scene, zoom: 1.8, center: NormalizedPoint(x: 0.5, y: 0.5))
        let mockData = MockMouseDataSource(duration: 10.0)

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan, mouseData: mockData, settings: defaultSettings
        )
        let first = samples[0].transform
        for sample in samples {
            XCTAssertEqual(sample.transform.zoom, first.zoom, accuracy: 0.001)
            XCTAssertEqual(sample.transform.center.x, first.center.x, accuracy: 0.001)
            XCTAssertEqual(sample.transform.center.y, first.center.y, accuracy: 0.001)
        }
    }

    func test_simulate_zeroLengthScene() {
        let scene = makeScene(start: 3, end: 3)
        let shotPlan = makeShotPlan(scene: scene, zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        let mockData = MockMouseDataSource(duration: 5.0)

        let samples = controller.simulate(
            scene: scene, shotPlan: shotPlan, mouseData: mockData, settings: defaultSettings
        )
        // Even a zero-length scene should produce at least one sample
        XCTAssertFalse(samples.isEmpty)
    }

    func test_simulate_clickingPrefersClickAnchorsOverMouseMoves() {
        let events = [
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.92, y: 0.88)),
            makeClickEvent(time: 2.0, position: NormalizedPoint(x: 0.22, y: 0.25))
        ]
        var settings = SimulationSettings()
        settings.eventTimeline = EventTimeline(events: events, duration: 5.0)

        let scene = makeScene(start: 0, end: 5)
        let shotPlan = makeShotPlan(
            scene: scene,
            zoom: 2.0,
            center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let mockData = MockMouseDataSource(duration: 5.0)

        let samples = controller.simulate(
            scene: scene,
            shotPlan: shotPlan,
            mouseData: mockData,
            settings: settings
        )

        guard let last = samples.last else {
            XCTFail("Expected samples")
            return
        }
        XCTAssertLessThan(
            last.transform.center.x,
            0.5,
            "Clicking scenes should follow click anchors instead of stray mouse moves"
        )
    }

    // MARK: - Helpers

    private func makeScene(
        start: TimeInterval, end: TimeInterval
    ) -> CameraScene {
        CameraScene(
            startTime: start, endTime: end, primaryIntent: .clicking
        )
    }

    private func makeShotPlan(
        scene: CameraScene, zoom: CGFloat, center: NormalizedPoint
    ) -> ShotPlan {
        ShotPlan(
            scene: scene,
            shotType: .medium(zoom: zoom),
            idealZoom: zoom,
            idealCenter: center
        )
    }

    private func makeMouseMoveEvent(
        time: TimeInterval,
        position: NormalizedPoint
    ) -> UnifiedEvent {
        UnifiedEvent(
            time: time,
            kind: .mouseMove,
            position: position,
            metadata: EventMetadata()
        )
    }

    private func makeClickEvent(
        time: TimeInterval,
        position: NormalizedPoint
    ) -> UnifiedEvent {
        let click = ClickEventData(
            time: time,
            position: position,
            clickType: .leftDown
        )
        return UnifiedEvent(
            time: time,
            kind: .click(click),
            position: position,
            metadata: EventMetadata()
        )
    }
}
