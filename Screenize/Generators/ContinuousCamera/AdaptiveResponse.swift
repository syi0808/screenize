import Foundation
import CoreGraphics

/// Computes adaptive spring response time based on time-to-next-action.
///
/// Since smart generation is post-processing, we can look ahead in the intent
/// timeline to know when the next meaningful action occurs. Camera moves faster
/// when the next action is imminent, slower when there's plenty of time.
enum AdaptiveResponse {

    static func compute(
        timeToNextAction: TimeInterval?,
        settings: DeadZoneSettings
    ) -> CGFloat {
        guard let timeToNext = timeToNextAction else {
            return settings.maxResponse
        }

        if timeToNext <= settings.responseFastThreshold {
            return settings.minResponse
        }
        if timeToNext >= settings.responseSlowThreshold {
            return settings.maxResponse
        }

        let progress = (timeToNext - settings.responseFastThreshold)
            / (settings.responseSlowThreshold - settings.responseFastThreshold)
        return settings.minResponse + CGFloat(progress) * (settings.maxResponse - settings.minResponse)
    }

    static func findNextActionTime(
        after time: TimeInterval,
        intentSpans: [IntentSpan]
    ) -> TimeInterval? {
        for span in intentSpans {
            guard span.startTime > time else { continue }
            switch span.intent {
            case .idle, .reading:
                continue
            default:
                return span.startTime
            }
        }
        return nil
    }
}
