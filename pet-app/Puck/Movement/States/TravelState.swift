//
//  TravelState.swift
//  Puck
//
//  Being carried from one world to the other -- desktop to tank, or back.
//
//  The move used to be a cut: fade out, set the position, fade in. It read as
//  the pet vanishing and a copy appearing somewhere else, which is not what
//  moving house looks like. This glides it across instead, so the eye follows
//  one pet the whole way.
//
//  Walking there was never an option and still isn't: the route would cross
//  window frames the pet cannot stand on. This is deliberately a flight --
//  the pet is being carried, not walking -- which is why it eases in and out
//  rather than moving at the walk speed.
//

import CoreGraphics
import Foundation

final class TravelState: StateHandler {
    let name = "Travel"
    /// The airborne clip. The pet is off the ground for the whole trip, and
    /// the walk cycle against a flight reads as running on air.
    let clipKey = "fall"
    let loopsClip = true

    /// One trip, ordered as a unit -- see `order(from:to:onProgress:onArrival:)`.
    struct Trip {
        var origin: CGPoint
        var destination: CGPoint
        var onProgress: ((Double) -> Void)?
        var onArrival: (() -> Void)?
    }

    /// The trip as it was ordered, kept so entering can put it back.
    ///
    /// Ordering a second trip while one is in the air means transitioning
    /// into this state again, and re-entry is exit-then-enter: `exit()` clears
    /// the four fields below, which the caller had just filled in. So the
    /// second trip was wiped before its first frame -- `update` found no
    /// origin, took the no-op exit, and neither `onProgress` nor `onArrival`
    /// ever ran.
    ///
    /// What that looked like is the pet shrinking. The size is carried across
    /// on `onProgress` and put back on `onArrival`, so a dropped trip left it
    /// frozen part-way between the two worlds' sizes -- and the next trip home
    /// wrote that half-size down as the size to come back out at. Every fast
    /// alt-tab took another bite.
    private var ordered: Trip?

    /// Set together, immediately before transitioning in.
    var origin: CGPoint?
    var destination: CGPoint?
    /// Short enough not to hold up whatever prompted the move, long enough to
    /// be a movement rather than a jump.
    var duration: TimeInterval = 0.42
    /// Called every frame with the eased progress, so the caller can carry
    /// anything else across on the same curve -- the pet's size shrinks into
    /// the island this way rather than snapping when it lands.
    var onProgress: ((Double) -> Void)?
    /// Called on arrival, before the next state is requested -- the caller
    /// uses it to put `roamableArea` back to the world being arrived in.
    var onArrival: (() -> Void)?

    /// Re-entering restarts the trip.
    ///
    /// The default is not to, which is right for a state whose entry is
    /// expensive or whose timers should survive -- and wrong here: a second
    /// trip is ordered by installing a new origin, destination and callbacks
    /// and then transitioning again. Without a restart the new endpoints were
    /// driven by the *old* elapsed time, so a trip ordered a third of the way
    /// through the last one rendered its first frame two thirds of the way
    /// across the screen. The pet teleported instead of gliding, and its
    /// size lerp jumped with it.
    var restartsOnReentry: Bool { true }

    private var elapsed: TimeInterval = 0
    private var oneShot = OneShotTransition()

    /// Installs the trip to run, and is the only way to start one.
    ///
    /// Through here rather than by setting the four fields, because they do
    /// not survive being re-entered -- see `ordered`.
    func order(
        from origin: CGPoint,
        to destination: CGPoint,
        onProgress: @escaping (Double) -> Void,
        onArrival: @escaping () -> Void
    ) {
        let trip = Trip(origin: origin, destination: destination, onProgress: onProgress, onArrival: onArrival)
        ordered = trip
        apply(trip)
    }

    /// Sends a trip already in the air somewhere else, keeping where it
    /// started and how far along it is. What the island does when the window
    /// it is drawn in moves while the pet is on its way to it.
    func retarget(to destination: CGPoint, onArrival: @escaping () -> Void) {
        guard ordered != nil else { return }
        ordered?.destination = destination
        ordered?.onArrival = onArrival
        self.destination = destination
        self.onArrival = onArrival
    }

    private func apply(_ trip: Trip) {
        origin = trip.origin
        destination = trip.destination
        onProgress = trip.onProgress
        onArrival = trip.onArrival
    }

    func enter() {
        oneShot.reset()
        elapsed = 0
        // Put back whatever the exit on the way in cleared. Nothing else
        // enters this state -- a trip is always ordered immediately before
        // transitioning -- so this can only ever restore the trip that is
        // being started right now.
        if let ordered { apply(ordered) }
    }

    func exit() {
        // Cleared so a stale trip cannot be replayed by a later entry. Only
        // the live copy: `ordered` is what a re-entry restores, and it is
        // dropped when the trip actually completes.
        origin = nil
        destination = nil
        onProgress = nil
        onArrival = nil
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }
        guard let origin, let destination else {
            finish(context)
            return
        }

        elapsed += dt
        let progress = duration > 0 ? min(1, elapsed / duration) : 1
        let eased = Self.eased(progress)
        context.body.position = CGPoint(
            x: origin.x + (destination.x - origin.x) * eased,
            y: origin.y + (destination.y - origin.y) * eased
        )
        if let facing = MovementSolver.facing(from: origin, toward: destination) {
            context.body.facing = facing
        }
        onProgress?(eased)

        if progress >= 1 { finish(context) }
    }

    private func finish(_ context: StateContext) {
        // The end of the same curve, so a trip that arrived in one long frame
        // still lands at the size it was heading for.
        onProgress?(1)
        let arrival = onArrival
        // Consumed here rather than in `exit`: this trip is over, and the
        // transition below is what clears the live copy.
        ordered = nil
        arrival?()
        // Land, not idle: arriving is a landing, and the bounce is what makes
        // the trip end rather than just stop.
        oneShot.fire(.land, using: context.requestTransition)
    }

    /// Smoothstep. Constant speed reads as a machine sliding the pet across;
    /// easing both ends reads as something picking it up and setting it down.
    static func eased(_ t: Double) -> Double {
        let clamped = max(0, min(1, t))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
