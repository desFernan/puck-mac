//
//  FlipAnimation.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  The turn the pet plays when it changes direction — the sprite narrows to
//  nothing edge-on and opens back out the other way, like a sheet of paper
//  being turned over.
//
//  This used to happen by accident: `position`/`transform` were animating
//  implicitly, so a facing change eased its scaleX from +1 to -1 over Core
//  Animation's default 0.25s and passed through zero on the way. Turning
//  those implicit animations off (they were wrecking the pet's movement --
//  see CALayer+ImplicitAnimations) took the turn with them. It is rebuilt
//  here deliberately instead, which also means it can be a proper flip rather
//  than whatever the default timing curve happened to produce.
//
//  Computed from elapsed time rather than handed to Core Animation, because
//  SpriteAvatar.applyTransform rewrites the layer's transform every frame
//  (procedural bounce) -- an animation attached to the layer would be
//  overwritten on the very next frame.
//

import CoreGraphics
import Foundation

/// The turn is tracked as an **angle**, not as a scale.
///
/// Interpolating the scale directly cannot recover from the halfway point:
/// with the sprite exactly edge-on its scale is 0, and every scale-space
/// formula multiplies through that zero, so a pet told to turn back at that
/// instant would stay edge-on forever. Angles have no such degenerate value
/// — facing right is 0, facing left is π, edge-on is π/2, and turning back
/// from anywhere is just a new target angle.
enum FlipAnimation {
    /// A full 180° turn. Long enough to read as a turn, short enough never to
    /// delay the pet's response to anything — the pet keeps moving
    /// throughout, only its horizontal scale is animated.
    static let duration: TimeInterval = 0.12

    /// The angle a facing settles at. Y-up/down doesn't enter into it: this
    /// is rotation about the sprite's vertical axis.
    static func angle(facing: AvatarFacing) -> CGFloat {
        facing == .left ? .pi : 0
    }

    /// How long a turn between two angles should take, so that a turn already
    /// half done finishes in half the time instead of restarting a full one.
    static func duration(from: CGFloat, to: CGFloat) -> TimeInterval {
        duration * TimeInterval(abs(to - from) / .pi)
    }

    /// The angle `elapsed` seconds into a turn from `from` to `to`.
    static func angle(elapsed: TimeInterval, from: CGFloat, to: CGFloat, duration: TimeInterval) -> CGFloat {
        guard elapsed > 0 else { return from }
        guard duration > 0, elapsed < duration else { return to }

        return from + (to - from) * CGFloat(elapsed / duration)
    }

    /// What that angle looks like head-on. A sheet of paper turning at a
    /// constant angular rate has a projected width of cos(angle), which is
    /// why the sprite lingers near full width and sweeps quickly through
    /// edge-on; a linear scale ramp instead reads as a squash-and-stretch.
    static func horizontalScale(atAngle angle: CGFloat) -> CGFloat {
        cos(angle)
    }
}
