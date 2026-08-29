//
//  MovementSolver.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Pure motion arithmetic for MoveTo/Walk/Fall.
//
//  F3: "물리엔진 없음. MoveTo 등속(px/sec) + 도착 반경,
//  Fall만 낙하 가속도". Kept free of any entity/state so the arithmetic is
//  testable on its own — the states below it only decide *when* to call this.
//
//  All positions are GlobalScreenSpace pixels: top-left origin, Y increasing
//  downward. Gravity therefore adds to Y.
//

import CoreGraphics
import Foundation

enum MovementSolver {
    /// Default walking speed, px/sec.
    static let walkSpeed: CGFloat = 90
    /// Default gravity, px/sec². High enough that even a short fall (off a
    /// window's top edge) picks up real speed within roughly a window's
    /// height, instead of staying floaty for the whole drop the way a gentler
    /// value does over so short a distance.
    ///
    static let gravity: CGFloat = 2400
    /// The speed a fall settles at, px/sec — what air resistance does to a
    /// real falling object, and the reason a dropped ball reads as descending
    /// steadily rather than ever faster, the way a real thrown ball does.
    ///
    /// Uncapped, the pet spends the last quarter of a long drop moving 35px a
    /// frame, which reads as it being yanked onto the floor rather than
    /// landing on it. The pairing matters: gravity stays high so a short fall
    /// off a window edge still gets up to speed within its own height, and
    /// this keeps a long fall from running away past that same speed.
    static let terminalVelocity: CGFloat = 1200
    /// How close counts as "there".
    static let arrivalRadius: CGFloat = 2
    /// Fastest the pet can be thrown, px/sec. A flick of the wrist can move the cursor
    /// several thousand px/sec, which would fire the pet off the far edge of
    /// the screen before the eye can follow it; this crosses a display in
    /// roughly half a second, which still reads as a hard throw.
    static let maxThrowSpeed: CGFloat = 2500
    /// How fast horizontal speed decays once the pet has touched the ground
    /// after a bounce -- a slide
    /// to a stop, not an instant one, is what makes a landing read as bouncy
    /// rather than stopping dead. Frame-rate-independent exponential
    /// decay, same idiom as ReactDragState's cursor-velocity smoothing.
    static let groundFrictionRate: CGFloat = 3.0
    struct Step: Equatable {
        let position: CGPoint
        let hasArrived: Bool
    }

    struct FallStep: Equatable {
        let position: CGPoint
        let velocity: CGFloat
        let hasLanded: Bool
        /// True the frame gravity brought the pet down onto (or into) the
        /// landing surface, whether that produced a bounce or the final rest
        /// -- false throughout ordinary free fall. FallState uses this to
        /// know when to start applying ground friction to horizontal speed.
        let touchedFloor: Bool
    }

    /// One constant-velocity frame toward `target`.
    ///
    /// The travelled distance is clamped to the remaining distance: at high
    /// speed or after a long frame the pet would otherwise fly past the target
    /// and oscillate around it, never landing inside `arrivalRadius`.
    static func step(
        from position: CGPoint,
        toward target: CGPoint,
        speed: CGFloat = walkSpeed,
        dt: TimeInterval,
        arrivalRadius: CGFloat = arrivalRadius
    ) -> Step {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = hypot(dx, dy)

        guard distance > arrivalRadius else {
            return Step(position: position, hasArrived: true)
        }

        let travel = speed * CGFloat(dt)
        guard travel < distance else {
            return Step(position: target, hasArrived: true)
        }

        // Normalize so diagonal motion isn't 1.41x faster than axis-aligned.
        let moved = CGPoint(x: position.x + dx / distance * travel, y: position.y + dy / distance * travel)
        return Step(position: moved, hasArrived: false)
    }

    /// `velocity` with its magnitude capped at `maxThrowSpeed`, keeping its
    /// direction. Capped along the throw's own direction rather than per
    /// axis, so clamping a hard diagonal slows it without also bending where
    /// it goes.
    static func cappedThrow(_ velocity: CGPoint, maxSpeed: CGFloat = maxThrowSpeed) -> CGPoint {
        let speed = hypot(velocity.x, velocity.y)
        guard speed > maxSpeed else { return velocity }

        let scale = maxSpeed / speed
        return CGPoint(x: velocity.x * scale, y: velocity.y * scale)
    }

    /// Which way the character should face to head toward `target`, or nil for
    /// purely vertical motion (climbing must not flip it).
    static func facing(from position: CGPoint, toward target: CGPoint) -> AvatarFacing? {
        let dx = target.x - position.x
        guard dx != 0 else { return nil }
        return dx > 0 ? .right : .left
    }

    /// One accelerating frame of free fall, settling at `terminalVelocity`.
    /// `landingY` stops the pet on a surface instead of sinking through it
    /// when a frame overshoots.
    static func fallStep(
        position: CGPoint,
        velocity: CGFloat,
        gravity: CGFloat = gravity,
        dt: TimeInterval,
        landingY: CGFloat? = nil,
        terminalVelocity: CGFloat = terminalVelocity,
        // Defaults to the original "stop dead on contact" behavior --
        // BallPhysics's drop reuses this same function with its own
        // separate bounce/juggle mechanics already tuned around landing
        // meaning "resting", so it must not start bouncing too. Only
        // FallState (the pet itself) opts in.
        bounceOnLanding: Bool = false
    ) -> FallStep {
        let newVelocity = min(velocity + gravity * CGFloat(dt), terminalVelocity)
        let newY = position.y + newVelocity * CGFloat(dt)

        guard let landingY, newY >= landingY else {
            return FallStep(position: CGPoint(x: position.x, y: newY), velocity: newVelocity, hasLanded: false, touchedFloor: false)
        }

        guard bounceOnLanding else {
            return FallStep(position: CGPoint(x: position.x, y: landingY), velocity: 0, hasLanded: true, touchedFloor: true)
        }

        // ScreenBounds.bounceOffFloor rests for real once the damped speed
        // drops below its own threshold, so this needs no separate "how many
        // bounces" bookkeeping here.
        let bounce = ScreenBounds.bounceOffFloor(position: CGPoint(x: position.x, y: newY), velocity: newVelocity, floorY: landingY)
        return FallStep(position: bounce.position, velocity: bounce.velocity, hasLanded: bounce.velocity == 0, touchedFloor: true)
    }

    /// Ground friction applied to horizontal speed once FallState has
    /// touched down -- a slide that
    /// decays to a stop, rather than either staying constant forever or
    /// dropping to zero the instant contact happens. Snaps to exactly zero
    /// once negligible so a fall doesn't drift forever at an imperceptible
    /// speed.
    static func applyGroundFriction(_ velocity: CGFloat, dt: TimeInterval) -> CGFloat {
        let decayed = velocity * CGFloat(exp(-groundFrictionRate * dt))
        return abs(decayed) < 1 ? 0 : decayed
    }
}
