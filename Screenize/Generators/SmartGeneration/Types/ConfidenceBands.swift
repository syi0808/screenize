import Foundation

/// Three discrete confidence bands for camera movement suppression.
///
/// IntentClassifier assigns confidence values (0.5-0.95) but downstream
/// consumers need discrete decisions. This helper maps continuous confidence
/// to three bands: low (no movement), medium (reduced movement), high (full).
enum ConfidenceBands {
    static let lowThreshold: Float = 0.6
    static let mediumThreshold: Float = 0.85

    enum Band { case none, reduced, full }

    static func band(for confidence: Float) -> Band {
        if confidence < lowThreshold { return .none }
        if confidence < mediumThreshold { return .reduced }
        return .full
    }
}
