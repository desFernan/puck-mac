//
//  ReactDragState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  ReactDrag state's StateHandler implementation.
//
//  The pet hangs off the cursor while being dragged and drops when let go
//  (a drag puts it in ReactDrag, following the cursor, and releasing hands
//  it to Fall).
//
//  While held, the pet is **not moving** — it is being carried. So this state
//  runs no locomotion at all: no easing, no speed, no MovementSolver. The pet
//  is rigidly attached to the cursor and its position is assigned outright,
//  exactly like dragging a window ("구글 창 같은걸 드래그 할때처럼"). Every
//  earlier version -- eased follow, then a speed-capped follow -- had the pet
//  travelling toward the cursor under its own power, which is what made a fast
//  drag read as the pet chasing the hand instead of being in it.
//
//  The grab offset is captured on the first frame and held for the whole drag,
//  so whatever point you grabbed stays under the cursor and grabbing the pet
//  never jumps it.
//

import CoreGraphics
import Foundation

final class ReactDragState: StateHandler {
    let name = "ReactDrag"
    let clipKey = "react_drag"
    let loopsClip = true

    /// Where the cursor is, in the pet's coordinate space. Updated by whoever
    /// owns the mouse monitor; nil means it hasn't moved since the grab.
    var cursorPosition: CGPoint?

    private var isReleased = false
    private var oneShot = OneShotTransition()
    /// Where the pet sat relative to the cursor when it was grabbed. Held for
    /// the whole drag so the grabbed point stays under the cursor.
    private var grabOffset: CGPoint?
    /// The throw's speed if released now. Shared with the toy's drag so the
    /// same flick launches both at the same speed.
    private var cursorVelocity = CursorVelocityTracker()

    func enter() {
        isReleased = false
        oneShot.reset()
        cursorPosition = nil
        grabOffset = nil
        cursorVelocity.reset()
    }

    /// The mouse came up — stop following and let go on the next frame.
    func release() {
        isReleased = true
    }

    func update(dt: TimeInterval, context: StateContext) {
        if isReleased {
            guard !oneShot.hasFired else { return }
            // Hand the throw to Fall. Let go of a still cursor and this is
            // zero, i.e. the plain straight-down drop it always was.
            context.body.launchVelocity = MovementSolver.cappedThrow(cursorVelocity.velocity)
            // Dropped where it was let go, not wherever the cursor went next.
            oneShot.fire(.fall, using: context.requestTransition)
            return
        }

        guard let cursorPosition else { return }
        cursorVelocity.track(to: cursorPosition, dt: dt)

        // First frame of the grab: remember where the pet sat relative to the
        // cursor and don't move it at all, so grabbing never jumps it.
        guard let grabOffset else {
            grabOffset = CGPoint(x: context.body.position.x - cursorPosition.x, y: context.body.position.y - cursorPosition.y)
            return
        }

        let target = CGPoint(x: cursorPosition.x + grabOffset.x, y: cursorPosition.y + grabOffset.y)
        if let facing = MovementSolver.facing(from: context.body.position, toward: target) {
            context.body.facing = facing
        }
        // Assigned outright, with no speed of its own: while held, the pet is
        // part of the cursor rather than something travelling toward it.
        context.body.position = target
    }

}
