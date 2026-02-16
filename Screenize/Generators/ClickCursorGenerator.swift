import Foundation
import CoreGraphics

/// Cursor style generator
/// Creates a default cursor style track. Cursor position is always derived from mouse data.
final class ClickCursorGenerator: KeyframeGenerator {

    typealias Output = CursorTrack

    // MARK: - Properties

    let name = "Cursor Style"
    let description = "Generate cursor style segments (position always follows mouse data)"

    // MARK: - Generate

    func generate(from mouseData: MouseDataSource, settings: GeneratorSettings) -> CursorTrack {
        let cursorSettings = settings.clickCursor

        // Create a single keyframe at time 0 with default style
        let keyframe = CursorStyleKeyframe(
            time: 0,
            style: .arrow,
            visible: true,
            scale: cursorSettings.cursorScale
        )

        return CursorTrack(
            id: UUID(),
            name: "Cursor",
            isEnabled: true,
            defaultStyle: .arrow,
            defaultScale: cursorSettings.cursorScale,
            defaultVisible: true,
            styleKeyframes: [keyframe]
        )
    }
}

// MARK: - Statistics Extension

extension ClickCursorGenerator {

    func generateWithStatistics(
        from mouseData: MouseDataSource,
        settings: GeneratorSettings
    ) -> GeneratorResult<CursorTrack> {
        let startTime = Date()

        let track = generate(from: mouseData, settings: settings)

        let processingTime = Date().timeIntervalSince(startTime)

        let statistics = GeneratorStatistics(
            analyzedEvents: 0,
            generatedKeyframes: track.styleKeyframes?.count ?? 0,
            processingTime: processingTime,
            additionalInfo: [:]
        )

        return GeneratorResult(
            track: track,
            keyframeCount: track.styleKeyframes?.count ?? 0,
            statistics: statistics
        )
    }
}
