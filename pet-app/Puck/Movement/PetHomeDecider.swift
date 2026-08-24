//
//  PetHomeDecider.swift
//  Puck
//
//  Whether the pet is in its tank or out on the desktop.
//
//  One place decides this, and it is here rather than in the client: the
//  client knows about its own window, but only pet-app knows whether the pet
//  is hidden, and a decision split across a socket is a decision that can
//  disagree with itself.
//

import Foundation

final class PetHomeDecider {
    enum Move: Equatable {
        case home
        case desktop
    }

    /// How long a state has to hold before the pet acts on it. Alt-tabbing
    /// past the window would otherwise send the pet there and back.
    ///
    /// Short enough to read as the pet answering the window rather than
    /// noticing it later: at 0.7 the window was up and being typed in before
    /// the pet set off. What it has to outlast is a window passing through
    /// focus, which takes an instant, not most of a second.
    static let holdSeconds: TimeInterval = 0.25

    /// The menu bar's Hide toggle. Outranks everything: a hidden pet is not
    /// somewhere, it is nowhere.
    ///
    /// Showing it again re-decides from the last thing the client said rather
    /// than waiting to be told again -- the client only sends when something
    /// changes, so nothing would arrive, and the pet would stay wherever it
    /// happened to be when it was hidden.
    var isPetHidden = false {
        didSet {
            guard isPetHidden != oldValue else { return }
            elapsed = 0
            pending = isPetHidden ? nil : lastReported
        }
    }

    /// The user has hold of the pet. Nothing moves it while that is true:
    /// picking it up is the one moment it is under somebody else's control,
    /// and a decision that fires mid-drag pulls it out of the hand holding
    /// it. Letting go re-decides from the last report, so a pet dragged out
    /// of its tank still goes back to it.
    var isBeingHeld = false {
        didSet {
            guard isBeingHeld != oldValue else { return }
            elapsed = 0
            if !isBeingHeld { pending = lastReported }
        }
    }

    private var current: Move = .desktop
    private var pending: Move?
    /// What the last report worked out to, kept so an unhide -- or the end of
    /// a code tour -- can re-decide without waiting to be told again.
    private var lastReported: Move?
    /// A move that skips the hold entirely, set by forceDesktop().
    private var forced: Move?
    private var elapsed: TimeInterval = 0

    /// The client's latest word on its tank. `hasTank` is false when there is
    /// no usable rect at all (window closed, or too small for a pet).
    func report(hasTank: Bool, visible: Bool) {
        // Two facts, one answer: the pet lives in the tank while there is one
        // and the user is looking at it. There used to be a third -- a pin
        // that kept it home regardless -- reachable only from a toolbar
        // button nobody wanted there.
        let wanted: Move = hasTank && visible ? .home : .desktop
        lastReported = wanted
        // Repeating the same answer must not restart the hold, or a client
        // that reports every frame would never leave it.
        guard wanted != pending else { return }
        pending = wanted
        elapsed = 0
    }

    /// Leaves the tank now, without waiting out the hold: a code tour points
    /// at things below the tank, and the pet cannot reach them from inside it.
    /// The client's reports decide again as soon as one changes, or when
    /// `resumeReportedState()` is called at the end of the run.
    func forceDesktop() {
        pending = nil
        elapsed = 0
        guard current != .desktop else { return }
        current = .desktop
        forced = .desktop
    }

    /// Back to whatever the client last reported, now that the run is over.
    func resumeReportedState() {
        elapsed = 0
        forced = nil
        pending = lastReported
    }

    /// - Returns: the move to make, once and only once, when a reported state
    ///   has held long enough and differs from where the pet already is.
    func tick(dt: TimeInterval) -> Move? {
        // After the two guards, not before. A code tour calls forceDesktop()
        // at whatever moment the agent reaches one, and a forced move that
        // jumped the queue took the pet out of the hand holding it -- the one
        // thing `isBeingHeld` exists to prevent -- or relocated a pet the
        // user had hidden.
        guard !isPetHidden, !isBeingHeld else { return nil }
        if let forced {
            self.forced = nil
            return forced
        }
        guard let pending else { return nil }
        elapsed += dt
        guard elapsed >= Self.holdSeconds else { return nil }
        self.pending = nil
        elapsed = 0
        guard pending != current else { return nil }
        current = pending
        return pending
    }
}
