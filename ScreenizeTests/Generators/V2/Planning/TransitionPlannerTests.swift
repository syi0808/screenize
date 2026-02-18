import XCTest
@testable import Screenize

final class TransitionPlannerTests: XCTestCase {

    private let defaultSettings = TransitionSettings()

    // MARK: - Edge Cases

    func test_plan_empty_returnsEmpty() {
        let plans = TransitionPlanner.plan(shotPlans: [], settings: defaultSettings)
        XCTAssertTrue(plans.isEmpty)
    }

    func test_plan_singleScene_noTransitions() {
        let shot = makeShotPlan(center: NormalizedPoint(x: 0.5, y: 0.5))
        let plans = TransitionPlanner.plan(shotPlans: [shot], settings: defaultSettings)
        XCTAssertTrue(plans.isEmpty)
    }

    // MARK: - Transition Count

    func test_plan_transitionCountIsSceneCountMinusOne() {
        let shots = [
            makeShotPlan(start: 0, end: 3, center: NormalizedPoint(x: 0.3, y: 0.3)),
            makeShotPlan(start: 3, end: 6, center: NormalizedPoint(x: 0.5, y: 0.5)),
            makeShotPlan(start: 6, end: 10, center: NormalizedPoint(x: 0.7, y: 0.7))
        ]
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        XCTAssertEqual(plans.count, 2)
    }

    // MARK: - Short Distance → Direct Pan (Short)

    func test_plan_closeScenes_directPanShort() {
        let shots = [
            makeShotPlan(start: 0, end: 3, center: NormalizedPoint(x: 0.5, y: 0.5)),
            makeShotPlan(start: 3, end: 6, center: NormalizedPoint(x: 0.55, y: 0.55))
        ]
        // distance ≈ 0.07 < 0.15
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        XCTAssertEqual(plans.count, 1)
        if case .directPan(let duration) = plans[0].style {
            XCTAssertGreaterThanOrEqual(duration, defaultSettings.shortPanDurationRange.lowerBound)
            XCTAssertLessThanOrEqual(duration, defaultSettings.shortPanDurationRange.upperBound)
        } else {
            XCTFail("Expected directPan for close scenes")
        }
    }

    // MARK: - Medium Distance → Direct Pan (Long)

    func test_plan_mediumDistanceScenes_directPanLong() {
        let shots = [
            makeShotPlan(start: 0, end: 3, center: NormalizedPoint(x: 0.3, y: 0.3)),
            makeShotPlan(start: 3, end: 6, center: NormalizedPoint(x: 0.5, y: 0.5))
        ]
        // distance ≈ 0.28 > 0.15 but < 0.4
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        XCTAssertEqual(plans.count, 1)
        if case .directPan(let duration) = plans[0].style {
            XCTAssertGreaterThanOrEqual(duration, defaultSettings.mediumPanDurationRange.lowerBound)
            XCTAssertLessThanOrEqual(duration, defaultSettings.mediumPanDurationRange.upperBound)
        } else {
            XCTFail("Expected directPan for medium distance")
        }
    }

    // MARK: - Far Distance → Zoom Out and In

    func test_plan_farScenes_zoomOutAndIn() {
        let shots = [
            makeShotPlan(start: 0, end: 3, center: NormalizedPoint(x: 0.1, y: 0.1)),
            makeShotPlan(start: 3, end: 6, center: NormalizedPoint(x: 0.9, y: 0.9))
        ]
        // distance ≈ 1.13 > 0.4
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        XCTAssertEqual(plans.count, 1)
        if case .zoomOutAndIn(let outDur, let inDur) = plans[0].style {
            XCTAssertEqual(outDur, defaultSettings.zoomOutDuration, accuracy: 0.01)
            XCTAssertEqual(inDur, defaultSettings.zoomInDuration, accuracy: 0.01)
        } else {
            XCTFail("Expected zoomOutAndIn for far scenes")
        }
    }

    // MARK: - App Switch → Cut

    func test_plan_appSwitch_cut() {
        let shots = [
            makeShotPlan(
                start: 0, end: 3,
                center: NormalizedPoint(x: 0.5, y: 0.5),
                intent: .clicking
            ),
            makeShotPlan(
                start: 3, end: 6,
                center: NormalizedPoint(x: 0.5, y: 0.5),
                intent: .switching
            )
        ]
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        XCTAssertEqual(plans.count, 1)
        if case .cut = plans[0].style {
            // expected
        } else {
            XCTFail("Expected cut for switching scene")
        }
    }

    // MARK: - Easing

    func test_plan_directPan_springEasing() {
        let shots = [
            makeShotPlan(start: 0, end: 3, center: NormalizedPoint(x: 0.5, y: 0.5)),
            makeShotPlan(start: 3, end: 6, center: NormalizedPoint(x: 0.55, y: 0.55))
        ]
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        if case .spring = plans[0].easing {
            // expected
        } else {
            XCTFail("Expected spring easing for direct pan")
        }
    }

    func test_plan_zoomOutAndIn_easeOutEasing() {
        let shots = [
            makeShotPlan(start: 0, end: 3, center: NormalizedPoint(x: 0.1, y: 0.1)),
            makeShotPlan(start: 3, end: 6, center: NormalizedPoint(x: 0.9, y: 0.9))
        ]
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        XCTAssertEqual(plans[0].easing, .easeOut)
    }

    // MARK: - Helpers

    private func makeShotPlan(
        start: TimeInterval = 0,
        end: TimeInterval = 5,
        center: NormalizedPoint,
        zoom: CGFloat = 2.0,
        intent: UserIntent = .clicking
    ) -> ShotPlan {
        let scene = CameraScene(
            startTime: start, endTime: end,
            primaryIntent: intent
        )
        return ShotPlan(
            scene: scene,
            shotType: zoom > 2.0 ? .closeUp(zoom: zoom) : .medium(zoom: zoom),
            idealZoom: zoom,
            idealCenter: center
        )
    }
}
