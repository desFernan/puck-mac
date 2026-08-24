//
//  IdleChatterTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  The occasional idle voice line: fires on its own timer, draws from the
//  avatar's own chatter keys, silent for an avatar that has none.
//

import XCTest
@testable import Puck

final class IdleChatterTests: XCTestCase {
    private func chatter(interval: TimeInterval) -> IdleChatter {
        IdleChatter(nextIntervalProvider: { interval })
    }

    func test_staysSilentUntilTheIntervalHasPassed() {
        let sut = chatter(interval: 10)
        sut.keys = ["chatter_a"]

        XCTAssertNil(sut.tick(dt: 4))
        XCTAssertNil(sut.tick(dt: 5))
        XCTAssertEqual(sut.tick(dt: 1), "chatter_a")
    }

    func test_resetsAndFiresAgainAfterTheNextInterval() {
        let sut = chatter(interval: 10)
        sut.keys = ["chatter_a"]

        XCTAssertEqual(sut.tick(dt: 10), "chatter_a")
        XCTAssertNil(sut.tick(dt: 9))
        XCTAssertEqual(sut.tick(dt: 1), "chatter_a")
    }

    func test_anAvatarWithNoChatterKeysNeverSpeaks() {
        let sut = chatter(interval: 10)

        XCTAssertNil(sut.tick(dt: 100))
    }

    func test_drawsFromTheKeysItWasGiven() throws {
        let sut = chatter(interval: 1)
        sut.keys = ["chatter_a", "chatter_b", "chatter_c"]

        XCTAssertTrue(sut.keys.contains(try XCTUnwrap(sut.tick(dt: 1))))
    }

    /// The keys are the avatar's to declare, not the app's to name.
    func test_soundTable_findsTheChatterKeysByPrefix() {
        let table = SoundTable(
            avatarDirectory: URL(fileURLWithPath: "/tmp/Avatars/dummy"),
            sounds: [
                "walk": "sounds/footstep.wav",
                "chatter_b": "sounds/b.wav",
                "chatter_a": "sounds/a.wav",
            ]
        )

        XCTAssertEqual(table.keys(withPrefix: "chatter_"), ["chatter_a", "chatter_b"])
    }
}
