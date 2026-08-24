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
}
