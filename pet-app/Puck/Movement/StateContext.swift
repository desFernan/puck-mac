//
//  StateContext.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  What a state can see and do during one frame.
//
//  States used to receive nothing but `dt`, so they could neither move the
//  character nor hand control to another state — the transition table had no
//  way to express itself in code. This
//  passes the character and the world it moves through, plus the one way a
//  state asks to be replaced.
//
//  All coordinates are GlobalScreenSpace pixels: top-left origin, Y down.
//

import CoreGraphics

struct StateContext {
    /// Position and facing, already wired to the avatar.
    let body: CharacterBody

    /// The area the pet may roam, normally the box around every display.
    ///
    /// The box, not the displays themselves: `roamableAreas` is the list, and
    /// anything that has to know whether a spot is actually on a screen asks
    /// that instead (see `artworkHasGround(at:)`).
    let roamableArea: CGRect

    /// One area per display -- or the single rect of the pet's tank while it
    /// is in one. Empty means "whoever built this context has only the one
    /// area", which is what every test and every single-display run is, and
    /// the helpers below fall back to `roamableArea` for it.
    var roamableAreas: [CGRect] = []

    /// Every camera housing there is, in the pet's own space.
    ///
    /// Usually none of them are in the pet's way: the roamable area comes
    /// from `visibleFrame`, which has the menu bar subtracted, and on a
    /// notched Mac the menu bar is exactly as tall as the notch. In a
    /// fullscreen Space that height is given back and a housing really is
    /// hanging into the room -- see ScreenNotch.
    var notches: [ScreenNotch] = []

    /// The rendered avatar's current height (manifest hitbox * scale). F3
    /// ceiling-crawling (2026-07-29): ClimbToCeilingState needs this to climb
    /// to where the character's HEAD reaches the ceiling, not its feet --
    /// climbing feet-to-roamableArea.minY while still right-side-up (body
    /// extending upward from the feet) pushes the head off the top of the
    /// screen before "arrival," since there is no room above the literal
    /// screen edge the way there is above a window's top edge.
    let avatarHeight: CGFloat

    /// The pet's visible outline relative to its ground point (see
    /// AvatarPlayable.visualBounds). States clamp and bounce against this
    /// rather than the bare position, so the pet stops when its artwork meets
    /// a screen edge instead of when its centre does.
    let visualBounds: CGRect

    /// px/sec for Walk/Climb/WalkOnTop/MoveTo/Ceiling -- MovementSolver.walkSpeed
    /// scaled by Settings' movement-speed slider.
    let walkSpeed: CGFloat

    /// Layer-0 windows in front-to-back Z order, already converted into the
    /// pet's coordinate space (F4 reports global Quartz frames; AppDelegate
    /// rebases them onto the overlay window before they get here).
    let windows: [WindowInfo]

    /// Windows the pet must not climb, by CGWindowID. Fed by Settings'
    /// "포커스된 창 위로는 올라가지 않기" toggle (F3), which resolves to the
    /// focused window's id while it is on and to nothing while it is off.
    /// They stay in `windows`: the pet still lands on them and still senses
    /// them, it just doesn't scale their sides.
    ///
    /// Defaulted so every existing construction of this context (and every
    /// test that builds one) keeps the previous "climb anything" behaviour.
    var unclimbableWindowIDs: Set<CGWindowID> = []

    /// The surface the pet would land on if it fell straight down from `point`
    /// — a window top edge (F4) or the bottom of the screen. Injected as a
    /// closure so states stay independent of WindowListWatcher.
    let landingY: (CGPoint) -> CGFloat

    /// Asks the FSM to enter another state after this frame. Deferred rather
    /// than immediate so a state never mutates the controller mid-update.
    let requestTransition: (StateKind) -> Void

    /// The housing over `area`, if one of them is.
    ///
    /// Matched by which display it is horizontally over rather than by an
    /// index alongside the areas: a MacBook driving an external monitor has
    /// one housing and two displays, and a pet crawling the external one must
    /// not duck around a housing that is over the other. It also means a
    /// housing that has gone -- lid closed, monitor unplugged -- simply stops
    /// matching, because it is no longer in the list.
    ///
    /// Horizontally, not by overlap: with the menu bar present the housing
    /// sits entirely *above* the roamable area -- that is the whole reason
    /// the pet does not normally meet it -- so an overlap test would find
    /// nothing exactly when there is nothing to find, and also exactly when
    /// there is.
    func notch(over area: CGRect) -> ScreenNotch? {
        notches.first { area.minX <= $0.rect.midX && $0.rect.midX <= area.maxX }
    }

    /// How high the pet may go at `x`: the top of the display it is on, or
    /// the bottom of the housing where a housing is in the way.
    ///
    /// The ceiling is a function of x rather than a line, which is what
    /// having a physical object hang into the room means.
    func ceilingY(atX x: CGFloat, on area: CGRect) -> CGFloat {
        notch(over: area)?.ceiling(atX: x, areaTop: area.minY) ?? area.minY
    }

    /// The display `point` is on -- what "the top of the screen" and "the
    /// bottom of the screen" mean where the pet currently is. With several
    /// displays the roamable box has neither: its top edge can be a monitor
    /// away from the pet, and a ceiling crawl aimed at it walks the pet off
    /// the top of the screen it is actually on.
    func area(at point: CGPoint) -> CGRect {
        ScreenGround.area(at: point, in: roamableAreas) ?? roamableArea
    }

    /// Whether the pet's whole outline has a display under it at `position`.
    func artworkHasGround(at position: CGPoint) -> Bool {
        guard !roamableAreas.isEmpty else { return true }
        if ScreenGround.artworkHasGround(at: position, visualBounds: visualBounds, in: roamableAreas) {
            return true
        }
        // An avatar wider than the display it stands on (Settings' size
        // slider, a small display) has no position where all of it is on
        // screen -- the same case ScreenBounds.isOversizedHorizontally exists
        // for. Answering "no ground anywhere" for it would freeze the pet
        // where it stands and pin it there every frame.
        return ScreenBounds.isOversizedHorizontally(visualBounds: visualBounds, in: area(at: position))
    }

    /// Where the pet would stand after climbing the ledge in `directionX`.
    func ledge(beyond position: CGPoint, directionX: CGFloat) -> CGPoint? {
        ScreenGround.ledge(
            beyond: position,
            directionX: directionX,
            visualBounds: visualBounds,
            in: roamableAreas
        )
    }
}
