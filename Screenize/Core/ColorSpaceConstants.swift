import CoreGraphics

/// Safe CGColorSpace constants with fallbacks.
/// Eliminates force unwraps on CGColorSpace(name:) calls throughout the codebase.
extension CGColorSpace {
    static let screenizeSRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    static let screenizeP3: CGColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? screenizeSRGB
    static let screenizeBT709: CGColorSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? screenizeSRGB
    static let screenizeBT2020: CGColorSpace = CGColorSpace(name: CGColorSpace.itur_2020) ?? screenizeSRGB
}
