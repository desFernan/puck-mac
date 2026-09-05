//
//  ManifestSFXKeyCoverageTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Every SFX key EventRouter.reaction(for:) can produce must have a matching
//  entry in the manifest's sounds table —
//  F5's rule is that an unmapped key is silent, so a schema gap means a
//  spec-required sound silently never plays. The original review finding
//  here (commit 57615a8 item #7) was exactly that: "await_approval" was
//  emitted but undefined in the schema; the schema has since been fixed at
//  the source, closing the gap this test tracked.
//  knownMissingSFXKeys stays as the mechanism for any future gap that's
//  blocked on a cross-team schema change: the
//  first test fails on an unexplained gap, the second fails if an entry in
//  the list goes stale.
//

import XCTest
@testable import Puck

final class ManifestSFXKeyCoverageTests: XCTestCase {
    private static let knownMissingSFXKeys: Set<String> = []

    // Mirrors Puck/Resources/Avatars/dummy/manifest.json (same fixture
    // AvatarManifestParsingTests.swift uses) — keep in sync if that file changes.
    private let dummyManifestJSON = """
    {
      "schema_version": 1,
      "name": "dummy",
      "type": "sprites",
      "scale": 1.0,
      "hitbox": { "width": 120, "height": 140 },
      "clips": {
        "idle": "idle", "walk": "walk", "climb": "climb",
        "fall": "fall", "land": "land", "point": "point",
        "type": "type", "listen": "listen",
        "react_click": "react_click", "react_drag": "react_drag"
      },
      "sounds": {
        "walk": "sounds/footstep.wav",
        "point": "sounds/point.wav",
        "react_click": "sounds/boop.wav",
        "app_launch": "sounds/launch.wav",
        "task_success": "sounds/ding.wav",
        "task_fail": "sounds/buzz.wav",
        "await_approval": "sounds/awaiting.wav",
        "listen_start": "sounds/listen.wav"
      }
    }
    """

    private func loadManifestSoundsKeys() throws -> Set<String> {
        let manifest = try JSONDecoder().decode(AvatarManifest.self, from: Data(dummyManifestJSON.utf8))
        return Set(manifest.sounds.keys)
    }

    private func allEventRouterSFXKeys() -> Set<String> {
        let events: [BridgeEvent] = [
            .agentThinking,
            .toolCall(id: "t1", tool: "code_editor", args: nil, detail: nil),
            .toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil),
            .toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil),
            .toolResult(id: "t1", ok: false, data: nil, error: nil, detail: nil),
            .awaitApproval(summary: "", approvalId: ""),
            .agentDone(ok: true, summary: ""),
            .agentDone(ok: false, summary: ""),
        ]
        return Set(events.compactMap { EventRouter.reaction(for: $0).sfxKey })
    }

    func test_everyEventRouterSFXKey_isInManifestOrAKnownTrackedGap() throws {
        let manifestKeys = try loadManifestSoundsKeys()
        let codeKeys = allEventRouterSFXKeys()

        let unexplainedGaps = codeKeys.subtracting(manifestKeys).subtracting(Self.knownMissingSFXKeys)
        XCTAssertTrue(
            unexplainedGaps.isEmpty,
            "SFX key(s) \(unexplainedGaps) are used by EventRouter but missing from both the manifest "
                + "and knownMissingSFXKeys — add them to the manifest or document them as a tracked gap."
        )
    }

    func test_knownMissingSFXKeys_doesNotGoStale() throws {
        let manifestKeys = try loadManifestSoundsKeys()

        let staleEntries = Self.knownMissingSFXKeys.intersection(manifestKeys)
        XCTAssertTrue(
            staleEntries.isEmpty,
            "\(staleEntries) are now present in the manifest — remove from knownMissingSFXKeys."
        )
    }
}
