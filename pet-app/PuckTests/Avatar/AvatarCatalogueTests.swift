//
//  AvatarCatalogueTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  A preset picker needs to know what's actually installed. Multiple
//  differently-named avatar folders already coexist fine on disk
//  (AvatarInstaller only ever touches its own destination name), so this is
//  purely an enumeration, not a storage change.
//

import XCTest
@testable import Puck

final class AvatarCatalogueTests: XCTestCase {
    private var avatarsDirectory: URL!

    override func setUpWithError() throws {
        avatarsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: avatarsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: avatarsDirectory)
    }

    private func makeAvatarFolder(named name: String, withManifest: Bool = true) throws {
        let directory = avatarsDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if withManifest {
            try Data("{}".utf8).write(to: directory.appendingPathComponent("manifest.json"))
        }
    }

    func test_emptyDirectory_hasNoAvatars() {
        XCTAssertEqual(AvatarCatalogue.installedAvatarNames(in: avatarsDirectory), [])
    }

    func test_nonexistentDirectory_hasNoAvatars() {
        let missing = avatarsDirectory.appendingPathComponent("nope", isDirectory: true)
        XCTAssertEqual(AvatarCatalogue.installedAvatarNames(in: missing), [])
    }

    func test_returnsFoldersThatHaveAManifest() throws {
        try makeAvatarFolder(named: "dummy")
        try makeAvatarFolder(named: "wizard")

        XCTAssertEqual(AvatarCatalogue.installedAvatarNames(in: avatarsDirectory), ["dummy", "wizard"])
    }

    /// A folder with no manifest.json is a broken/partial install (same
    /// standard AvatarInstaller itself uses to decide "not a real install"),
    /// not a pickable preset.
    func test_excludesFoldersWithoutAManifest() throws {
        try makeAvatarFolder(named: "dummy")
        try makeAvatarFolder(named: "half-copied", withManifest: false)

        XCTAssertEqual(AvatarCatalogue.installedAvatarNames(in: avatarsDirectory), ["dummy"])
    }

    func test_sortsNamesAlphabetically() throws {
        try makeAvatarFolder(named: "zebra")
        try makeAvatarFolder(named: "apple")

        XCTAssertEqual(AvatarCatalogue.installedAvatarNames(in: avatarsDirectory), ["apple", "zebra"])
    }
}
