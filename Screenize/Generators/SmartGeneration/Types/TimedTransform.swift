import Foundation

/// A transform value at a specific point in time, used by the continuous camera pipeline.
struct TimedTransform: Codable, Equatable {
    let time: TimeInterval
    let transform: TransformValue
}
