//
//  IslandShape.swift
//  Puck
//
//  The island's outline: a panel whose top edge steps up once, where there is
//  room for it to.
//
//  The window's toolbar buttons float in a group at the left; to their right
//  the whole band is empty. A rectangle stopping below that band leaves a
//  strip of nothing across the top of the window, so the island rises into it
//  -- but only past where the buttons end, and it climbs with a curve rather
//  than a step, which is the part that reads as liquid rather than as two
//  rectangles glued together.
//
//  Where the buttons end is measured, not assumed: the toolbar reports its
//  own trailing edge (GlobalFrameReporter), so adding or removing a button
//  moves the shoulder with it.
//

import SwiftUI

struct IslandShape: InsettableShape {
    /// The panel's corners, all four of them.
    var cornerRadius: CGFloat
    /// How far the raised part rises above the rest of the top edge. Zero
    /// draws a plain rounded rectangle, which is what happens when there is
    /// nowhere to rise into.
    var rise: CGFloat
    /// Where the rise begins, in this shape's own space. Clamped into the
    /// rect: a shoulder that starts past the right edge is no shoulder, and
    /// one that starts before the left edge is a taller island.
    var shoulderStart: CGFloat
    /// Set by `inset(by:)` when the shape is asked to stroke its own border,
    /// so the line lands inside the fill rather than straddling it.
    var insetAmount: CGFloat = 0

    /// How much horizontal run the climb takes. Longer than the rise itself,
    /// so the curve leans rather than turning a corner.
    ///
    /// Settled by eye against the real window, then fixed here.
    static let blend: CGFloat = 48

    var blend: CGFloat = IslandShape.blend

    /// Animatable so the shoulder slides rather than jumps when the sidebar
    /// is collapsed and the island's own left edge moves under the buttons.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(rise, shoulderStart) }
        set {
            rise = newValue.first
            shoulderStart = newValue.second
        }
    }

    /// The blend, as the path uses it: never wider than the space between the
    /// corners, or the climb would start inside one of them.
    private func run(in rect: CGRect, radius: CGFloat) -> CGFloat {
        max(1, min(blend, rect.width - radius * 2))
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(cornerRadius, rect.height / 2, rect.width / 2)
        let rise = max(0, min(self.rise, rect.height - radius * 2))
        // Kept clear of both corners: a climb that starts inside the rounded
        // corner has no straight edge to leave from. Whether there is room at
        // all is asked of the value that came in, not of the clamped one --
        // clamping first turns "starts past the right edge" into "starts just
        // inside it", which is the one case that must not rise.
        let run = run(in: rect, radius: radius)
        let room = rect.maxX - radius - run
        let raised = rise > 0 && shoulderStart <= room
        let start = min(max(shoulderStart, rect.minX + radius), room)
        let lowTop = rect.minY + rise

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: lowTop + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: lowTop),
            tangent2End: CGPoint(x: rect.minX + radius, y: lowTop),
            radius: radius
        )
        if raised {
            path.addLine(to: CGPoint(x: start, y: lowTop))
            // One curve for the whole climb, its control points on the two
            // levels: the top and bottom of the step stay flat right up to
            // where the curve takes over.
            path.addCurve(
                to: CGPoint(x: start + run, y: rect.minY),
                control1: CGPoint(x: start + run * 0.55, y: lowTop),
                control2: CGPoint(x: start + run * 0.45, y: rect.minY)
            )
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
                radius: radius
            )
        } else {
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: lowTop),
                tangent2End: CGPoint(x: rect.maxX, y: lowTop + radius),
                radius: radius
            )
        }
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius),
            radius: radius
        )
        path.closeSubpath()
        return path
    }
}
