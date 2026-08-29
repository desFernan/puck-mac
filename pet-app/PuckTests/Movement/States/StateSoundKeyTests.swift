//
//  StateSoundKeyTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Which sound key each state asks the table for, and whether it loops.
//

import XCTest
@testable import Puck

/// `@MainActor`: the character and its states belong to the main thread,
/// which is where the frame loop drives them.
@MainActor
final class StateSoundKeyTests: XCTestCase {
    func test_soundKeyDefaultsToClipKey() {
        XCTAssertEqual(IdleState().soundKey, IdleState().clipKey)
        XCTAssertEqual(KickBallState().soundKey, "kick")
    }

    func test_juggle_usesToySpecificKey_soEachToyGetsItsOwnLine() {
        let state = JuggleBallState()
        state.toyName = ToyCatalogue.pumpkin.name

        XCTAssertEqual(state.soundKey, "kick_pumpkin")
    }

    func test_juggle_withoutAToy_fallsBackToTheClipKey() {
        XCTAssertEqual(JuggleBallState().soundKey, "kick")
    }

    func test_spokenLineStates_doNotLoopTheirSound_evenThoughTheClipLoops() {
        for state: StateHandler in [ReactDragState(), PointState(), SpinState()] {
            XCTAssertTrue(state.loopsClip, "\(state.name) clip should loop")
            XCTAssertFalse(state.loopsSound, "\(state.name) line must play once")
        }
    }

    /// The keys the states above ask for have to exist in the shipped avatar,
    /// or the whole wiring is silent in the app while green in tests.
    ///
    /// Skipped while the shipped pack carries no sounds at all, which it does
    /// deliberately -- the ones it had were third party and went with the rest
    /// of that artwork. This comes back the moment the pack names a sound
    /// again, which is exactly when it is worth checking.
    func test_dummyManifest_mapsTheKeysTheStatesAskFor() throws {
        let manifestURL = RepositorySources.url("Resources/Avatars/dummy/manifest.json")
        let manifest = try JSONDecoder().decode(AvatarManifest.self, from: Data(contentsOf: manifestURL))
        try XCTSkipIf(manifest.sounds.isEmpty, "the shipped pack ships no sounds yet")
        let table = SoundTable(
            avatarDirectory: manifestURL.deletingLastPathComponent(),
            sounds: manifest.sounds
        )

        for key in ["kick_pumpkin", "kick_wand", "react_drag", "fall", "land", "point", "spin", "react_click", "pet", "kick"] {
            let url = try XCTUnwrap(table.fileURL(for: key), "\(key) is unmapped")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(key) points at a missing file")
        }
    }
}
