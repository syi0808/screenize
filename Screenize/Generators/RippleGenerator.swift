import Foundation

/// Ripple generator
/// Auto-creates ripple effect keyframes at click locations
final class RippleGenerator: KeyframeGenerator {

    typealias Output = RippleTrack

    // MARK: - Properties

    let name = "Ripple"
    let description = "Generate ripple effects at click positions"

    // MARK: - Generate

    func generate(from mouseData: MouseDataSource, settings: GeneratorSettings) -> RippleTrack {
        let rippleSettings = settings.ripple

        guard rippleSettings.enabled else {
            return createEmptyTrack()
        }

        var keyframes: [RippleKeyframe] = []

        // Filter click events
        let clicks: [ClickEventData]
        if rippleSettings.doubleClickOnly {
            clicks = mouseData.clicks.filter { $0.clickType == .doubleClick }
        } else {
            clicks = mouseData.clicks.filter { $0.clickType == .leftDown }
        }

        guard !clicks.isEmpty else {
            return createEmptyTrack()
        }

        // Generate a ripple keyframe for each click
        for click in clicks {
            // Filter out clicks that are too close together (minimum 0.1s apart)
            if let lastKeyframe = keyframes.last,
               click.time - lastKeyframe.time < 0.1 {
                continue
            }

            let keyframe = RippleKeyframe(
                time: click.time,
                x: click.x,
                y: click.y,
                intensity: rippleSettings.intensity,
                duration: rippleSettings.duration,
                color: rippleSettings.color,
                easing: .springBouncy
            )

            keyframes.append(keyframe)
        }

        return RippleTrack(
            id: UUID(),
            name: "Ripple (Auto)",
            isEnabled: true,
            keyframes: keyframes
        )
    }

    // MARK: - Helpers

    private func createEmptyTrack() -> RippleTrack {
        RippleTrack(
            id: UUID(),
            name: "Ripple (Auto)",
            isEnabled: true,
            keyframes: []
        )
    }
}

// MARK: - Ripple Generator with Statistics

extension RippleGenerator {

    func generateWithStatistics(
        from mouseData: MouseDataSource,
        settings: GeneratorSettings
    ) -> GeneratorResult<RippleTrack> {
        let startTime = Date()

        let track = generate(from: mouseData, settings: settings)

        let processingTime = Date().timeIntervalSince(startTime)

        let clicks: [ClickEventData]
        if settings.ripple.doubleClickOnly {
            clicks = mouseData.clicks.filter { $0.clickType == .doubleClick }
        } else {
            clicks = mouseData.clicks.filter { $0.clickType == .leftDown }
        }

        let statistics = GeneratorStatistics(
            analyzedEvents: clicks.count,
            generatedKeyframes: track.keyframes.count,
            processingTime: processingTime,
            additionalInfo: [
                "filteredDueToTiming": clicks.count - track.keyframes.count,
                "averageIntensity": settings.ripple.intensity
            ]
        )

        return GeneratorResult(
            track: track,
            keyframeCount: track.keyframes.count,
            statistics: statistics
        )
    }
}
