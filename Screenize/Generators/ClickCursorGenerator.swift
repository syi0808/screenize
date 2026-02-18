import Foundation
import CoreGraphics

/// Cursor style generator
/// Creates a default cursor style track. Cursor position is always derived from mouse data.
final class ClickCursorGenerator {

    // MARK: - Properties

    let name = "Cursor Style"
    let description = "Generate cursor style segments (position always follows mouse data)"

    // MARK: - Generate

    func generate(from mouseData: MouseDataSource, settings: GeneratorSettings) -> CursorTrackV2 {
        let cursorSettings = settings.clickCursor

        let segment = CursorSegment(
            startTime: 0,
            endTime: mouseData.duration,
            style: .arrow,
            visible: true,
            scale: cursorSettings.cursorScale
        )

        return CursorTrackV2(
            name: "Cursor",
            isEnabled: true,
            segments: [segment]
        )
    }
}
