//
//  AvatarPackagePathTests.swift
//  PuckTests
//
//  manifest.json is data an avatar package brings with it. The clip and sound
//  tables used to be joined onto the package directory verbatim, so a
//  manifest could name a file anywhere on the disk and pet-app would read it.
//

import XCTest
@testable import Puck

final class AvatarPackagePathTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/Avatars/pet", isDirectory: true)

    func test_aPlainName_resolvesInsideThePackage() throws {
        let url = try XCTUnwrap(AvatarPackagePath.fileURL(in: directory, relativePath: "idle.png"))

        XCTAssertEqual(url.path, "/tmp/Avatars/pet/idle.png")
    }

    /// Sounds are documented as relative paths, so a subdirectory is a normal
    /// thing for a package to use.
    func test_aSubdirectory_resolvesInsideThePackage() throws {
        let url = try XCTUnwrap(AvatarPackagePath.fileURL(in: directory, relativePath: "sounds/walk.wav"))

        XCTAssertEqual(url.path, "/tmp/Avatars/pet/sounds/walk.wav")
    }

    func test_aNameThatClimbsOut_isRefused() {
        XCTAssertNil(AvatarPackagePath.fileURL(in: directory, relativePath: "../../../../etc/passwd"))
    }

    /// Climbing out and back in is still outside for as long as it is out --
    /// and names a file in a sibling avatar's package.
    func test_aNameThatClimbsIntoASibling_isRefused() {
        XCTAssertNil(AvatarPackagePath.fileURL(in: directory, relativePath: "../other/idle.png"))
    }

    func test_anAbsolutePath_isRefused() {
        XCTAssertNil(AvatarPackagePath.fileURL(in: directory, relativePath: "/etc/passwd"))
    }

    func test_anEmptyName_isRefused() {
        XCTAssertNil(AvatarPackagePath.fileURL(in: directory, relativePath: ""))
    }

    /// The package directory itself is not a file in it.
    func test_theDirectoryItself_isRefused() {
        XCTAssertNil(AvatarPackagePath.fileURL(in: directory, relativePath: "."))
    }

    /// The table that actually plays the sounds goes through the same rule.
    func test_soundTable_refusesAPathOutsideThePackage() {
        let table = SoundTable(
            avatarDirectory: directory,
            sounds: ["walk": "sounds/walk.wav", "escape": "../../../../System/Library/Sounds/Ping.aiff"]
        )

        XCTAssertEqual(table.fileURL(for: "walk")?.path, "/tmp/Avatars/pet/sounds/walk.wav")
        XCTAssertNil(table.fileURL(for: "escape"))
    }
}
