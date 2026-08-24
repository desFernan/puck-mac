//
//  ToyInterestPolicy.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Which toy the pet goes for when more than one is lying around.
//
//  Several toys can be out at once as of 2026-07-30, via a menu that shows
//  each toy's name and image and toggles it out/away, which turns "play
//  with the toy" into a choice for the first time.
//
//  The rule is deliberately boring: the nearest one, except the one just
//  played with. Nearest alone would have the pet loop on whichever toy it is
//  already standing next to -- which is precisely the toy it has just finished
//  kicking away -- and the point of putting two toys out is to see it use both.
//  A single skip is enough for that; a longer memory would start reading as the
//  pet avoiding a toy.
//

import CoreGraphics
import Foundation

enum ToyInterestPolicy {
    struct Candidate: Equatable {
        let name: String
        let position: CGPoint
        /// Only a toy settled on a surface can be walked up to and played with.
        /// One in mid-air, in the user's hand, or already held by the pet is not
        /// a candidate -- chasing a moving target is a different behaviour and
        /// grabbing one out of the cursor's hand would fight the user.
        let isResting: Bool
    }

    /// - Parameter lastPlayed: the toy the pet finished with most recently,
    ///   skipped when there is anything else to pick instead.
    /// - Returns: the toy's name, or nil when nothing is playable.
    static func next(from candidates: [Candidate], lastPlayed: String?, petPosition: CGPoint) -> String? {
        let playable = candidates.filter(\.isResting)
        guard !playable.isEmpty else { return nil }

        // Only skip the last-played toy while a real alternative exists: with
        // one toy out, skipping it would mean the pet never plays at all.
        let alternatives = playable.filter { $0.name != lastPlayed }
        let choices = alternatives.isEmpty ? playable : alternatives

        // min(by:) keeps the first of equally-distant candidates, so the order
        // the caller supplies (the catalogue's) decides ties instead of leaving
        // the pet to flip between two toys frame to frame.
        return choices.min { distance(from: petPosition, to: $0.position) < distance(from: petPosition, to: $1.position) }?.name
    }

    private static func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy // squared: ordering is all this is used for
    }
}
