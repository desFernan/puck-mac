//
//  GroundedSpawnPositionTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The pet used to spawn/reset at the window's vertical center, leaving it
//  floating in empty space far above the Dock instead of standing on the
//  ground like every other roaming/landing calculation already assumes
//  (WanderScheduler's walk targets and LandingSurfaceResolver's screen-bottom
//  fallback both use the bottom edge, not the center).
//
//  No hitbox/height knowledge needed here -- AvatarPlayable.setScreenPosition
//  treats its input as the ground/feet point uniformly (SpriteAvatar converts
//  internally to its own CALayer center; USDZAvatar's rig is root-at-feet by
//  convention already), so "the ground" is simply the window's bottom edge.
//

import XCTest
@testable import Puck

final class GroundedSpawnPositionTests: XCTestCase {
    func test_positionsHorizontallyCentered() {
        let position = GroundedSpawnPosition.position(in: CGSize(width: 1000, height: 600))
        XCTAssertEqual(position.x, 500)
    }

    func test_positionsAtTheWindowsBottomEdge_minusASmallMargin() {
        let position = GroundedSpawnPosition.position(in: CGSize(width: 1000, height: 600))
        XCTAssertEqual(position.y, 600 - GroundedSpawnPosition.groundMargin)
    }
}
