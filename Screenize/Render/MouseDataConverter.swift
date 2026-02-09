import Foundation
import CoreGraphics

// MARK: - Mouse Data Converter

/// Utility for converting mouse recording data into rendering data
/// Shared by ExportEngine and PreviewEngine
struct MouseDataConverter {

    /// Convert from a MouseDataSource (v4 event streams or legacy adapter) to render data
    static func convertFromMouseDataSource(
        _ source: MouseDataSource
    ) -> (positions: [RenderMousePosition], clicks: [RenderClickEvent]) {
        let positions = source.positions.map { pos in
            RenderMousePosition(
                timestamp: pos.time,
                x: pos.position.x,
                y: pos.position.y,
                velocity: 0
            )
        }
        let clicks = source.clicks.map { click in
            let clickType: ClickType = (click.clickType == .leftDown || click.clickType == .doubleClick) ? .left : .right
            return RenderClickEvent(
                timestamp: click.time,
                duration: 0.1,
                x: click.position.x,
                y: click.position.y,
                clickType: clickType
            )
        }
        return (positions, clicks)
    }

    // MARK: - Legacy v2 (remove in next minor version)

    /// Convert mouse recording data for rendering (without interpolation)
    static func convert(
        from recording: MouseRecording
    ) -> (positions: [RenderMousePosition], clicks: [RenderClickEvent]) {
        let boundsSize = CGSize(
            width: recording.screenBounds.width,
            height: recording.screenBounds.height
        )

        // DEBUG: Log mouse data conversion details
        print("🔍 [DEBUG] MouseDataConverter: screenBounds=\(recording.screenBounds), boundsSize=\(boundsSize)")
        for (i, pos) in recording.positions.prefix(3).enumerated() {
            let normalized = CoordinateConverter.pixelToNormalized(
                CGPoint(x: pos.x, y: pos.y), size: boundsSize
            )
            print("🔍 [DEBUG] MouseDataConverter: position[\(i)] raw=(\(pos.x), \(pos.y)) -> normalized=(\(normalized.x), \(normalized.y))")
        }

        let positions = toRenderPositions(from: recording.positions, boundsSize: boundsSize)
        let clicks = toRenderClickEvents(from: recording.clicks, boundsSize: boundsSize)

        return (positions, clicks)
    }

    /// Convert MousePosition array to RenderMousePosition array
    static func toRenderPositions(
        from positions: [MousePosition],
        boundsSize: CGSize
    ) -> [RenderMousePosition] {
        positions.map { pos in
            let normalized = CoordinateConverter.pixelToNormalized(
                CGPoint(x: pos.x, y: pos.y),
                size: boundsSize
            )
            return RenderMousePosition(
                timestamp: pos.timestamp,
                x: normalized.x,
                y: normalized.y,
                velocity: pos.velocity
            )
        }
    }

    /// Convert MouseClickEvent array to RenderClickEvent array
    static func toRenderClickEvents(
        from clicks: [MouseClickEvent],
        boundsSize: CGSize
    ) -> [RenderClickEvent] {
        clicks.map { click in
            let normalized = CoordinateConverter.pixelToNormalized(
                CGPoint(x: click.x, y: click.y),
                size: boundsSize
            )
            let clickType: ClickType = (click.type == .left) ? .left : .right
            return RenderClickEvent(
                timestamp: click.timestamp,
                duration: click.duration,
                x: normalized.x,
                y: normalized.y,
                clickType: clickType
            )
        }
    }

    // MARK: - Load and Convert

    /// Load and convert mouse data from a project (without interpolation)
    static func loadAndConvert(
        from project: ScreenizeProject
    ) throws -> (positions: [RenderMousePosition], clicks: [RenderClickEvent]) {
        // v4 path: load from event streams
        if let source = loadMouseDataSourceFromEventStreams(project: project) {
            return convertFromMouseDataSource(source)
        }

        // MARK: - Legacy v2 (remove in next minor version)
        guard project.media.mouseDataExists else {
            return ([], [])
        }
        let recording = try MouseRecording.load(from: project.media.mouseDataURL)
        return convert(from: recording)
    }

    /// Load and convert mouse data from a project (with interpolation)
    @MainActor
    static func loadAndConvertWithInterpolation(
        from project: ScreenizeProject,
        frameRate: Double
    ) throws -> (positions: [RenderMousePosition], clicks: [RenderClickEvent]) {
        // v4 path: load from event streams
        if let source = loadMouseDataSourceFromEventStreams(project: project) {
            let result = convertFromMouseDataSource(source)
            let interpolatedPositions = PreviewEngine.interpolateMousePositions(
                result.positions,
                outputFrameRate: frameRate
            )
            return (interpolatedPositions, result.clicks)
        }

        // MARK: - Legacy v2 (remove in next minor version)
        guard project.media.mouseDataExists else {
            return ([], [])
        }
        let recording = try MouseRecording.load(from: project.media.mouseDataURL)
        let result = convert(from: recording)
        let interpolatedPositions = PreviewEngine.interpolateMousePositions(
            result.positions,
            outputFrameRate: frameRate
        )
        return (interpolatedPositions, result.clicks)
    }

    // MARK: - Private

    /// Derive the package root URL from the project's video URL and load event streams.
    private static func loadMouseDataSourceFromEventStreams(
        project: ScreenizeProject
    ) -> MouseDataSource? {
        guard let interop = project.interop else { return nil }

        // Package root is two levels up from the video file:
        // <package>/recording/recording.mp4 → <package>
        let packageURL = project.media.videoURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return EventStreamLoader.load(
            from: packageURL,
            interop: interop,
            duration: project.media.duration,
            frameRate: project.media.frameRate
        )
    }
}
