//
//  AvatarManifestEditorTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Read/write the *currently installed* avatar's manifest.json, for the
//  Settings size slider and emotion-image mapping (2026-07-29).
//

import XCTest
@testable import Puck

final class AvatarManifestEditorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeManifest(scale: Double = 1.0) throws {
        let json = """
        {
          "schema_version": 1, "name": "dummy", "type": "sprites", "scale": \(scale),
          "hitbox": { "width": 120, "height": 140 },
          "clips": { "idle": "idle" },
          "sounds": {}
        }
        """
        try json.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    }

    private func writePNG(named name: String) throws {
        // Contents don't matter for these tests -- only that copying happens.
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: directory.appendingPathComponent("\(name).png"))
    }

    func test_loadManifest_readsFromDisk() throws {
        try writeManifest(scale: 1.5)

        let manifest = try AvatarManifestEditor.loadManifest(directory: directory)

        XCTAssertEqual(manifest.name, "dummy")
        XCTAssertEqual(manifest.scale, 1.5)
    }

    func test_loadManifest_missingFile_throws() {
        XCTAssertThrowsError(try AvatarManifestEditor.loadManifest(directory: directory))
    }

    func test_updateScale_persistsToDiskAndReturnsUpdatedManifest() throws {
        try writeManifest(scale: 1.0)

        let updated = try AvatarManifestEditor.updateScale(2.0, directory: directory)
        XCTAssertEqual(updated.scale, 2.0)

        let reloaded = try AvatarManifestEditor.loadManifest(directory: directory)
        XCTAssertEqual(reloaded.scale, 2.0)
    }

    func test_updateScale_leavesOtherFieldsUntouched() throws {
        try writeManifest(scale: 1.0)

        let updated = try AvatarManifestEditor.updateScale(2.0, directory: directory)

        XCTAssertEqual(updated.name, "dummy")
        XCTAssertEqual(updated.hitbox, AvatarManifest.Hitbox(width: 120, height: 140))
        XCTAssertEqual(updated.clips["idle"], .name("idle"))
    }

    func test_setEmotionImage_copiesTheFileAndUpdatesTheManifest() throws {
        try writeManifest()
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        let sourceFile = sourceDirectory.appendingPathComponent("my_happy_face.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceFile)

        let updated = try AvatarManifestEditor.setEmotionImage(named: "happy", sourceFile: sourceFile, directory: directory)

        XCTAssertEqual(updated.emotions?["happy"], .name("happy"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("happy.png").path))

        let reloaded = try AvatarManifestEditor.loadManifest(directory: directory)
        XCTAssertEqual(reloaded.emotions?["happy"], .name("happy"))
    }

    func test_setEmotionImage_overwritesAnExistingMapping() throws {
        try writeManifest()
        try writePNG(named: "happy") // an old mapping's file already present
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        let sourceFile = sourceDirectory.appendingPathComponent("new_face.png")
        try Data([0x01, 0x02, 0x03, 0x04]).write(to: sourceFile)

        let updated = try AvatarManifestEditor.setEmotionImage(named: "happy", sourceFile: sourceFile, directory: directory)

        XCTAssertEqual(updated.emotions?["happy"], .name("happy"))
        let installedData = try Data(contentsOf: directory.appendingPathComponent("happy.png"))
        XCTAssertEqual(installedData, Data([0x01, 0x02, 0x03, 0x04]))
    }

    func test_setEmotionImage_preservesOtherEmotions() throws {
        try writeManifest()
        _ = try AvatarManifestEditor.setEmotionImage(
            named: "sad",
            sourceFile: try makeSourceFile(name: "a.png"),
            directory: directory
        )

        let updated = try AvatarManifestEditor.setEmotionImage(
            named: "happy",
            sourceFile: try makeSourceFile(name: "b.png"),
            directory: directory
        )

        XCTAssertEqual(updated.emotions?["sad"], .name("sad"))
        XCTAssertEqual(updated.emotions?["happy"], .name("happy"))
    }

    // A custom emotion name typed into Settings' TextField was only trimmed
    // of whitespace before being used as `"\(emotion).png"` -- a name
    // containing "/" or ".." let writes land outside the avatar directory
    // (found via review). This is the defense-in-depth check at the point
    // the path is actually built; AvatarManagementView.addCustomEmotion also
    // rejects these earlier, at input time.
    func test_setEmotionImage_rejectsANameContainingAPathSeparator() throws {
        try writeManifest()

        XCTAssertThrowsError(
            try AvatarManifestEditor.setEmotionImage(
                named: "../../evil",
                sourceFile: try makeSourceFile(name: "a.png"),
                directory: directory
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("evil.png").path))
    }

    func test_setEmotionImage_rejectsADotOnlyName() throws {
        try writeManifest()

        XCTAssertThrowsError(
            try AvatarManifestEditor.setEmotionImage(named: "..", sourceFile: try makeSourceFile(name: "a.png"), directory: directory)
        )
    }

    private func makeSourceFile(name: String) throws -> URL {
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let file = sourceDirectory.appendingPathComponent(name)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)
        return file
    }
}
