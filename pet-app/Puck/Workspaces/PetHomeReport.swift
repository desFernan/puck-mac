//
//  PetHomeReport.swift
//  Puck
//
//  What this window tells pet-app about the island: where it is, and whether
//  the pet should be standing on it.
//
//  Three pieces of state that only make sense together. The island's frame is
//  meaningless without knowing the window is open -- a pet left standing on a
//  tank that no longer exists floats in the space where the window had been
//  -- and being open is not the same as being looked at, because pinning
//  keeps the pet home behind another window but must not keep it home after
//  the window is closed.
//
//  Pure, and what it decides is worth deciding in one place: the same three
//  facts produce the rect on the wire, whether the pet is visible on it, and
//  whether the whole thing collapses to "no tank". They were three properties
//  and a private method on ClientWindowStore, among forty other members.
//

import CoreGraphics

struct PetHomeReport: Equatable {
    /// Where the island is, in AppKit global coordinates, or nil when it is
    /// not on screen. One frame: the island is one view above the columns it
    /// covers, and the sidebar it does not cover is outside it.
    private(set) var tankFrame: CGRect?

    /// Whether the client window is the one the user is looking at. The pet
    /// only comes home for a frontmost window.
    private(set) var windowIsFrontmost = false

    /// Whether there is a window at all -- see the header for why this is
    /// not the same question as frontmost.
    private(set) var windowIsOpen = true

    /// - Returns: whether anything changed, and so whether there is news to
    ///   send. A resize produces a rect per layout pass and an unchanged one
    ///   carries none.
    @discardableResult
    mutating func setTankFrame(_ frame: CGRect?) -> Bool {
        guard tankFrame != frame else { return false }
        tankFrame = frame
        return true
    }

    @discardableResult
    mutating func setWindowIsFrontmost(_ isFrontmost: Bool) -> Bool {
        guard windowIsFrontmost != isFrontmost else { return false }
        windowIsFrontmost = isFrontmost
        return true
    }

    @discardableResult
    mutating func setWindowIsOpen(_ isOpen: Bool) -> Bool {
        guard windowIsOpen != isOpen else { return false }
        windowIsOpen = isOpen
        // A window that has been closed is not the one being looked at
        // either, whatever it last said.
        if !isOpen { windowIsFrontmost = false }
        return true
    }

    /// The island in the pet's own space, or nil when there is nowhere to
    /// stand.
    ///
    /// A closed window has no tank whatever its last reported frame was --
    /// that is the whole reason `windowIsOpen` is separate from the frame.
    func wireRect(in space: GlobalScreenSpace) -> BridgeRect? {
        guard windowIsOpen, let frame = tankFrame else { return nil }
        let topLeft = space.normalized(fromAppKit: CGPoint(x: frame.minX, y: frame.maxY))
        return BridgeRect(x: topLeft.x, y: topLeft.y, width: frame.width, height: frame.height)
    }

    /// Whether the pet should be standing on it. There has to be an island
    /// before there is a pet on one.
    func isPetVisible(in space: GlobalScreenSpace) -> Bool {
        windowIsFrontmost && wireRect(in: space) != nil
    }
}
