//
//  CeilingState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Ceiling state's StateHandler implementation.
//
//  F3 ceiling-crawling (2026-07-29): crawls upside-down along the roamable
//  area's top edge, reversing direction at its horizontal bounds instead of
//  falling off the end (unlike WalkOnTopState, which does fall off a
//  window's edge -- there is no "edge of the ceiling" to walk off of, only
//  the screen's own bounds). Reuses the "walk" clip, same as WalkOnTop.
//
//  isUpsideDown is set every frame rather than once on entry: enter() has no
//  StateContext/body access (see StateHandler.swift), so a per-frame set-if-
//  changed guarded by CharacterBody itself is simpler than tracking a
//  separate "have I flipped yet" flag here.
//

import CoreGraphics
import Foundation

final class CeilingState: StateHandler {
    let name = "Ceiling"
    let clipKey = "walk"
    let loopsClip = true
    let preservesUpsideDown = true

    private let durationProvider: () -> TimeInterval
    private var direction: CGFloat = 1
    private var elapsed: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var oneShot = OneShotTransition()

    init(durationProvider: @escaping () -> TimeInterval = { TimeInterval.random(in: 3...8) }) {
        self.durationProvider = durationProvider
    }

    func enter() {
        oneShot.reset()
        elapsed = 0
        duration = durationProvider()
        direction = 1
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }

        context.body.isUpsideDown = true

        elapsed += dt
        guard elapsed < duration else {
            oneShot.fire(.fall, using: context.requestTransition)
            return
        }

        // Turns around where the pet's artwork meets the edge, not where its
        // centre does -- ScreenBounds owns that limit for every state, so a
        // ceiling crawl reverses at the same place a walk stops. Measuring it
        // here instead used to turn the pet with half of it off-screen, which
        // CharacterController's containment backstop then pulled back on the
        // same frame: the turn and the render disagreed.
        // The ceiling of the display the pet is on, not the top of the box
        // around every display: with a taller monitor beside this one, that
        // box's top edge is somewhere off this screen entirely, and a crawl
        // aimed at it takes the pet off the top of the screen it is on.
        let area = context.area(at: context.body.position)
        // Where the pet is going, and how high the ceiling is *there*. A
        // MacBook's camera housing hangs into this room once the menu bar is
        // out of the way, and a crawl that kept aiming at the screen's own
        // top edge walks the pet straight through it -- see ScreenNotch.
        let travelledX = context.body.position.x + direction * context.walkSpeed * CGFloat(dt)
        let travelled = CGPoint(x: travelledX, y: context.ceilingY(atX: travelledX, on: area))
        // Contained horizontally against the display, then dropped to the
        // ceiling at wherever containment actually put it: pinning at a wall
        // and reading the ceiling from before the pin disagree by a step, and
        // at the notch's edge a step is the difference between hugging it and
        // clipping the corner.
        let pinned = ScreenBounds.contain(travelled, visualBounds: context.visualBounds, in: area)
        let contained = CGPoint(x: pinned.x, y: context.ceilingY(atX: pinned.x, on: area))
        // An oversized avatar (Settings' size slider) has no position where
        // it actually fits -- `contain` always pins to leftLimit regardless
        // of `travelled`, so comparing against it would flip `direction`
        // every frame forever instead of settling.
        if contained.x != travelled.x, !ScreenBounds.isOversizedHorizontally(visualBounds: context.visualBounds, in: area) {
            direction = -direction
        }

        context.body.facing = direction > 0 ? .right : .left
        context.body.position = contained
    }
}
