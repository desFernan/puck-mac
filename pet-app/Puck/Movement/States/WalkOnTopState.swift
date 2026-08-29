//
//  WalkOnTopState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  WalkOnTop state's StateHandler implementation
//
//  Strolls along a window's top edge until the window stops being there —
//  closed, minimized, or simply walked off the end of. Both are the same
//  situation: nothing underfoot (the transition table hands WalkOnTop to
//  Fall when the supporting window goes away or is minimized).
//
//  Reuses the "walk" clip; the manifest has no dedicated one.

import CoreGraphics
import Foundation

final class WalkOnTopState: StateHandler {
    let name = "WalkOnTop"
    let clipKey = "walk"
    let loopsClip = true

    /// Resolved on the first update() after enter() -- Climb always arrives
    /// at whichever edge is nearer the approach direction (WalkState.swift
    /// walks up to a window's left edge approaching from the left, right
    /// edge approaching from the right), so walking a hardcoded direction
    /// from there could walk straight back off the very edge just climbed.
    private var direction: CGFloat?
    private var oneShot = OneShotTransition()

    func enter() {
        oneShot.reset()
        direction = nil
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }

        guard let window = WindowSupport.supportingWindow(under: context.body.position, in: context.windows) else {
            // Logged because this is the one transition whose cause is
            // invisible from the outside: the pet just drops, and whether that
            // was "the window closed" (correct) or "the window list stopped
            // reporting the window it is standing on" (a bug) cannot be told
            // apart by watching. ClimbHandoffTests covers the geometry; this
            // covers the live data those tests can't see.
            let nearby = context.windows.prefix(6).map {
                "[\(Int($0.frame.minX))..\(Int($0.frame.maxX)) top=\(Int($0.frame.minY)) \($0.ownerName ?? "?")]"
            }.joined(separator: " ")
            AppLogger.shared.log(.warning, "WalkOnTop fell: pet=(\(Int(context.body.position.x)),\(Int(context.body.position.y))) windows=\(context.windows.count) \(nearby)")
            oneShot.fire(.fall, using: context.requestTransition)
            return
        }

        var resolvedDirection = direction ?? Self.initialDirection(position: context.body.position, windowFrame: window.frame)
        var nextX = context.body.position.x + resolvedDirection * context.walkSpeed * CGFloat(dt)

        // Turning around at the screen edge, the way a wander target already
        // stays clear of it (AppDelegate+Wander.roamEdgeMargin). A window
        // reaching the edge of the display has no end to walk off, so without
        // this the pet walked into the edge and stayed there, still playing
        // the walk clip -- looking like it was trying to leave the screen
        // (2026-08-22).
        let limits = Self.walkableX(in: context.roamableArea, visualBounds: context.visualBounds)
        // The same guard CeilingState has: an oversized avatar (Settings'
        // size slider on a narrow area) has no x where it fits, so the range
        // collapses to a point and every frame is "outside" it -- the pet
        // stands pinned while its facing flips at the frame rate.
        let fits = !ScreenBounds.isOversizedHorizontally(
            visualBounds: context.visualBounds,
            in: context.roamableArea
        )
        if fits, nextX < limits.lowerBound || nextX > limits.upperBound {
            resolvedDirection = -resolvedDirection
            nextX = context.body.position.x + resolvedDirection * context.walkSpeed * CGFloat(dt)
        }
        direction = resolvedDirection

        context.body.facing = resolvedDirection > 0 ? .right : .left
        context.body.position = CGPoint(
            x: min(max(nextX, limits.lowerBound), limits.upperBound),
            y: window.frame.minY
        )
    }

    /// The x a pet may stand at with its whole body on screen. Empty-safe:
    /// an area narrower than the pet collapses to a single point rather than
    /// an invalid range.
    private static func walkableX(in area: CGRect, visualBounds: CGRect) -> ClosedRange<CGFloat> {
        let low = area.minX - visualBounds.minX
        let high = area.maxX - visualBounds.maxX
        return low...max(low, high)
    }

    /// Walk into the window from whichever edge is nearer, not off the side
    /// just climbed.
    private static func initialDirection(position: CGPoint, windowFrame: CGRect) -> CGFloat {
        let distanceToLeftEdge = abs(position.x - windowFrame.minX)
        let distanceToRightEdge = abs(position.x - windowFrame.maxX)
        return distanceToLeftEdge <= distanceToRightEdge ? 1 : -1
    }
}
