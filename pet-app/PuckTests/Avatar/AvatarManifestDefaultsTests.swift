//
//  AvatarManifestDefaultsTests.swift
//  PuckTests
//
//  The smallest manifest that describes a character. What the README tells
//  someone to write has to be a thing that actually loads.
//

import XCTest
@testable import Puck

final class AvatarManifestDefaultsTests: XCTestCase {
    /// Copied from the README's "Adding one, start to finish". One drawing,
    /// no scale, no sounds.
    private let minimal = """
    {
      "schema_version": 1,
      "name": "my-pet",
      "type": "sprites",
      "hitbox": { "width": 130, "height": 133 },
      "clips": { "idle": "idle" }
    }
    """

    func testTheSmallestManifestLoads() throws {
        let manifest = try JSONDecoder().decode(AvatarManifest.self, from: Data(minimal.utf8))

        XCTAssertEqual(manifest.name, "my-pet")
        XCTAssertEqual(manifest.clips["idle"], .name("idle"))
        XCTAssertEqual(manifest.scale, 1, "drawn at the size it was drawn")
        XCTAssertEqual(manifest.sounds, [:], "silent, not invalid")
        XCTAssertNil(manifest.emotions)
        XCTAssertNil(manifest.bounceIntensity)
    }

    /// The defaults must not overwrite what a file does say.
    func testStatedValuesAreKept() throws {
        let json = """
        {
          "schema_version": 1,
          "name": "my-pet",
          "type": "sprites",
          "scale": 0.5,
          "bounce_intensity": 0.6,
          "hitbox": { "width": 10, "height": 20 },
          "clips": { "idle": "idle" },
          "sounds": { "land": "sounds/thud.wav" }
        }
        """

        let manifest = try JSONDecoder().decode(AvatarManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.scale, 0.5)
        XCTAssertEqual(manifest.bounceIntensity, 0.6)
        XCTAssertEqual(manifest.sounds, ["land": "sounds/thud.wav"])
    }

    /// A manifest with no clips at all is still refused: `idle` is what every
    /// other state falls back to, and there is nothing to draw without it.
    func testTheThingsWithNoSensibleDefaultAreStillRequired() {
        let noHitbox = """
        { "schema_version": 1, "name": "x", "type": "sprites", "clips": { "idle": "idle" } }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(AvatarManifest.self, from: Data(noHitbox.utf8)))

        let noClips = """
        { "schema_version": 1, "name": "x", "type": "sprites", "hitbox": { "width": 1, "height": 1 } }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(AvatarManifest.self, from: Data(noClips.utf8)))
    }
}
