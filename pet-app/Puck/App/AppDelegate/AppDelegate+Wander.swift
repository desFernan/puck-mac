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
        let atHome = desktopRoamableAreas != nil
        let outcome = Self.wanderOutcome(
            outcome,
            atHome: atHome,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        // Whatever was half-walked is abandoned: the pet has been given
        // something else to do, and finishing the old route afterwards would
        // read as it changing its mind twice.
        if case .walkToRandomPoint = outcome {} else { cancelWander() }
        switch outcome {
        case .walkToRandomPoint:
            // A wander is one to three legs with a beat between them, not one
            // straight line to one point. Drawn here; the rest are started by
            // continueWanderIfNeeded once each leg lands.
            wanderRun.begin(atHome: atHome)
            startWanderLeg(controller)
        case .climbNearestWindow:
            // Walk to the nearest climbable window's side; WalkState's own
            // blockingWindow check takes it from there and hands off to Climb.
            // Falls back to roaming when there's nothing to climb, rather
            // than standing still.
            states.walk.target = characterBody.flatMap { body in
                let windows = overlayLocalWindows(excluding: nil)
                return WindowSupport.nearestClimbTarget(
                    from: body.position,
                    in: windows,
                    roamableTop: petArea(controller).minY,
                    avatarHeight: avatarHitboxSize.height,
                    excluding: unclimbableWindowIDs(in: windows)
                )
            } ?? self.randomRoamPoint(controller)
            controller.transition(to: .walk)
        case .climbToCeiling:
            // ClimbToCeilingState falls back to .fall on its own if there's no
            // wall underfoot, but that costs one visible frame of the climb
            // clip flashing before it drops -- climbing should only ever
            // happen against an actual on-screen wall, never arbitrary
            // terrain. Checking here avoids ever entering the state
            // without a wall to begin with.
            let ceilingWindows = overlayLocalWindows(excluding: nil)
            guard let body = characterBody else { return }
            let ceilingArea = petArea(controller)
            guard WindowSupport.hasWall(
                at: body.position,
                visualBounds: body.visualBounds,
                in: ceilingWindows,
                area: ceilingArea,
                excluding: unclimbableWindowIDs(in: ceilingWindows)
            ) else {
                // Nothing underfoot to climb, so walk to something first --
                // the same walk `.climbNearestWindow` makes, remembering that
                // the ceiling is where this was going.
                //
                // It used to give up here and roam instead, which made this
                // outcome very nearly unreachable: the pet is idle on the
                // floor or on a window's top, and being pressed against a
                // wall while idle is a coincidence. Measured over three
                // minutes on a normal desktop, the draw came up twice and had
                // nothing to climb either time -- so the ceiling crawl, and
                // everything up there, was drawn and thrown away.
                pendingCeilingClimb = true
                states.walk.target = WindowSupport.nearestClimbTarget(
                    from: body.position,
                    in: ceilingWindows,
                    roamableTop: ceilingArea.minY,
                    avatarHeight: avatarHitboxSize.height,
                    excluding: unclimbableWindowIDs(in: ceilingWindows)
                ) ?? Self.nearestScreenEdge(from: body.position, visualBounds: body.visualBounds, in: ceilingArea)
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
                states.walk.target = self.randomRoamPoint(controller)
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

    /// Whichever side of the screen is closer, at the pet's own height.
    ///
    /// The fallback wall: always there, and the one that cannot be closed or
    /// moved out from under the pet on the way over.
    /// Where the pet's feet go for its outline to meet that edge -- the same
    /// place containment would put it, so the walk arrives rather than being
    /// clamped a step short of its own target forever.
    nonisolated static func nearestScreenEdge(
        from position: CGPoint,
        visualBounds: CGRect,
        in area: CGRect
    ) -> CGPoint {
        let left = position.x - area.minX
        let right = area.maxX - position.x
        let x = left <= right ? area.minX - visualBounds.minX : area.maxX - visualBounds.maxX
        return CGPoint(x: x, y: position.y)
    }

    /// Sends a climb that a wander meant for the ceiling all the way up.
    ///
    /// Called every frame, and does nothing the rest of the time -- the same
    /// shape `perchAfterLandingIfNeeded` uses, and for the same reason:
    /// nothing reports an arrival, so the moment has to be noticed.
    ///
    /// Two moments, because there are two kinds of wall. Walking into a
    /// *window's* side is intercepted by WalkState itself, which hands off to
    /// Climb the frame it makes contact, so the pet is never idle there to be
    /// caught. Walking to the *screen's* edge is blocked by nothing, so it
    /// simply arrives and stands still.
    func climbToCeilingWhenAtAWall() {
        guard pendingCeilingClimb, let controller = characterController else { return }
        let arrived = controller.currentState === states.idle
        let alreadyClimbing = controller.currentState === states.climb
        guard arrived || alreadyClimbing else { return }
        pendingCeilingClimb = false

        // Asked again here rather than trusted from the draw: the walk takes
        // a moment, and a window it was aimed at can be closed or moved
        // during it. With nothing to hold, the pet stays where it walked to
        // -- which is what it would have done anyway.
        guard let body = characterBody else { return }
        let windows = overlayLocalWindows(excluding: nil)
        guard WindowSupport.hasWall(
            at: body.position,
            visualBounds: body.visualBounds,
            in: windows,
            area: petArea(controller),
            excluding: unclimbableWindowIDs(in: windows)
        ) else {
            return
        }
        controller.transition(to: .climbToCeiling)
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
              controller.currentState === states.idle
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
                  roamableTop: petArea(controller).minY,
                  avatarHeight: avatarHitboxSize.height,
                  petHalfWidth: avatarHitboxSize.width / 2
              )
        else {
            return
        }
        states.moveTo.target = perch
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
    /// `area` is the display the pet is on, which is what the distance is
    /// drawn against -- a wander is a stroll across the screen in front of
    /// you, and scaling it to the box around three monitors would turn every
    /// long trip into a half-minute commute. `limits` is how far it may
    /// actually end up, which is every display: the pet is allowed to wander
    /// onto the next monitor, it just doesn't set off across two of them in
    /// one leg. Defaults to `area`, i.e. one display, i.e. what this was.
    ///
    /// Static and pure so the distribution is testable without a screen.
    nonisolated static func randomRoamPoint(
        in area: CGRect,
        from currentX: CGFloat,
        limitedTo limits: CGRect? = nil
    ) -> CGPoint {
        guard area.width > 0 else { return .zero }
        let bounds = limits ?? area
        let margin = bounds.width * roamEdgeMargin
        let low = bounds.minX + margin
        let high = max(low, bounds.maxX - margin)

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
    ///
    /// `reduceMotion` is the system setting, and it settles the question
    /// before the rest: a wander is the one thing here nobody asked for. The
    /// pet still walks when it is dragged, thrown, sent somewhere by a tool
    /// or called home to its island -- what stops is it setting off across
    /// the screen on a timer while somebody is trying to read.
    nonisolated static func wanderOutcome(
        _ outcome: WanderScheduler.Outcome,
        atHome: Bool,
        reduceMotion: Bool = false
    ) -> WanderScheduler.Outcome {
        if reduceMotion { return .stay }
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
        states.walk.target = randomRoamPoint(controller)
        controller.transition(to: .walk)
    }

    /// Starts the next leg once the previous one has landed and the pause has
    /// run out. Called every frame; does nothing the rest of the time.
    ///
    /// Driven from the frame loop because nothing reports an arrival: Walk
    /// hands back to Idle on its own, and Idle's next draw is 8-15s away --
    /// which is the gap that made a wander read as one trip and a long sit.
    func continueWanderIfNeeded(dt: TimeInterval) {
        guard wanderRun.isRunning,
              let controller = characterController,
              controller.currentState === states.idle
        else {
            return
        }
        guard wanderRun.tick(dt: dt) else { return }
        startWanderLeg(controller)
    }

    /// Drops whatever legs are left. Anything that takes the pet over --
    /// another wander outcome, a tool, a fall behind a window -- calls this,
    /// or the pet would resume a walk nobody asked for any more.
    func cancelWander() {
        wanderRun.cancel()
        // The climb this was walking toward is part of the same wander, so
        // whatever takes the pet over drops it too -- or the pet arrives
        // somewhere it was sent for another reason and climbs anyway.
        pendingCeilingClimb = false
    }

    /// Where the pet is now, or the middle of the area before there is a
    /// body to ask -- a wander drawn without one has nothing to be relative to.
    private func currentRoamX(in controller: CharacterController) -> CGFloat {
        characterBody?.position.x ?? controller.roamableArea.midX
    }

    /// The display the pet is standing on. Wander draws happen in it rather
    /// than in the box around every display: that box's floor is the lowest
    /// monitor's and parts of it are on no screen at all, so a point drawn
    /// there sends the pet walking down and off its own screen.
    private func petArea(_ controller: CharacterController) -> CGRect {
        controller.area(at: characterBody?.position ?? .zero)
    }

    /// One wander destination: a stroll's worth of distance, anywhere on any
    /// display. WalkState is what stops at an edge with nothing beyond it and
    /// what climbs the step onto a taller monitor, so a target on the display
    /// next door is an ordinary walk rather than a special case.
    private func randomRoamPoint(_ controller: CharacterController) -> CGPoint {
        Self.randomRoamPoint(
            in: petArea(controller),
            from: currentRoamX(in: controller),
            limitedTo: controller.roamableArea
        )
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
