//
//  AvatarPose.swift
//  Puck
//
//  The handful of orientations the pet is ever drawn in, and how to correct
//  one that came out wrong.
//
//  Which way a character faces, and which way up it climbs, is decided by
//  whoever drew it. The app assumes one answer; an avatar drawn to the other
//  answer walks backwards, or climbs a wall head-first, for its whole life --
//  and the only fix was to edit the artwork in an image editor and reimport
//  it. This is that fix, made from inside the app: a small transform per
//  pose, kept beside the pose it corrects.
//
//  The transform is written the same way the renderer's is -- a flip on each
//  axis and a number of quarter turns -- so what the settings window shows
//  and what walks across the desktop cannot drift apart. See
//  `SpriteAvatar.applyTransform`.
//

import CoreGraphics
import Foundation

/// One of the orientations worth previewing, because it is one the pet
/// actually spends time in and one an avatar can be drawn wrong for.
enum AvatarPose: String, CaseIterable, Codable {
    case walkingRight
    case walkingLeft
    /// Climbing is two poses, not one. The pet keeps the facing it arrived
    /// with all the way up, so a wall on its left and a wall on its right are
    /// mirror images of each other -- and artwork that is right for one is
    /// upside down or backwards for the other. Correcting them together
    /// meant fixing one and breaking the other.
    case climbingRightWall
    case climbingLeftWall
    /// The ceiling is two poses for the same reason the walls are: the pet
    /// crawls it in both directions, and upside down a character drawn to
    /// face one way is wrong the other way in a way flipping the pair
    /// together cannot fix.
    case onTheCeilingFacingRight
    case onTheCeilingFacingLeft

    /// The clip the pet plays while it is in this pose, so a preview shows
    /// the artwork the pet will actually be wearing.
    var clip: String {
        switch self {
        case .walkingRight, .walkingLeft,
             .onTheCeilingFacingRight, .onTheCeilingFacingLeft: return "walk"
        case .climbingRightWall, .climbingLeftWall: return "climb"
        }
    }

    /// Which way the pet is facing, which the renderer mirrors on.
    var facing: AvatarFacing {
        switch self {
        case .walkingLeft, .climbingLeftWall, .onTheCeilingFacingLeft: return .left
        case .walkingRight, .climbingRightWall, .onTheCeilingFacingRight: return .right
        }
    }

    /// Whether the pet is hanging upside down, which flips it on Y.
    var isUpsideDown: Bool {
        self == .onTheCeilingFacingRight || self == .onTheCeilingFacingLeft
    }

    /// Whether the sprite is turned a quarter turn, which climbing is.
    ///
    /// Read from the clip's own preset rather than decided here, so the
    /// preview turns the picture exactly when the pet does -- the two used to
    /// each work it out and could disagree.
    var rotatesQuarterTurn: Bool {
        BouncePreset.preset(for: clip).transform(elapsed: 0, intensity: 1).rotatesQuarterTurn
    }
}

/// A correction applied on top of whatever the pose already does.
///
/// Deliberately only flips and quarter turns. Anything finer is a request to
/// redraw the character, and an app that lets you shear your own pet is an
/// app that lets you break it in ways nobody can describe over a bug report.
struct AvatarPoseAdjustment: Equatable, Codable {
    var flipsHorizontally = false
    var flipsVertically = false
    /// 0 to 3. Kept as turns rather than radians so it cannot land anywhere
    /// but square, and so "rotate" is one button pressed repeatedly.
    var quarterTurns = 0

    static let none = AvatarPoseAdjustment()

    var isIdentity: Bool { self == .none }

    /// Rotates one step, wrapping. Four presses is where you started.
    mutating func rotate() {
        quarterTurns = (quarterTurns + 1) % 4
    }

    var rotation: CGFloat { CGFloat(quarterTurns) * .pi / 2 }
}

/// Every pose's correction, as one value.
///
/// A dictionary rather than four properties: the settings window walks
/// `AvatarPose.allCases` to draw its previews, and a fifth pose should mean
/// adding a case and nothing else.
struct AvatarPoseAdjustments: Equatable, Codable {
    private var byPose: [String: AvatarPoseAdjustment] = [:]

    init() {}

    subscript(pose: AvatarPose) -> AvatarPoseAdjustment {
        get { byPose[pose.rawValue] ?? .none }
        set {
            // Identity is the absence of a correction, not a correction that
            // does nothing: storing it would mean a settings file that grows
            // an entry every time somebody presses rotate four times.
            if newValue.isIdentity {
                byPose.removeValue(forKey: pose.rawValue)
            } else {
                byPose[pose.rawValue] = newValue
            }
        }
    }

    var isEmpty: Bool { byPose.isEmpty }
}

/// How a pose is oriented before anything moves.
///
/// One place, because there were two: the renderer composed the flips, the
/// correction and the climb's quarter turn in one order, and the settings
/// window's preview composed them in another. Rotating after a negative scale
/// turns the other way, so the two agreed until a correction involved both --
/// and then the picture in the window was not the pet on the screen, which is
/// the one thing a preview must never be.
///
/// Returns the parts rather than a matrix: the renderer multiplies the clip's
/// bounce into the scale before building its own, and SwiftUI wants them
/// separately too.
struct AvatarPoseOrientation: Equatable {
    var scaleX: CGFloat
    var scaleY: CGFloat
    /// Radians, applied after the scale.
    var rotation: CGFloat

    static func of(
        _ pose: AvatarPose?,
        adjustment: AvatarPoseAdjustment,
        isMirrored: Bool
    ) -> AvatarPoseOrientation {
        let facingX: CGFloat = (pose?.facing == .left) ? -1 : 1
        let upsideDownY: CGFloat = (pose?.isUpsideDown ?? false) ? -1 : 1
        let quarterTurn: CGFloat = (pose?.rotatesQuarterTurn ?? false) ? .pi / 2 : 0
        return AvatarPoseOrientation(
            scaleX: facingX * (isMirrored ? -1 : 1) * (adjustment.flipsHorizontally ? -1 : 1),
            scaleY: upsideDownY * (adjustment.flipsVertically ? -1 : 1),
            // The correction first, then the turn climbing puts on top of it:
            // the correction is fixing how the artwork was drawn, and the
            // turn is what the pet is doing with it.
            rotation: adjustment.rotation + quarterTurn
        )
    }
}
