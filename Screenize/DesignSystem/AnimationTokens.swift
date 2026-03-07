import SwiftUI

// MARK: - Animation Tokens

/// Standardized animation curves and durations for consistent motion.
enum AnimationTokens {
    /// 0.15s ease-in-out — Fastest state changes (hover, press feedback)
    static let quick: Animation = .easeInOut(duration: 0.15)

    /// 0.2s ease-in-out — Standard transitions (show/hide controls, selection)
    static let standard: Animation = .easeInOut(duration: 0.2)

    /// 0.3s ease-in-out — Gentle transitions (panel expand/collapse)
    static let gentle: Animation = .easeInOut(duration: 0.3)

    /// 0.5s ease-in-out — Slow, dramatic transitions
    static let slow: Animation = .easeInOut(duration: 0.5)

    /// Spring — Natural bounce for interactive elements (toolbar, drag)
    static let springy: Animation = .spring(response: 0.4, dampingFraction: 0.7)

    /// Toolbar spring — Slightly tighter for toolbar phase transitions
    static let toolbarSpring: Animation = .spring(response: 0.35, dampingFraction: 0.85)

    /// Pulse — Repeating animation for indicators (recording dot, loading)
    static let pulse: Animation = .easeInOut(duration: 0.5).repeatForever(autoreverses: true)

    /// Linear fast — For progress bars and continuous updates
    static let linearFast: Animation = .linear(duration: 0.1)
}
