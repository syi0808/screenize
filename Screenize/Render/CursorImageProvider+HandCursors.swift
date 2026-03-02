import Foundation
import CoreGraphics
import CoreImage

extension CursorImageProvider {

    // MARK: - Pointer

    func renderPointer(pixelHeight: CGFloat) -> CIImage? {
        let designW: CGFloat = 19
        let designH: CGFloat = 24
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        // Pointing hand — simplified outline
        let path = CGMutablePath()
        // Index finger
        path.move(to: CGPoint(x: 7.0, y: 1.0))
        path.addLine(to: CGPoint(x: 5.5, y: 1.0))
        path.addCurve(to: CGPoint(x: 4.5, y: 3.0),
                      control1: CGPoint(x: 4.5, y: 1.0),
                      control2: CGPoint(x: 4.5, y: 2.0))
        path.addLine(to: CGPoint(x: 4.5, y: 10.0))
        // Thumb side
        path.addLine(to: CGPoint(x: 2.5, y: 10.5))
        path.addCurve(to: CGPoint(x: 1.0, y: 12.5),
                      control1: CGPoint(x: 1.5, y: 10.5),
                      control2: CGPoint(x: 1.0, y: 11.5))
        path.addLine(to: CGPoint(x: 1.0, y: 14.0))
        // Palm bottom
        path.addCurve(to: CGPoint(x: 3.0, y: 21.0),
                      control1: CGPoint(x: 1.0, y: 17.0),
                      control2: CGPoint(x: 1.5, y: 19.5))
        path.addCurve(to: CGPoint(x: 8.0, y: 23.0),
                      control1: CGPoint(x: 4.5, y: 22.5),
                      control2: CGPoint(x: 6.0, y: 23.0))
        path.addLine(to: CGPoint(x: 13.0, y: 23.0))
        path.addCurve(to: CGPoint(x: 17.5, y: 19.0),
                      control1: CGPoint(x: 15.5, y: 23.0),
                      control2: CGPoint(x: 17.5, y: 21.5))
        path.addLine(to: CGPoint(x: 17.5, y: 12.5))
        // Other fingers
        path.addLine(to: CGPoint(x: 17.5, y: 10.5))
        path.addCurve(to: CGPoint(x: 16.0, y: 9.0),
                      control1: CGPoint(x: 17.5, y: 9.5),
                      control2: CGPoint(x: 17.0, y: 9.0))
        path.addCurve(to: CGPoint(x: 14.5, y: 10.5),
                      control1: CGPoint(x: 15.0, y: 9.0),
                      control2: CGPoint(x: 14.5, y: 9.5))
        path.addLine(to: CGPoint(x: 14.5, y: 9.0))
        path.addCurve(to: CGPoint(x: 13.0, y: 7.5),
                      control1: CGPoint(x: 14.5, y: 8.0),
                      control2: CGPoint(x: 14.0, y: 7.5))
        path.addCurve(to: CGPoint(x: 11.5, y: 9.0),
                      control1: CGPoint(x: 12.0, y: 7.5),
                      control2: CGPoint(x: 11.5, y: 8.0))
        path.addLine(to: CGPoint(x: 11.5, y: 8.5))
        path.addCurve(to: CGPoint(x: 10.0, y: 7.0),
                      control1: CGPoint(x: 11.5, y: 7.5),
                      control2: CGPoint(x: 11.0, y: 7.0))
        path.addCurve(to: CGPoint(x: 8.5, y: 8.5),
                      control1: CGPoint(x: 9.0, y: 7.0),
                      control2: CGPoint(x: 8.5, y: 7.5))
        path.addLine(to: CGPoint(x: 8.5, y: 3.0))
        path.addCurve(to: CGPoint(x: 7.0, y: 1.0),
                      control1: CGPoint(x: 8.5, y: 2.0),
                      control2: CGPoint(x: 8.5, y: 1.0))
        path.closeSubpath()

        // Shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.5),
            blur: 3.0,
            color: CGColor(gray: 0, alpha: 0.3)
        )
        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()

        return ciImage(from: ctx)
    }

    // MARK: - Open Hand

    func renderOpenHand(pixelHeight: CGFloat) -> CIImage? {
        let designW: CGFloat = 20
        let designH: CGFloat = 20
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        let path = CGMutablePath()
        // Palm body
        path.move(to: CGPoint(x: 4.0, y: 8.0))
        // Left side of palm
        path.addLine(to: CGPoint(x: 4.0, y: 13.0))
        path.addCurve(to: CGPoint(x: 5.5, y: 17.5),
                      control1: CGPoint(x: 4.0, y: 15.0),
                      control2: CGPoint(x: 4.5, y: 16.5))
        path.addCurve(to: CGPoint(x: 10.0, y: 19.0),
                      control1: CGPoint(x: 6.5, y: 18.5),
                      control2: CGPoint(x: 8.0, y: 19.0))
        path.addCurve(to: CGPoint(x: 14.5, y: 17.5),
                      control1: CGPoint(x: 12.0, y: 19.0),
                      control2: CGPoint(x: 13.5, y: 18.5))
        path.addCurve(to: CGPoint(x: 16.0, y: 13.0),
                      control1: CGPoint(x: 15.5, y: 16.5),
                      control2: CGPoint(x: 16.0, y: 15.0))
        // Right side fingers
        path.addLine(to: CGPoint(x: 16.0, y: 7.0))
        path.addCurve(to: CGPoint(x: 15.0, y: 5.5),
                      control1: CGPoint(x: 16.0, y: 6.0),
                      control2: CGPoint(x: 15.5, y: 5.5))
        path.addCurve(to: CGPoint(x: 14.0, y: 7.0),
                      control1: CGPoint(x: 14.5, y: 5.5),
                      control2: CGPoint(x: 14.0, y: 6.0))
        path.addLine(to: CGPoint(x: 14.0, y: 5.5))
        path.addCurve(to: CGPoint(x: 13.0, y: 4.0),
                      control1: CGPoint(x: 14.0, y: 4.5),
                      control2: CGPoint(x: 13.5, y: 4.0))
        path.addCurve(to: CGPoint(x: 12.0, y: 5.5),
                      control1: CGPoint(x: 12.5, y: 4.0),
                      control2: CGPoint(x: 12.0, y: 4.5))
        path.addLine(to: CGPoint(x: 12.0, y: 4.0))
        path.addCurve(to: CGPoint(x: 10.5, y: 2.0),
                      control1: CGPoint(x: 12.0, y: 3.0),
                      control2: CGPoint(x: 11.5, y: 2.0))
        path.addCurve(to: CGPoint(x: 9.0, y: 4.0),
                      control1: CGPoint(x: 9.5, y: 2.0),
                      control2: CGPoint(x: 9.0, y: 3.0))
        path.addLine(to: CGPoint(x: 9.0, y: 3.5))
        path.addCurve(to: CGPoint(x: 7.5, y: 1.5),
                      control1: CGPoint(x: 9.0, y: 2.5),
                      control2: CGPoint(x: 8.5, y: 1.5))
        path.addCurve(to: CGPoint(x: 6.0, y: 3.5),
                      control1: CGPoint(x: 6.5, y: 1.5),
                      control2: CGPoint(x: 6.0, y: 2.5))
        path.addLine(to: CGPoint(x: 6.0, y: 8.5))
        // Thumb
        path.addLine(to: CGPoint(x: 5.0, y: 9.5))
        path.addCurve(to: CGPoint(x: 4.0, y: 8.0),
                      control1: CGPoint(x: 4.5, y: 9.5),
                      control2: CGPoint(x: 4.0, y: 9.0))
        path.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.0),
            blur: 2.0,
            color: CGColor(gray: 0, alpha: 0.25)
        )
        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()

        return ciImage(from: ctx)
    }

    // MARK: - Closed Hand

    func renderClosedHand(pixelHeight: CGFloat) -> CIImage? {
        let designW: CGFloat = 18
        let designH: CGFloat = 18
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        let path = CGMutablePath()
        // Closed fist shape
        path.move(to: CGPoint(x: 4.0, y: 7.0))
        // Knuckles
        path.addCurve(to: CGPoint(x: 5.0, y: 5.0),
                      control1: CGPoint(x: 4.0, y: 6.0),
                      control2: CGPoint(x: 4.5, y: 5.0))
        path.addCurve(to: CGPoint(x: 6.0, y: 5.5),
                      control1: CGPoint(x: 5.5, y: 5.0),
                      control2: CGPoint(x: 6.0, y: 5.0))
        path.addLine(to: CGPoint(x: 6.5, y: 4.5))
        path.addCurve(to: CGPoint(x: 8.0, y: 3.5),
                      control1: CGPoint(x: 6.5, y: 3.5),
                      control2: CGPoint(x: 7.0, y: 3.5))
        path.addCurve(to: CGPoint(x: 9.0, y: 4.5),
                      control1: CGPoint(x: 8.5, y: 3.5),
                      control2: CGPoint(x: 9.0, y: 4.0))
        path.addLine(to: CGPoint(x: 9.5, y: 4.0))
        path.addCurve(to: CGPoint(x: 11.0, y: 3.5),
                      control1: CGPoint(x: 9.5, y: 3.0),
                      control2: CGPoint(x: 10.0, y: 3.5))
        path.addCurve(to: CGPoint(x: 12.0, y: 5.0),
                      control1: CGPoint(x: 11.5, y: 3.5),
                      control2: CGPoint(x: 12.0, y: 4.0))
        path.addLine(to: CGPoint(x: 12.5, y: 4.5))
        path.addCurve(to: CGPoint(x: 14.0, y: 4.0),
                      control1: CGPoint(x: 12.5, y: 3.5),
                      control2: CGPoint(x: 13.0, y: 4.0))
        path.addCurve(to: CGPoint(x: 15.0, y: 5.5),
                      control1: CGPoint(x: 14.5, y: 4.0),
                      control2: CGPoint(x: 15.0, y: 4.5))
        // Right side
        path.addLine(to: CGPoint(x: 15.0, y: 12.0))
        path.addCurve(to: CGPoint(x: 13.5, y: 16.0),
                      control1: CGPoint(x: 15.0, y: 14.0),
                      control2: CGPoint(x: 14.5, y: 15.5))
        path.addCurve(to: CGPoint(x: 9.5, y: 17.0),
                      control1: CGPoint(x: 12.5, y: 16.5),
                      control2: CGPoint(x: 11.0, y: 17.0))
        path.addCurve(to: CGPoint(x: 5.5, y: 16.0),
                      control1: CGPoint(x: 8.0, y: 17.0),
                      control2: CGPoint(x: 6.5, y: 16.5))
        path.addCurve(to: CGPoint(x: 4.0, y: 12.0),
                      control1: CGPoint(x: 4.5, y: 15.5),
                      control2: CGPoint(x: 4.0, y: 14.0))
        path.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.0),
            blur: 2.0,
            color: CGColor(gray: 0, alpha: 0.25)
        )
        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setFillColor(CGColor.black)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()

        return ciImage(from: ctx)
    }

    // MARK: - Context Menu

    func renderContextMenu(pixelHeight: CGFloat) -> CIImage? {
        // Context menu cursor: arrow + small menu icon to the right
        let designW: CGFloat = 25
        let designH: CGFloat = 25
        let scale = pixelHeight / designH
        let width = Int(ceil(designW * scale))
        let height = Int(ceil(designH * scale))

        guard let ctx = makeContext(width: width, height: height) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        // Draw arrow part (same as arrow cursor)
        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: 1.5, y: 1.0))
        arrowPath.addLine(to: CGPoint(x: 1.5, y: 18.5))
        arrowPath.addLine(to: CGPoint(x: 5.5, y: 14.5))
        arrowPath.addLine(to: CGPoint(x: 9.5, y: 22.5))
        arrowPath.addLine(to: CGPoint(x: 12.0, y: 21.5))
        arrowPath.addLine(to: CGPoint(x: 8.0, y: 13.5))
        arrowPath.addLine(to: CGPoint(x: 13.5, y: 13.5))
        arrowPath.closeSubpath()

        // Shadow for arrow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.5),
            blur: 3.0,
            color: CGColor(gray: 0, alpha: 0.35)
        )
        ctx.setFillColor(CGColor.black)
        ctx.addPath(arrowPath)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setFillColor(CGColor.black)
        ctx.addPath(arrowPath)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.addPath(arrowPath)
        ctx.strokePath()

        // Mini menu icon (top-right area)
        let menuX: CGFloat = 14.0
        let menuY: CGFloat = 2.0
        let menuW: CGFloat = 10.0
        let menuH: CGFloat = 10.0
        let menuRect = CGRect(x: menuX, y: menuY, width: menuW, height: menuH)
        let menuPath = CGPath(roundedRect: menuRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)

        ctx.setFillColor(CGColor.black)
        ctx.addPath(menuPath)
        ctx.fillPath()
        ctx.setStrokeColor(CGColor.white)
        ctx.setLineWidth(1.0)
        ctx.addPath(menuPath)
        ctx.strokePath()

        // Menu lines
        let lineInset: CGFloat = 2.0
        let lineSpacing: CGFloat = 2.5
        ctx.setStrokeColor(CGColor(gray: 0.8, alpha: 1.0))
        ctx.setLineWidth(0.8)
        for i in 0..<3 {
            let lineY = menuY + 2.5 + CGFloat(i) * lineSpacing
            ctx.move(to: CGPoint(x: menuX + lineInset, y: lineY))
            ctx.addLine(to: CGPoint(x: menuX + menuW - lineInset, y: lineY))
        }
        ctx.strokePath()

        return ciImage(from: ctx)
    }
}
