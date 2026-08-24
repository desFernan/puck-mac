//
//  CursorVelocityTracker.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  How fast the cursor is moving, smoothed enough to throw something with.
//
//  Extracted from ReactDragState when the toy became throwable too -- the
//  pet and the toy have
//  to agree about what "flicked hard" means, or the same gesture launches
//  them at different speeds.
//
//  Raw frame-to-frame deltas are far too jumpy to throw with: the cursor
//  routinely stalls for a frame mid-drag, and releasing on one of those would
//  drop the thing straight down after an obvious hard flick. The exponential
//  average is frame-rate independent -- `1 - exp(-rate * dt)` closes the same
//  fraction of the gap per unit time however the time was divided into
//  samples, which matters here because mouse events do not arrive on a clock.
//

import CoreGraphics
import Foundation

struct CursorVelocityTracker {
    /// How quickly older samples are forgotten, 1/sec. Roughly an 80ms
    /// window: long enough that one stuttering frame can't decide the throw,
    /// short enough that only the final flick counts and not the leisurely
    /// dragging that came before it.
    static let smoothingRate: CGFloat = 12

    /// px/sec, smoothed. Zero until there are two samples to compare.
    private(set) var velocity: CGPoint = .zero

    private var previousPosition: CGPoint?

    /// Start over — no history, no velocity. Call when a new grab begins, so
    /// the last throw's speed can't leak into it.
    mutating func reset() {
        velocity = .zero
        previousPosition = nil
    }

    mutating func track(to position: CGPoint, dt: TimeInterval) {
        defer { previousPosition = position }
        guard let previousPosition, dt > 0 else { return }

        let sample = CGPoint(
            x: (position.x - previousPosition.x) / CGFloat(dt),
            y: (position.y - previousPosition.y) / CGFloat(dt)
        )
        let weight = 1 - exp(-Self.smoothingRate * CGFloat(dt))
        velocity = CGPoint(
            x: velocity.x + (sample.x - velocity.x) * weight,
            y: velocity.y + (sample.y - velocity.y) * weight
        )
    }
}
