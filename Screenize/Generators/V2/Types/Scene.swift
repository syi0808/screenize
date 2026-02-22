import Foundation
import CoreGraphics

/// A semantically meaningful scene within the recording.
struct CameraScene {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let primaryIntent: UserIntent
    let focusRegions: [FocusRegion]
    let appContext: String?

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        primaryIntent: UserIntent,
        focusRegions: [FocusRegion] = [],
        appContext: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.primaryIntent = primaryIntent
        self.focusRegions = focusRegions
        self.appContext = appContext
    }
}

/// A region of interest on screen at a given time.
struct FocusRegion {
    let time: TimeInterval
    let region: CGRect
    let confidence: Float
    let source: FocusSource
}

/// Source of a focus region detection.
enum FocusSource {
    case cursorPosition
    case activeElement(UIElementInfo)
    case caretPosition
    case clickTarget
    case saliency
}
