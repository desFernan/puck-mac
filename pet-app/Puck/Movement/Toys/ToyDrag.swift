//
//  ToyDrag.swift
//  Puck
//
//  A toy in somebody's hand: where it was grabbed, and how fast it was
//  moving when they let go.
//
//  The three numbers this holds -- the grab offset, the velocity tracker and
//  the time of the last move -- were three properties on the app delegate,
//  declared where all eighteen of its extensions can see them and touched by
//  exactly one. Swift extensions cannot hold stored properties, which is why
//  they were up there; a type they can belong to is the way down.
//
//  Pure, and it is the arithmetic that is worth pinning: a drag that does not
//  keep the grabbed point under the cursor makes the toy jump the moment it
//  is picked up, which is the sort of thing that looks like physics going
//  wrong rather than like a subtraction going wrong.
//

import CoreGraphics
import Foundation

struct ToyDrag {
    /// Where the toy's own origin sits relative to the point that was
    /// grabbed. Captured once, so whatever the user took hold of stays under
    /// the cursor for the rest of the drag rather than the toy snapping its
    /// centre to the pointer.
    private(set) var grabOffset: CGPoint = .zero

    /// How fast the cursor was moving, which is what the toy is thrown with.
    private var throwVelocity = CursorVelocityTracker()

    /// When the last move was seen, for the interval the tracker needs.
    private var lastMoveTime: TimeInterval?

    /// The velocity to release at. Zero after a still cursor, which is the
    /// plain drop it should be.
    var releaseVelocity: CGPoint { throwVelocity.velocity }

    /// Picking it up. `toyPosition` is nil for a toy that has no position
    /// yet, which grabs it by its own origin.
    mutating func begin(at cursor: CGPoint, toyPosition: CGPoint?, now: TimeInterval) {
        grabOffset = CGPoint(
            x: (toyPosition?.x ?? cursor.x) - cursor.x,
            y: (toyPosition?.y ?? cursor.y) - cursor.y
        )
        throwVelocity.reset()
        lastMoveTime = now
    }

    /// Moving it, and the position to put it at.
    ///
    /// The first move after `begin` has no interval of its own to measure
    /// against, so it reports no speed rather than an infinite one.
    mutating func move(to cursor: CGPoint, now: TimeInterval) -> CGPoint {
        throwVelocity.track(to: cursor, dt: now - (lastMoveTime ?? now))
        lastMoveTime = now
        return CGPoint(x: cursor.x + grabOffset.x, y: cursor.y + grabOffset.y)
    }
}
