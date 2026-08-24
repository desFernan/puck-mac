//
//  ToyApproach.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Where the pet should stand to play with the toy, so it stands beside the
//  toy rather than on top of it.
//
//  ChaseBall used to be sent the toy's own position, which is the middle of
//  it. That was harmless only while the toy rested with its centre buried in
//  the floor -- once it started resting on its artwork, its centre sits a
//  toy-radius above the ground, and walking the pet to that point put the
//  pet's feet up in the air at exactly the height of the toy: standing on it.
//
//  So this answers two things the toy's own position can't: the pet walks on
//  the surface the toy is resting ON, and it stops beside the toy rather than
//  inside it.
//

import CoreGraphics
import Foundation

enum ToyApproach {
    /// A little air between the two outlines, so the pet reads as standing
    /// next to the toy rather than pressed against it.
    static let gap: CGFloat = 4

    /// - Parameters:
    ///   - toyPosition: the toy's centre.
    ///   - toyBounds: the toy's visible outline, relative to that centre.
    ///   - petPosition: where the pet is now — only its side matters, so the
    ///     pet approaches from whichever way it's already coming.
    ///   - petBounds: the pet's visible outline, relative to its ground point.
    /// - Returns: the ground point for the pet to walk to.
    static func standingPosition(
        toyPosition: CGPoint,
        toyBounds: CGRect,
        petPosition: CGPoint,
        petBounds: CGRect
    ) -> CGPoint {
        // The toy rests ON a surface, so its bottom edge IS the ground here.
        // The pet's position is its feet, so that's the height to walk to.
        let ground = toyPosition.y + toyBounds.maxY

        let approachingFromLeft = petPosition.x <= toyPosition.x
        // Outline to outline: half the toy on the near side, plus however far
        // the pet's own artwork sticks out toward it.
        let clearance = approachingFromLeft
            ? -toyBounds.minX + petBounds.maxX
            : toyBounds.maxX - petBounds.minX

        return CGPoint(
            x: approachingFromLeft
                ? toyPosition.x - clearance - gap
                : toyPosition.x + clearance + gap,
            y: ground
        )
    }
}
