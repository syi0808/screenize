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
            visible: true
        )

        return CursorTrackV2(
            name: "Cursor (Smart V2)",
            isEnabled: true,
            scale: settings.cursorScale,
            segments: [segment]
        )
    }
}

// MARK: - Settings

/// Cursor track emission settings.
struct CursorEmissionSettings {
    var cursorScale: CGFloat = 2.0
}

// MARK: - GenerationSettings Factory

extension CursorEmissionSettings {
    init(from gs: GenerationSettings) {
        self.init()
        cursorScale = gs.cursorKeystroke.cursorScale
    }
}
