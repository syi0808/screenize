import XCTest
@testable import Screenize

final class CameraSimulatorTests: XCTestCase {

    private let simulator = CameraSimulator()
    private let defaultSettings = SimulationSettings()
    private let mockData = MockMouseDataSource(duration: 10.0)

    // MARK: - Empty Input

    func test_simulate_emptyInput_returnsEmptyPath() {
        let path = simulator.simulate(
            shotPlans: [], transitions: [], mouseData: mockData,
            settings: defaultSettings, duration: 10.0
        )
        XCTAssertTrue(path.sceneSegments.isEmpty)
        XCTAssertTrue(path.transitionSegments.isEmpty)
    }

    // MARK: - Single Scene

    func test_simulate_singleScene_oneSceneSegment() {
        let shot = makeShotPlan(start: 0, end: 5, zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        let path = simulator.simulate(
            shotPlans: [shot], transitions: [], mouseData: mockData,
            settings: defaultSettings, duration: 10.0
        )
        XCTAssertEqual(path.sceneSegments.count, 1)
        XCTAssertTrue(path.transitionSegments.isEmpty)
    }

    func test_simulate_singleScene_noTransitionSegments() {
        let shot = makeShotPlan(start: 0, end: 5, zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        let path = simulator.simulate(
            shotPlans: [shot], transitions: [], mouseData: mockData,
            settings: defaultSettings, duration: 10.0
        )
        XCTAssertTrue(path.transitionSegments.isEmpty)
    }

    // MARK: - Two Scenes with Transition

    func test_simulate_twoScenes_oneTransitionSegment() {
        let shot1 = makeShotPlan(start: 0, end: 3, zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let shot2 = makeShotPlan(start: 3, end: 6, zoom: 1.5, center: NormalizedPoint(x: 0.7, y: 0.7))
        let transition = makeTransition(from: shot1, to: shot2, style: .directPan(duration: 0.5))

        let path = simulator.simulate(
            shotPlans: [shot1, shot2], transitions: [transition],
            mouseData: mockData, settings: defaultSettings, duration: 10.0
        )
        XCTAssertEqual(path.sceneSegments.count, 2)
        XCTAssertEqual(path.transitionSegments.count, 1)
    }

    func test_simulate_transitionSegment_matchesSurroundingScenes() {
        let center1 = NormalizedPoint(x: 0.3, y: 0.3)
        let center2 = NormalizedPoint(x: 0.7, y: 0.7)
        let shot1 = makeShotPlan(start: 0, end: 3, zoom: 2.0, center: center1)
        let shot2 = makeShotPlan(start: 3, end: 6, zoom: 1.5, center: center2)
        let transition = makeTransition(from: shot1, to: shot2, style: .directPan(duration: 0.5))

        let path = simulator.simulate(
            shotPlans: [shot1, shot2], transitions: [transition],
            mouseData: mockData, settings: defaultSettings, duration: 10.0
        )
        let trans = path.transitionSegments[0]
        // Start transform should match end of first scene
        XCTAssertEqual(trans.startTransform.zoom, 2.0, accuracy: 0.01)
        XCTAssertEqual(trans.startTransform.center.x, center1.x, accuracy: 0.01)
        // End transform should match start of second scene
        XCTAssertEqual(trans.endTransform.zoom, 1.5, accuracy: 0.01)
        XCTAssertEqual(trans.endTransform.center.x, center2.x, accuracy: 0.01)
    }

    // MARK: - Scene Segment Samples

    func test_simulate_sceneSegmentSamplesMatchController() {
        let center = NormalizedPoint(x: 0.4, y: 0.6)
        let shot = makeShotPlan(start: 0, end: 5, zoom: 1.8, center: center)
        let path = simulator.simulate(
            shotPlans: [shot], transitions: [], mouseData: mockData,
            settings: defaultSettings, duration: 10.0
        )
        let segment = path.sceneSegments[0]
        // StaticHoldController produces constant transform
        for sample in segment.samples {
            XCTAssertEqual(sample.transform.zoom, 1.8, accuracy: 0.01)
            XCTAssertEqual(sample.transform.center.x, center.x, accuracy: 0.01)
        }
    }

    // MARK: - Multiple Scenes

    func test_simulate_threeScenes_twoTransitions() {
        let shot1 = makeShotPlan(start: 0, end: 3, zoom: 2.0, center: NormalizedPoint(x: 0.2, y: 0.2))
        let shot2 = makeShotPlan(start: 3, end: 6, zoom: 1.5, center: NormalizedPoint(x: 0.5, y: 0.5))
        let shot3 = makeShotPlan(start: 6, end: 10, zoom: 2.0, center: NormalizedPoint(x: 0.8, y: 0.8))
        let t1 = makeTransition(from: shot1, to: shot2, style: .directPan(duration: 0.5))
        let t2 = makeTransition(from: shot2, to: shot3, style: .zoomOutAndPan(duration: 1.0))

        let path = simulator.simulate(
            shotPlans: [shot1, shot2, shot3], transitions: [t1, t2],
            mouseData: mockData, settings: defaultSettings, duration: 10.0
        )
        XCTAssertEqual(path.sceneSegments.count, 3)
        XCTAssertEqual(path.transitionSegments.count, 2)
    }

    // MARK: - Helpers

    private func makeShotPlan(
        start: TimeInterval, end: TimeInterval,
        zoom: CGFloat, center: NormalizedPoint
    ) -> ShotPlan {
        let scene = CameraScene(
            startTime: start, endTime: end, primaryIntent: .clicking
        )
        return ShotPlan(
            scene: scene,
            shotType: .medium(zoom: zoom),
            idealZoom: zoom,
            idealCenter: center
        )
    }

    private func makeTransition(
        from: ShotPlan, to: ShotPlan,
        style: TransitionStyle
    ) -> TransitionPlan {
        TransitionPlan(
            fromScene: from.scene,
            toScene: to.scene,
            style: style,
            easing: .spring(dampingRatio: 0.85, response: 0.5)
        )
    }
}
