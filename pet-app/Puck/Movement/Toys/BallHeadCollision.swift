//
//  BallHeadCollision.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Whether a falling ball's X currently overlaps the character's head, and
//  if so, where it should land. Without this, a thrown ball
//  falls straight through the character to the floor/window below it,
//  since LandingSurfaceResolver only knows about windows, not the pet.
//
//  Pure geometry, no BallController/CharacterBody coupling, so the caller
//  (AppDelegate's frame loop) decides each frame whether the head or the
//  normal floor/window surface is nearer and feeds MovementSolver.fallStep
//  the smaller of the two -- the existing fall/kick physics do the rest
//  unchanged.
//

import CoreGraphics

enum BallHeadCollision {
    /// - Parameters:
    ///   - ballX: the falling toy's current x (the middle of it).
    ///   - ballHalfWidth: half the toy's *visible* width. Treating the toy as
    ///     a point meant a 40pt pumpkin whose middle cleared the head by a
    ///     pixel passed straight through it while visibly overlapping.
    ///     Pass 0 for a genuinely point-sized toy.
    ///   - characterPosition: the character's ground/feet point.
    ///   - avatarSize: the rendered avatar's current size (hitbox * scale).
    /// - Returns: the head's Y (top of the avatar) if the toy overlaps the
    ///   avatar horizontally at all, else nil -- there's nothing to hit.
    static func landingY(
        ballX: CGFloat,
        ballHalfWidth: CGFloat,
        characterPosition: CGPoint,
        avatarSize: CGSize
    ) -> CGFloat? {
        // Edge-to-edge, so grazing the side of the head counts as a hit the
        // same way it looks like one.
        guard abs(ballX - characterPosition.x) <= avatarSize.width / 2 + ballHalfWidth else { return nil }
        return characterPosition.y - avatarSize.height
    }
}
