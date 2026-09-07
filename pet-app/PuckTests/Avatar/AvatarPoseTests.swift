//
//  AvatarPoseTests.swift
//  PuckTests
//
//  Correcting artwork that was drawn the other way round.
//

import XCTest
@testable import Puck

final class AvatarPoseTests: XCTestCase {
    /// The preview and the pet have to agree about what a pose *is*, or the
    /// picture in the settings window is of a different animal. Both read
    /// these two.
    func testEachPoseKnowsItsClipAndOrientation() {
        XCTAssertEqual(AvatarPose.walkingRight.clip, "walk")
        XCTAssertEqual(AvatarPose.walkingLeft.clip, "walk")
        XCTAssertEqual(AvatarPose.climbingLeftWall.clip, "climb")
        XCTAssertEqual(AvatarPose.climbingRightWall.clip, "climb")

        XCTAssertEqual(AvatarPose.walkingLeft.facing, .left)
        XCTAssertEqual(AvatarPose.walkingRight.facing, .right)
        XCTAssertTrue(AvatarPose.onTheCeilingFacingLeft.isUpsideDown)
        XCTAssertTrue(AvatarPose.onTheCeilingFacingRight.isUpsideDown)
        XCTAssertFalse(AvatarPose.walkingRight.isUpsideDown)
    }

    /// Four presses is where you started, so the button is safe to lean on.
    func testFourRotationsComeBackAround() {
        var adjustment = AvatarPoseAdjustment()

        for _ in 0..<4 { adjustment.rotate() }

        XCTAssertEqual(adjustment.quarterTurns, 0)
        XCTAssertTrue(adjustment.isIdentity)
    }

    /// It only ever lands square. Anything finer is a request to redraw the
    /// character.
    func testRotationOnlyLandsSquare() {
        var adjustment = AvatarPoseAdjustment()

        for turn in 1...3 {
            adjustment.rotate()
            XCTAssertEqual(adjustment.rotation, CGFloat(turn) * .pi / 2, accuracy: 0.0001)
        }
    }

    /// Each pose is corrected on its own: a character drawn facing the wrong
    /// way when it climbs is not necessarily wrong when it walks.
    func testPosesAreCorrectedIndependently() {
        var adjustments = AvatarPoseAdjustments()

        adjustments[.climbingLeftWall].flipsVertically = true

        XCTAssertTrue(adjustments[.climbingLeftWall].flipsVertically)
        XCTAssertFalse(adjustments[.walkingLeft].flipsVertically)
    }

    /// Undoing a correction removes it rather than storing one that does
    /// nothing, or a settings file grows an entry every time somebody presses
    /// rotate four times.
    func testUndoingACorrectionLeavesNothingBehind() {
        var adjustments = AvatarPoseAdjustments()

        adjustments[.climbingLeftWall].flipsHorizontally = true
        XCTAssertFalse(adjustments.isEmpty)
        adjustments[.climbingLeftWall].flipsHorizontally = false

        XCTAssertTrue(adjustments.isEmpty)
    }

    /// It has to survive a relaunch, which is the only reason it is stored.
    func testCorrectionsSurviveBeingWrittenAndReadBack() throws {
        var adjustments = AvatarPoseAdjustments()
        adjustments[.onTheCeilingFacingLeft].flipsHorizontally = true
        adjustments[.climbingRightWall].quarterTurns = 3

        let restored = try JSONDecoder().decode(
            AvatarPoseAdjustments.self,
            from: try JSONEncoder().encode(adjustments)
        )

        XCTAssertEqual(restored, adjustments)
        XCTAssertEqual(restored[.climbingRightWall].quarterTurns, 3)
    }

    // MARK: - Finding the picture

    private func manifest(clips: [String: ClipReference]) -> AvatarManifest {
        AvatarManifest(
            schemaVersion: 1,
            name: "test",
            type: .sprites,
            scale: 1,
            bounceIntensity: 0.6,
            hitbox: AvatarManifest.Hitbox(width: 100, height: 100),
            clips: clips,
            emotions: nil,
            sounds: [:]
        )
    }

    /// The reported fault: every preview came back empty. A clip is a
    /// `ClipReference`, not a string -- it can name a file or a span of an
    /// animation -- and interpolating one straight into a path compiles,
    /// because interpolation accepts anything. It produced a name no file
    /// has, and nothing said why.
    func testAClipResolvesToTheFileNameAndNotItsDescription() {
        let found = AvatarPoseThumbnail.spriteName(
            for: "walk",
            in: manifest(clips: ["walk": .name("pose")])
        )

        XCTAssertEqual(found, "pose")
    }

    /// A package with no dedicated clip for a pose falls back to idle, the
    /// same way the renderer does -- most avatars have one drawing.
    func testAMissingClipFallsBackToIdle() {
        let found = AvatarPoseThumbnail.spriteName(
            for: "climb",
            in: manifest(clips: ["idle": .name("standing")])
        )

        XCTAssertEqual(found, "standing")
    }

    /// A clip that is a span of an animation rather than a file has no
    /// picture to show, and must say so rather than name something that is
    /// not there.
    func testATimeRangeClipHasNoPicture() {
        let found = AvatarPoseThumbnail.spriteName(
            for: "walk",
            in: manifest(clips: ["walk": .timeRange(in: 0, out: 1)])
        )

        XCTAssertNil(found)
    }

    /// The reported fault: the two walls are mirror images, so artwork that
    /// is right for one is backwards for the other. Correcting them as one
    /// pose meant fixing a wall and breaking the opposite one.
    func testTheTwoWallsAreSeparatePoses() {
        var adjustments = AvatarPoseAdjustments()

        adjustments[.climbingLeftWall].flipsVertically = true

        XCTAssertTrue(adjustments[.climbingLeftWall].flipsVertically)
        XCTAssertFalse(adjustments[.climbingRightWall].flipsVertically)
    }

    /// And they face opposite ways, which is what makes them mirror images
    /// and what the preview has to show.
    func testTheTwoWallsFaceOppositeWays() {
        XCTAssertEqual(AvatarPose.climbingLeftWall.facing, .left)
        XCTAssertEqual(AvatarPose.climbingRightWall.facing, .right)
    }

    /// Every pose the settings window offers has a name, or a row comes up
    /// blank and nobody can tell which one they are correcting.
    func testEveryPoseIsNamedInEveryLanguage() {
        let keys: [AvatarPose: L10nKey] = [
            .walkingRight: .poseWalkingRight,
            .walkingLeft: .poseWalkingLeft,
            .climbingRightWall: .poseClimbingRightWall,
            .climbingLeftWall: .poseClimbingLeftWall,
            .onTheCeilingFacingRight: .poseOnTheCeilingFacingRight,
            .onTheCeilingFacingLeft: .poseOnTheCeilingFacingLeft,
        ]

        for pose in AvatarPose.allCases {
            guard let key = keys[pose] else {
                XCTFail("\(pose) has no name key")
                continue
            }
            for language in AppLanguage.allCases {
                XCTAssertFalse(
                    Strings.text(key, language: language).isEmpty,
                    "\(language) has no name for \(pose)"
                )
            }
        }
    }

    // MARK: - The preview and the pet agreeing

    /// The reported fault: the preview did not match what walked across the
    /// screen. The renderer composed the flips, the correction and the
    /// climb's quarter turn in one order and the preview in another --
    /// rotating after a negative scale turns the other way, so the two agreed
    /// until a correction involved both.
    ///
    /// They now read the same function, which is what this holds them to: for
    /// every pose and every correction, one answer.
    func testTheOrientationIsTheSameForEveryPoseAndCorrection() {
        for pose in AvatarPose.allCases {
            for flipH in [false, true] {
                for flipV in [false, true] {
                    for turns in 0..<4 {
                        for mirrored in [false, true] {
                            var adjustment = AvatarPoseAdjustment()
                            adjustment.flipsHorizontally = flipH
                            adjustment.flipsVertically = flipV
                            adjustment.quarterTurns = turns

                            let a = AvatarPoseOrientation.of(pose, adjustment: adjustment, isMirrored: mirrored)
                            let b = AvatarPoseOrientation.of(pose, adjustment: adjustment, isMirrored: mirrored)

                            XCTAssertEqual(a, b)
                            XCTAssertEqual(abs(a.scaleX), 1, "\(pose) scaled rather than flipped")
                            XCTAssertEqual(abs(a.scaleY), 1, "\(pose) scaled rather than flipped")
                        }
                    }
                }
            }
        }
    }

    /// Facing is what makes the two of a pair different, and it has to reach
    /// the scale rather than being read and dropped.
    func testFacingLeftMirrorsTheDrawing() {
        let right = AvatarPoseOrientation.of(.walkingRight, adjustment: .none, isMirrored: false)
        let left = AvatarPoseOrientation.of(.walkingLeft, adjustment: .none, isMirrored: false)

        XCTAssertEqual(right.scaleX, 1)
        XCTAssertEqual(left.scaleX, -1)
    }

    /// The global mirror is part of how the pet is drawn, and the preview did
    /// not have it at all -- so turning it on made every thumbnail wrong.
    func testTheGlobalMirrorReachesTheOrientation() {
        let plain = AvatarPoseOrientation.of(.walkingRight, adjustment: .none, isMirrored: false)
        let mirrored = AvatarPoseOrientation.of(.walkingRight, adjustment: .none, isMirrored: true)

        XCTAssertEqual(mirrored.scaleX, -plain.scaleX)
    }

    /// Climbing is a quarter turn, and it comes from the clip's own preset
    /// rather than from a second opinion about which clip climbs.
    func testClimbingTurnsAQuarterAndWalkingDoesNot() {
        XCTAssertTrue(AvatarPose.climbingLeftWall.rotatesQuarterTurn)
        XCTAssertFalse(AvatarPose.walkingLeft.rotatesQuarterTurn)
        XCTAssertFalse(AvatarPose.onTheCeilingFacingLeft.rotatesQuarterTurn)

        let climbing = AvatarPoseOrientation.of(.climbingLeftWall, adjustment: .none, isMirrored: false)
        XCTAssertEqual(climbing.rotation, .pi / 2, accuracy: 0.0001)
    }

    /// The order the two halves go together in, which is the whole of the
    /// preview being a picture of the pet rather than of a different one.
    ///
    /// A pet climbing the wall on its left is mirrored and quarter-turned at
    /// once, and rotating a mirrored sprite turns it the other way: composed
    /// the wrong way round, the corner that should ride up the wall goes down
    /// it instead. The settings window used to compose it the wrong way
    /// round.
    func testTheTurnIsComposedBeforeTheFlipsAndNotAfter() {
        let climbingLeft = AvatarPoseOrientation.of(.climbingLeftWall, adjustment: .none, isMirrored: false)
        XCTAssertEqual(climbingLeft.scaleX, -1, "a pet facing left is mirrored")

        let corner = CGPoint(x: 10, y: 0).applying(climbingLeft.transform)
        let theOtherWayRound = CGPoint(x: 10, y: 0).applying(
            CGAffineTransform(scaleX: climbingLeft.scaleX, y: climbingLeft.scaleY)
                .concatenating(CGAffineTransform(rotationAngle: climbingLeft.rotation))
        )

        XCTAssertEqual(corner.y, 10, accuracy: 0.0001)
        XCTAssertEqual(theOtherWayRound.y, -10, accuracy: 0.0001, "the order is not a detail")
    }

    /// What the preview's SwiftUI modifiers add up to, written as a matrix:
    /// `.rotationEffect` and then `.scaleEffect` turns the artwork first and
    /// flips the result, which is what the renderer does. Swapping those two
    /// lines in AvatarPosePreview is what this catches.
    func testThePreviewsOrderOfModifiersMatchesTheRenderers() {
        for pose in AvatarPose.allCases {
            var adjustment = AvatarPoseAdjustment()
            adjustment.flipsHorizontally = true
            adjustment.rotate()
            let orientation = AvatarPoseOrientation.of(pose, adjustment: adjustment, isMirrored: true)

            let asThePreviewApplies = CGAffineTransform(rotationAngle: orientation.rotation)
                .concatenating(CGAffineTransform(scaleX: orientation.scaleX, y: orientation.scaleY))

            XCTAssertEqual(asThePreviewApplies, orientation.transform, "\(pose)")
        }
    }

    /// The ceiling is two poses now, for the reason the walls are.
    func testTheTwoCeilingDirectionsAreSeparatePoses() {
        var adjustments = AvatarPoseAdjustments()

        adjustments[.onTheCeilingFacingLeft].flipsHorizontally = true

        XCTAssertTrue(adjustments[.onTheCeilingFacingLeft].flipsHorizontally)
        XCTAssertFalse(adjustments[.onTheCeilingFacingRight].flipsHorizontally)
        XCTAssertEqual(AvatarPose.onTheCeilingFacingLeft.facing, .left)
        XCTAssertEqual(AvatarPose.onTheCeilingFacingRight.facing, .right)
    }
}
