import SwiftUI

// MARK: - Reduce Motion

/// Wraps `withAnimation` to respect the system Reduce Motion setting.
/// When Reduce Motion is enabled, changes apply instantly (no animation).
///
/// Usage:
///     withMotionSafeAnimation(AnimationTokens.standard) {
///         showControls.toggle()
///     }
func withMotionSafeAnimation<Result>(
    _ animation: Animation? = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        return try body()
    } else {
        return try withAnimation(animation, body)
    }
}

/// View modifier that applies an animation only when Reduce Motion is OFF.
struct MotionSafeAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Applies an animation that respects the Reduce Motion accessibility setting.
    func motionSafeAnimation<Value: Equatable>(
        _ animation: Animation?,
        value: Value
    ) -> some View {
        self.modifier(MotionSafeAnimationModifier(animation: animation, value: value))
    }
}
