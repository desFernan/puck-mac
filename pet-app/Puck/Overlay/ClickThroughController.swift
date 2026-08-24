//
//  ClickThroughController.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Toggles ignoresMouseEvents based on the manifest hitbox AABB
//
//  Precise alpha-pixel hit testing is a later-priority improvement
//  (plan/02_pet-app.md F1) — this is the AABB version.

import AppKit
import CoreGraphics

/// Keeps a window's `ignoresMouseEvents` in sync with whether the cursor is
/// over the character's hitbox: click-through everywhere else, clickable
/// over the character so clicks/drags reach the app instead of passing
/// through to whatever's behind it.
final class ClickThroughController {
    private weak var window: NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var characterScreenPosition: CGPoint = .zero
    private var hitboxSize: CGSize = .zero
    private var isUpsideDown = false
    private var gestureRecognizer = PetGestureRecognizer()
    /// Asks whether a cursor position (AppKit global) lands on the pet's
    /// artwork, and on the toy's. Injected rather than computed here: only
    /// the renderers know their own silhouettes and transforms, and this type
    /// deliberately knows nothing about either.
    var isOnPet: ((CGPoint) -> Bool)?
    var isOnToy: ((CGPoint) -> Bool)?
    /// Which subject the in-flight gesture belongs to. Decided once on
    /// mouse-down and held for the whole press: the pet and the toy move
    /// while being dragged, so re-testing per event could hand the second
    /// half of a drag to the other one.
    private var gestureSubject: GestureSubject = .pet

    enum GestureSubject {
        case pet
        case toy
    }

    /// Emitted when the user clicks or drags the character itself. Cursor
    /// positions are AppKit global screen coordinates — the same space
    /// `updateCharacter(screenPosition:)` is given.
    var onGesture: ((PetGesture) -> Void)?

    /// Every cursor sample over the overlay, with whether it landed on the
    /// pet's head. Petting is recognised from plain movement rather than
    /// clicks, so it can't come through `onGesture` -- and the recognising
    /// itself lives outside this type, which only knows about hit testing.
    var onCursorMoved: ((CGPoint, Bool) -> Void)?

    /// The same gestures, for the toy rather than the pet.
    var onToyGesture: ((PetGesture) -> Void)?

    init(window: NSWindow) {
        self.window = window
        window.ignoresMouseEvents = true
    }

    /// Called whenever the character moves or its avatar (and thus hitbox) changes.
    func updateCharacter(screenPosition: CGPoint, hitboxSize: CGSize, isUpsideDown: Bool = false) {
        characterScreenPosition = screenPosition
        self.hitboxSize = hitboxSize
        self.isUpsideDown = isUpsideDown
    }

    /// A *global* monitor only delivers events sent to OTHER apps -- the
    /// instant handleMouseMoved() sets ignoresMouseEvents = false, our own
    /// window starts receiving mouseMoved itself, and the global monitor goes
    /// silent for it. Without a local monitor too, clicks stayed enabled
    /// permanently after the cursor's first hitbox entry.
    func startMonitoring() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleMouseMoved()
        }
        // Mouse-down/drag/up only reach the *local* monitor, because the
        // window stops ignoring mouse events precisely when the cursor is over
        // the character — so those events are delivered to us, not to the app
        // behind. The global monitor would never see them.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    /// AppKit keeps both monitors, so dropping this object is not the same as
    /// stopping it -- the same reason WindowListWatcher and FocusModeObserver
    /// stop themselves.
    deinit {
        stopMonitoring()
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let cursor = NSEvent.mouseLocation
        let gesture: PetGesture?
        switch event.type {
        case .leftMouseDown:
            // The toy is tested first: it is much the smaller target, and it
            // sits in front of the pet, so a press that could be either is
            // the one the user aimed at.
            if isOnToy?(cursor) == true {
                gestureSubject = .toy
            } else if isOnPet?(cursor) == true {
                gestureSubject = .pet
            } else {
                // Neither — ignoresMouseEvents may not have caught up with a
                // fast cursor.
                return
            }
            gesture = gestureRecognizer.mouseDown(at: cursor)
        case .leftMouseDragged:
            gesture = gestureRecognizer.mouseDragged(to: cursor)
        case .leftMouseUp:
            gesture = gestureRecognizer.mouseUp(at: cursor)
        default:
            handleMouseMoved()
            return
        }
        if let gesture {
            switch gestureSubject {
            case .pet: onGesture?(gesture)
            case .toy: onToyGesture?(gesture)
            }
        }
    }

    private func handleMouseMoved() {
        let cursor = NSEvent.mouseLocation
        // The toy has to make the window clickable too, or a press on it goes
        // straight through to whatever is behind the overlay.
        let overSomething = isOnPet?(cursor) == true || isOnToy?(cursor) == true
        window?.ignoresMouseEvents = !overSomething

        let head = Self.headRect(
            characterScreenPosition: characterScreenPosition,
            hitboxSize: hitboxSize,
            isUpsideDown: isUpsideDown
        )
        onCursorMoved?(cursor, head.contains(cursor))
    }

    /// Pure hit test. Both points must already be in the same coordinate
    /// space (the caller is responsible for that consistency).
    ///
    /// `characterScreenPosition` is the character's ground/feet point (the
    /// same convention CharacterBody.position uses everywhere), in AppKit
    /// global space (bottom-left origin, Y increases upward) -- so the
    /// hitbox extends *upward* from it, not symmetrically around it. Building
    /// it symmetric around the feet left the character's upper half outside
    /// its own hitbox.
    ///
    /// F3 ceiling-crawling (2026-07-29): hanging from the ceiling, the body
    /// extends *downward* from the attachment point instead -- the same
    /// SpriteAvatar.setScreenPosition flip this mirrors on the click-test
    /// side. Missing this made a visibly-hanging pet unclickable.
    ///

    /// The character's full body rect: the ground point plus hitboxSize,
    /// flipped by isUpsideDown. `headRect` slices a fraction off its "head"
    /// edge.
    private static func bodyRect(characterScreenPosition: CGPoint, hitboxSize: CGSize, isUpsideDown: Bool) -> CGRect {
        let originY = isUpsideDown
            ? characterScreenPosition.y - hitboxSize.height
            : characterScreenPosition.y
        return CGRect(
            x: characterScreenPosition.x - hitboxSize.width / 2,
            y: originY,
            width: hitboxSize.width,
            height: hitboxSize.height
        )
    }


    /// Fraction of the character's height, measured down from the top, that
    /// counts as its head for petting. The art is a chibi with a very large
    /// head, so this is generous — but it stops short of the body, because
    /// "쓰담쓰담" on the pet's feet isn't petting.
    static let headFraction: CGFloat = 0.45

    /// The head's rectangle, in the same AppKit global space as the cursor
    /// positions this type is given.
    ///
    /// Still a rectangle, deliberately, where clicking is now measured
    /// against the artwork's silhouette: petting asks "is the cursor over the
    /// pet's head?", which is a region of the body, not a set of drawn
    /// pixels. Stroking the air just above the hair should still count.
    static func headRect(
        characterScreenPosition: CGPoint,
        hitboxSize: CGSize,
        isUpsideDown: Bool = false
    ) -> CGRect {
        guard hitboxSize != .zero else { return .zero }
        let body = bodyRect(characterScreenPosition: characterScreenPosition, hitboxSize: hitboxSize, isUpsideDown: isUpsideDown)
        let headHeight = hitboxSize.height * headFraction
        // Y grows upward here, and the body extends up from the feet -- so the
        // head is the TOP slice, unless the pet is hanging from the ceiling
        // and its head is the bottom one.
        let originY = isUpsideDown ? body.minY : body.maxY - headHeight
        return CGRect(x: body.minX, y: originY, width: body.width, height: headHeight)
    }
}
