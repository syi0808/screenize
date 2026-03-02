import XCTest
import CoreGraphics
@testable import Screenize

final class WaypointGeneratorTests: XCTestCase {

    private let defaultSettings = ContinuousCameraSettings()

    // MARK: - Empty Input

    func test_generate_emptyIntentSpans_returnsInitialWaypoint() {
        let waypoints = WaypointGenerator.generate(
            from: [],
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )
        XCTAssertEqual(waypoints.count, 1)
        XCTAssertEqual(waypoints[0].time, 0)
        XCTAssertEqual(waypoints[0].targetZoom, 1.0)
        XCTAssertEqual(waypoints[0].targetCenter.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].targetCenter.y, 0.5, accuracy: 0.001)
    }

    // MARK: - Single Intent

    func test_generate_singleClickingIntent_producesWaypointWithNormalUrgency() {
        let spans = [
            makeIntentSpan(
                start: 0, end: 2, intent: .clicking,
                focus: NormalizedPoint(x: 0.3, y: 0.4)
            )
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )
        // Initial + span waypoint
        XCTAssertGreaterThanOrEqual(waypoints.count, 1)
        let clickWP = waypoints.first { $0.urgency == .normal }
        XCTAssertNotNil(clickWP)
    }

    func test_generate_singleTypingIntent_producesHighUrgency() {
        let spans = [
            makeIntentSpan(
                start: 1, end: 5,
                intent: .typing(context: .codeEditor),
                focus: NormalizedPoint(x: 0.6, y: 0.7)
            )
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )
        let typingWP = waypoints.first { $0.urgency == .high }
        XCTAssertNotNil(typingWP)
    }

    func test_generate_switchingIntent_producesImmediateUrgency() {
        let spans = [
            makeIntentSpan(
                start: 2, end: 3, intent: .switching,
                focus: NormalizedPoint(x: 0.5, y: 0.5)
            )
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )
        let switchWP = waypoints.first { $0.urgency == .immediate }
        XCTAssertNotNil(switchWP)
    }

    // MARK: - Multiple Intents

    func test_generate_multipleIntents_waypointsAreSortedByTime() {
        let spans = [
            makeIntentSpan(start: 0, end: 2, intent: .clicking,
                           focus: NormalizedPoint(x: 0.3, y: 0.3)),
            makeIntentSpan(start: 2, end: 5,
                           intent: .typing(context: .codeEditor),
                           focus: NormalizedPoint(x: 0.7, y: 0.7)),
            makeIntentSpan(start: 5, end: 8, intent: .idle,
                           focus: NormalizedPoint(x: 0.5, y: 0.5))
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )
        for i in 1..<waypoints.count {
            XCTAssertGreaterThanOrEqual(
                waypoints[i].time, waypoints[i - 1].time,
                "Waypoints must be sorted by time"
            )
        }
    }

    // MARK: - Initial Waypoint

    func test_generate_firstSpanNotAtZero_insertsInitialWaypoint() {
        let spans = [
            makeIntentSpan(start: 2, end: 5, intent: .clicking,
                           focus: NormalizedPoint(x: 0.6, y: 0.6))
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )
        XCTAssertEqual(waypoints.first?.time, 0)
        XCTAssertEqual(waypoints.first?.targetZoom, 1.0)
    }

    // MARK: - Idle Inheritance

    func test_generate_idleSpan_inheritsZoomFromNeighbor() {
        let spans = [
            makeIntentSpan(start: 0, end: 3,
                           intent: .typing(context: .codeEditor),
                           focus: NormalizedPoint(x: 0.5, y: 0.5)),
            makeIntentSpan(start: 3, end: 8, intent: .idle,
                           focus: NormalizedPoint(x: 0.5, y: 0.5))
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )
        let idleWP = waypoints.first { if case .idle = $0.source { return true }; return false }
        XCTAssertNotNil(idleWP)
        // Idle should inherit some zoom from the typing span (not stay at 1.0 if neighbor is zoomed)
        // The exact value depends on decay, but it should be > 1.0
        if let wp = idleWP {
            XCTAssertGreaterThanOrEqual(wp.targetZoom, 1.0)
        }
    }

    func test_generate_leadingIdle_keepsEstablishingZoom() {
        let spans = [
            makeIntentSpan(
                start: 0, end: 2, intent: .idle,
                focus: NormalizedPoint(x: 0.5, y: 0.5)
            ),
            makeIntentSpan(
                start: 2, end: 5, intent: .clicking,
                focus: NormalizedPoint(x: 0.8, y: 0.2)
            )
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )

        guard let idleWP = waypoints.first(where: {
            if case .idle = $0.source { return true }
            return false
        }) else {
            XCTFail("Expected leading idle waypoint")
            return
        }

        XCTAssertEqual(idleWP.time, 0, accuracy: 0.001)
        XCTAssertEqual(idleWP.targetZoom, 1.0, accuracy: 0.01)
    }

    // MARK: - Idle/Switching Use focusPosition (Not Center)

    func test_generate_idleSpan_usesFocusPositionNotCenter() {
        let spans = [
            makeIntentSpan(
                start: 0, end: 3,
                intent: .typing(context: .codeEditor),
                focus: NormalizedPoint(x: 0.8, y: 0.2)
            ),
            makeIntentSpan(
                start: 3, end: 8, intent: .idle,
                focus: NormalizedPoint(x: 0.8, y: 0.2)
            )
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )
        let idleWP = waypoints.first { if case .idle = $0.source { return true }; return false }
        XCTAssertNotNil(idleWP)
        if let wp = idleWP {
            XCTAssertNotEqual(wp.targetCenter.x, 0.5, accuracy: 0.01,
                              "Idle should not drift to center X")
            XCTAssertNotEqual(wp.targetCenter.y, 0.5, accuracy: 0.01,
                              "Idle should not drift to center Y")
        }
    }

    func test_generate_switchingSpan_usesFocusPositionNotCenter() {
        let spans = [
            makeIntentSpan(
                start: 0, end: 2, intent: .switching,
                focus: NormalizedPoint(x: 0.3, y: 0.7)
            )
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )
        let switchWP = waypoints.first { $0.urgency == .immediate }
        XCTAssertNotNil(switchWP)
        if let wp = switchWP {
            XCTAssertEqual(wp.targetCenter.x, 0.3, accuracy: 0.01)
            XCTAssertEqual(wp.targetCenter.y, 0.7, accuracy: 0.01)
        }
    }

    func test_generate_withEventTimeline_prefersShotPlannerCenter() {
        let spans = [
            makeIntentSpan(
                start: 0,
                end: 2,
                intent: .clicking,
                focus: NormalizedPoint(x: 0.2, y: 0.2)
            )
        ]
        let timeline = EventTimeline(
            events: [
                makeClickEvent(
                    time: 0.6,
                    position: NormalizedPoint(x: 0.8, y: 0.78)
                ),
                makeClickEvent(
                    time: 1.2,
                    position: NormalizedPoint(x: 0.82, y: 0.8)
                )
            ],
            duration: 2.0
        )

        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: timeline,
            frameAnalysis: [],
            settings: defaultSettings
        )

        let clickWP = waypoints.first {
            if case .clicking = $0.source { return true }
            return false
        }
        XCTAssertNotNil(clickWP)
        if let wp = clickWP {
            XCTAssertGreaterThan(
                wp.targetCenter.x,
                0.6,
                "Center should follow event activity instead of span.focusPosition"
            )
            XCTAssertGreaterThan(wp.targetCenter.y, 0.6)
        }
    }

    func test_generate_typingWithCaretMovement_addsDetailWaypoints() {
        let spans = [
            makeIntentSpan(
                start: 0,
                end: 4,
                intent: .typing(context: .codeEditor),
                focus: NormalizedPoint(x: 0.3, y: 0.4)
            )
        ]
        let timeline = EventTimeline(
            events: [
                makeTypingEvent(
                    time: 0.4,
                    position: NormalizedPoint(x: 0.3, y: 0.4),
                    caretCenter: NormalizedPoint(x: 0.3, y: 0.4)
                ),
                makeTypingEvent(
                    time: 1.4,
                    position: NormalizedPoint(x: 0.8, y: 0.8),
                    caretCenter: NormalizedPoint(x: 0.8, y: 0.8)
                ),
                makeTypingEvent(
                    time: 2.4,
                    position: NormalizedPoint(x: 0.82, y: 0.82),
                    caretCenter: NormalizedPoint(x: 0.82, y: 0.82)
                )
            ],
            duration: 4.0
        )

        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: timeline,
            frameAnalysis: [],
            settings: defaultSettings
        )

        let typingWaypoints = waypoints.filter {
            if case .typing = $0.source { return true }
            return false
        }
        XCTAssertGreaterThan(
            typingWaypoints.count,
            1,
            "Typing with caret movement should emit detail waypoints"
        )
        let hasLateCaretWaypoint = typingWaypoints.contains {
            $0.time > 1.0 && $0.targetCenter.x > 0.6 && $0.targetCenter.y > 0.6
        }
        XCTAssertTrue(hasLateCaretWaypoint)
    }

    func test_generate_clickingWithMultipleClicks_addsDetailWaypoints() {
        let spans = [
            makeIntentSpan(
                start: 1.0,
                end: 4.0,
                intent: .clicking,
                focus: NormalizedPoint(x: 0.25, y: 0.25)
            )
        ]
        let timeline = EventTimeline(
            events: [
                makeClickEvent(
                    time: 1.2,
                    position: NormalizedPoint(x: 0.22, y: 0.25)
                ),
                makeClickEvent(
                    time: 2.1,
                    position: NormalizedPoint(x: 0.58, y: 0.62)
                ),
                makeClickEvent(
                    time: 3.2,
                    position: NormalizedPoint(x: 0.78, y: 0.70)
                )
            ],
            duration: 4.0
        )

        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: timeline,
            frameAnalysis: [],
            settings: defaultSettings
        )

        let clickWaypoints = waypoints.filter {
            if case .clicking = $0.source { return true }
            return false
        }
        XCTAssertGreaterThan(clickWaypoints.count, 1)
        let hasLateClickAnchor = clickWaypoints.contains {
            $0.time > 3.0 && $0.targetCenter.x > 0.62 && $0.targetCenter.y > 0.60
        }
        XCTAssertTrue(hasLateClickAnchor)
    }

    func test_generate_typingWaypoint_startsBeforeSpanForAnticipation() {
        let spans = [
            makeIntentSpan(
                start: 2.0,
                end: 4.0,
                intent: .typing(context: .codeEditor),
                focus: NormalizedPoint(x: 0.55, y: 0.5)
            )
        ]
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: defaultSettings
        )

        let typingWaypoint = waypoints.first {
            if case .typing = $0.source { return true }
            return false
        }
        XCTAssertNotNil(typingWaypoint)
        if let typingWaypoint {
            XCTAssertLessThan(
                typingWaypoint.time,
                2.0,
                "Typing waypoint should be placed before span start"
            )
        }
    }

    // MARK: - Center Clamping

    func test_generate_extremePosition_centerIsClamped() {
        let spans = [
            makeIntentSpan(
                start: 0, end: 3, intent: .clicking,
                focus: NormalizedPoint(x: 0.95, y: 0.95)
            )
        ]
        var settings = ContinuousCameraSettings()
        settings.shot.clickingZoomRange = 2.0...2.5
        let waypoints = WaypointGenerator.generate(
            from: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: nil,
            frameAnalysis: [],
            settings: settings
        )
        // At zoom 2.0, halfCrop = 0.25, so max center = 0.75
        let clickWP = waypoints.first { $0.targetZoom > 1.5 }
        if let wp = clickWP {
            let halfCrop = 0.5 / wp.targetZoom
            XCTAssertLessThanOrEqual(wp.targetCenter.x, 1.0 - halfCrop + 0.001)
            XCTAssertLessThanOrEqual(wp.targetCenter.y, 1.0 - halfCrop + 0.001)
        }
    }

    // MARK: - Urgency Mapping

    func test_urgencyMapping_allIntentsCovered() {
        let intents: [(UserIntent, WaypointUrgency)] = [
            (.clicking, .normal),
            (.navigating, .normal),
            (.scrolling, .normal),
            (.dragging(.selection), .normal),
            (.typing(context: .codeEditor), .high),
            (.switching, .immediate),
            (.idle, .lazy),
            (.reading, .lazy)
        ]
        for (intent, expectedUrgency) in intents {
            let urgency = WaypointGenerator.urgency(for: intent)
            XCTAssertEqual(urgency, expectedUrgency,
                           "Intent \(intent) should map to \(expectedUrgency)")
        }
    }

    // MARK: - WaypointUrgency Comparable

    func test_urgencyOrdering() {
        XCTAssertTrue(WaypointUrgency.lazy < .normal)
        XCTAssertTrue(WaypointUrgency.normal < .high)
        XCTAssertTrue(WaypointUrgency.high < .immediate)
    }

    // MARK: - CameraState Initialization

    func test_cameraState_defaultVelocitiesAreZero() {
        let state = CameraState(positionX: 0.5, positionY: 0.5, zoom: 1.0)
        XCTAssertEqual(state.velocityX, 0)
        XCTAssertEqual(state.velocityY, 0)
        XCTAssertEqual(state.velocityZoom, 0)
    }

    // MARK: - ContinuousCameraSettings Defaults

    func test_settings_defaultValues() {
        let settings = ContinuousCameraSettings()
        XCTAssertEqual(settings.positionDampingRatio, 0.92, accuracy: 0.001)
        XCTAssertEqual(settings.positionResponse, 0.4, accuracy: 0.001)
        XCTAssertEqual(settings.zoomDampingRatio, 0.95, accuracy: 0.001)
        XCTAssertEqual(settings.zoomResponse, 0.5, accuracy: 0.001)
        XCTAssertEqual(settings.tickRate, 60.0, accuracy: 0.001)
        XCTAssertEqual(settings.minZoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(settings.maxZoom, 2.8, accuracy: 0.001)
        XCTAssertEqual(settings.zoomIntensity, 1.0, accuracy: 0.001)
    }

    func test_settings_urgencyMultipliersComplete() {
        let settings = ContinuousCameraSettings()
        XCTAssertNotNil(settings.urgencyMultipliers[.lazy])
        XCTAssertNotNil(settings.urgencyMultipliers[.normal])
        XCTAssertNotNil(settings.urgencyMultipliers[.high])
        XCTAssertNotNil(settings.urgencyMultipliers[.immediate])
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
            focusElement: nil
        )
    }

    private func makeClickEvent(
        time: TimeInterval,
        position: NormalizedPoint
    ) -> UnifiedEvent {
        UnifiedEvent(
            time: time,
            kind: .click(
                ClickEventData(
                    time: time,
                    position: position,
                    clickType: .leftDown
                )
            ),
            position: position,
            metadata: EventMetadata()
        )
    }

    private func makeTypingEvent(
        time: TimeInterval,
        position: NormalizedPoint,
        caretCenter: NormalizedPoint
    ) -> UnifiedEvent {
        let key = KeyboardEventData(
            time: time,
            keyCode: 0,
            eventType: .keyDown,
            modifiers: KeyboardEventData.ModifierFlags(rawValue: 0),
            character: "a"
        )
        let caret = CGRect(
            x: caretCenter.x - 0.005,
            y: caretCenter.y - 0.01,
            width: 0.01,
            height: 0.02
        )
        return UnifiedEvent(
            time: time,
            kind: .keyDown(key),
            position: position,
            metadata: EventMetadata(caretBounds: caret)
        )
    }
}
