//
//  NotchLayer.swift
//  Puck
//
//  The camera housing, painted on a display that has not got one.
//
//  A real notch needs nothing drawn: it is a piece of black plastic, and
//  anything painted there is behind it. A display without one has to be given
//  the shape or the pet ducks around nothing and stops under nothing, which
//  is worse than not having the feature at all.
//
//  Drawn in the overlay, which sits at `.floating` -- below the menu bar.
//  That is the right level rather than a compromise: with the menu bar there
//  the pet's ceiling is already below the housing and it never meets it, so
//  there is nothing to show; in a fullscreen Space the menu bar goes and both
//  the housing and the pet under it appear together.
//
//  The shape is the hardware's: square across the top where it meets the
//  bezel, rounded at the two bottom corners where it juts into the screen.
//

import QuartzCore

enum NotchLayer {
    /// How round the two bottom corners are. A real housing's are about a
    /// third of its depth; squarer reads as a black rectangle somebody left
    /// on the screen.
    static let cornerFraction: CGFloat = 0.34

    /// The housing's outline in a layer of `size`, with the two bottom
    /// corners rounded and the top left square against the bezel.
    static func path(in rect: CGRect) -> CGPath {
        let radius = min(rect.height * cornerFraction, rect.width / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX + radius, y: rect.maxY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }

    /// A layer drawing `notch`, or nil for one that needs no drawing.
    @MainActor
    static func make(for notch: ScreenNotch) -> CAShapeLayer? {
        guard notch.isVirtual else { return nil }
        let layer = CAShapeLayer()
        layer.frame = notch.rect
        // In the layer's own space, so moving the layer never re-derives it.
        layer.path = path(in: CGRect(origin: .zero, size: notch.rect.size))
        layer.fillColor = CGColor(gray: 0, alpha: 1)
        // Behind the pet: the point of a housing is that the pet is in front
        // of it, coming out from under it.
        layer.zPosition = -1
        return layer
    }
}
