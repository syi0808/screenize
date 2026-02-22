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
        // At zoom 2.0, effective distance = raw * 2.0
        // Use positions where effective distance is in medium range (0.15...0.4)
        let shots = [
            makeShotPlan(start: 0, end: 3, center: NormalizedPoint(x: 0.45, y: 0.45)),
            makeShotPlan(start: 3, end: 6, center: NormalizedPoint(x: 0.55, y: 0.55))
        ]
        // raw distance ≈ 0.14, effective = 0.14 * 2.0 = 0.28 (medium range)
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
        if case .zoomOutAndIn(let outDur, let inDur, _) = plans[0].style {
            XCTAssertGreaterThanOrEqual(outDur, defaultSettings.zoomOutDurationRange.lowerBound)
            XCTAssertLessThanOrEqual(outDur, defaultSettings.zoomOutDurationRange.upperBound)
            XCTAssertGreaterThanOrEqual(inDur, defaultSettings.zoomOutDurationRange.lowerBound)
            XCTAssertLessThanOrEqual(inDur, defaultSettings.zoomOutDurationRange.upperBound)
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

    // MARK: - Zoom-Aware Distance

    func test_plan_highZoomShortRawDistance_usesLongerTransition() {
        // Raw distance 0.12 at zoom 2.5 → effective 0.30 → medium pan
        let shots = [
            makeShotPlan(
                start: 0, end: 3,
                center: NormalizedPoint(x: 0.44, y: 0.5), zoom: 2.5
            ),
            makeShotPlan(
                start: 3, end: 6,
                center: NormalizedPoint(x: 0.56, y: 0.5), zoom: 2.5
            )
        ]
        // raw distance = 0.12, effective = 0.12 * 2.5 = 0.30 → medium pan
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        XCTAssertEqual(plans.count, 1)
        if case .directPan(let duration) = plans[0].style {
            XCTAssertGreaterThanOrEqual(
                duration, defaultSettings.mediumPanDurationRange.lowerBound
            )
        } else {
            XCTFail("Expected medium directPan at high zoom, got \(plans[0].style)")
        }
    }

    func test_plan_lowZoomMediumRawDistance_usesDirectPan() {
        // Raw distance 0.35 at zoom 1.0 → effective 0.35 → medium pan (not zoomOutAndIn)
        let shots = [
            makeShotPlan(
                start: 0, end: 3,
                center: NormalizedPoint(x: 0.3, y: 0.5), zoom: 1.0
            ),
            makeShotPlan(
                start: 3, end: 6,
                center: NormalizedPoint(x: 0.65, y: 0.5), zoom: 1.0
            )
        ]
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        XCTAssertEqual(plans.count, 1)
        if case .directPan = plans[0].style {
            // expected: 0.35 * 1.0 = 0.35 < 0.4 → direct pan
        } else {
            XCTFail("Expected directPan at low zoom for medium distance")
        }
    }

    func test_plan_highZoomMediumRawDistance_usesZoomOutAndIn() {
        // Raw distance 0.25 at zoom 2.0 → effective 0.50 > 0.4 → zoomOutAndIn
        let shots = [
            makeShotPlan(
                start: 0, end: 3,
                center: NormalizedPoint(x: 0.35, y: 0.5), zoom: 2.0
            ),
            makeShotPlan(
                start: 3, end: 6,
                center: NormalizedPoint(x: 0.6, y: 0.5), zoom: 2.0
            )
        ]
        let plans = TransitionPlanner.plan(shotPlans: shots, settings: defaultSettings)
        XCTAssertEqual(plans.count, 1)
        if case .zoomOutAndIn = plans[0].style {
            // expected
        } else {
            XCTFail("Expected zoomOutAndIn at high zoom for medium raw distance")
        }
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
