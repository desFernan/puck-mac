//
//  DummyAvatarPackageTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  The committed dummy avatar is what a fresh clone runs on, so its manifest
//  and its PNGs have to agree with each other. Every failure mode here is
//  silent at runtime -- a typo'd stem, a file that never got copied, or a
//  clip key the FSM plays but the manifest doesn't define all end up as the
//  pet quietly showing its idle picture instead.
//

import XCTest
@testable import Puck

/// `@MainActor`: the character and its states belong to the main thread,
/// which is where the frame loop drives them.
@MainActor
final class DummyAvatarPackageTests: XCTestCase {
    /// The package as committed in the repo, not the installed copy under
    /// Application Support -- this is the one other people clone.
    private var packageDirectory: URL {
        RepositorySources.url("Resources/Avatars/dummy")
    }

    private func loadManifest() throws -> AvatarLoadResult {
        let data = try Data(contentsOf: packageDirectory.appendingPathComponent("manifest.json"))
        return try AvatarLoader.load(manifestData: data)
    }

    private func stems(_ references: [ClipReference]) -> Set<String> {
        Set(references.compactMap { reference -> String? in
            guard case .name(let stem) = reference else { return nil }
            return stem
        })
    }

    func test_dummyPackagePassesTheImportValidator() throws {
        let report = try AvatarImportValidator.validate(packageDirectory: packageDirectory)

        XCTAssertTrue(report.isValid, "missing required clip files: \(report.missingRequiredClipFiles)")
        XCTAssertEqual(report.missingRecommendedClipFiles, [])
        XCTAssertEqual(report.oversizedClipFiles, [], "over the per-file size budget")
    }

    func test_everyClipAndEmotionHasItsPNG() throws {
        let manifest = try loadManifest().manifest

        let referenced = stems(Array(manifest.clips.values))
            .union(stems(Array((manifest.emotions ?? [:]).values)))
        XCTAssertFalse(referenced.isEmpty)

        for stem in referenced.sorted() {
            let png = packageDirectory.appendingPathComponent("\(stem).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "missing \(stem).png")
        }
    }

    /// Every recommended clip has real art now, so nothing should still be
    /// falling back to idle.
    func test_noRecommendedClipIsStillMissing() throws {
        XCTAssertEqual(try loadManifest().missingRecommendedClips, [])
    }

    /// The FSM's clip keys and the manifest's have to match exactly: a state
    /// asking for a key the manifest doesn't define falls back to idle with
    /// no error anywhere.
    func test_manifestCoversEveryClipKeyTheStatesPlay() throws {
        let states: [StateHandler] = [
            IdleState(), WalkState(), ClimbState(), ClimbToCeilingState(), CeilingState(),
            WalkOnTopState(), FallState(), LandState(), MoveToState(), PointState(),
            TypeState(), ListenState(), ReactClickState(), ReactDragState(), PettingState(),
            SpinState(),
        ]
        let manifestKeys = Set(try loadManifest().manifest.clips.keys)

        XCTAssertEqual(
            Set(states.map(\.clipKey)).subtracting(manifestKeys),
            [],
            "clip keys the FSM plays that the manifest lacks — these silently fall back to idle"
        )
    }

    /// EventRouter drives these three by name; an avatar that doesn't map
    /// them shows no emotion at all for agent activity.
    func test_theEmotionsEventRouterDrivesAreAllMapped() throws {
        let emotions = try loadManifest().manifest.emotions ?? [:]

        for key in ["happy", "thinking", "sad"] {
            XCTAssertNotNil(emotions[key], "EventRouter emits \"\(key)\" but the manifest doesn't map it")
        }
    }
}
