//
//  ScreenBounds.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Keeps the pet inside the screen, and bounces it off the edges.
//
//  Every state used to clamp (or not) on its own, against the bare position
//  — a point at the character's feet. Since that point is the horizontal
//  centre of the artwork, "inside the roamable area" still left half the pet
//  hanging off the side of the display, and a hard throw could put all of it
//  past the edge before anything noticed.
//
//  The rule lives here so there is one definition of "inside the screen" for
//  walking, falling and being thrown alike, expressed in terms of the pet's
//  own outline (StateContext.visualBounds).
//

import CoreGraphics
import Foundation

enum ScreenBounds {
    /// How much speed survives a bounce. A thrown pet coming off a wall
    /// should visibly lose energy — a perfectly elastic bounce reads as the
    /// pet being batted back and forth forever.
    static let restitution: CGFloat = 0.55
    /// Below this, a bounce is not worth playing: the pet would jitter
    /// against the edge in ever-smaller hops instead of settling.
    static let minimumBounceSpeed: CGFloat = 60
    /// Landing loses more energy per bounce than a wall/ceiling hit does — a
    /// soft flop onto the ground, not a rubber ball off a wall: a couple of
    /// quick, decaying thumps, not a long bouncy rally.
    static let landingRestitution: CGFloat = 0.35
    /// Below this, the pet just rests on the floor rather than playing an
    /// imperceptible micro-bounce.
    static let minimumLandingBounceSpeed: CGFloat = 100

    struct Bounce: Equatable {
        /// The position with the pet's outline pushed back inside.
        var position: CGPoint
        /// The velocity after the bounce — reversed and damped if an edge was
        /// hit, unchanged otherwise.
        var velocity: CGFloat
    }

    /// True when `visualBounds` is wider than `area` -- there's no position
    /// where the avatar fits, so `contain`/`bounceHorizontally` always pin to
    /// `leftLimit` regardless of input. A caller comparing its own pre-pin
    /// position against that pinned result (to detect a bounce, e.g.
    /// CeilingState reversing direction) would see a mismatch every single
    /// frame and oscillate forever instead of settling -- found via review.
    static func isOversizedHorizontally(visualBounds: CGRect, in area: CGRect) -> Bool {
        (area.minX - visualBounds.minX) > (area.maxX - visualBounds.maxX)
    }

    /// Clamps `position` so `visualBounds` stays inside `area`, without any
    /// velocity involved. For states that move under their own power (walk,
    /// climb) and simply must not leave the screen.
    static func contain(_ position: CGPoint, visualBounds: CGRect, in area: CGRect) -> CGPoint {
        // The outline's offsets from the ground point. Symmetric artwork
        // gives -width/2 and +width/2, but nothing requires symmetry.
        let leftLimit = area.minX - visualBounds.minX
        let rightLimit = area.maxX - visualBounds.maxX
        // A pet wider than the screen has no valid position; keeping it
        // pinned to the left edge at least keeps it on screen.
        guard leftLimit <= rightLimit else { return CGPoint(x: leftLimit, y: position.y) }

        return CGPoint(x: min(max(position.x, leftLimit), rightLimit), y: position.y)
    }

    /// One frame of horizontal travel that bounces off the left and right
    /// edges instead of stopping at them.
    static func bounceHorizontally(
        position: CGPoint,
        velocity: CGFloat,
        visualBounds: CGRect,
        in area: CGRect
    ) -> Bounce {
        let leftLimit = area.minX - visualBounds.minX
        let rightLimit = area.maxX - visualBounds.maxX
        guard leftLimit <= rightLimit else {
            return Bounce(position: CGPoint(x: leftLimit, y: position.y), velocity: 0)
        }

        let limit: CGFloat
        if position.x < leftLimit, velocity < 0 {
            limit = leftLimit
        } else if position.x > rightLimit, velocity > 0 {
            limit = rightLimit
        } else {
            return Bounce(position: position, velocity: velocity)
        }

        let reflected = reflect(position.x, at: limit, velocity: velocity)
        return Bounce(position: CGPoint(x: reflected.coordinate, y: position.y), velocity: reflected.velocity)
    }

    /// One frame's worth of upward travel bounced off the top of the screen.
    ///
    /// Only upward motion is handled here: coming back *down* is a landing,
    /// and which surface it lands on is F4's business (a window top edge, the
    /// Dock, the floor), not a screen edge. The limit is where the pet's head
    /// — the top of its outline — meets the top of the area, so a tall avatar
    /// bounces sooner than a short one.
    static func bounceOffCeiling(
        position: CGPoint,
        velocity: CGFloat,
        visualBounds: CGRect,
        in area: CGRect
    ) -> Bounce {
        // Y grows downward, so upward velocity is negative and the pet's head
        // sits at position.y + visualBounds.minY (a negative offset).
        let topLimit = area.minY - visualBounds.minY
        guard velocity < 0, position.y < topLimit else {
            return Bounce(position: position, velocity: velocity)
        }

        let reflected = reflect(position.y, at: topLimit, velocity: velocity)
        return Bounce(position: CGPoint(x: position.x, y: reflected.coordinate), velocity: reflected.velocity)
    }

    /// One frame of downward travel that bounces off a landing surface
    /// instead of stopping dead on it — a hard landing, e.g. after being
    /// thrown and bouncing off
    /// a wall, should visibly bounce a couple of times before it settles,
    /// not freeze the instant it touches down. `floorY` is F4's landing
    /// surface (a window top edge or the screen bottom), not a fixed area
    /// edge — dynamic the same way ceiling/wall bounces aren't.
    static func bounceOffFloor(position: CGPoint, velocity: CGFloat, floorY: CGFloat) -> Bounce {
        guard velocity > 0, position.y >= floorY else {
            return Bounce(position: position, velocity: velocity)
        }

        let reflected = reflect(
            position.y, at: floorY, velocity: velocity,
            restitution: landingRestitution, minimumBounceSpeed: minimumLandingBounceSpeed
        )
        return Bounce(position: CGPoint(x: position.x, y: reflected.coordinate), velocity: reflected.velocity)
    }

    /// The bounce itself, on whichever single axis is hitting an edge — the
    /// arithmetic is one-dimensional, so the callers own the CGPoint and this
    /// stays free of any left/right/up/down special cases. `restitution`/
    /// `minimumBounceSpeed` default to the wall/ceiling tuning; bounceOffFloor
    /// passes its own, lossier pair.
    ///
    /// A returned velocity of 0 means the bounce ran out of energy and the
    /// thing has come to rest against the edge -- which is how a caller that
    /// tracks its own phase (BallPhysics) knows to settle.
    static func reflect(
        _ coordinate: CGFloat,
        at limit: CGFloat,
        velocity: CGFloat,
        restitution: CGFloat = Self.restitution,
        minimumBounceSpeed: CGFloat = Self.minimumBounceSpeed
    ) -> (coordinate: CGFloat, velocity: CGFloat) {
        let speed = abs(velocity) * restitution
        guard speed >= minimumBounceSpeed else {
            // Out of energy: rest against the edge rather than buzzing on it.
            // Off the ceiling that means dropping away from it immediately,
            // which gravity does on the very next frame.
            return (limit, 0)
        }
        // Reflected about the edge, so a frame that overshot deep past the
        // wall comes back out as far as it went in -- landing exactly on the
        // limit instead would swallow part of the movement and make a fast
        // bounce visibly lose ground.
        return (2 * limit - coordinate, velocity < 0 ? speed : -speed)
    }
}
