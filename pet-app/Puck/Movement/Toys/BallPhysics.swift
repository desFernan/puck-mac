//
//  BallPhysics.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Pure physics for the ball-toy interaction (02_pet-app.md F12, optional,
//  lowest priority). The drop reuses MovementSolver.fallStep's free-fall
//  arithmetic directly rather than reimplementing it; the kicked-away fling
//  is the one bit of new motion this file adds.
//
//  Kept free of any rendering/window/FSM concerns so the arithmetic is
//  testable on its own -- BallController (or whatever drives it per frame)
//  only decides *when* to call this and what to render.
//
//  2026-07-29: the toy is permanent. It used to be a decorative fling that
//  expired after 1.2s, and separately a head-bonk was meant to make it
//  disappear -- it should stay out and stick around instead, so a kick now
//  always ends by coming to rest somewhere, ready
//  to be chased again. `.gone` survives only as a safety valve for a toy with
//  no surface anywhere below it.
//

import CoreGraphics
import Foundation

enum BallPhase: Equatable {
    /// Dropped and still falling toward a landing surface.
    case falling
    /// Landed, waiting for the pet to kick it.
    case resting
    /// Picked up by the cursor. Physics is suspended entirely -- the toy is
    /// wherever the hand puts it, the same model ReactDrag uses for the pet.
    case held
    /// Held by the PET rather than the cursor -- spinning over its head.
    /// Physics is suspended for the same reason `held` suspends it.
    case carried
    /// Kicked away -- flying off under gravity until its lifetime elapses or
    /// it exits the roamable area.
    case kicked
    /// On a surface and still moving along it. A kick used to end with the
    /// toy stopping dead the instant its bounce ran out, which is the one
    /// moment of the whole interaction that reads as a bug rather than as
    /// physics. Friction takes it from here to `.resting`.
    case rolling
    /// Done -- nothing left to render or simulate.
    case gone
}

struct BallState: Equatable {
    var position: CGPoint
    var verticalVelocity: CGFloat = 0
    var horizontalVelocity: CGFloat = 0
    var phase: BallPhase = .falling
    /// Seconds since entering `.kicked`. Kept for diagnostics; nothing ends a
    /// kick on time any more (see BallPhysics's header).
    var kickedElapsed: TimeInterval = 0
}

enum BallPhysics {
    static let gravity = MovementSolver.gravity
    /// How far outside roamableArea still counts as "worth simulating" before
    /// a kicked ball is considered gone.
    static let outOfBoundsMargin: CGFloat = 200
    /// How much of its sideways speed a toy keeps each time it bounces off
    /// the floor. Nothing touched the horizontal component before, so a
    /// kicked toy crossed the screen at its launch speed however many times
    /// it bounced on the way.
    static let floorFriction: CGFloat = 0.8
    /// How quickly a rolling toy is slowed by the surface, in points per
    /// second squared. The default is a round one; `step` takes it as a
    /// parameter because a wand lying on its side does not roll, it scrapes.
    static let rollingFriction: CGFloat = 900
    /// Below this speed, in points per second, a rolling toy has stopped.
    /// Without a floor the friction curve approaches zero and never reaches
    /// it, leaving a toy that creeps for ever and is never playable again.
    static let restingSpeed: CGFloat = 12

    /// How far a resting toy may sit above its surface before it counts as
    /// having nothing underneath it. Absorbs the rounding of the landing
    /// itself, so a toy that just settled doesn't immediately re-fall.
    static let surfaceTolerance: CGFloat = 0.5

    /// `visualBounds` is the toy's visible outline relative to its position,
    /// so it bounces off a wall when its artwork meets it rather than when
    /// its centre does -- the same rule the pet uses, bouncing off the
    /// screen edge instead of leaving it. Zero means a
    /// point-sized toy, which is what the drawn-circle fallback and the
    /// existing tests assume.
    static func step(
        _ state: BallState,
        dt: TimeInterval,
        landingY: CGFloat,
        roamableArea: CGRect,
        visualBounds: CGRect = .zero,
        rollingFriction: CGFloat = rollingFriction
    ) -> BallState {
        switch state.phase {
        case .falling:
            let fall = MovementSolver.fallStep(
                position: state.position,
                velocity: state.verticalVelocity,
                dt: dt,
                landingY: landingY
            )
            var next = state
            next.position = ScreenBounds.contain(fall.position, visualBounds: visualBounds, in: roamableArea)
            next.verticalVelocity = fall.velocity
            next.phase = fall.hasLanded ? .resting : .falling
            return next

        case .resting:
            // Whatever it was resting on can go away -- most obviously the
            // pet's own head, which walks off leaving the toy floating in
            // place, but
            // equally a window that closes. Without this a resting toy is
            // pinned in the air forever, because nothing else ever re-examines
            // a toy that has already landed.
            //
            // IdleState does exactly this for the pet, for the same reason.
            guard state.position.y < landingY - surfaceTolerance else { return state }
            var next = state
            next.phase = .falling
            return next

        case .held, .carried:
            return state // someone is holding it; nothing else may move it

        case .kicked:
            let newVerticalVelocity = state.verticalVelocity + gravity * CGFloat(dt)
            let travelled = CGPoint(
                x: state.position.x + state.horizontalVelocity * CGFloat(dt),
                y: state.position.y + newVerticalVelocity * CGFloat(dt)
            )

            // Off the sides, then off the ceiling -- the same two edges the
            // pet bounces off when thrown, and the same restitution, so a
            // kicked toy and a thrown pet behave alike.
            let sideways = ScreenBounds.bounceHorizontally(
                position: travelled,
                velocity: state.horizontalVelocity,
                visualBounds: visualBounds,
                in: roamableArea
            )
            let ceiling = ScreenBounds.bounceOffCeiling(
                position: sideways.position,
                velocity: newVerticalVelocity,
                visualBounds: visualBounds,
                in: roamableArea
            )

            var next = state
            next.position = ceiling.position
            next.horizontalVelocity = sideways.velocity
            next.verticalVelocity = ceiling.velocity
            next.kickedElapsed = state.kickedElapsed + dt

            // ...and off the floor. Without this a kicked toy ignored the
            // surface entirely and dropped straight through it and off the
            // bottom of the screen -- which is what "화면 밖으로 나가는데"
            // was: the sides and ceiling were closed, the floor wasn't.
            if next.position.y >= landingY, next.verticalVelocity > 0 {
                // The same reflection every other edge uses, rather than the
                // copy of its arithmetic that used to live here -- two places
                // to change and one of them always forgotten.
                let bounced = ScreenBounds.reflect(next.position.y, at: landingY, velocity: next.verticalVelocity)
                next.position.y = bounced.coordinate
                next.verticalVelocity = bounced.velocity
                // The floor takes some of the sideways speed too, every time.
                next.horizontalVelocity *= floorFriction
                if bounced.velocity == 0 {
                    // Out of bounce, but not necessarily out of motion: what
                    // is left of the sideways speed rolls along the surface.
                    // Stopping dead here is what made a kick end abruptly.
                    if abs(next.horizontalVelocity) > restingSpeed {
                        next.phase = .rolling
                        return next
                    }
                    next.horizontalVelocity = 0
                    next.phase = .resting
                    return next
                }
            }

            // Nothing times out: the toy stays on the desk once thrown.
            // The bounds
            // check is the one remaining way it can end, and with all four
            // edges now closed it only fires when there is no surface under
            // it at all -- a safety valve, not a rule of play.
            let outOfBounds = !roamableArea.insetBy(dx: -outOfBoundsMargin, dy: -outOfBoundsMargin)
                .contains(next.position)
            next.phase = outOfBounds ? .gone : .kicked
            return next

        case .rolling:
            // Rolled off whatever it was on -- a window edge, mostly. Back to
            // the airborne case, which is the one that moves along both axes;
            // `.falling` only moves down and would drop it straight off the
            // edge it was still travelling over.
            guard state.position.y >= landingY - surfaceTolerance else {
                var next = state
                next.phase = .kicked
                next.kickedElapsed = 0
                return next
            }

            var next = state
            let travelled = CGPoint(x: state.position.x + state.horizontalVelocity * CGFloat(dt), y: landingY)
            let sideways = ScreenBounds.bounceHorizontally(
                position: travelled,
                velocity: state.horizontalVelocity,
                visualBounds: visualBounds,
                in: roamableArea
            )
            next.position = sideways.position
            next.verticalVelocity = 0

            // Toward zero from whichever side it is on, and never past it:
            // a friction that overshoots would have the toy roll backwards.
            let slowed = abs(sideways.velocity) - rollingFriction * CGFloat(dt)
            guard slowed > restingSpeed else {
                next.horizontalVelocity = 0
                next.phase = .resting
                return next
            }
            next.horizontalVelocity = slowed * (sideways.velocity < 0 ? -1 : 1)
            next.phase = .rolling
            return next

        case .gone:
            return state
        }
    }

    /// How hard the pet hits a toy, in points per second. Named like every
    /// other tuning value here rather than written into the signatures: these
    /// are the numbers someone comes back to change.
    static let juggleLiftSpeed: CGFloat = 260
    static let kickHorizontalSpeed: CGFloat = 260
    static let kickLiftSpeed: CGFloat = 420

    /// Pops a resting ball straight up, back into `.falling` -- it arcs back
    /// down and lands (`.resting`) the same way a drop does, since a
    /// negative (upward) initial velocity just decelerates under gravity,
    /// peaks, and falls back via the exact same math (2026-07-29, more
    /// interaction variety: a juggle before the final kick-away).
    static func juggle(_ state: BallState, liftSpeed: CGFloat = juggleLiftSpeed) -> BallState {
        var next = state
        next.phase = .falling
        next.verticalVelocity = -liftSpeed
        next.horizontalVelocity = 0
        return next
    }

    /// Launches a resting ball up and in the pet's facing direction, so the
    /// "header" visually reads as sending it forward rather than straight up.
    static func kick(
        _ state: BallState,
        direction: AvatarFacing,
        horizontalSpeed: CGFloat = kickHorizontalSpeed,
        liftSpeed: CGFloat = kickLiftSpeed
    ) -> BallState {
        var next = state
        next.phase = .kicked
        next.kickedElapsed = 0
        next.horizontalVelocity = direction == .right ? horizontalSpeed : -horizontalSpeed
        next.verticalVelocity = -liftSpeed // negative = upward (Y increases downward)
        return next
    }
}
