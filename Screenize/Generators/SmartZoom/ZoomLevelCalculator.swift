import Foundation
import CoreGraphics

// MARK: - Zoom Level Calculator

/// Zoom level calculation utility
struct ZoomLevelCalculator {

    /// Calculate a zoom level that fits the session work area
    static func calculateSessionZoom(workArea: CGRect, settings: SmartZoomSettings) -> CGFloat {
        let areaSize = max(workArea.width, workArea.height)

        // Adjust zoom so the work area matches targetAreaCoverage
        // Zoom in for small areas; reduce zoom for larger areas
        guard areaSize > 0.01 else {
            return settings.defaultZoom
        }

        let zoom = settings.targetAreaCoverage / areaSize
        return min(max(zoom, settings.minZoom), settings.maxZoom)
    }

    /// Determine whether a forced zoom-out is needed (modals, large frame changes, etc.)
    static func checkForceZoomOut(
        session: WorkSession,
        frameAnalysisArray: [VideoFrameAnalyzer.FrameAnalysis],
        uiStateSamples: [UIStateSample],
        settings: SmartZoomSettings
    ) -> Bool {
        // Detect modals
        let midTime = (session.startTime + session.endTime) / 2
        if let uiSample = lookupUIStateSample(at: midTime, in: uiStateSamples) {
            let previousSample = lookupUIStateSample(at: midTime - 1.0, in: uiStateSamples)
            let contextChange = uiSample.detectContextChange(
                from: previousSample,
                threshold: settings.contextExpansionThreshold
            )

            switch contextChange {
            case .modalOpened(let role):
                if settings.modalRoles.contains(role) {
                    return true
                }
            default:
                break
            }
        }

        return false
    }

    /// Lookup a UI state sample at a specific time
    static func lookupUIStateSample(at time: TimeInterval, in samples: [UIStateSample]) -> UIStateSample? {
        guard !samples.isEmpty else { return nil }
        return samples.min { abs($0.timestamp - time) < abs($1.timestamp - time) }
    }

    /// Lookup the frame analysis result at a specific time
    static func lookupFrameAnalysis(at time: TimeInterval, in array: [VideoFrameAnalyzer.FrameAnalysis]) -> VideoFrameAnalyzer.FrameAnalysis? {
        guard !array.isEmpty else { return nil }
        return array.min { abs($0.time - time) < abs($1.time - time) }
    }
}
