import SwiftUI

// MARK: - Typography

/// Semantic typography scale. Replaces inline `.font(.system(size: N))` calls
/// with meaningful, consistent names.
enum Typography {

    // MARK: Display

    /// Large titles — welcome screen headline, permission wizard title
    static let displayLarge: Font = .largeTitle.bold()

    /// Medium titles — section or screen titles
    static let displayMedium: Font = .title.bold()

    // MARK: Headings

    /// Section headers — inspector section titles, track names
    static let heading: Font = .headline

    /// Sub-section headers — secondary labels
    static let subheading: Font = .subheadline.weight(.medium)

    // MARK: Body

    /// Default body text
    static let body: Font = .body

    /// Emphasized body — medium weight
    static let bodyMedium: Font = .body.weight(.medium)

    // MARK: Detail

    /// Small secondary text — descriptions, hints
    static let caption: Font = .caption

    /// Emphasized caption — small labels with medium weight
    static let captionMedium: Font = .caption.weight(.medium)

    /// Very small text — caption2 equivalent
    static let footnote: Font = .caption2

    // MARK: Monospaced

    /// Monospaced for time codes, numeric values (11pt)
    static let mono: Font = .system(size: 11, design: .monospaced)

    /// Smaller monospaced — frame numbers, secondary numeric data (10pt)
    static let monoSmall: Font = .system(size: 10, design: .monospaced)

    // MARK: Timeline-specific

    /// Timeline track labels — 11pt medium weight
    static let timelineLabel: Font = .system(size: 11, weight: .medium)

    /// Timeline micro text — 8pt for very compact labels
    static let timelineMicro: Font = .system(size: 8, weight: .medium)

    /// Ruler time labels — 9pt monospaced medium
    static let rulerLabel: Font = .system(size: 9, weight: .medium, design: .monospaced)
}
