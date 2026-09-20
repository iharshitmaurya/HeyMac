//  The island's outline: a rounded body with two concave "ears" at the top that
//  blend it into the menu bar. `style` picks a plain capsule-like shape instead for
//  Macs without a notch.
//
//  Only the two radii animate; `style` is fixed for a given screen.

import SwiftUI

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var style: NotchPanelStyle = .notch

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { (topRadius, bottomRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        style == .notch ? notchOutline(in: rect) : capsuleOutline(in: rect)
    }

    /// The body is a continuous-corner rectangle inset by the ear width on each side;
    /// each ear is a small concave wedge that reaches out to the rect's top corner.
    /// Ears overlap the body by a point (same winding) so no hairline shows between them.
    private func notchOutline(in rect: CGRect) -> Path {
        let ear = max(0, min(topRadius, rect.width / 2))
        let corner = max(0, min(bottomRadius, min(rect.width / 2 - ear, rect.height)))
        let overlap: CGFloat = 1

        let body = CGRect(x: rect.minX + ear, y: rect.minY, width: rect.width - 2 * ear, height: rect.height)
        var path = UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: corner,
            bottomTrailingRadius: corner, topTrailingRadius: 0,
            style: .continuous
        ).path(in: body)

        // Left ear.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: body.minX + overlap, y: rect.minY))
        path.addLine(to: CGPoint(x: body.minX + overlap, y: rect.minY + ear))
        path.addLine(to: CGPoint(x: body.minX, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                          control: CGPoint(x: body.minX, y: rect.minY))
        path.closeSubpath()

        // Right ear.
        path.move(to: CGPoint(x: body.maxX - overlap, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: body.maxX, y: rect.minY + ear),
                          control: CGPoint(x: body.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: body.maxX - overlap, y: rect.minY + ear))
        path.closeSubpath()
        return path
    }

    private func capsuleOutline(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let top = max(0, min(topRadius, limit))
        let bottom = max(0, min(bottomRadius, limit))
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top,
            style: .continuous
        ).path(in: rect)
    }
}
