//
//  FallState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Fall state's StateHandler implementation.
//
//  The only state with acceleration (plan/02_pet-app.md F3: "물리엔진 없음 …
//  Fall만 낙하 가속도"). The surface comes from StateContext.landingY, which
//  F4's LandingSurfaceResolver answers with a window top edge or the floor.
//
//  Also where a throw plays out. Being thrown is not a state of its own -- it is this same fall
//  with a sideways speed to start with, taken from CharacterBody.launchVelocity
//  on the first frame. Walking off a window leaves that at zero and falls
//  straight down exactly as before.
//

import CoreGraphics
import Foundation

final class FallState: StateHandler {
    let name = "Fall"
    let clipKey = "fall"
    let loopsClip = false

    private var velocity: CGFloat = 0
    private var horizontalVelocity: CGFloat = 0
    private var hasLanded = false
    private var hasTakenLaunchVelocity = false
    /// True once gravity has brought the pet down onto the landing surface
    /// at least once (a bounce or the final rest). Ground friction only applies from here on, so
    /// mid-air/wall-bounce speed during the throw itself is unaffected.
    private var hasTouchedGround = false

    func enter() {
        // From rest every time: carrying the previous fall's velocity would
        // make a second fall start at whatever speed the first ended with.
        velocity = 0
        horizontalVelocity = 0
        hasLanded = false
        hasTouchedGround = false
        // enter() has no context, so the throw is picked up on frame one.
        hasTakenLaunchVelocity = false
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasLanded else { return }

        if !hasTakenLaunchVelocity {
            hasTakenLaunchVelocity = true
            velocity = context.body.launchVelocity.y
            horizontalVelocity = context.body.launchVelocity.x
            // Consumed, so it can't leak into the next, untossed fall.
            context.body.launchVelocity = .zero
        }

        if hasTouchedGround {
            horizontalVelocity = MovementSolver.applyGroundFriction(horizontalVelocity, dt: dt)
        }

        // A fall off the ceiling must land right-side up regardless of which
        // state preceded it (CeilingState is the only one that sets this, but
        // Fall shouldn't need to know that -- it just always restores normal
        // orientation before landing).
        context.body.isUpsideDown = false

        // Sideways first, so the landing surface is looked up under where the
        // pet is about to be rather than where it was -- thrown across the
        // screen it passes over different windows every frame.
        let carried = carriedSideways(from: context.body.position, in: context, dt: dt)
        if let facing = MovementSolver.facing(from: context.body.position, toward: carried) {
            context.body.facing = facing
        }

        let step = MovementSolver.fallStep(
            position: carried,
            velocity: velocity,
            dt: dt,
            landingY: context.landingY(carried),
            bounceOnLanding: true
        )
        if step.touchedFloor {
            hasTouchedGround = true
        }

        // Thrown upward, the pet has to come off the top of the screen the
        // same way it comes off the sides -- otherwise a hard upward throw
        // simply leaves the display. Applied after the fall step so gravity
        // has already been integrated: what bounces is the velocity the pet
        // actually has at the ceiling.
        // Off the top of the display the pet is over, for the same reason
        // CeilingState crawls along that one: the box around several displays
        // has a top edge that can be a monitor away, and a throw bouncing off
        // that one leaves the screen on the way up.
        let ceiling = ScreenBounds.bounceOffCeiling(
            position: step.position,
            velocity: step.velocity,
            visualBounds: context.visualBounds,
            in: context.area(at: step.position)
        )
        context.body.position = ceiling.position
        velocity = ceiling.velocity

        if step.hasLanded {
            hasLanded = true
            context.requestTransition(.land)
        }
    }

    /// One frame of the throw's sideways travel, bouncing off the sides of
    /// the screen. The pet's own outline decides where the wall is, so it
    /// rebounds when its artwork touches the edge rather than when its centre
    /// reaches it — half the pet would already be off-screen by then.
    private func carriedSideways(from position: CGPoint, in context: StateContext, dt: TimeInterval) -> CGPoint {
        // A plain drop needs no clamping here: CharacterController applies
        // ScreenBounds.contain after every state update, and that is the one
        // authoritative definition of "inside the screen".
        guard horizontalVelocity != 0 else { return position }

        let travelled = CGPoint(x: position.x + horizontalVelocity * CGFloat(dt), y: position.y)
        let bounce = ScreenBounds.bounceHorizontally(
            position: travelled,
            velocity: horizontalVelocity,
            visualBounds: context.visualBounds,
            in: context.roamableArea
        )
        horizontalVelocity = bounce.velocity
        return bounce.position
    }
}
