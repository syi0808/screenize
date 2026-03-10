import XCTest
import AppKit
import CoreGraphics
import CoreImage
@testable import Screenize

final class TransparentBackgroundFallbackTests: XCTestCase {

    func test_swiftUIColor_isDarkGray() {
        let nsColor = NSColor(TransparentBackgroundFallback.swiftUIColor)
        guard let ciColor = CIColor(color: nsColor) else {
            return XCTFail("Expected CIColor conversion for fallback color")
        }

        XCTAssertEqual(ciColor.red, 0.16, accuracy: 0.02)
        XCTAssertEqual(ciColor.green, 0.16, accuracy: 0.02)
        XCTAssertEqual(ciColor.blue, 0.16, accuracy: 0.02)
        XCTAssertEqual(ciColor.alpha, 1.0, accuracy: 0.001)
    }

    func test_image_cropsToRequestedSize() {
        let image = TransparentBackgroundFallback.image(size: CGSize(width: 320, height: 180))

        XCTAssertEqual(image.extent, CGRect(x: 0, y: 0, width: 320, height: 180))
    }

    func test_previewBackgroundStyle_usesSharedDarkGrayWhenBackgroundDisabled() {
        let style = WindowModeRenderer.previewBackgroundStyle(
            backgroundEnabled: false,
            configuredStyle: .gradient(.defaultGradient),
            isPreview: true
        )

        XCTAssertEqual(style, .solid(TransparentBackgroundFallback.swiftUIColor))
    }

    func test_previewBackgroundStyle_backgroundEnabled_keepsConfiguredStyle() {
        let style = WindowModeRenderer.previewBackgroundStyle(
            backgroundEnabled: true,
            configuredStyle: .gradient(.midnight),
            isPreview: true
        )

        XCTAssertEqual(style, .gradient(.midnight))
    }

    func test_maskFallbackImage_zeroSize_returnsSharedFallbackImage() {
        let image = WindowEffectApplicator.maskFallbackImage(size: .zero)
        let sharedImage = TransparentBackgroundFallback.image(size: .zero)

        XCTAssertEqual(image.extent, sharedImage.extent)
    }

    func test_maskFallbackImage_nonZeroSize_matchesSharedFallbackExtent() {
        let size = CGSize(width: 200, height: 120)
        let image = WindowEffectApplicator.maskFallbackImage(size: size)

        XCTAssertEqual(image.extent, CGRect(origin: .zero, size: size))
    }
}
