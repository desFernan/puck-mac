//
//  AvatarManifestParsingTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  manifest.json parsing + required-clip fallback verification.
//

import XCTest
@testable import Puck

final class AvatarManifestParsingTests: XCTestCase {
    // Same structure as the protocol's own example (copy of Puck/Resources/Avatars/dummy/manifest.json)
    private let dummyManifestJSON = """
    {
      "schema_version": 1,
      "name": "dummy",
      "type": "sprites",
      "scale": 1.0,
      "bounce_intensity": 0.6,
      "hitbox": { "width": 120, "height": 140 },
      "clips": {
        "idle": "idle", "walk": "walk", "climb": "climb",
        "fall": "fall", "land": "land", "point": "point",
        "type": "type", "listen": "listen",
        "react_click": "react_click", "react_drag": "react_drag", "kick": "kick"
      },
      "emotions": {
        "happy": "happy", "thinking": "thinking"
      },
      "sounds": {
        "walk": "sounds/footstep.wav",
        "point": "sounds/point.wav",
        "react_click": "sounds/boop.wav",
        "kick": "sounds/kick.wav",
        "app_launch": "sounds/launch.wav",
        "task_success": "sounds/ding.wav",
        "task_fail": "sounds/buzz.wav",
        "listen_start": "sounds/listen.wav"
      }
    }
    """

    // MARK: - AvatarManifest parsing

    func test_decodesManifest_allFields() throws {
        let manifest = try JSONDecoder().decode(AvatarManifest.self, from: Data(dummyManifestJSON.utf8))

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.name, "dummy")
        XCTAssertEqual(manifest.type, .sprites)
        XCTAssertEqual(manifest.scale, 1.0)
        XCTAssertEqual(manifest.bounceIntensity, 0.6)
        XCTAssertEqual(manifest.hitbox, AvatarManifest.Hitbox(width: 120, height: 140))
        XCTAssertEqual(manifest.clips["idle"], .name("idle"))
        XCTAssertEqual(manifest.emotions?["happy"], .name("happy"))
        XCTAssertEqual(manifest.sounds["walk"], "sounds/footstep.wav")
    }

    func test_decodesManifest_withoutBounceIntensityOrEmotions_defaultsToNil() throws {
        let json = """
        {
          "schema_version": 1, "name": "minimal", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "idle": "idle" },
          "sounds": {}
        }
        """
        let manifest = try JSONDecoder().decode(AvatarManifest.self, from: Data(json.utf8))

        XCTAssertNil(manifest.bounceIntensity)
        XCTAssertNil(manifest.emotions)
    }

    func test_clipReference_decodesPlainStringAsName() throws {
        let ref = try JSONDecoder().decode(ClipReference.self, from: Data(#""idle""#.utf8))
        XCTAssertEqual(ref, .name("idle"))
    }

    func test_clipReference_decodesTimeRangeObject() throws {
        let json = #"{"in": 0.5, "out": 1.5}"#
        let ref = try JSONDecoder().decode(ClipReference.self, from: Data(json.utf8))
        XCTAssertEqual(ref, .timeRange(in: 0.5, out: 1.5))
    }

    // MARK: - AvatarLoader: load from data + clip validation

    func test_load_withAllClipsPresent_reportsNoMissingClips() throws {
        let result = try AvatarLoader.load(manifestData: Data(dummyManifestJSON.utf8))

        XCTAssertEqual(result.manifest.name, "dummy")
        XCTAssertTrue(result.missingRecommendedClips.isEmpty)
    }

    func test_load_withOnlyRequiredClip_reportsMissingRecommendedClips() throws {
        // idle alone is required as of the 2026-07-29 2D switch -- walk is now
        // one of the recommended-with-fallback clips, same as the rest.
        let json = """
        {
          "schema_version": 1, "name": "minimal", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "idle": "idle" },
          "sounds": {}
        }
        """
        let result = try AvatarLoader.load(manifestData: Data(json.utf8))

        XCTAssertEqual(
            Set(result.missingRecommendedClips),
            Set(["walk", "climb", "fall", "land", "point", "type", "listen", "react_click", "react_drag", "kick"])
        )
    }

    func test_load_withMissingWalk_doesNotThrow_walkIsNowRecommendedOnly() throws {
        let json = """
        {
          "schema_version": 1, "name": "no-walk", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "idle": "idle" },
          "sounds": {}
        }
        """
        XCTAssertNoThrow(try AvatarLoader.load(manifestData: Data(json.utf8)))
    }

    func test_load_withGarbageJSON_throwsManifestNotDecodable() {
        XCTAssertThrowsError(try AvatarLoader.load(manifestData: Data(#"{"not":"a manifest"}"#.utf8))) { error in
            guard case AvatarLoaderError.manifestNotDecodable = error else {
                return XCTFail("expected .manifestNotDecodable, got \(error)")
            }
        }
    }

    func test_load_withMissingIdle_throwsMissingRequiredClips() {
        let json = """
        {
          "schema_version": 1, "name": "no-idle", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "walk": "walk" },
          "sounds": {}
        }
        """
        XCTAssertThrowsError(try AvatarLoader.load(manifestData: Data(json.utf8))) { error in
            guard case AvatarLoaderError.missingRequiredClips(let missing) = error else {
                return XCTFail("expected .missingRequiredClips, got \(error)")
            }
            XCTAssertEqual(missing, ["idle"])
        }
    }

    func test_load_withUnsupportedSchemaVersion_throws() {
        let json = """
        {
          "schema_version": 2, "name": "future", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "idle": "idle", "walk": "walk" },
          "sounds": {}
        }
        """
        XCTAssertThrowsError(try AvatarLoader.load(manifestData: Data(json.utf8))) { error in
            guard case AvatarLoaderError.unsupportedSchemaVersion(let version) = error else {
                return XCTFail("expected .unsupportedSchemaVersion, got \(error)")
            }
            XCTAssertEqual(version, 2)
        }
    }

    /// A package this build has no renderer for is refused with a reason.
    ///
    /// It used to load: the type decoded, the clip keys were there, and then
    /// SpriteAvatar went looking for a PNG per clip that a usdz package does
    /// not have. What that produced was a pet that had silently vanished, and
    /// nothing in the log naming the cause.
    func test_load_withATypeThisBuildCannotDraw_throws() {
        for type in ["usdz", "video"] {
            let json = """
            {
              "schema_version": 1, "name": "legacy", "type": "\(type)", "scale": 1.0,
              "hitbox": { "width": 100, "height": 100 },
              "clips": { "idle": "idle" },
              "sounds": {}
            }
            """
            XCTAssertThrowsError(try AvatarLoader.load(manifestData: Data(json.utf8))) { error in
                guard case AvatarLoaderError.unsupportedAvatarType(let reported) = error else {
                    return XCTFail("expected .unsupportedAvatarType, got \(error)")
                }
                XCTAssertEqual(reported, type)
            }
        }
    }

    func test_load_withNoClipsAtAll_reportsOnlyIdleAsMissingRequired() {
        // walk is no longer required, so an empty clips table's only required-clip
        // failure is idle -- walk instead shows up in missingRecommendedClips.
        let json = """
        {
          "schema_version": 1, "name": "no-required-clips", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": {},
          "sounds": {}
        }
        """
        XCTAssertThrowsError(try AvatarLoader.load(manifestData: Data(json.utf8))) { error in
            guard case AvatarLoaderError.missingRequiredClips(let missing) = error else {
                return XCTFail("expected .missingRequiredClips, got \(error)")
            }
            XCTAssertEqual(missing, ["idle"])
        }
    }

    // MARK: - Missing clip -> idle fallback

    func test_resolvedClipName_returnsRequestedClip_whenPresent() throws {
        let result = try AvatarLoader.load(manifestData: Data(dummyManifestJSON.utf8))
        XCTAssertEqual(AvatarLoader.resolvedClipName(for: "walk", in: result), "walk")
    }

    func test_resolvedClipName_fallsBackToIdle_whenClipMissing() throws {
        let json = """
        {
          "schema_version": 1, "name": "minimal", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "idle": "idle", "walk": "walk" },
          "sounds": {}
        }
        """
        let result = try AvatarLoader.load(manifestData: Data(json.utf8))
        XCTAssertEqual(AvatarLoader.resolvedClipName(for: "climb", in: result), "idle")
    }

    func test_resolvedClipName_returnsNil_whenIdleIsNotAStringNamedClip() throws {
        // idle/walk are both present (satisfies the required-clip check), but as
        // {in,out} time ranges rather than clip names — resolvedClipName only
        // understands the .name case, so idle can't be used as a fallback
        // target here even though the key technically exists.
        let json = """
        {
          "schema_version": 1, "name": "time-ranges", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "idle": {"in": 0, "out": 1}, "walk": {"in": 1, "out": 2} },
          "sounds": {}
        }
        """
        let result = try AvatarLoader.load(manifestData: Data(json.utf8))
        XCTAssertNil(AvatarLoader.resolvedClipName(for: "climb", in: result))
    }

    // MARK: - Load from disk (directory scan)

    func test_loadFromDirectory_readsManifestFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try dummyManifestJSON.write(
            to: directory.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = try AvatarLoader.load(avatarDirectory: directory)
        XCTAssertEqual(result.manifest.name, "dummy")
    }

    func test_loadFromDirectory_withoutManifest_throwsAvatarNotFound() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        XCTAssertThrowsError(try AvatarLoader.load(avatarDirectory: directory)) { error in
            guard case AvatarLoaderError.avatarNotFound = error else {
                return XCTFail("expected .avatarNotFound, got \(error)")
            }
        }
    }
}
