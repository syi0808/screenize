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
            let zooms = extractZooms(from: segment)
            XCTAssertGreaterThanOrEqual(zooms.start, 0.99)
            XCTAssertLessThanOrEqual(zooms.start, 2.81)
            XCTAssertGreaterThanOrEqual(zooms.end, 0.99)
            XCTAssertLessThanOrEqual(zooms.end, 2.81)
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
        let defaultZooms: [Double] = defaultResult.cameraTrack.segments
            .flatMap { seg in let z = extractZooms(from: seg); return [Double(z.start), Double(z.end)] }
        let defaultMaxZoom = defaultZooms.max() ?? 1.0
        let highZooms: [Double] = highResult.cameraTrack.segments
            .flatMap { seg in let z = extractZooms(from: seg); return [Double(z.start), Double(z.end)] }
        let highMaxZoom = highZooms.max() ?? 1.0
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
            let zooms = extractZooms(from: $0)
            return zooms.start > 1.01 || zooms.end > 1.01
        }
        XCTAssertTrue(hasZoomedSegment,
                      "Clicking activity should produce zoomed-in segments")
    }

    func test_generate_quietStart_startsWithEstablishingShot() {
        let quietStart = makeQuietOffCenterMouseData(duration: 2.0)
        let result = generator.generate(
            from: quietStart,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: ContinuousCameraSettings()
        )

        guard let firstSeg = result.cameraTrack.segments.first,
              let first = extractContinuousTransforms(from: firstSeg)?.first else {
            XCTFail("Expected continuous transforms for quiet-start recording")
            return
        }

        XCTAssertEqual(first.time, 0, accuracy: 0.001)
        XCTAssertEqual(first.transform.zoom, 1.0, accuracy: 0.05)
        XCTAssertEqual(first.transform.center.x, 0.5, accuracy: 0.05)
        XCTAssertEqual(first.transform.center.y, 0.5, accuracy: 0.05)
    }

    func test_generate_immediateClick_releasesStartupBiasEarly() {
        let mockData = makeImmediateClickMouseData(duration: 2.0)

        let result = generator.generate(
            from: mockData,
            uiStateSamples: [],
            frameAnalysis: [],
            screenBounds: screenBounds,
            settings: ContinuousCameraSettings()
        )

        guard let firstSeg = result.cameraTrack.segments.first,
              let samples = extractContinuousTransforms(from: firstSeg),
              let first = samples.first,
              let postRelease = samples.first(where: { $0.time >= 0.35 }) else {
            XCTFail("Expected generated continuous transforms")
            return
        }

        XCTAssertEqual(first.transform.center.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(first.transform.center.y, 0.5, accuracy: 0.01)
        XCTAssertLessThan(postRelease.transform.center.x, 0.45)
        XCTAssertGreaterThan(postRelease.transform.center.y, 0.55)
    }

    func test_fixtureProjectURL_searchesAncestorCheckoutWhenRunningFromWorktree() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fixtureDirectory = tempRoot
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("Recording_2026-02-24_02-19-36.screenize", isDirectory: true)
        let worktreeTestFilePath = tempRoot
            .appendingPathComponent(".worktrees", isDirectory: true)
            .appendingPathComponent("codex-transparent-background-fallback", isDirectory: true)
            .appendingPathComponent("ScreenizeTests", isDirectory: true)
            .appendingPathComponent("Generators", isDirectory: true)
            .appendingPathComponent("ContinuousCamera", isDirectory: true)
            .appendingPathComponent("ContinuousCameraGeneratorTests.swift")

        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let resolvedURL = try fixtureProjectURL(fromTestFilePath: worktreeTestFilePath.path)

        XCTAssertEqual(resolvedURL, fixtureDirectory)
    }

    // MARK: - Kind Helpers

    private func extractZooms(from segment: CameraSegment) -> (start: CGFloat, end: CGFloat) {
        switch segment.kind {
        case .manual(let start, let end):
            return (start.zoom, end.zoom)
        case .continuous(let transforms):
            return (transforms.first?.transform.zoom ?? 1.0, transforms.last?.transform.zoom ?? 1.0)
        }
    }

    private func extractContinuousTransforms(from segment: CameraSegment) -> [TimedTransform]? {
        if case .continuous(let transforms) = segment.kind {
            return transforms
        }
        return nil
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

    private func makeImmediateClickMouseData(duration: TimeInterval) -> MockMouseDataSource {
        let posCount = Int(duration * 10)
        let positions = (0..<posCount).map { i -> MousePositionData in
            let t = Double(i) / 10.0
            return MousePositionData(
                time: t,
                position: NormalizedPoint(x: 0.15, y: 0.80)
            )
        }
        let clicks = [
            ClickEventData(
                time: 0.05,
                position: NormalizedPoint(x: 0.15, y: 0.80),
                clickType: .leftDown
            ),
            ClickEventData(
                time: 0.15,
                position: NormalizedPoint(x: 0.15, y: 0.80),
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

    private func makeQuietOffCenterMouseData(duration: TimeInterval) -> MockMouseDataSource {
        let posCount = Int(duration * 10)
        let positions = (0..<posCount).map { i -> MousePositionData in
            let t = Double(i) / 10.0
            return MousePositionData(
                time: t,
                position: NormalizedPoint(x: 0.20, y: 0.80)
            )
        }
        return MockMouseDataSource(
            duration: duration,
            frameRate: 60.0,
            positions: positions
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

    private func fixtureProjectURL(fromTestFilePath filePath: String = #filePath) throws -> URL {
        guard let testsRange = filePath.range(of: "/ScreenizeTests/") else {
            throw FixtureError.invalidTestPath
        }
        let rootPath = String(filePath[..<testsRange.lowerBound])
        let fileManager = FileManager.default
        var searchRootURL = URL(fileURLWithPath: rootPath, isDirectory: true)

        while true {
            let candidateURL = searchRootURL
                .appendingPathComponent("projects", isDirectory: true)
                .appendingPathComponent("Recording_2026-02-24_02-19-36.screenize", isDirectory: true)

            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            let parentURL = searchRootURL.deletingLastPathComponent()
            guard parentURL.path != searchRootURL.path else {
                throw FixtureError.fixtureProjectNotFound
            }
            searchRootURL = parentURL
        }
    }

    private func decode<T: Decodable>(from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private enum FixtureError: Error {
        case invalidTestPath
        case fixtureProjectNotFound
    }
}
