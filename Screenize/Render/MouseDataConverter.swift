import Foundation
import CoreGraphics

// MARK: - Mouse Data Converter

/// Utility for converting mouse recording data into rendering data
/// Shared by ExportEngine and PreviewEngine
struct MouseDataConverter {

    /// Convert mouse recording data for rendering (without interpolation)
    /// - Parameter recording: Mouse recording data
    /// - Returns: Converted mouse positions and click events (pre-interpolation)
    static func convert(
        from recording: MouseRecording
    ) -> (positions: [RenderMousePosition], clicks: [RenderClickEvent]) {
        let boundsSize = CGSize(
            width: recording.screenBounds.width,
            height: recording.screenBounds.height
        )

        let positions = toRenderPositions(from: recording.positions, boundsSize: boundsSize)
        let clicks = toRenderClickEvents(from: recording.clicks, boundsSize: boundsSize)

        return (positions, clicks)
    }

    /// Convert MousePosition array to RenderMousePosition array
    /// - Parameters:
    ///   - positions: Original mouse positions
    ///   - boundsSize: Capture bounds size
    /// - Returns: Normalized mouse positions for rendering
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
    /// - Parameters:
    ///   - clicks: Original click events
    ///   - boundsSize: Capture bounds size
    /// - Returns: Normalized click events for rendering
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

    /// Load and convert mouse data from a project (without interpolation)
    /// - Parameter project: Screenize project
    /// - Returns: Converted mouse positions and click events (pre-interpolation), or empty arrays if missing
    static func loadAndConvert(
        from project: ScreenizeProject
    ) throws -> (positions: [RenderMousePosition], clicks: [RenderClickEvent]) {
        guard project.media.mouseDataExists else {
            return ([], [])
        }

        let recording = try MouseRecording.load(from: project.media.mouseDataURL)
        return convert(from: recording)
    }

    /// Load and convert mouse data from a project (with interpolation)
    /// - Parameters:
    ///   - project: Screenize project
    ///   - frameRate: Output frame rate
    /// - Returns: Converted and interpolated mouse positions and click events
    /// - Note: Must be called on the MainActor (interpolateMousePositions is MainActor-isolated)
    @MainActor
    static func loadAndConvertWithInterpolation(
        from project: ScreenizeProject,
        frameRate: Double
    ) throws -> (positions: [RenderMousePosition], clicks: [RenderClickEvent]) {
        guard project.media.mouseDataExists else {
            return ([], [])
        }

        let recording = try MouseRecording.load(from: project.media.mouseDataURL)
        let result = convert(from: recording)

        // Apply interpolation
        let interpolatedPositions = PreviewEngine.interpolateMousePositions(
            result.positions,
            outputFrameRate: frameRate
        )

        return (interpolatedPositions, result.clicks)
    }
}
