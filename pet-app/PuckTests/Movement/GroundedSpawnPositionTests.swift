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
        let position = GroundedSpawnPosition.position(in: CGRect(x: 0, y: 0, width: 1000, height: 600))
        XCTAssertEqual(position.x, 500)
    }

    func test_positionsAtTheAreasBottomEdge_minusASmallMargin() {
        let position = GroundedSpawnPosition.position(in: CGRect(x: 0, y: 0, width: 1000, height: 600))
        XCTAssertEqual(position.y, 600 - GroundedSpawnPosition.groundMargin)
    }

    /// A second display's work area does not start at the overlay window's
    /// origin, and spawning at half its width would put the pet on the
    /// display next to it.
    func test_spawnsInsideTheAreaGiven_notInTheWindowItSitsIn() {
        let secondDisplay = CGRect(x: 1000, y: 200, width: 800, height: 400)
        let position = GroundedSpawnPosition.position(in: secondDisplay)
        XCTAssertEqual(position.x, 1400)
        XCTAssertEqual(position.y, 600 - GroundedSpawnPosition.groundMargin)
    }
}
