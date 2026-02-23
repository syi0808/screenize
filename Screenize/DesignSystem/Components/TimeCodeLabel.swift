import SwiftUI

// MARK: - Time Code Label

/// Displays a time interval as a formatted time code string.
/// Uses monospaced font for consistent digit width.
struct TimeCodeLabel: View {
    let time: TimeInterval
    var style: Style = .standard

    enum Style {
        case standard   // MM:SS or SS.f
        case compact    // MM:SS only
        case precise    // MM:SS.ff with frames
    }

    var body: some View {
        Text(formatted)
            .font(style == .standard ? Typography.mono : Typography.monoSmall)
            .monospacedDigit()
    }

    private var formatted: String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        switch style {
        case .standard:
            if minutes > 0 {
                let fraction = Int((time - Double(totalSeconds)) * 10)
                return String(format: "%d:%02d.%d", minutes, seconds, fraction)
            } else {
                let fraction = Int((time - Double(totalSeconds)) * 10)
                return String(format: "%d.%d", seconds, fraction)
            }
        case .compact:
            return String(format: "%d:%02d", minutes, seconds)
        case .precise:
            let fraction = Int((time - Double(totalSeconds)) * 100)
            if minutes > 0 {
                return String(format: "%d:%02d.%02d", minutes, seconds, fraction)
            } else {
                return String(format: "%d.%02d", seconds, fraction)
            }
        }
    }
}
