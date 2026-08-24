//
//  SoundTableTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  manifest sounds table lookup — unmapped key means silence by design
//  (plan/02_pet-app.md F5: "미매핑 키 무음").
//

import XCTest
@testable import Puck

final class SoundTableTests: XCTestCase {
    private let avatarDirectory = URL(fileURLWithPath: "/tmp/Avatars/dummy")

    func test_mappedKey_resolvesToFileURLUnderAvatarDirectory() {
        let table = SoundTable(avatarDirectory: avatarDirectory, sounds: ["walk": "sounds/footstep.wav"])

        XCTAssertEqual(
            table.fileURL(for: "walk"),
            avatarDirectory.appendingPathComponent("sounds/footstep.wav")
        )
    }

    func test_unmappedKey_resolvesToNil() {
        let table = SoundTable(avatarDirectory: avatarDirectory, sounds: ["walk": "sounds/footstep.wav"])

        XCTAssertNil(table.fileURL(for: "climb"))
    }

    func test_sharesKeySpaceBetweenClipNamesAndEventNames() {
        // Same table, same lookup for both an FSM clip key and a socket event-name key.
        let table = SoundTable(
            avatarDirectory: avatarDirectory,
            sounds: ["walk": "sounds/footstep.wav", "task_success": "sounds/ding.wav"]
        )

        XCTAssertNotNil(table.fileURL(for: "walk"))
        XCTAssertNotNil(table.fileURL(for: "task_success"))
    }
}
