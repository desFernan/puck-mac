//
//  AppDelegate+Wander.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Picks wander destinations for IdleState's scheduler -- roam points,
//  climbable windows, and toy interest.
//

import AppKit
import CoreGraphics
import Foundation

extension AppDelegate {
    // MARK: - Wander (F3)

    /// IdleState computes a wander outcome and previously had nowhere to send
    /// it — `wanderDelegate` was never assigned, so the scheduler fired into
    /// the void. Picking the destination needs the roamable area (and, later,
    /// the window list), which is bootstrap knowledge, not state knowledge.
    func idleStateDidRequestWander(_ outcome: WanderScheduler.Outcome) {
        guard let controller = characterController else { return }
        let atHome = desktopRoamableArea != nil
        let outcome = Self.wanderOutcome(outcome, atHome: atHome)
        // Whatever was half-walked is abandoned: the pet has been given
        // something else to do, and finishing the old route afterwards would
        // read as it changing its mind twice.
        if case .walkToRandomPoint = outcome {} else { cancelWander() }
        switch outcome {
        case .walkToRandomPoint:
            // A wander is one to three legs with a beat between them, not one
            // straight line to one point. Drawn here; the rest are started by
            // continueWanderIfNeeded once each leg lands.
            pendingWanderLegs = Self.drawWanderLegs(atHome: atHome) - 1
            wanderLegPause = Self.randomLegPause(atHome: atHome)
            startWanderLeg(controller)
        case .climbNearestWindow:
            // Walk to the nearest climbable window's side; WalkState's own
            // blockingWindow check takes it from there and hands off to Climb.
            // Falls back to roaming when there's nothing to climb, rather
            // than standing still.
            walkState.target = characterBody.flatMap { body in
                let windows = overlayLocalWindows(excluding: nil)
                return WindowSupport.nearestClimbTarget(
                    from: body.position,
                    in: windows,
                    roamableTop: controller.roamableArea.minY,
                    avatarHeight: avatarHitboxSize.height,
                    excluding: unclimbableWindowIDs(in: windows)
                )
            } ?? Self.randomRoamPoint(in: controller.roamableArea, from: self.currentRoamX(in: controller))
            controller.transition(to: .walk)
        case .climbToCeiling:
            // ClimbToCeilingState falls back to .fall on its own if there's no
            // wall underfoot, but that costs one visible frame of the climb
            // clip flashing before it drops -- climbing should only ever
            // happen against an actual on-screen wall, never arbitrary
            // terrain. Checking here avoids ever entering the state
            // without a wall to begin with.
            let ceilingWindows = overlayLocalWindows(excluding: nil)
            guard let body = characterBody,
                  WindowSupport.windowBeingClimbed(
                      at: body.position,
                      in: ceilingWindows,
                      excluding: unclimbableWindowIDs(in: ceilingWindows)
                  ) != nil else {
                walkState.target = Self.randomRoamPoint(in: controller.roamableArea, from: self.currentRoamX(in: controller))
                controller.transition(to: .walk)
                return
            }
            controller.transition(to: .climbToCeiling)
        case .playWithToy:
            // Before this draw, play could only ever start at the moment a toy
            // LANDED -- so a toy the pet had kicked away and walked off from
            // was abandoned for good. Falls back to roaming when nothing is
            // out or nothing has settled yet, same as the climbs do.
            guard !isRestingFromToys,
                  let box = toyBox,
                  let name = ToyInterestPolicy.next(
                      from: box.candidates,
                      lastPlayed: box.lastPlayedName,
                      petPosition: characterBody?.position ?? .zero
                  )
            else {
                walkState.target = Self.randomRoamPoint(in: controller.roamableArea, from: self.currentRoamX(in: controller))
                controller.transition(to: .walk)
                return
            }
            startPlaying(with: ToyCatalogue.toy(named: name))
        case .stay:
            break
        }
    }

    /// Settings' "포커스된 창 위로는 올라가지 않기" toggle, resolved against the
    /// window list the pet is currently walking through. Empty while the
    /// toggle is off, so the pet climbs whatever it reaches.
    ///
    /// The reader the setting never had: `avoidClimbingFocusedWindow` was
    /// written by the Settings panel and consulted by nothing, so the toggle
    /// changed nothing at all. Same shape as `autoMuteOnFocus`'s reader in
    /// AppDelegate+OverlayAvatar -- read fresh at the moment the decision is
    /// made rather than cached, since the panel writes it while the pet runs.
    /// The pet's footing went behind a window the user just brought forward.
    ///
    /// It still falls: the surface it was standing on really did go away, and
    /// dropping is what that looks like. Where it lands is the part that was
    /// wrong -- the window that took the footing usually covers the floor too,
    /// and the pet draws above every window, so it came to rest on top of the
    /// user's content (2026-08-22). `perchAfterLandingIfNeeded` picks it up
    /// from there, once the fall is over.
    func idleStateDidLoseFootingBehind(_ window: WindowInfo) {
        cancelWander()
        pendingPerchWindowID = window.windowID
        characterController?.transition(to: .fall)
    }

    /// Moves a pet that landed inside a window up onto its top edge. Called
    /// from the frame loop because the decision belongs *after* the fall, and
    /// nothing else reports a landing.
    ///
    /// The title bar is the one place left on a window that covers the screen:
    /// its sides leave no room for a pet, and every spot below is the user's
    /// content. Deliberately not gated on "포커스된 창 위로는 올라가지 않기" --
    /// that setting is there to keep the pet off the work you are looking at,
    /// which is the same thing this move is for.
    func perchAfterLandingIfNeeded() {
        guard let windowID = pendingPerchWindowID,
              let controller = characterController,
              let body = characterBody,
              controller.currentState === idleState
        else {
            return
        }
        pendingPerchWindowID = nil

        let windows = overlayLocalWindows(excluding: nil)
        guard let window = windows.first(where: { $0.windowID == windowID }),
              // It may have come down somewhere clear after all -- a window
              // that stops above the floor, a pet that fell past its edge.
              WindowSupport.coveringWindow(
                  standingAt: body.position,
                  petHeight: avatarHitboxSize.height,
                  in: windows
              )?.windowID == windowID,
              let perch = WindowSupport.perchTarget(
                  on: window,
                  from: body.position,
                  roamableTop: controller.roamableArea.minY,
                  avatarHeight: avatarHitboxSize.height,
                  petHalfWidth: avatarHitboxSize.width / 2
              )
        else {
            return
        }
        moveToState.target = perch
        controller.transition(to: .moveTo)
    }

    func unclimbableWindowIDs(in windows: [WindowInfo]) -> Set<CGWindowID> {
        guard settingsStore.avoidClimbingFocusedWindow else { return [] }
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let focused = WindowSupport.focusedWindow(ownedBy: focusedPID, in: windows) else { return [] }
        return [focused.windowID]
    }

    /// How much of each side of the screen wander targets stay out of, as a
    /// fraction of its width. Targeting the literal edges meant a good share
    /// of wanders ended with the pet pressed into a corner, where it then sat
    /// until the next timer -- and screen-edge containment holds it there
    /// exactly, so it reads as being stuck rather than as having wandered.
    /// It can still be *carried* or thrown into a corner; it just won't
    /// choose one.
    nonisolated static let roamEdgeMargin: CGFloat = 0.08

    /// Where the next wander goes, drawn as a *distance from where the pet
    /// already is* rather than as a point anywhere on screen.
    ///
    /// Uniform over the whole width, almost every draw landed far away, so
    /// the pet spent its life crossing the screen end to end at one speed --
    /// the same trip over and over. A distance draw gives mostly short
    /// shuffles with the occasional long trip, which is what reads as
    /// wandering rather than commuting.
    ///
    /// Static and pure so the distribution is testable without a screen.
    nonisolated static func randomRoamPoint(in area: CGRect, from currentX: CGFloat) -> CGPoint {
        guard area.width > 0 else { return .zero }
        let margin = area.width * roamEdgeMargin
        let low = area.minX + margin
        let high = max(low, area.maxX - margin)

        let range = CGFloat.random(in: 0...1) < longTripChance ? longTripDistance : shortHopDistance
        let distance = CGFloat.random(in: range) * area.width
        let step = Bool.random() ? distance : -distance

        // Reflected off the ends rather than clamped: clamping piles every
        // over-long draw onto the same two x values, which is the metronome
        // this is meant to break.
        var x = currentX + step
        if x < low { x = low + (low - x) }
        if x > high { x = high - (x - high) }
        return CGPoint(x: min(max(x, low), high), y: area.maxY)
    }

    /// What the pet may do where it currently is. Climbing and the ceiling are
    /// desktop-only: a climb aims at the window list, which is the desktop's
    /// however small the pet's world is right now, so a pet in its tank would
    /// set off at a window outside its own glass. A 90pt strip has no ceiling
    /// worth crawling along either.
    nonisolated static func wanderOutcome(
        _ outcome: WanderScheduler.Outcome,
        atHome: Bool
    ) -> WanderScheduler.Outcome {
        guard atHome else { return outcome }
        switch outcome {
        case .climbNearestWindow, .climbToCeiling: return .walkToRandomPoint
        case .walkToRandomPoint, .playWithToy, .stay: return outcome
        }
    }

    /// One leg of a wander: somewhere nearby, at a slightly different pace
    /// each time.
    private func startWanderLeg(_ controller: CharacterController) {
        varyWalkSpeed()
        walkState.target = Self.randomRoamPoint(in: controller.roamableArea, from: currentRoamX(in: controller))
        controller.transition(to: .walk)
    }

    /// Starts the next leg once the previous one has landed and the pause has
    /// run out. Called every frame; does nothing the rest of the time.
    ///
    /// Driven from the frame loop because nothing reports an arrival: Walk
    /// hands back to Idle on its own, and Idle's next draw is 8-15s away --
    /// which is the gap that made a wander read as one trip and a long sit.
    func continueWanderIfNeeded(dt: TimeInterval) {
        guard pendingWanderLegs > 0,
              let controller = characterController,
              controller.currentState === idleState
        else {
            return
        }
        wanderLegPause -= dt
        guard wanderLegPause <= 0 else { return }
        pendingWanderLegs -= 1
        wanderLegPause = Self.randomLegPause(atHome: desktopRoamableArea != nil)
        startWanderLeg(controller)
    }

    /// Drops whatever legs are left. Anything that takes the pet over --
    /// another wander outcome, a tool, a fall behind a window -- calls this,
    /// or the pet would resume a walk nobody asked for any more.
    func cancelWander() {
        pendingWanderLegs = 0
        wanderLegPause = 0
    }

    /// Mostly one leg, sometimes two, now and then three. More than that and
    /// the pet never settles.
    /// On the island it walks further per wander: the shelf is small enough
    /// that one leg of it is barely a step, and the pet is being watched
    /// there rather than glanced at.
    nonisolated static func drawWanderLegs(atHome: Bool = false) -> Int {
        let roll = CGFloat.random(in: 0...1)
        if atHome {
            if roll < 0.3 { return 2 }
            return roll < 0.75 ? 3 : 4
        }
        if roll < 0.55 { return 1 }
        return roll < 0.85 ? 2 : 3
    }

    /// Long enough to read as the pet stopping to look at something, short
    /// enough that the walk still feels like one wander. Shorter on the
    /// island, where the legs themselves are short.
    nonisolated static func randomLegPause(atHome: Bool = false) -> TimeInterval {
        atHome ? .random(in: 0.2...0.7) : .random(in: 0.4...1.4)
    }

    /// Where the pet is now, or the middle of the area before there is a
    /// body to ask -- a wander drawn without one has nothing to be relative to.
    private func currentRoamX(in controller: CharacterController) -> CGFloat {
        characterBody?.position.x ?? controller.roamableArea.midX
    }

    /// As a fraction of the roamable width.
    nonisolated private static let shortHopDistance: ClosedRange<CGFloat> = 0.05...0.3
    nonisolated private static let longTripDistance: ClosedRange<CGFloat> = 0.3...0.8
    /// Most wanders are short; now and then the pet crosses the room.
    nonisolated private static let longTripChance: CGFloat = 0.25

    /// A little slower or quicker each time, so repeated walks don't look
    /// like the same clip replayed. Applied per wander, on top of Settings'
    /// movement slider, and overwritten by the code tour's own speed while
    /// one is running (restoreWalkSpeed).
    private func varyWalkSpeed() {
        characterController?.walkSpeed = MovementSolver.walkSpeed
            * settingsStore.walkSpeedMultiplier
            * CGFloat.random(in: 0.8...1.25)
    }
}
