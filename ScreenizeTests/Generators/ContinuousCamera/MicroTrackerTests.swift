import XCTest
import CoreGraphics
@testable import Screenize

final class MicroTrackerTests: XCTestCase {

    private let defaultSettings = MicroTrackerSettings()

    // MARK: - Active Movement: No Correction

    func test_activeCursor_noCorrectionApplied() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0

        for i in 0..<60 {
            let t = CGFloat(i) / 60.0
            let cursorX = 0.3 + t * 0.4
            let cameraCenter = NormalizedPoint(x: 0.3 + t * 0.35, y: 0.5)
            tracker.update(
                cursorPosition: NormalizedPoint(x: cursorX, y: 0.5),
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        XCTAssertEqual(tracker.correction.x, 0, accuracy: 0.01,
                       "No re-centering during active movement")
    }

    // MARK: - Idle: Slow Re-centering

    func test_idleCursor_slowlyRecenters() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.6, y: 0.5)
        let cameraCenter = NormalizedPoint(x: 0.5, y: 0.5)

        for _ in 0..<180 {
            tracker.update(
                cursorPosition: cursor,
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        XCTAssertGreaterThan(tracker.correction.x, 0.01,
                             "Should re-center toward cursor during idle")
    }

    func test_idleCursor_correctionConvergesOnOffset() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.6, y: 0.5)
        let cameraCenter = NormalizedPoint(x: 0.5, y: 0.5)

        for _ in 0..<600 {
            tracker.update(
                cursorPosition: cursor,
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        XCTAssertEqual(tracker.correction.x, 0.1, accuracy: 0.02,
                       "Correction should converge to fill gap between camera and cursor")
    }

    // MARK: - Transition from Idle to Active

    func test_idleToActive_correctionDecays() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cameraCenter = NormalizedPoint(x: 0.5, y: 0.5)

        for _ in 0..<300 {
            tracker.update(
                cursorPosition: NormalizedPoint(x: 0.6, y: 0.5),
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }
        let idleCorrection = tracker.correction.x
        XCTAssertGreaterThan(idleCorrection, 0.01)

        for i in 0..<120 {
            let cursorX = 0.6 + CGFloat(i) / 60.0 * 0.1
            tracker.update(
                cursorPosition: NormalizedPoint(x: cursorX, y: 0.5),
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        XCTAssertLessThan(abs(tracker.correction.x), idleCorrection,
                          "Correction should decay when cursor becomes active")
    }

    // MARK: - Smoothness

    func test_correction_changesGradually() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.7, y: 0.5)
        let cameraCenter = NormalizedPoint(x: 0.5, y: 0.5)

        var corrections: [CGFloat] = []
        for _ in 0..<120 {
            tracker.update(
                cursorPosition: cursor,
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
            corrections.append(tracker.correction.x)
        }

        for i in 1..<corrections.count {
            let jump = abs(corrections[i] - corrections[i - 1])
            XCTAssertLessThan(jump, 0.02,
                              "Correction should change smoothly (jump=\(jump) at frame \(i))")
        }
    }

    // MARK: - Boundary Awareness

    func test_correction_respectsViewportBounds() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.5
        let cameraCenter = NormalizedPoint(x: 0.8, y: 0.5)
        let cursor = NormalizedPoint(x: 0.95, y: 0.5)

        for _ in 0..<600 {
            tracker.update(
                cursorPosition: cursor,
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        let finalX = cameraCenter.x + tracker.correction.x
        let halfCrop = 0.5 / zoom
        XCTAssertLessThanOrEqual(finalX, 1.0 - halfCrop + 0.02,
                                 "Re-centered position should respect viewport bounds")
    }
}
