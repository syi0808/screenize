import XCTest
@testable import Screenize

final class HoldEnforcerTests: XCTestCase {

    private let defaultSettings = HoldSettings()

    // MARK: - Helpers

    private func makeScene(
        start: TimeInterval,
        end: TimeInterval,
        intent: UserIntent = .clicking
    ) -> CameraScene {
        CameraScene(
            startTime: start, endTime: end, primaryIntent: intent
        )
    }

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval,
        zoom: CGFloat = 2.0,
        center: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5),
        intent: UserIntent = .clicking
    ) -> SimulatedSceneSegment {
        let scene = makeScene(start: start, end: end, intent: intent)
        let transform = TransformValue(zoom: zoom, center: center)
        let shotPlan = ShotPlan(
            scene: scene,
            shotType: zoom > 2.0 ? .closeUp(zoom: zoom)
                : zoom > 1.0 ? .medium(zoom: zoom) : .wide,
            idealZoom: zoom,
            idealCenter: center
        )
        return SimulatedSceneSegment(
            scene: scene, shotPlan: shotPlan,
            samples: [
                TimedTransform(time: start, transform: transform),
                TimedTransform(time: end, transform: transform)
            ]
        )
    }

    private func makeTransition(
        from: SimulatedSceneSegment,
        to: SimulatedSceneSegment,
        style: TransitionStyle = .directPan(duration: 0.5)
    ) -> SimulatedTransitionSegment {
        SimulatedTransitionSegment(
            fromScene: from.scene, toScene: to.scene,
            transitionPlan: TransitionPlan(
                fromScene: from.scene, toScene: to.scene,
                style: style, easing: .easeInOut
            ),
            startTransform: from.samples.last!.transform,
            endTransform: to.samples.first!.transform
        )
    }

    // MARK: - Empty Path

    func test_enforce_emptyPath_returnsEmpty() {
        let path = SimulatedPath(sceneSegments: [], transitionSegments: [])
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        XCTAssertTrue(result.sceneSegments.isEmpty)
        XCTAssertTrue(result.transitionSegments.isEmpty)
    }

    // MARK: - Long Enough Scenes (No Change)

    func test_enforce_longZoomInScene_returnsUnchanged() {
        let seg = makeSegment(start: 0, end: 3, zoom: 2.0)
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        XCTAssertEqual(result.sceneSegments.count, 1)
        XCTAssertEqual(
            result.sceneSegments[0].scene.startTime, 0, accuracy: 0.001
        )
        XCTAssertEqual(
            result.sceneSegments[0].scene.endTime, 3, accuracy: 0.001
        )
    }

    func test_enforce_longZoomOutScene_returnsUnchanged() {
        let seg = makeSegment(start: 0, end: 2, zoom: 1.0)
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        XCTAssertEqual(
            result.sceneSegments[0].scene.endTime, 2, accuracy: 0.001
        )
    }

    // MARK: - Short Zoomed-In Scene

    func test_enforce_shortZoomInScene_extendsToMinimum() {
        // 0.4s scene at zoom 2.0 → should extend to 0.8s
        let seg = makeSegment(start: 1, end: 1.4, zoom: 2.0)
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        let scene = result.sceneSegments[0].scene
        let duration = scene.endTime - scene.startTime
        XCTAssertGreaterThanOrEqual(duration, 0.8 - 0.001)
    }

    // MARK: - Short Zoomed-Out Scene

    func test_enforce_shortZoomOutScene_extendsToMinimum() {
        // 0.2s scene at zoom 1.0 → should extend to 0.5s
        let seg = makeSegment(start: 0, end: 0.2, zoom: 1.0)
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        let scene = result.sceneSegments[0].scene
        let duration = scene.endTime - scene.startTime
        XCTAssertGreaterThanOrEqual(duration, 0.5 - 0.001)
    }

    // MARK: - Scene At Threshold

    func test_enforce_sceneExactlyAtMinimum_notExtended() {
        // Scene at exactly 0.8s with zoom > 1.05 — should not change
        let seg = makeSegment(start: 0, end: 0.8, zoom: 2.0)
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        let scene = result.sceneSegments[0].scene
        XCTAssertEqual(scene.endTime - scene.startTime, 0.8, accuracy: 0.001)
    }

    // MARK: - Subsequent Scene Shifting

    func test_enforce_shortScene_shiftsSubsequentScenes() {
        // Scene1: 0-0.4s (short, zoom 2.0) → extended by 0.4s
        // Scene2: 0.4-3.0s (long enough) → shifted by 0.4s
        let seg1 = makeSegment(start: 0, end: 0.4, zoom: 2.0)
        let seg2 = makeSegment(start: 0.4, end: 3.0, zoom: 2.0)
        let trans = makeTransition(from: seg1, to: seg2)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)

        let s1 = result.sceneSegments
            .sorted { $0.scene.startTime < $1.scene.startTime }[0]
        let s2 = result.sceneSegments
            .sorted { $0.scene.startTime < $1.scene.startTime }[1]

        // Scene1 extended to at least 0.8s
        XCTAssertGreaterThanOrEqual(
            s1.scene.endTime - s1.scene.startTime, 0.8 - 0.001
        )
        // Scene2 starts after scene1 ends
        XCTAssertGreaterThanOrEqual(
            s2.scene.startTime, s1.scene.endTime - 0.001
        )
    }

    // MARK: - Multiple Short Scenes

    func test_enforce_multipleShortScenes_allExtended() {
        let seg1 = makeSegment(start: 0, end: 0.3, zoom: 2.0)
        let seg2 = makeSegment(start: 0.3, end: 0.5, zoom: 1.5)
        let seg3 = makeSegment(start: 0.5, end: 3.0, zoom: 2.0)
        let t1 = makeTransition(from: seg1, to: seg2)
        let t2 = makeTransition(from: seg2, to: seg3)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2, seg3],
            transitionSegments: [t1, t2]
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        let sorted = result.sceneSegments
            .sorted { $0.scene.startTime < $1.scene.startTime }

        for (i, seg) in sorted.enumerated() {
            let dur = seg.scene.endTime - seg.scene.startTime
            let minHold = seg.shotPlan.idealZoom > 1.05 ? 0.8 : 0.5
            XCTAssertGreaterThanOrEqual(
                dur, minHold - 0.001,
                "Scene \(i) should meet minimum hold"
            )
        }
    }

    // MARK: - Transition Adjustment

    func test_enforce_transitionsRebuiltForShiftedScenes() {
        let seg1 = makeSegment(start: 0, end: 0.3, zoom: 2.0)
        let seg2 = makeSegment(start: 0.3, end: 3.0, zoom: 1.5)
        let trans = makeTransition(from: seg1, to: seg2)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)

        XCTAssertEqual(result.transitionSegments.count, 1)
        let newTrans = result.transitionSegments[0]
        let sorted = result.sceneSegments
            .sorted { $0.scene.startTime < $1.scene.startTime }

        // Transition should reference the new scene times
        XCTAssertEqual(
            newTrans.fromScene.endTime, sorted[0].scene.endTime,
            accuracy: 0.001
        )
        XCTAssertEqual(
            newTrans.toScene.startTime, sorted[1].scene.startTime,
            accuracy: 0.001
        )
    }

    // MARK: - Sample Times Adjusted

    func test_enforce_sampleTimesAdjustedProportionally() {
        // Scene: 0-0.4s, zoom 2.0 → extended to 0.8s
        // Samples at t=0 and t=0.4 should become t=0 and t=0.8
        let seg = makeSegment(start: 0, end: 0.4, zoom: 2.0)
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        let samples = result.sceneSegments[0].samples
        XCTAssertEqual(samples.first!.time, 0, accuracy: 0.001)
        let newDur = result.sceneSegments[0].scene.endTime
            - result.sceneSegments[0].scene.startTime
        XCTAssertEqual(samples.last!.time, newDur, accuracy: 0.001)
    }

    // MARK: - UUID Preservation

    func test_enforce_preservesSceneUUIDs() {
        let seg = makeSegment(start: 0, end: 0.3, zoom: 2.0)
        let originalID = seg.scene.id
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        XCTAssertEqual(result.sceneSegments[0].scene.id, originalID)
    }

    // MARK: - ShotPlan Preservation

    func test_enforce_preservesShotPlanProperties() {
        var seg = makeSegment(start: 0, end: 0.3, zoom: 2.0)
        // Simulate a shot plan with non-default properties
        var shotPlan = seg.shotPlan
        shotPlan.zoomSource = .element
        shotPlan.inherited = true
        seg = SimulatedSceneSegment(
            scene: seg.scene, shotPlan: shotPlan, samples: seg.samples
        )
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        XCTAssertEqual(result.sceneSegments[0].shotPlan.zoomSource, .element)
        XCTAssertTrue(result.sceneSegments[0].shotPlan.inherited)
    }

    // MARK: - Zoom Below Threshold

    func test_enforce_zoomBelowThreshold_usesZoomOutMinHold() {
        // Zoom at 1.03 (below 1.05 threshold) → uses minZoomOutHold (0.5s)
        let seg = makeSegment(start: 0, end: 0.3, zoom: 1.03)
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = HoldEnforcer.enforce(path, settings: defaultSettings)
        let dur = result.sceneSegments[0].scene.endTime
            - result.sceneSegments[0].scene.startTime
        XCTAssertGreaterThanOrEqual(dur, 0.5 - 0.001)
        // Should NOT be extended to 0.8s
        XCTAssertLessThan(dur, 0.8 + 0.001)
    }
}
