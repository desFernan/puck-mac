//
//  PlayerNodePoolTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Pool selection logic (prefer idle, fall back to round-robin) tested
//  against a fake node instead of a real, engine-attached AVAudioPlayerNode.
//

import XCTest
@testable import Puck

private final class FakeNode: PooledAudioNode {
    var isPlaying: Bool
    init(isPlaying: Bool = false) { self.isPlaying = isPlaying }
}

final class PlayerNodePoolTests: XCTestCase {
    func test_prefersAnIdleNode() {
        let busy = FakeNode(isPlaying: true)
        let idle = FakeNode(isPlaying: false)
        let pool = PlayerNodePool(nodes: [busy, idle])

        XCTAssertTrue(pool.nextAvailableNode() === idle)
    }

    func test_allBusy_fallsBackToRoundRobin() {
        let first = FakeNode(isPlaying: true)
        let second = FakeNode(isPlaying: true)
        let pool = PlayerNodePool(nodes: [first, second])

        XCTAssertTrue(pool.nextAvailableNode() === first)
        XCTAssertTrue(pool.nextAvailableNode() === second)
        XCTAssertTrue(pool.nextAvailableNode() === first) // wraps around
    }

    func test_singleNodePool_alwaysReturnsThatNode() {
        let only = FakeNode(isPlaying: true)
        let pool = PlayerNodePool(nodes: [only])

        XCTAssertTrue(pool.nextAvailableNode() === only)
        XCTAssertTrue(pool.nextAvailableNode() === only)
    }
}
