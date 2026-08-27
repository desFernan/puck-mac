//
//  CharacterController.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Drives update(dt) every frame; runs and transitions the current StateHandler.
//

import CoreGraphics
import Foundation


/// Drives and transitions the current StateHandler. On every state entry,
/// AvatarPlayable.play and SFXTriggering.trigger are always called together
/// from the same spot (enterCurrentState) — 02_pet-app.md F3's shared "enter()" requirement.
/// `@MainActor`, like the states it drives: the frame loop hops onto the main
/// thread and everything below this line moves a character AppKit is drawing.
@MainActor
final class CharacterController {
    private(set) var currentState: StateHandler
    private let body: CharacterBody
    private let sfxPlayer: SFXTriggering

    /// StateKind -> the one long-lived instance for that kind. States are
    /// reused rather than recreated so their timers survive (see EventRouter's
    /// note); a kind with nothing registered is simply not reachable.
    private var states: [StateKind: StateHandler] = [:]

    /// Where the pet may roam: one area per display, or the single rect of
    /// its tank while it is in one. Set at bootstrap and refreshed when the
    /// display configuration, the Space or the client's island changes.
    ///
    /// A list rather than a rectangle because two displays are not one: the
    /// box around them contains space belonging to neither, and a pet put
    /// there is off every screen (see ScreenGround).
    var roamableAreas: [CGRect] = [] {
        didSet { roamableArea = ScreenGround.union(roamableAreas) }
    }

    /// The camera housing on the display the pet is on, when there is one.
    /// Set by whoever measures the screens; nil on every Mac without a notch,
    /// which is most of them.
    var notch: ScreenNotch?

    /// The box around `roamableAreas`. What horizontal containment measures
    /// against, so a throw can still cross from one display to the next.
    private(set) var roamableArea: CGRect = .zero
    /// Kept in sync with the live avatar's rendered height -- see
    /// StateContext.avatarHeight.
    var avatarHeight: CGFloat = 0
    /// Kept in sync with Settings' movement-speed slider -- see
    /// StateContext.walkSpeed.
    var walkSpeed: CGFloat = MovementSolver.walkSpeed
    var landingY: (CGPoint) -> CGFloat = { _ in .zero }
    /// Refreshed from F4 every frame by the bootstrap wiring.
    var windows: () -> [WindowInfo] = { [] }
    /// See StateContext.unclimbableWindowIDs. A closure, not a stored set, for
    /// the same reason `windows` is one: which window has focus changes while
    /// the pet is walking, and so does the setting behind it.
    var unclimbableWindows: () -> Set<CGWindowID> = { [] }

    /// The unprompted "가끔씩" voice line while the pet is standing around.
    /// Ticked only in Idle -- see IdleChatter. Its keys are filled in at
    /// bootstrap from the avatar's own sounds table.
    let idleChatter = IdleChatter()

    /// A state asking to be replaced. Applied after update() returns so a
    /// state never swaps itself out mid-frame.
    private var pendingTransition: StateKind?
    /// A state handed straight to `transition(to:)` while an update was
    /// running, applied at the end of it. Distinct from `pendingTransition`,
    /// which is the same thing named by kind.
    private var pendingState: StateHandler?
    /// True for the duration of `update(dt:)`, so a transition asked for
    /// inside it is deferred rather than taken mid-frame.
    private var isUpdating = false

    /// Seconds since the current state was entered -- reset on every
    /// transition, fed to AvatarPlayable.updateBounce so the 2D bounce
    /// motion (BouncePreset) knows where in its cycle to be (02_pet-app.md F2).
    private var stateElapsedTime: TimeInterval = 0

    init(initialState: StateHandler, body: CharacterBody, sfxPlayer: SFXTriggering) {
        self.currentState = initialState
        self.body = body
        self.sfxPlayer = sfxPlayer
        enterCurrentState()
    }

    func register(_ state: StateHandler, as kind: StateKind) {
        states[kind] = state
        if kind == .idle { idleState = state }
    }

    /// The display `point` is on -- see StateContext.area(at:), which is the
    /// same question asked from inside a frame.
    func area(at point: CGPoint) -> CGRect {
        ScreenGround.area(at: point, in: roamableAreas) ?? roamableArea
    }

    /// Cached at register time -- update(dt:) asks "is the pet idle?" every
    /// frame, and the answer never changes after bootstrap.
    private var idleState: StateHandler?

    /// Transition by kind — how states and EventRouter reactions ask, since
    /// neither holds concrete instances.
    func transition(to kind: StateKind) {
        guard let state = states[kind] else {
            // Silent otherwise: a StateKind added later without a matching
            // register(_:as:) call at bootstrap would strand the pet in its
            // current state with zero diagnostic.
            AppLogger.shared.log(.error, "transition(to:) requested unregistered StateKind \(kind) -- ignored")
            return
        }
        transition(to: state)
    }

    /// Allows transitioning from any state to any state (tools/events/PTT/click
    /// can all interrupt at any time — see the section 3 transition table).
    ///
    /// A transition asked for *during* `update(dt:)` is deferred to the end of
    /// that update rather than taken immediately. The rest of update -- screen
    /// containment, the elapsed-time clock, the bounce clip -- is written
    /// against the state that was running when the frame began, and swapping
    /// it out from under them mid-frame runs the new state's first frame with
    /// the old one's bookkeeping. That was previously true only because every
    /// caller inside a state happened to go through `requestTransition`;
    /// anything reaching for this method directly (a tool handler called from
    /// a state, say) broke it silently. Now the rule holds whoever asks.
    func transition(to newState: StateHandler) {
        guard newState !== currentState || newState.restartsOnReentry else { return }
        guard !isUpdating else {
            pendingState = newState
            return
        }
        currentState.exit()
        currentState = newState
        enterCurrentState()
    }

    func update(dt: TimeInterval) {
        let context = StateContext(
            body: body,
            roamableArea: roamableArea,
            roamableAreas: roamableAreas,
            notch: notch,
            avatarHeight: avatarHeight,
            visualBounds: body.visualBounds,
            walkSpeed: walkSpeed,
            windows: windows(),
            unclimbableWindowIDs: unclimbableWindows(),
            landingY: landingY,
            requestTransition: { [weak self] kind in self?.pendingTransition = kind }
        )
        isUpdating = true
        currentState.update(dt: dt, context: context)

        // Idle only: a line dropped mid-walk or mid-tool-run reads as the pet
        // talking over itself, and the timer running down while it's busy
        // would make one land the instant it settles.
        if currentState === idleState, let key = idleChatter.tick(dt: dt) {
            sfxPlayer.trigger(key, loop: false)
        }

        // The backstop for "펫이 화면 밖으로 나가지 못하게": states that bounce
        // (Fall) or clamp deliberately have already had their say, and this
        // catches every other route out of the screen — a drag carried past
        // the edge, a wander target near a corner, an avatar that just grew
        // via the size slider. Horizontal only: vertical placement is owned
        // by landing surfaces and the ceiling, which legitimately sit on the
        // area's own edges.
        body.position = ScreenBounds.contain(body.position, visualBounds: context.visualBounds, in: roamableArea)
        // And the other half of that backstop, which only a second display
        // makes necessary: inside the box is not the same as on a screen.
        // Enforced here rather than in the states that can put the pet there
        // -- a throw, a drag, a monitor unplugged mid-walk, and whatever
        // state gets written next -- because missing one of them costs the
        // pet entirely: it comes to rest in the space between two displays,
        // where nothing draws it and nothing looks for it again.
        if !context.artworkHasGround(at: body.position) {
            body.position = ScreenGround.standable(body.position, visualBounds: context.visualBounds, in: roamableAreas)
        }
        stateElapsedTime += dt
        body.updateBounce(clip: currentState.clipKey, elapsed: stateElapsedTime)

        isUpdating = false
        if let kind = pendingTransition {
            pendingTransition = nil
            transition(to: kind)
        }
        if let state = pendingState {
            pendingState = nil
            transition(to: state)
        }
    }

    private func enterCurrentState() {
        stateElapsedTime = 0
        if !currentState.preservesUpsideDown {
            body.isUpsideDown = false
        }
        body.play(clip: currentState.clipKey, loop: currentState.loopsClip)
        // Use soundKey (defaults to clipKey, e.g. "walk"), not name (e.g. "Walk")
        // — the manifest sounds table is keyed by lowercase clip/event names
        // (protocol section 6), so the capitalized FSM state name never matches.
        sfxPlayer.trigger(currentState.soundKey, loop: currentState.loopsSound)
        currentState.enter()
    }
}
