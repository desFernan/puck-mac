//
//  SpriteAvatarTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  2026-07-29 2D switch: SpriteAvatar loads PNG clips instead of usdz.
//

import XCTest
import AppKit
import QuartzCore
@testable import Puck

/// `@MainActor`: sprite layers and their animations are the main
/// thread's, like the window they are drawn in.
@MainActor
final class SpriteAvatarTests: XCTestCase {
    private var packageDirectory: URL!

    override func setUpWithError() throws {
        packageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: packageDirectory)
    }

    /// A minimal valid 4x4 PNG, distinguishable by fill color so different
    /// clips' images are provably different files.
    private func writePNG(named name: String, color: NSColor) throws {
        let size = CGSize(width: 4, height: 4)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            return XCTFail("failed to synthesize a test PNG")
        }
        try png.write(to: packageDirectory.appendingPathComponent("\(name).png"))
    }

    private func makeLoadResult(
        clips: [String: String] = ["idle": "idle"],
        emotions: [String: String] = [:]
    ) throws -> AvatarLoadResult {
        let clipsJSON = clips.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        let emotionsJSON = emotions.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        let json = """
        {
          "schema_version": 1, "name": "test", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 120, "height": 140 },
          "clips": { \(clipsJSON) },
          "emotions": { \(emotionsJSON) },
          "sounds": {}
        }
        """
        return try AvatarLoader.load(manifestData: Data(json.utf8))
    }

    // MARK: - Implicit animations

    /// A CALayer that isn't a view's backing layer animates position/transform
    /// implicitly, 0.25s per assignment. The FSM assigns 60 times a second, so
    /// what renders is a value perpetually easing toward a target that already
    /// moved -- the sprite trails the pet and slides past where it stopped,
    /// reading as janky rather than smooth. Every per-frame property has to opt out, or the frame loop's
    /// output gets smoothed behind its back.
    func test_spriteLayer_hasImplicitAnimationsDisabled() throws {
        try writePNG(named: "idle", color: .red)

        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory,
            loadResult: try makeLoadResult(),
            parent: CALayer()
        )

        // Asserted on the actions dictionary rather than action(forKey:):
        // the lookup only resolves to a real animation once the layer is in a
        // live render tree, so off-screen it reports nil either way and would
        // pass just as happily with the opt-out missing.
        let actions = avatar.spriteLayer.actions ?? [:]
        for property in ["position", "transform", "contents", "bounds"] {
            XCTAssertTrue(
                actions[property] is NSNull,
                "\(property) must be mapped to NSNull so it never animates implicitly"
            )
        }
    }

    // MARK: - Retina rasterization

    /// A hand-made CALayer defaults to contentsScale 1.0 regardless of the
    /// display it ends up on -- only a view's own backing layer gets the
    /// window's scale for free. Left at 1.0 on a 2x screen the sprite is
    /// rasterized at half the physical resolution and upscaled: visibly soft,
    /// and because the bitmap is aligned to the coarser 1x pixel grid, a walk
    /// that advances ~1.5pt per frame renders as stair-stepped jitter instead
    /// of smooth motion.
    func test_spriteLayer_inheritsParentContentsScale_soItRasterizesAtRetinaResolution() throws {
        try writePNG(named: "idle", color: .red)
        let parent = CALayer()
        parent.contentsScale = 2

        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory,
            loadResult: try makeLoadResult(),
            parent: parent
        )

        XCTAssertEqual(avatar.spriteLayer.contentsScale, 2)
    }

    /// OverlayWindowController rebuilds every window/view on a display change,
    /// so reparenting is exactly when the pet can move between a 1x and a 2x
    /// screen -- the scale has to follow it there.
    func test_reparent_adoptsTheNewParentsContentsScale() throws {
        try writePNG(named: "idle", color: .red)
        let onex = CALayer()
        onex.contentsScale = 1
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory,
            loadResult: try makeLoadResult(),
            parent: onex
        )

        let retina = CALayer()
        retina.contentsScale = 2
        avatar.reparent(to: retina)

        XCTAssertEqual(avatar.spriteLayer.contentsScale, 2)
    }

    func test_play_setsLayerContentsFromThePNGFile() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let parent = CALayer()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: parent)

        avatar.play(clip: "idle", loop: true)

        XCTAssertNotNil(avatar.spriteLayer.contents)
    }

    func test_play_missingClip_fallsBackToIdlesImage() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.play(clip: "walk", loop: true) // not in the manifest's clips -- falls back to idle
        let afterFallback = avatar.spriteLayer.contents

        avatar.play(clip: "idle", loop: true)
        let afterIdle = avatar.spriteLayer.contents

        XCTAssertNotNil(afterFallback)
        // Both should be the same cached CGImage instance (idle's), not merely non-nil.
        XCTAssertTrue((afterFallback as! CGImage) === (afterIdle as! CGImage))
    }

    func test_play_withMissingFileOnDisk_doesNotCrashAndLeavesContentsUnchanged() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult(clips: ["idle": "idle", "walk": "walk"])
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.play(clip: "idle", loop: true)
        let beforeMissingPlay = avatar.spriteLayer.contents

        avatar.play(clip: "walk", loop: true) // walk.png was never written
        XCTAssertTrue((avatar.spriteLayer.contents as! CGImage) === (beforeMissingPlay as! CGImage))
    }

    /// The FSM's `position` is the character's ground/feet point everywhere
    /// else in the codebase (WalkState's targets, LandingSurfaceResolver,
    /// USDZAvatar's root-at-feet rig convention) -- CALayer's own `position`
    /// is its *center* by default, so SpriteAvatar has to convert, or the
    /// pet floats half its height above wherever the FSM thinks it's
    /// standing (this was an observed bug: the pet hanging in empty
    /// space instead of standing on the Dock).
    func test_setScreenPosition_treatsInputAsGroundPoint_notLayerCenter() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // hitbox height 140, scale 1.0
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setScreenPosition(CGPoint(x: 42, y: 99))

        // Center = ground point minus half the rendered height, so the
        // sprite's bottom edge lands exactly on the ground point.
        XCTAssertEqual(avatar.spriteLayer.position, CGPoint(x: 42, y: 99 - 70))
    }

    /// Hanging from the ceiling (F3, 2026-07-29): `position` is
    /// `roamableArea.minY`, the ceiling line. The flip (setUpsideDown)
    /// makes the art's feet render at the TOP of the layer and its head at
    /// the bottom, so the layer must extend DOWNWARD from the ceiling point
    /// -- the opposite offset from the ground-standing case. Getting this
    /// wrong doesn't just look wrong, it renders the sprite entirely off the
    /// top edge of the screen (this was the actual bug: nothing visibly hung
    /// from the ceiling because the sprite was pushed off-screen).
    func test_setScreenPosition_whenUpsideDown_hangsDownwardFromTheCeilingPoint() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // hitbox height 140, scale 1.0
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setUpsideDown(true)
        avatar.setScreenPosition(CGPoint(x: 42, y: 0))

        XCTAssertEqual(avatar.spriteLayer.position, CGPoint(x: 42, y: 70))
    }

    /// setUpsideDown only used to flip the transform (scaleY), never
    /// recomputing the position offset -- that happened lazily, the next
    /// time something called setScreenPosition. For one frame right as
    /// CeilingState hands off to FallState (which resets isUpsideDown before
    /// its own first position update runs), the sprite would render
    /// right-side-up but still positioned with the hanging-downward offset:
    /// a one-frame pop that reads as a stutter/teleport.
    func test_setUpsideDown_immediatelyRecomputesTheCachedPosition() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // hitbox height 140, scale 1.0
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setScreenPosition(CGPoint(x: 42, y: 0))
        avatar.setUpsideDown(true)

        XCTAssertEqual(avatar.spriteLayer.position, CGPoint(x: 42, y: 70))
    }

    // MARK: - triggerJump (F3: agent_done / code_editor path change)

    func test_triggerJump_offsetsPositionUpwardMidway() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let clock = TestClock()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer(), now: clock.now)
        avatar.setScreenPosition(CGPoint(x: 10, y: 100))
        let restingY = avatar.spriteLayer.position.y

        avatar.triggerJump()
        clock.advance(JumpFlourish.duration / 2)
        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 0)

        XCTAssertLessThan(avatar.spriteLayer.position.y, restingY, "midway through a jump the sprite should be higher up (smaller y)")
    }

    func test_triggerJump_settlesBackToRestAfterItEnds() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let clock = TestClock()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer(), now: clock.now)
        avatar.setScreenPosition(CGPoint(x: 10, y: 100))
        let restingY = avatar.spriteLayer.position.y

        avatar.triggerJump()
        clock.advance(JumpFlourish.duration + 1)
        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 0)

        XCTAssertEqual(avatar.spriteLayer.position.y, restingY, accuracy: 0.001)
    }

    func test_setFacingLeft_flipsLayerHorizontally() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let clock = TestClock()
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer(), now: clock.now
        )

        avatar.setFacing(.left)
        // Past the end of the turn: the settled value is what matters here.
        clock.advance(FlipAnimation.duration)
        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 0)

        XCTAssertEqual(avatar.spriteLayer.affineTransform().a, -1, accuracy: 0.0001)
    }

    func test_setFacingRight_isIdentityScaleX() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let clock = TestClock()
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer(), now: clock.now
        )

        avatar.setFacing(.left)
        clock.advance(FlipAnimation.duration)
        avatar.setFacing(.right)
        clock.advance(FlipAnimation.duration)
        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 0)

        XCTAssertEqual(avatar.spriteLayer.affineTransform().a, 1, accuracy: 0.0001)
    }

    // MARK: - Turning (the paper-flip motion)

    /// The turn has to be recomputed from elapsed time on every frame, not
    /// handed to Core Animation: applyTransform rewrites the layer transform
    /// each frame for the procedural bounce, so an attached animation would
    /// be overwritten immediately.
    func test_turning_narrowsToEdgeOnPartWayThrough() throws {
        try writePNG(named: "idle", color: .red)
        let clock = TestClock()
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory, loadResult: try makeLoadResult(), parent: CALayer(), now: clock.now
        )

        avatar.setFacing(.left)
        clock.advance(FlipAnimation.duration / 2)
        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 0)

        XCTAssertEqual(avatar.spriteLayer.affineTransform().a, 0, accuracy: 0.0001, "edge-on at the halfway point")
    }

    func test_turning_startsAtFullWidthFacingTheOldWay() throws {
        try writePNG(named: "idle", color: .red)
        let clock = TestClock()
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory, loadResult: try makeLoadResult(), parent: CALayer(), now: clock.now
        )

        avatar.setFacing(.left)

        XCTAssertEqual(avatar.spriteLayer.affineTransform().a, 1, accuracy: 0.0001, "the turn has not started yet")
    }

    /// Turning back mid-turn must resume from the width currently on screen,
    /// not snap out to full width and start over.
    func test_turningBackMidTurn_resumesFromTheCurrentWidth() throws {
        try writePNG(named: "idle", color: .red)
        let clock = TestClock()
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory, loadResult: try makeLoadResult(), parent: CALayer(), now: clock.now
        )

        avatar.setFacing(.left)
        clock.advance(FlipAnimation.duration / 2) // edge-on
        avatar.setFacing(.right)
        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 0)

        XCTAssertEqual(avatar.spriteLayer.affineTransform().a, 0, accuracy: 0.0001, "still edge-on, no snap")

        clock.advance(FlipAnimation.duration)
        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 0)
        XCTAssertEqual(avatar.spriteLayer.affineTransform().a, 1, accuracy: 0.0001, "and settles facing right")
    }

    func test_updateBounce_combinesWithFacing() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let clock = TestClock()
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer(), now: clock.now
        )

        avatar.setFacing(.left)
        clock.advance(FlipAnimation.duration)
        avatar.updateBounce(clip: "land", elapsed: 0, intensity: 1.0) // land at t=0 -> scaleX 1.3, scaleY 0.7

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.a, -1.3, accuracy: 0.001) // 1.3 scale, flipped negative
        XCTAssertEqual(transform.d, 0.7, accuracy: 0.001)
    }

    // MARK: - Climbing rotation (F3 wall-climbing, 2026-07-29)

    /// Climbing (both
    /// ClimbState and ClimbToCeilingState share the "climb" clip) rotates
    /// the sprite 90 degrees, the same way isUpsideDown flips it for the
    /// ceiling. Derived from the clip name already passed into updateBounce
    /// every frame -- no new AvatarPlayable method needed.
    func test_updateBounce_withClimbClip_rotatesTheSpriteNinetyDegrees() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateBounce(clip: "climb", elapsed: 0, intensity: 1.0)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.a, 0, accuracy: 0.001)
        XCTAssertEqual(abs(transform.b), 1, accuracy: 0.001)
    }

    func test_updateBounce_withNonClimbClip_doesNotRotate() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 1.0)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.b, 0, accuracy: 0.001)
    }

    func test_updateBounce_leavingClimbClip_resetsRotation() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateBounce(clip: "climb", elapsed: 0, intensity: 1.0)
        avatar.updateBounce(clip: "walk", elapsed: 0, intensity: 1.0)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.b, 0, accuracy: 0.001)
    }

    func test_init_sizesLayerToHitboxTimesScale() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        XCTAssertEqual(avatar.spriteLayer.bounds.size, CGSize(width: 120, height: 140))
    }

    // MARK: - updateScale (Settings size slider, 2026-07-29)

    func test_updateScale_resizesTheLayerFromTheOriginalHitbox() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // hitbox 120x140
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateScale(0.5)

        XCTAssertEqual(avatar.spriteLayer.bounds.size, CGSize(width: 60, height: 70))
    }

    func test_updateScale_appliedTwice_isNotCumulative() throws {
        // Each call recomputes from the original hitbox, not the layer's
        // current (already-scaled) bounds -- otherwise repeated slider
        // changes would compound instead of just reflecting the latest value.
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateScale(0.5)
        avatar.updateScale(2.0)

        XCTAssertEqual(avatar.spriteLayer.bounds.size, CGSize(width: 240, height: 280))
    }

    /// updateScale changes spriteLayer.bounds.height, which
    /// setScreenPosition's ground-point offset depends on -- previously left
    /// as an undocumented-in-code caller contract ("the caller is expected to
    /// re-push the character's position afterward"), unlike setUpsideDown,
    /// which already self-heals via the same setScreenPosition(lastPosition)
    /// call (found via review). A future caller that forgot the follow-up
    /// would leave the sprite floating at the stale ground offset.
    func test_updateScale_reappliesTheGroundOffsetForTheNewHeight() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // hitbox 120x140
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())
        avatar.setScreenPosition(CGPoint(x: 100, y: 200))

        avatar.updateScale(0.5) // new height 70 -> offset -35

        XCTAssertEqual(avatar.spriteLayer.position, CGPoint(x: 100, y: 165))
    }

    // MARK: - showEmotion (Settings emotion mapping, 2026-07-29)

    func test_showEmotion_setsLayerContentsFromTheMappedPNG() throws {
        try writePNG(named: "idle", color: .red)
        try writePNG(named: "happy", color: .green)
        let loadResult = try makeLoadResult(emotions: ["happy": "happy"])
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())
        avatar.play(clip: "idle", loop: true)
        let idleContents = avatar.spriteLayer.contents

        avatar.showEmotion("happy")

        XCTAssertFalse((avatar.spriteLayer.contents as! CGImage) === (idleContents as! CGImage))
    }

    func test_showEmotion_unmappedKey_isSilentNoOp() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // no emotions at all
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())
        avatar.play(clip: "idle", loop: true)
        let idleContents = avatar.spriteLayer.contents

        avatar.showEmotion("thinking") // not in the (empty) emotions table

        XCTAssertTrue((avatar.spriteLayer.contents as! CGImage) === (idleContents as! CGImage))
    }

    // MARK: - setUpsideDown (F3 ceiling-crawling, 2026-07-29)

    /// A Y-only flip, not a 180deg rotation -- rotation would also reverse
    /// the apparent left/right walking direction while upside-down.
    func test_setUpsideDownTrue_flipsLayerVertically() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setUpsideDown(true)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.a, 1, accuracy: 0.0001)
        XCTAssertEqual(transform.d, -1, accuracy: 0.0001)
    }

    func test_setUpsideDownFalse_afterTrue_restoresIdentity() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setUpsideDown(true)
        avatar.setUpsideDown(false)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.d, 1, accuracy: 0.0001)
    }

    func test_setUpsideDown_combinesWithFacingLeft() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let clock = TestClock()
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer(), now: clock.now
        )

        avatar.setFacing(.left)
        clock.advance(FlipAnimation.duration) // let the turn settle
        avatar.setUpsideDown(true)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.a, -1, accuracy: 0.0001)
        XCTAssertEqual(transform.d, -1, accuracy: 0.0001)
    }

    /// OverlayWindowController tears down and recreates every window+SpriteLayerView
    /// on a real display change -- mirrors USDZAvatar.reparent's precedent.
    func test_reparent_movesTheSpriteLayerToTheNewParent() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let oldParent = CALayer()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: oldParent)
        XCTAssertTrue(oldParent.sublayers?.contains(avatar.spriteLayer) ?? false)

        let newParent = CALayer()
        avatar.reparent(to: newParent)

        XCTAssertFalse(oldParent.sublayers?.contains(avatar.spriteLayer) ?? false)
        XCTAssertTrue(newParent.sublayers?.contains(avatar.spriteLayer) ?? false)
    }
}

/// A hand-cranked clock, so the turn animation can be tested at exact points
/// along its 0.12s without any waiting or flakiness.
final class TestClock {
    private var current: TimeInterval = 1000

    func now() -> TimeInterval { current }

    func advance(_ seconds: TimeInterval) {
        current += seconds
    }
}

/// The rainbow tint is applied by masking a colour layer with the sprite, and
/// nothing but rendering can tell you whether that actually landed on the
/// artwork -- the preset's hue number being right says nothing about the
/// compositing being wired up. So this renders the layer for real.
final class SpriteAvatarTintTests: XCTestCase {
    private var packageDirectory: URL!

    override func setUpWithError() throws {
        packageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)

        // A solid white square, so any colour in the output came from the tint.
        let size = CGSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: packageDirectory.appendingPathComponent("idle.png"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: packageDirectory)
        super.tearDown()
    }

    private func makeAvatar() throws -> SpriteAvatar {
        let json = """
        {"schema_version":1,"name":"t","type":"sprites","scale":1.0,
         "hitbox":{"width":8,"height":8},"clips":{"idle":"idle"},"sounds":{}}
        """
        let parent = CALayer()
        parent.contentsScale = 1
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory,
            loadResult: try AvatarLoader.load(manifestData: Data(json.utf8)),
            parent: parent
        )
        avatar.play(clip: "idle", loop: false)
        return avatar
    }

    /// Average colour of the rendered sprite.
    private func render(_ avatar: SpriteAvatar) throws -> (r: Int, g: Int, b: Int) {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            avatar.spriteLayer.render(in: context)
        }
        var totals = (0, 0, 0)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            totals.0 += Int(pixels[index])
            totals.1 += Int(pixels[index + 1])
            totals.2 += Int(pixels[index + 2])
        }
        let count = side * side
        return (totals.0 / count, totals.1 / count, totals.2 / count)
    }

    func test_untintedSpriteKeepsItsOwnColours() throws {
        let avatar = try makeAvatar()
        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 1)

        let colour = try render(avatar)

        XCTAssertEqual(colour.r, colour.g, accuracy: 6, "white art should render neutral")
        XCTAssertEqual(colour.g, colour.b, accuracy: 6)
    }

    func test_theSpinTintsTheArtworkRed() throws {
        let avatar = try makeAvatar()
        // Elapsed 0 is the first half turn — hue 0, red.
        avatar.updateBounce(clip: "spin", elapsed: 0, intensity: 1)

        let colour = try render(avatar)

        XCTAssertGreaterThan(colour.r, colour.g + 30, "not noticeably red")
        XCTAssertGreaterThan(colour.r, colour.b + 30)
    }

    /// Different points in the spin must give different colours, or the
    /// rainbow never actually reaches the screen.
    func test_laterInTheSpinTheTintIsADifferentColour() throws {
        let avatar = try makeAvatar()
        avatar.updateBounce(clip: "spin", elapsed: 0, intensity: 1)
        let first = try render(avatar)

        // Far enough in to be several half-turns along.
        avatar.updateBounce(clip: "spin", elapsed: SpinState.duration * 0.5, intensity: 1)
        let later = try render(avatar)

        XCTAssertTrue(
            first.r != later.r || first.g != later.g || first.b != later.b,
            "the tint never changed on screen"
        )
    }

    /// Leaving the spin has to put the pet back to its own colours.
    func test_leavingTheSpinClearsTheTint() throws {
        let avatar = try makeAvatar()
        avatar.updateBounce(clip: "spin", elapsed: 0, intensity: 1)
        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 1)

        let colour = try render(avatar)

        XCTAssertEqual(colour.r, colour.g, accuracy: 6, "tint outlived the spin")
    }
}
