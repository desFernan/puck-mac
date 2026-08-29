//
//  AvatarImportValidatorTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Validates the file-per-clip package layout:
//  each clip's {name}.usdz must actually exist on disk (not just as a
//  manifest key) and fit the per-file size budget. Mesh height/scale and
//  loop pose-matching aren't checked here — there is no fixture for it.
//

import XCTest
@testable import Puck

final class AvatarImportValidatorTests: XCTestCase {
    private var packageDirectory: URL!

    override func setUpWithError() throws {
        packageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: packageDirectory)
    }

    private func writeManifest(clips: [String: String], type: String = "usdz") throws {
        let clipsJSON = clips.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        let json = """
        {
          "schema_version": 1, "name": "test", "type": "\(type)", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { \(clipsJSON) },
          "sounds": {}
        }
        """
        try json.write(
            to: packageDirectory.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeClipFile(_ fileName: String, sizeInBytes: Int = 1024, extension fileExtension: String = "usdz") throws {
        let data = Data(repeating: 0, count: sizeInBytes)
        try data.write(to: packageDirectory.appendingPathComponent("\(fileName).\(fileExtension)"))
    }

    func test_allClipFilesPresentAndUnderBudget_isValid() throws {
        let allClips = AvatarLoader.requiredClips + AvatarLoader.recommendedClips
        try writeManifest(clips: Dictionary(uniqueKeysWithValues: allClips.map { ($0, $0) }))
        for clip in allClips {
            try writeClipFile(clip)
        }

        let report = try AvatarImportValidator.validate(packageDirectory: packageDirectory)

        XCTAssertTrue(report.isValid)
        XCTAssertTrue(report.missingRequiredClipFiles.isEmpty)
        XCTAssertTrue(report.missingRecommendedClipFiles.isEmpty)
        XCTAssertTrue(report.oversizedClipFiles.isEmpty)
    }

    func test_missingRequiredClipFile_isInvalid() throws {
        // idle is the sole required clip as of the 2026-07-29 2D switch.
        try writeManifest(clips: ["idle": "idle"])
        // idle.usdz intentionally not written, even though the manifest key exists

        let report = try AvatarImportValidator.validate(packageDirectory: packageDirectory)

        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.missingRequiredClipFiles, ["idle"])
    }

    func test_missingRecommendedClipFile_isStillValid() throws {
        try writeManifest(clips: ["idle": "idle"])
        try writeClipFile("idle")
        // walk/climb/fall/etc. not written at all -- recommended, non-fatal

        let report = try AvatarImportValidator.validate(packageDirectory: packageDirectory)

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(Set(report.missingRecommendedClipFiles), Set(AvatarLoader.recommendedClips))
    }

    func test_sprites_checksPngFilesNotUsdz() throws {
        try writeManifest(clips: ["idle": "idle", "walk": "walk"], type: "sprites")
        try writeClipFile("idle", extension: "png")
        // walk.png intentionally not written, even though the manifest key exists

        let report = try AvatarImportValidator.validate(packageDirectory: packageDirectory)

        XCTAssertTrue(report.isValid)
        XCTAssertTrue(report.missingRequiredClipFiles.isEmpty)
        XCTAssertTrue(report.missingRecommendedClipFiles.contains("walk"))
    }

    func test_oversizedClipFile_isReported() throws {
        try writeManifest(clips: ["idle": "idle", "walk": "walk"])
        try writeClipFile("idle")
        try writeClipFile("walk", sizeInBytes: AvatarImportValidator.maxClipFileSizeBytes + 1)

        let report = try AvatarImportValidator.validate(packageDirectory: packageDirectory)

        XCTAssertEqual(report.oversizedClipFiles, ["walk"])
        // Oversized is a soft budget (spec says "recommended"), not fatal on its own.
        XCTAssertTrue(report.isValid)
    }

    func test_manifestMissingRequiredKey_throwsFromAvatarLoader() throws {
        try writeManifest(clips: ["walk": "walk"]) // idle key itself missing
        try writeClipFile("walk")

        XCTAssertThrowsError(try AvatarImportValidator.validate(packageDirectory: packageDirectory)) { error in
            guard case AvatarLoaderError.missingRequiredClips(let missing) = error else {
                return XCTFail("expected .missingRequiredClips, got \(error)")
            }
            XCTAssertEqual(missing, ["idle"])
        }
    }
}
