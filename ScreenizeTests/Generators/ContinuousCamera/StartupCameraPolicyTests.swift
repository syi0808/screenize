import XCTest
@testable import Screenize

final class StartupCameraPolicyTests: XCTestCase {

    func test_defaultSettings_defineStartupBias() {
        let settings = ContinuousCameraSettings()

        XCTAssertTrue(settings.startup.enabled)
        XCTAssertEqual(settings.startup.initialCenter, NormalizedPoint.center)
        XCTAssertGreaterThan(settings.startup.deliberateMotionDistance, 0)
        XCTAssertGreaterThan(settings.startup.deliberateMotionWindow, 0)
        XCTAssertGreaterThan(settings.startup.jitterDistance, 0)
    }

    func test_resolve_withoutActions_keepsCenteredBias() {
        let policy = StartupCameraPolicy.resolve(
            cursorPositions: [
                MousePositionData(time: 0, position: NormalizedPoint(x: 0.15, y: 0.85)),
                MousePositionData(time: 0.10, position: NormalizedPoint(x: 0.16, y: 0.84))
            ],
            clickEvents: [],
            keyboardEvents: [],
            dragEvents: [],
            intentSpans: [],
            settings: ContinuousCameraSettings().startup
        )

        XCTAssertEqual(policy.initialCenter, NormalizedPoint.center)
        XCTAssertNil(policy.releaseTime)
    }

    func test_resolve_clickReleasesBiasAtClickTime() {
        let policy = StartupCameraPolicy.resolve(
            cursorPositions: [],
            clickEvents: [
                ClickEventData(
                    time: 0.12,
                    position: NormalizedPoint(x: 0.2, y: 0.8),
                    clickType: .leftDown
                )
            ],
            keyboardEvents: [],
            dragEvents: [],
            intentSpans: [],
            settings: ContinuousCameraSettings().startup
        )

        XCTAssertEqual(policy.initialCenter, NormalizedPoint.center)
        XCTAssertNotNil(policy.releaseTime)
        XCTAssertEqual(policy.releaseTime ?? -1, 0.12, accuracy: 0.001)
    }

    func test_resolve_dragReleasesBiasAtDragStart() {
        let policy = StartupCameraPolicy.resolve(
            cursorPositions: [],
            clickEvents: [],
            keyboardEvents: [],
            dragEvents: [
                DragEventData(
                    startTime: 0.18,
                    endTime: 0.42,
                    startPosition: NormalizedPoint(x: 0.25, y: 0.75),
                    endPosition: NormalizedPoint(x: 0.6, y: 0.4),
                    dragType: .move
                )
            ],
            intentSpans: [],
            settings: ContinuousCameraSettings().startup
        )

        XCTAssertNotNil(policy.releaseTime)
        XCTAssertEqual(policy.releaseTime ?? -1, 0.18, accuracy: 0.001)
    }

    func test_resolve_typingIntentReleasesBiasAtSpanStart() {
        let policy = StartupCameraPolicy.resolve(
            cursorPositions: [],
            clickEvents: [],
            keyboardEvents: [],
            dragEvents: [],
            intentSpans: [
                makeIntentSpan(
                    start: 0.22,
                    end: 1.0,
                    intent: .typing(context: .codeEditor),
                    focus: NormalizedPoint.center
                )
            ],
            settings: ContinuousCameraSettings().startup
        )

        XCTAssertNotNil(policy.releaseTime)
        XCTAssertEqual(policy.releaseTime ?? -1, 0.22, accuracy: 0.001)
    }

    func test_resolve_smallJitter_doesNotReleaseBias() {
        let policy = StartupCameraPolicy.resolve(
            cursorPositions: [
                MousePositionData(time: 0, position: NormalizedPoint(x: 0.12, y: 0.88)),
                MousePositionData(time: 0.08, position: NormalizedPoint(x: 0.13, y: 0.87)),
                MousePositionData(time: 0.16, position: NormalizedPoint(x: 0.125, y: 0.875))
            ],
            clickEvents: [],
            keyboardEvents: [],
            dragEvents: [],
            intentSpans: [],
            settings: ContinuousCameraSettings().startup
        )

        XCTAssertNil(policy.releaseTime)
    }

    func test_resolve_largeEarlyMovement_releasesAtThresholdCrossing() {
        let policy = StartupCameraPolicy.resolve(
            cursorPositions: [
                MousePositionData(time: 0, position: NormalizedPoint(x: 0.10, y: 0.90)),
                MousePositionData(time: 0.10, position: NormalizedPoint(x: 0.12, y: 0.88)),
                MousePositionData(time: 0.20, position: NormalizedPoint(x: 0.22, y: 0.78)),
                MousePositionData(time: 0.30, position: NormalizedPoint(x: 0.30, y: 0.70))
            ],
            clickEvents: [],
            keyboardEvents: [],
            dragEvents: [],
            intentSpans: [],
            settings: ContinuousCameraSettings().startup
        )

        XCTAssertNotNil(policy.releaseTime)
        XCTAssertEqual(policy.releaseTime ?? -1, 0.20, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeIntentSpan(
        start: TimeInterval,
        end: TimeInterval,
        intent: UserIntent,
        focus: NormalizedPoint
    ) -> IntentSpan {
        IntentSpan(
            startTime: start,
            endTime: end,
            intent: intent,
            confidence: 1.0,
            focusPosition: focus,
            focusElement: nil,
            contextChange: nil
        )
    }
}
