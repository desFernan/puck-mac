//
//  HeadPetDetector.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Recognises the cursor being rubbed back and forth over the pet's head.
//
//  Deliberately NOT a click gesture: stroking something is done with an open
//  hand, and requiring a held button would make it a drag -- which already
//  means "pick the pet up and carry it". So this reads plain cursor movement,
//  which in turn means it has to be strict about what counts, or the pet gets
//  petted every time the cursor crosses it on its way somewhere else.
//
//  Three things together make it deliberate: the cursor must be over the
//  HEAD specifically (not the whole body), it must reverse direction several
//  times (a stroke, not a pass), and each leg of the stroke must cover real
//  distance (not jitter sitting still). Pure logic with an injected clock so
//  all of that is testable without a mouse.
//

import CoreGraphics
import Foundation

struct HeadPetDetector {
    /// Direction reversals needed before it counts as petting. Two would fire
    /// on a cursor that merely wobbled while crossing the pet.
    static let requiredReversals = 3
    /// How far the cursor must travel between reversals for that reversal to
    /// count -- filters out hand tremor and trackpad noise.
    static let minimumStrokeDistance: CGFloat = 8
    /// Reversals older than this stop counting, so three slow passes minutes
    /// apart never add up to petting.
    static let strokeWindow: TimeInterval = 1.2
    /// Petting ends this long after the last qualifying movement, so pausing
    /// mid-stroke doesn't immediately end it.
    static let idleTimeout: TimeInterval = 0.5

    enum Update: Equatable {
        case began
        case ended
        /// Nothing changed — either not petting, or petting and continuing.
        case unchanged
    }

    private(set) var isPetting = false

    private var lastX: CGFloat?
    private var direction: CGFloat = 0
    private var travelSinceReversal: CGFloat = 0
    private var reversalTimes: [TimeInterval] = []
    private var lastQualifyingMovement: TimeInterval?

    /// Feed every cursor sample, whether or not it's over the pet.
    /// - Parameter overHead: whether this sample is inside the head area.
    mutating func cursorMoved(to position: CGPoint, overHead: Bool, now: TimeInterval) -> Update {
        guard overHead else { return leaveHead() }

        defer { lastX = position.x }
        guard let lastX else { return timeout(now: now) }

        let dx = position.x - lastX
        guard dx != 0 else { return timeout(now: now) }

        let newDirection: CGFloat = dx > 0 ? 1 : -1
        if direction != 0, newDirection != direction, travelSinceReversal >= Self.minimumStrokeDistance {
            reversalTimes.append(now)
            reversalTimes.removeAll { now - $0 > Self.strokeWindow }
            travelSinceReversal = 0
            lastQualifyingMovement = now

            if !isPetting, reversalTimes.count >= Self.requiredReversals {
                isPetting = true
                return .began
            }
        } else if newDirection == direction {
            travelSinceReversal += abs(dx)
            if isPetting, abs(dx) > 0 {
                lastQualifyingMovement = now
            }
        } else {
            travelSinceReversal = abs(dx)
        }
        direction = newDirection

        return timeout(now: now)
    }

    /// Call every frame as well as on movement — petting has to end on the
    /// cursor going *still*, which produces no events of its own.
    mutating func tick(now: TimeInterval) -> Update {
        timeout(now: now)
    }

    /// The cursor left the head: petting is over immediately, and the stroke
    /// history is dropped so a later pass starts from scratch.
    private mutating func leaveHead() -> Update {
        lastX = nil
        direction = 0
        travelSinceReversal = 0
        reversalTimes.removeAll()
        guard isPetting else { return .unchanged }
        isPetting = false
        return .ended
    }

    private mutating func timeout(now: TimeInterval) -> Update {
        guard isPetting, let lastQualifyingMovement, now - lastQualifyingMovement >= Self.idleTimeout else {
            return .unchanged
        }
        isPetting = false
        reversalTimes.removeAll()
        return .ended
    }
}
