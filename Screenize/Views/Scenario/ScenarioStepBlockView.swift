import SwiftUI

/// Individual step block rendered on the timeline for a single ScenarioStep.
struct ScenarioStepBlockView: View {

    let step: ScenarioStep
    let isSelected: Bool
    /// Pre-calculated width from durationMs * pixelsPerSecond.
    let width: CGFloat
    /// Pixels per second, used to convert drag delta to duration change.
    let pixelsPerSecond: CGFloat
    /// Called when the trailing edge is dragged to resize; provides new durationMs.
    var onResize: ((Int) -> Void)?

    @GestureState private var resizeDragOffset: CGFloat = 0

    private let mouseMoveHeight: CGFloat = 24
    private let defaultHeight: CGFloat = 32
    private let resizeHandleWidth: CGFloat = 6

    var body: some View {
        let blockHeight = step.type == .mouseMove ? mouseMoveHeight : defaultHeight
        let borderWidth: CGFloat = isSelected ? 2 : 1
        let borderOpacity: Double = isSelected ? 1.0 : 0.6
        let bgOpacity: Double = 0.3
        let displayWidth = max(20, width + resizeDragOffset)

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(stepColor.opacity(bgOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(stepColor.opacity(borderOpacity), lineWidth: borderWidth)
                )

            HStack(spacing: Spacing.xs) {
                Image(systemName: stepIcon)
                    .font(.system(size: 10))
                    .foregroundColor(stepColor)
                    .frame(width: 12)

                if width > 40 {
                    Text(step.description)
                        .font(Typography.footnote)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.primary.opacity(0.85))
                }
            }
            .padding(.horizontal, Spacing.xs)

            // Resize handle on trailing edge
            HStack {
                Spacer()
                resizeHandle(blockHeight: blockHeight)
            }
        }
        .frame(width: displayWidth, height: blockHeight)
    }

    // MARK: - Resize Handle

    @ViewBuilder
    private func resizeHandle(blockHeight: CGFloat) -> some View {
        let dragGesture = DragGesture(minimumDistance: 2)
            .updating($resizeDragOffset) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                let deltaPx = value.translation.width
                let deltaMs = Int((deltaPx / pixelsPerSecond) * 1000)
                let newDurationMs = max(100, step.durationMs + deltaMs)
                onResize?(newDurationMs)
            }

        Rectangle()
            .fill(Color.white.opacity(0.3))
            .frame(width: resizeHandleWidth, height: blockHeight * 0.6)
            .cornerRadius(2)
            .padding(.trailing, 2)
            .contentShape(Rectangle().size(CGSize(width: resizeHandleWidth + 4, height: blockHeight)))
            .gesture(dragGesture)
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    // MARK: - Step Color

    private var stepColor: Color {
        switch step.type {
        case .activateApp:
            return .green
        case .click, .doubleClick:
            return .blue
        case .rightClick:
            return .orange
        case .mouseMove, .mouseDown, .mouseUp:
            return .gray
        case .scroll:
            return .purple
        case .keyboard, .typeText:
            return .yellow
        case .wait:
            return .gray
        }
    }

    // MARK: - Step Icon

    private var stepIcon: String {
        switch step.type {
        case .activateApp:
            return "app.badge.checkmark"
        case .click:
            return "cursorarrow.click"
        case .doubleClick:
            return "cursorarrow.click.2"
        case .rightClick:
            return "contextualmenu.and.cursorarrow"
        case .mouseMove:
            return "arrow.right"
        case .mouseDown:
            return "arrow.down"
        case .mouseUp:
            return "arrow.up"
        case .scroll:
            return "arrow.up.arrow.down"
        case .keyboard:
            return "keyboard"
        case .typeText:
            return "character.cursor.ibeam"
        case .wait:
            return "clock"
        }
    }
}
