//
//  CustomisationTests.swift
//  PuckTests
//
//  The folder people drop their own character and tank picture into, and the
//  rule that what they drop in wins over what the app ships.
//

import XCTest
@testable import Puck

final class CustomisationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// One folder, named once. The avatars directory is the one that already
    /// had users; it has to keep pointing at the same place.
    func test_avatarsIsWhereItAlwaysWas() {
        XCTAssertEqual(AvatarCatalogue.avatarsDirectory, Customisation.avatars)
        XCTAssertEqual(Customisation.avatars.lastPathComponent, "Avatars")
        XCTAssertEqual(Customisation.avatars.deletingLastPathComponent(), Customisation.directory)
    }

    func test_theTankFolderSitsBesideTheAvatars() {
        XCTAssertEqual(Customisation.tank.lastPathComponent, "Tank")
        XCTAssertEqual(Customisation.tank.deletingLastPathComponent(), Customisation.directory)
    }

    /// Opening an empty folder is how somebody learns where to put things, so
    /// both have to exist before it opens.
    func test_createDirectories_makesBothOfThem() {
        Customisation.createDirectories()

        XCTAssertTrue(FileManager.default.fileExists(atPath: Customisation.avatars.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: Customisation.tank.path))
    }

    /// The point of the folder: what is in it wins.
    func test_tankArtwork_prefersTheCustomFileOverTheBundledOne() throws {
        let custom = root.appendingPathComponent("seabed.png")
        try Data("not really a png".utf8).write(to: custom)
        let bundled = root.appendingPathComponent("bundled.png")

        XCTAssertEqual(TankArtwork.resolvedURL(custom: custom, bundled: bundled), custom)
    }

    func test_tankArtwork_fallsBackToTheBundledOne() {
        let missing = root.appendingPathComponent("seabed.png")
        let bundled = root.appendingPathComponent("bundled.png")

        XCTAssertEqual(TankArtwork.resolvedURL(custom: missing, bundled: bundled), bundled)
    }

    /// The app always ships one, so this is the state where somebody has
    /// deleted it out of the bundle -- the island falls back to plain ground
    /// rather than refusing to draw.
    func test_tankArtwork_withNeither_isNil() {
        XCTAssertNil(TankArtwork.resolvedURL(custom: root.appendingPathComponent("a.png"), bundled: nil))
    }

    /// The one that actually ships is found: this is the check that catches a
    /// resource dropped from the bundle.
    func test_theBundledArtwork_resolves() {
        XCTAssertNotNil(TankArtwork.resolvedURL())
    }
}
