//
//  CharacterBodyTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  States had no way to read or write the pet's position — StateHandler only
//  received `dt` — so MoveToState/WalkState could not move anything even once
//  a frame loop existed. CharacterBody is the position/facing they act on,
//  and the single place that pushes those onto the avatar.
//

import XCTest
@testable import Puck

private final class SpyAvatar: AvatarPlayable {
    private(set) var positions: [CGPoint] = []
    private(set) var facings: [AvatarFacing] = []
    private(set) var playedClips: [String] = []
    private(set) var upsideDownCalls: [Bool] = []

    func play(clip: String, loop: Bool) { playedClips.append(clip) }
    func stop() {}
    func setScreenPosition(_ position: CGPoint) { positions.append(position) }
    func setFacing(_ facing: AvatarFacing) { facings.append(facing) }
    func setUpsideDown(_ isUpsideDown: Bool) { upsideDownCalls.append(isUpsideDown) }
}

/// `@MainActor`: the character and its states belong to the main thread,
/// which is where the frame loop drives them.
@MainActor
final class CharacterBodyTests: XCTestCase {
    func test_movingTheBody_pushesThePositionToTheAvatar() {
        let avatar = SpyAvatar()
        let body = CharacterBody(avatar: avatar, position: CGPoint(x: 10, y: 20))

        body.position = CGPoint(x: 30, y: 40)

        XCTAssertEqual(avatar.positions.last, CGPoint(x: 30, y: 40))
        XCTAssertEqual(body.position, CGPoint(x: 30, y: 40))
    }

    func test_initialPositionIsPushedOnce() {
        let avatar = SpyAvatar()
        _ = CharacterBody(avatar: avatar, position: CGPoint(x: 5, y: 5))

        XCTAssertEqual(avatar.positions, [CGPoint(x: 5, y: 5)])
    }

    func test_settingFacing_pushesToTheAvatar() {
        let avatar = SpyAvatar()
        let body = CharacterBody(avatar: avatar, position: .zero)

        body.facing = .left

        XCTAssertEqual(avatar.facings.last, .left)
    }

    /// The FSM writes facing every frame while walking; forwarding an
    /// unchanged value would re-apply the same transform 60 times a second.
    func test_settingTheSameFacingTwice_onlyPushesOnce() {
        let avatar = SpyAvatar()
        let body = CharacterBody(avatar: avatar, position: .zero)

        body.facing = .left
        body.facing = .left

        XCTAssertEqual(avatar.facings, [.left])
    }

    // MARK: - Upside-down (F3 ceiling-crawling, 2026-07-29)

    func test_settingUpsideDown_pushesToTheAvatar() {
        let avatar = SpyAvatar()
        let body = CharacterBody(avatar: avatar, position: .zero)

        body.isUpsideDown = true

        XCTAssertEqual(avatar.upsideDownCalls, [true])
    }

    func test_settingTheSameUpsideDownTwice_onlyPushesOnce() {
        let avatar = SpyAvatar()
        let body = CharacterBody(avatar: avatar, position: .zero)

        body.isUpsideDown = true
        body.isUpsideDown = true

        XCTAssertEqual(avatar.upsideDownCalls, [true])
    }

    // MARK: - Clip playback

    /// CharacterController used to hold the avatar separately just to call
    /// play() on state entry. One owner of the avatar is enough — otherwise
    /// two objects can disagree about which clip is showing.
    func test_playForwardsToTheAvatar() {
        let avatar = SpyAvatar()
        let body = CharacterBody(avatar: avatar, position: .zero)

        body.play(clip: "walk", loop: true)

        XCTAssertEqual(avatar.playedClips, ["walk"])
    }

    // MARK: - Coming off the ceiling

    /// `position` means the point the pet hangs *from* while it is upside
    /// down and the point it stands *on* the rest of the time. Clearing the
    /// flag on its own therefore moved the drawing a full height up the
    /// screen: grabbing a pet off the ceiling threw it off the top, and it
    /// only came back because the fall that followed landed it somewhere
    /// real.
    func test_turningRightSideUp_keepsTheDrawingWhereItWas() {
        let body = CharacterBody(avatar: SpyAvatar(), position: CGPoint(x: 100, y: 0))
        body.isUpsideDown = true

        body.turnRightSideUp(drawnHeight: 260)

        XCTAssertFalse(body.isUpsideDown)
        // Hanging from y=0 the pet filled 0...260; standing, the same
        // rectangle is described by its feet at 260.
        XCTAssertEqual(body.position, CGPoint(x: 100, y: 260))
    }

    /// A pet that was already the right way up is not moved. Fall calls this
    /// on every frame of a fall, and a conversion that ran each time would
    /// walk the pet down the screen a height at a time.
    func test_turningRightSideUp_whenAlreadyUpright_movesNothing() {
        let body = CharacterBody(avatar: SpyAvatar(), position: CGPoint(x: 100, y: 500))

        body.turnRightSideUp(drawnHeight: 260)
        body.turnRightSideUp(drawnHeight: 260)

        XCTAssertEqual(body.position, CGPoint(x: 100, y: 500))
    }

    /// And the flip still reaches the renderer, since the drawing has to turn
    /// over as well as stay put.
    func test_turningRightSideUp_tellsTheAvatar() {
        let avatar = SpyAvatar()
        let body = CharacterBody(avatar: avatar, position: .zero)
        body.isUpsideDown = true

        body.turnRightSideUp(drawnHeight: 260)

        XCTAssertEqual(avatar.upsideDownCalls, [true, false])
    }
}
