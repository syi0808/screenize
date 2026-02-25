import XCTest
@testable import Screenize

final class ContinuousCameraGeneratorTests: XCTestCase {

    private let generator = ContinuousCameraGenerator()
    private let screenBounds = CGSize(width: 1920, height: 1080)

    // MARK: - Empty Input

    func test_generate_emptyMouseData_returnsEmptyTracks() {
        let mockData = MockMouseDataSource(
            duration: 0, positions: [], clicks: []
        )
        let result = generator.generate(
            from: mockData,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: ContinuousCameraSettings()
        )
        XCTAssertTrue(result.cameraTrack.segments.isEmpty)
    }

    // MARK: - Basic Recording

    func test_generate_basicRecording_producesNonEmptyCameraTrack() {
        let mockData = makeBasicMouseData(duration: 10.0)
        let result = generator.generate(
            from: mockData,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: ContinuousCameraSettings()
        )
        XCTAssertFalse(result.cameraTrack.segments.isEmpty,
                       "Should produce camera segments for non-empty recording")
    }

    func test_generate_basicRecording_producesCursorTrack() {
        let mockData = makeBasicMouseData(duration: 10.0)
        let result = generator.generate(
            from: mockData,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: ContinuousCameraSettings()
        )
        XCTAssertFalse(result.cursorTrack.segments.isEmpty,
                       "Should produce cursor segments")
    }

    // MARK: - No Overlapping Segments

    func test_generate_noOverlappingCameraSegments() {
        let mockData = makeBasicMouseData(duration: 10.0)
        let result = generator.generate(
            from: mockData,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: ContinuousCameraSettings()
        )
        for i in 1..<result.cameraTrack.segments.count {
            let prev = result.cameraTrack.segments[i - 1]
            let next = result.cameraTrack.segments[i]
            XCTAssertLessThanOrEqual(
                prev.endTime, next.startTime + 0.001,
                "Camera segments must not overlap"
            )
        }
    }

    // MARK: - Zoom Bounds

    func test_generate_zoomWithinBounds() {
        let mockData = makeBasicMouseData(duration: 10.0)
        var settings = ContinuousCameraSettings()
        settings.minZoom = 1.0
        settings.maxZoom = 2.8

        let result = generator.generate(
            from: mockData,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: settings
        )
        for segment in result.cameraTrack.segments {
            XCTAssertGreaterThanOrEqual(segment.startTransform.zoom, 0.99)
            XCTAssertLessThanOrEqual(segment.startTransform.zoom, 2.81)
            XCTAssertGreaterThanOrEqual(segment.endTransform.zoom, 0.99)
            XCTAssertLessThanOrEqual(segment.endTransform.zoom, 2.81)
        }
    }

    // MARK: - Zoom Intensity

    func test_generate_zoomIntensity_scalesZoom() {
        let mockData = makeClickingMouseData(duration: 5.0)

        var settingsDefault = ContinuousCameraSettings()
        settingsDefault.zoomIntensity = 1.0
        let defaultResult = generator.generate(
            from: mockData,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: settingsDefault
        )

        var settingsHigh = ContinuousCameraSettings()
        settingsHigh.zoomIntensity = 1.5
        let highResult = generator.generate(
            from: mockData,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: settingsHigh
        )

        // Higher intensity should produce higher max zoom
        let defaultMaxZoom = defaultResult.cameraTrack.segments
            .flatMap { [$0.startTransform.zoom, $0.endTransform.zoom] }.max() ?? 1.0
        let highMaxZoom = highResult.cameraTrack.segments
            .flatMap { [$0.startTransform.zoom, $0.endTransform.zoom] }.max() ?? 1.0
        XCTAssertGreaterThanOrEqual(highMaxZoom, defaultMaxZoom - 0.01,
                                   "Higher intensity should produce equal or higher zoom")
    }

    // MARK: - With Clicks

    func test_generate_withClicks_producesZoomedSegments() {
        let mockData = makeClickingMouseData(duration: 5.0)
        let result = generator.generate(
            from: mockData,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: ContinuousCameraSettings()
        )
        // At least some segments should have zoom > 1.0 due to clicking intent
        let hasZoomedSegment = result.cameraTrack.segments.contains {
            $0.startTransform.zoom > 1.01 || $0.endTransform.zoom > 1.01
        }
        XCTAssertTrue(hasZoomedSegment,
                      "Clicking activity should produce zoomed-in segments")
    }

    // MARK: - Helpers

    private func makeBasicMouseData(duration: TimeInterval) -> MockMouseDataSource {
        let posCount = Int(duration * 10) // 10Hz mouse data
        let positions = (0..<posCount).map { i -> MousePositionData in
            let t = Double(i) / 10.0
            return MousePositionData(
                time: t,
                position: NormalizedPoint(x: 0.5, y: 0.5)
            )
        }
        return MockMouseDataSource(
            duration: duration,
            frameRate: 60.0,
            positions: positions
        )
    }

    private func makeClickingMouseData(duration: TimeInterval) -> MockMouseDataSource {
        let posCount = Int(duration * 10)
        let positions = (0..<posCount).map { i -> MousePositionData in
            let t = Double(i) / 10.0
            return MousePositionData(
                time: t,
                position: NormalizedPoint(x: 0.3 + CGFloat(i) * 0.01, y: 0.5)
            )
        }
        let clicks = [
            ClickEventData(
                time: 1.0,
                position: NormalizedPoint(x: 0.3, y: 0.5),
                clickType: .leftDown
            ),
            ClickEventData(
                time: 1.1,
                position: NormalizedPoint(x: 0.3, y: 0.5),
                clickType: .leftUp
            ),
            ClickEventData(
                time: 2.0,
                position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown
            ),
            ClickEventData(
                time: 2.1,
                position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftUp
            )
        ]
        return MockMouseDataSource(
            duration: duration,
            frameRate: 60.0,
            positions: positions,
            clicks: clicks
        )
    }
}
