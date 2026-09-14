//
//  PosePreviewMatchesRendererTests.swift
//  PuckTests
//
//  The settings window's pose preview, measured against the renderer it is a
//  preview of.
//
//  Written after the second time the two disagreed. Reasoning about the
//  transforms is what produced both mistakes -- once the order they were
//  composed in, once a mirror hidden inside the bounce -- so this drives the
//  real SpriteAvatar and compares the matrix it puts on its layer against the
//  matrix the preview builds. Anything that reaches one and not the other
//  fails here.
//
//  The turn animation is allowed to settle first: the preview draws a pose,
//  and a pet caught halfway through turning around is not one.
//

import XCTest
import AppKit
import QuartzCore
@testable import Puck

@MainActor
final class PosePreviewMatchesRendererTests: XCTestCase {
    private var packageDirectory: URL!
    private var clock: TimeInterval = 0

    override func setUpWithError() throws {
        packageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)

        let size = CGSize(width: 4, height: 4)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return XCTFail("failed to synthesize a test PNG") }
        for name in ["idle", "walk", "climb"] {
            try png.write(to: packageDirectory.appendingPathComponent("\(name).png"))
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: packageDirectory)
    }

    private func makeAvatar() throws -> SpriteAvatar {
        let json = """
        {"schema_version":1,"name":"t","type":"sprites","scale":1.0,
         "hitbox":{"width":120,"height":140},
         "clips":{"idle":"idle","walk":"walk","climb":"climb"},"emotions":{},"sounds":{}}
        """
        return SpriteAvatar(
            avatarDirectory: packageDirectory,
            loadResult: try AvatarLoader.load(manifestData: Data(json.utf8)),
            parent: CALayer(),
            now: { self.clock }
        )
    }

    /// What the pet's layer is actually holding, once it has settled into the
    /// pose and with nothing moving.
    private func rendered(_ pose: AvatarPose, isMirrored: Bool = false) throws -> CGAffineTransform {
        clock = 0
        let avatar = try makeAvatar()
        avatar.play(clip: pose.clip, loop: true)
        avatar.setFacing(pose.facing)
        avatar.setUpsideDown(pose.isUpsideDown)
        avatar.setMirrored(isMirrored)
        // Past the turn's own duration, so the pet is facing where it means
        // to rather than partway there.
        clock = 10
        // elapsed 0: the waddle passes through its own zero there, so what is
        // left is the pose -- which is what a still preview can show.
        avatar.updateBounce(clip: pose.clip, elapsed: 0, intensity: 1)
        return avatar.spriteLayer.affineTransform()
    }

    private func assertMatches(
        _ pose: AvatarPose,
        isMirrored: Bool = false,
        adjustment: AvatarPoseAdjustment = .none,
        line: UInt = #line
    ) throws {
        let rendered = try rendered(pose, isMirrored: isMirrored)
        let preview = AvatarPoseOrientation.of(pose, adjustment: adjustment, isMirrored: isMirrored).transform

        for (name, drawn, shown) in [
            ("a", rendered.a, preview.a), ("b", rendered.b, preview.b),
            ("c", rendered.c, preview.c), ("d", rendered.d, preview.d),
        ] {
            XCTAssertEqual(
                drawn, shown, accuracy: 0.0001,
                "\(pose.rawValue): the preview's \(name) is not the pet's",
                line: line
            )
        }
    }

    func test_everyPoseIsDrawnTheWayThePreviewShowsIt() throws {
        for pose in AvatarPose.allCases {
            try assertMatches(pose)
        }
    }

    /// The global mirror reaches both, and reaches them the same way.
    func test_aMirroredAvatarMatchesToo() throws {
        for pose in AvatarPose.allCases {
            try assertMatches(pose, isMirrored: true)
        }
    }

    /// The climbing poses are the ones that went wrong: the clip holds the
    /// pet mirrored on both axes so its feet are against the wall, and the
    /// preview drew it 180 degrees the other way round.
    func test_aClimbingPetIsHeldFeetAgainstTheWallInBoth() throws {
        let rendered = try rendered(.climbingRightWall)

        // Feet-to-the-wall is the quarter turn *and* the two mirrors, which
        // together read as a quarter turn the other way.
        XCTAssertEqual(rendered.b, -1, accuracy: 0.0001)
        XCTAssertEqual(rendered.c, 1, accuracy: 0.0001)
        try assertMatches(.climbingRightWall)
    }

    /// Turning the wobble off is not the same as asking to be put on the wall
    /// the wrong way round -- which is what it used to mean, because the pose
    /// was returned from the bounce and the bounce was gated on intensity.
    func test_aPetWithNoBounceStillClimbsFeetFirst() throws {
        clock = 0
        let avatar = try makeAvatar()
        avatar.play(clip: "climb", loop: true)
        avatar.setFacing(.right)
        clock = 10
        avatar.updateBounce(clip: "climb", elapsed: 0.3, intensity: 0)

        let transform = avatar.spriteLayer.affineTransform()

        XCTAssertEqual(transform.b, -1, accuracy: 0.0001)
        XCTAssertEqual(transform.c, 1, accuracy: 0.0001)
    }
}
