//
//  ToyBox.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The toys currently out, and which one the pet is playing with.
//
//  Until 2026-07-30 the app had exactly one toy: a single BallController that
//  was rebuilt in place when the user picked a different one from Settings.
//  The menu should be able to put toys out and take them away individually,
//  so several can now be out at
//  once and each one owns its own layer and physics.
//
//  The FSM is deliberately untouched by this. ChaseBall/JuggleBall/KickBall
//  still only ever deal with ONE toy -- `focused`, the one the pet is playing
//  with -- so multi-toy support cost nothing in the state machine. Choosing
//  which toy that is lives in ToyInterestPolicy, and everything about drawing
//  and simulating them lives in BallController; this type is the register of
//  what exists.
//

import CoreGraphics
import Foundation
import QuartzCore

final class ToyBox {
    /// Out toys in the order they were put out, which is also their layer
    /// order -- the newest is drawn on top and is what the cursor grabs first.
    private var entries: [(toy: Toy, controller: BallController)] = []
    private var parent: CALayer
    private var scale: Double

    /// A toy came to rest. The toy is named because, with several out, the
    /// caller can no longer assume which one landed -- the head-collision and
    /// chase logic both need to know.
    var onLanded: ((Toy, CGPoint) -> Void)?

    /// The toy the pet is playing with right now, if any.
    private(set) var focused: BallController?
    /// The toy the pet played with most recently. Outlives `focused` on purpose:
    /// it is what ToyInterestPolicy uses to move the pet on to a different toy
    /// once this game ends.
    private(set) var lastPlayedName: String?

    init(parent: CALayer, scale: Double = 1) {
        self.parent = parent
        self.scale = scale
    }

    // MARK: - What's out

    var all: [BallController] { entries.map(\.controller) }

    var outToyNames: Set<String> { Set(entries.map(\.toy.name)) }

    func isOut(_ toy: Toy) -> Bool { entries.contains { $0.toy == toy } }

    func controller(for toy: Toy) -> BallController? {
        entries.first { $0.toy == toy }?.controller
    }

    /// What the menu does: out if it wasn't, gone if it was.
    /// - Returns: whether the toy is now out.
    @discardableResult
    func toggle(_ toy: Toy, at position: CGPoint) -> Bool {
        guard isOut(toy) else {
            spawn(toy, at: position)
            return true
        }
        remove(toy)
        return false
    }

    /// Puts a toy out, or moves it if it is already out. Moving rather than
    /// adding a second copy keeps one toy per catalogue entry, which is what
    /// lets the menu show a simple on/off state for each.
    func spawn(_ toy: Toy, at position: CGPoint) {
        if let existing = controller(for: toy) {
            existing.spawn(at: position)
            return
        }

        let controller = BallController(parent: parent, toy: toy, scale: scale)
        controller.onLanded = { [weak self] landedAt in
            self?.onLanded?(toy, landedAt)
        }
        controller.spawn(at: position)
        entries.append((toy, controller))
    }

    func remove(_ toy: Toy) {
        guard let index = entries.firstIndex(where: { $0.toy == toy }) else { return }
        let removed = entries.remove(at: index)
        // The pet cannot go on playing with something that no longer exists;
        // the caller is expected to notice `focused` went nil and leave the
        // play state.
        if focused === removed.controller {
            focused = nil
        }
        removed.controller.layer.removeFromSuperlayer()
    }

    func removeAll() {
        for entry in entries {
            entry.controller.layer.removeFromSuperlayer()
        }
        entries.removeAll()
        focused = nil
    }

    // MARK: - Playing

    func focus(_ controller: BallController?) {
        focused = controller
        if let controller, let entry = entries.first(where: { $0.controller === controller }) {
            lastPlayedName = entry.toy.name
        }
    }

    func clearFocus() {
        focused = nil
    }

    /// The toy `focused` is, so callers can read its play style without
    /// searching the catalogue themselves.
    var focusedToy: Toy? {
        guard let focused else { return nil }
        return entries.first { $0.controller === focused }?.toy
    }

    var candidates: [ToyInterestPolicy.Candidate] {
        entries.compactMap { entry in
            guard let state = entry.controller.state else { return nil }
            return ToyInterestPolicy.Candidate(
                name: entry.toy.name,
                position: state.position,
                isResting: state.phase == .resting
            )
        }
    }

    // MARK: - Per frame

    /// - Parameters:
    ///   - landingY: the surface a given toy should come to rest on. Resolved
    ///     per toy rather than once, because it depends on where that toy is
    ///     and how big it is (windows below it, the pet's head).
    ///   - roamableArea: the display that toy is over, per toy for the same
    ///     reason -- with two monitors there is no single rectangle that is
    ///     "the screen".
    func tickAll(
        dt: TimeInterval,
        landingY: (BallController) -> CGFloat,
        roamableArea: (BallController) -> CGRect
    ) {
        // Copied because a landing handler may remove a toy mid-iteration.
        for controller in all where controller.isActive {
            controller.tick(dt: dt, landingY: landingY(controller), roamableArea: roamableArea(controller))
        }
    }

    // MARK: - Cursor

    /// The topmost toy drawn under `point` (overlay-local), newest first.
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> BallController? {
        for entry in entries.reversed() {
            guard entry.controller.isActive, let position = entry.controller.state?.position else { continue }
            let local = CGPoint(x: point.x - position.x, y: point.y - position.y)
            if entry.controller.hitTest(local, tolerance: tolerance) {
                return entry.controller
            }
        }
        return nil
    }

    // MARK: - Display changes and settings

    func reparent(to newParent: CALayer) {
        parent = newParent
        for entry in entries {
            entry.controller.reparent(to: newParent)
        }
    }

    /// Applies to every toy out AND to any put out later -- the size is a
    /// setting, so a toy fetched after the slider moved must not come back at
    /// the old size.
    func updateScale(_ scale: Double) {
        self.scale = scale
        for entry in entries {
            entry.controller.updateScale(scale)
        }
    }
}
