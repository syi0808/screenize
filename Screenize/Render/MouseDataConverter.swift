import Foundation
import CoreGraphics

// MARK: - Mouse Data Converter

/// Utility for converting mouse recording data into rendering data
/// Shared by ExportEngine and PreviewEngine
struct MouseDataConverter {

    /// Convert from a MouseDataSource (v4 event streams or legacy adapter) to render data.
    /// Mouse button events are passed through as individual down/up events (no pairing)
    /// so that cursor press/release animation works correctly for clicks, drags, and
    /// rapid sequences.
    static func convertFromMouseDataSource(
        _ source: MouseDataSource
    ) -> (positions: [RenderMousePosition], mouseButtonEvents: [RenderMouseButtonEvent]) {
        let positions = source.positions.map { pos in
            RenderMousePosition(
                timestamp: pos.time,
                x: pos.position.x,
                y: pos.position.y,
                velocity: 0
            )
        }

        let sortedClicks = source.clicks.sorted { $0.time < $1.time }
        var buttonEvents: [RenderMouseButtonEvent] = []

        for click in sortedClicks {
            let clickType: ClickType
            let isDown: Bool

            switch click.clickType {
            case .leftDown:
                clickType = .left
                isDown = true
            case .leftUp:
                clickType = .left
                isDown = false
            case .rightDown:
                clickType = .right
                isDown = true
            case .rightUp:
                clickType = .right
                isDown = false
            case .doubleClick:
                // Synthesize a quick down+up pair for double-click events
                buttonEvents.append(RenderMouseButtonEvent(
                    timestamp: click.time,
                    isDown: true,
                    clickType: .left
                ))
                buttonEvents.append(RenderMouseButtonEvent(
                    timestamp: click.time + 0.05,
                    isDown: false,
                    clickType: .left
                ))
                continue
            }

            buttonEvents.append(RenderMouseButtonEvent(
                timestamp: click.time,
                isDown: isDown,
                clickType: clickType
            ))
        }

        // Already sorted since source was sorted by time
        return (positions, buttonEvents)
    }

    // MARK: - Load and Convert

    /// Load and convert mouse data from a project (without interpolation)
    static func loadAndConvert(
        from project: ScreenizeProject
    ) -> (positions: [RenderMousePosition], mouseButtonEvents: [RenderMouseButtonEvent]) {
        guard let source = loadMouseDataSourceFromEventStreams(project: project) else {
            return ([], [])
        }
        return convertFromMouseDataSource(source)
    }

    /// Load and convert mouse data from a project (with interpolation)
    @MainActor
    static func loadAndConvertWithInterpolation(
        from project: ScreenizeProject,
        frameRate: Double,
        springConfig: SpringCursorConfig? = nil
    ) -> (positions: [RenderMousePosition], mouseButtonEvents: [RenderMouseButtonEvent]) {
        guard let source = loadMouseDataSourceFromEventStreams(project: project) else {
            return ([], [])
        }
        let result = convertFromMouseDataSource(source)
        let interpolationFrameRate = max(frameRate, 60.0)
        let interpolatedPositions = PreviewEngine.interpolateMousePositions(
            result.positions,
            outputFrameRate: interpolationFrameRate,
            springConfig: springConfig,
            // Uses first continuous segment's transforms (generator produces exactly one)
            cameraTransforms: project.timeline.cameraTrack?.segments
                .first(where: { $0.isContinuous }).flatMap {
                    if case .continuous(let transforms) = $0.kind { return transforms }
                    return nil
                }
        )
        return (interpolatedPositions, result.mouseButtonEvents)
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
