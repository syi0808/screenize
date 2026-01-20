import Foundation
import CoreGraphics

struct ZoomSettings {
    var isEnabled: Bool
    var zoomLevel: Double
    var smoothness: Double
    var edgePadding: CGFloat
    var triggerThreshold: CGFloat

    init(
        isEnabled: Bool = true,
        zoomLevel: Double = 2.0,
        smoothness: Double = 0.15,
        edgePadding: CGFloat = 100,
        triggerThreshold: CGFloat = 50
    ) {
        self.isEnabled = isEnabled
        self.zoomLevel = zoomLevel
        self.smoothness = smoothness
        self.edgePadding = edgePadding
        self.triggerThreshold = triggerThreshold
    }

    static let `default` = Self()

    static let subtle = Self(
        isEnabled: true,
        zoomLevel: 1.5,
        smoothness: 0.2,
        edgePadding: 150,
        triggerThreshold: 100
    )

    static let aggressive = Self(
        isEnabled: true,
        zoomLevel: 3.0,
        smoothness: 0.1,
        edgePadding: 50,
        triggerThreshold: 30
    )
}

struct ZoomState {
    var currentZoom: Double = 1.0
    var targetZoom: Double = 1.0
    var centerX: CGFloat = 0
    var centerY: CGFloat = 0
    var targetCenterX: CGFloat = 0
    var targetCenterY: CGFloat = 0

    mutating func update(with settings: ZoomSettings, deltaTime: Double) {
        let factor = min(1.0, settings.smoothness * deltaTime * 60)

        currentZoom += (targetZoom - currentZoom) * factor
        centerX += (targetCenterX - centerX) * CGFloat(factor)
        centerY += (targetCenterY - centerY) * CGFloat(factor)
    }

    var zoomRect: CGRect {
        let width = 1.0 / currentZoom
        let height = 1.0 / currentZoom
        let x = centerX - CGFloat(width) / 2
        let y = centerY - CGFloat(height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
