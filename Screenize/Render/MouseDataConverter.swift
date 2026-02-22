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
        let sortedClicks = source.clicks.sorted { $0.time < $1.time }
        var pendingDownByType: [ClickEventData.ClickType: ClickEventData] = [:]
        var clicks: [RenderClickEvent] = []

        for click in sortedClicks {
            switch click.clickType {
            case .leftDown, .rightDown:
                pendingDownByType[click.clickType] = click

            case .leftUp, .rightUp:
                let downType: ClickEventData.ClickType = (click.clickType == .leftUp) ? .leftDown : .rightDown
                guard let down = pendingDownByType[downType] else { continue }

                let clickType: ClickType = (downType == .leftDown) ? .left : .right
                let duration = max(0.03, click.time - down.time)
                clicks.append(RenderClickEvent(
                    timestamp: down.time,
                    duration: duration,
                    x: down.position.x,
                    y: down.position.y,
                    clickType: clickType
                ))
                pendingDownByType.removeValue(forKey: downType)

            case .doubleClick:
                clicks.append(RenderClickEvent(
                    timestamp: click.time,
                    duration: 0.1,
                    x: click.position.x,
                    y: click.position.y,
                    clickType: .left
                ))
            }
        }

        for pending in pendingDownByType.values {
            let clickType: ClickType = (pending.clickType == .leftDown) ? .left : .right
            clicks.append(RenderClickEvent(
                timestamp: pending.time,
                duration: 0.1,
                x: pending.position.x,
                y: pending.position.y,
                clickType: clickType
            ))
        }

        return (positions, clicks)
    }

    // MARK: - Load and Convert

    /// Load and convert mouse data from a project (without interpolation)
    static func loadAndConvert(
        from project: ScreenizeProject
    ) -> (positions: [RenderMousePosition], clicks: [RenderClickEvent]) {
        guard let source = loadMouseDataSourceFromEventStreams(project: project) else {
            return ([], [])
        }
        return convertFromMouseDataSource(source)
    }

    /// Load and convert mouse data from a project (with interpolation)
    @MainActor
    static func loadAndConvertWithInterpolation(
        from project: ScreenizeProject,
        frameRate: Double
    ) -> (positions: [RenderMousePosition], clicks: [RenderClickEvent]) {
        guard let source = loadMouseDataSourceFromEventStreams(project: project) else {
            return ([], [])
        }
        let result = convertFromMouseDataSource(source)
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
