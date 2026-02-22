import Foundation
import CoreGraphics

/// Emits a CursorTrackV2 with a single full-duration cursor segment.
struct CursorTrackEmitter {

    /// Emit a cursor track spanning the full duration.
    static func emit(
        duration: TimeInterval,
        settings: CursorEmissionSettings
    ) -> CursorTrackV2 {
        guard duration > 0 else {
            return CursorTrackV2(name: "Cursor (Smart V2)", segments: [])
        }

        let segment = CursorSegment(
            startTime: 0,
            endTime: duration,
            style: .arrow,
            visible: true,
            scale: settings.cursorScale
        )

        return CursorTrackV2(
            name: "Cursor (Smart V2)",
            isEnabled: true,
            segments: [segment]
        )
    }
}
