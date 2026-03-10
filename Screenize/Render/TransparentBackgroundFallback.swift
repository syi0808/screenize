import AppKit
import CoreGraphics
import CoreImage
import SwiftUI

enum TransparentBackgroundFallback {
    static let grayLevel: CGFloat = 0.16

    static let nsColor = NSColor(
        srgbRed: grayLevel,
        green: grayLevel,
        blue: grayLevel,
        alpha: 1.0
    )
    static let swiftUIColor = Color(nsColor: nsColor)
    static let ciColor = CIColor(
        red: grayLevel,
        green: grayLevel,
        blue: grayLevel,
        alpha: 1.0
    )

    static func image(size: CGSize) -> CIImage {
        CIImage(color: ciColor).cropped(to: CGRect(origin: .zero, size: size))
    }
}
