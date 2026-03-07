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

    func test_generate_fixtureProject_startsWithEstablishingShot() throws {
        let fixture = try loadFixtureProjectInput()
        let result = generator.generate(
            from: fixture.mouseData,
            uiStateSamples: fixture.uiStateSamples,
            frameAnalysis: [],
            screenBounds: fixture.screenBounds,
            settings: ContinuousCameraSettings()
        )

        guard let first = result.continuousTransforms?.first else {
            XCTFail("Expected continuous transforms for fixture project")
            return
        }

        XCTAssertEqual(first.time, 0, accuracy: 0.001)
        XCTAssertEqual(first.transform.zoom, 1.0, accuracy: 0.05)
        XCTAssertEqual(first.transform.center.x, 0.5, accuracy: 0.05)
        XCTAssertEqual(first.transform.center.y, 0.5, accuracy: 0.05)
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

    private func loadFixtureProjectInput() throws -> (
        mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample],
        screenBounds: CGSize
    ) {
        let projectURL = try fixtureProjectURL()
        let metadataURL = projectURL.appendingPathComponent("recording/metadata.json")
        let mouseMovesURL = projectURL.appendingPathComponent("recording/mousemoves-0.json")
        let mouseClicksURL = projectURL.appendingPathComponent("recording/mouseclicks-0.json")
        let keystrokesURL = projectURL.appendingPathComponent("recording/keystrokes-0.json")

        let metadata: PolyRecordingMetadata = try decode(from: metadataURL)
        let mouseMoves: [PolyMouseMoveEvent] = try decode(from: mouseMovesURL)
        let mouseClicks: [PolyMouseClickEvent] = try decode(from: mouseClicksURL)
        let keystrokes: [PolyKeystrokeEvent] = try decode(from: keystrokesURL)

        let duration = Double(metadata.processTimeEndMs - metadata.processTimeStartMs) / 1000.0
        let mouseData = EventStreamAdapter(
            mouseMoves: mouseMoves,
            mouseClicks: mouseClicks,
            keystrokes: keystrokes,
            metadata: metadata,
            duration: duration,
            frameRate: 60.0
        )

        let interop = InteropBlock.forRecording(
            videoRelativePath: "recording/recording.mp4"
        )
        let uiStateSamples = EventStreamLoader.loadUIStateSamples(
            from: projectURL,
            interop: interop,
            metadata: metadata
        )

        return (
            mouseData,
            uiStateSamples,
            CGSize(width: metadata.display.widthPx, height: metadata.display.heightPx)
        )
    }

    private func fixtureProjectURL() throws -> URL {
        let filePath = #filePath
        guard let testsRange = filePath.range(of: "/ScreenizeTests/") else {
            throw FixtureError.invalidTestPath
        }
        let rootPath = String(filePath[..<testsRange.lowerBound])
        return URL(fileURLWithPath: rootPath)
            .appendingPathComponent("projects/Recording_2026-02-24_02-19-36.screenize")
    }

    private func decode<T: Decodable>(from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private enum FixtureError: Error {
        case invalidTestPath
    }
}
