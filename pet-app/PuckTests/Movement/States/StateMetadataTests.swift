//
//  StateMetadataTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Clip-key metadata for the remaining states, per the state transition table
//  in plan/02_pet-app.md section 3.
//

import XCTest
@testable import Puck

/// `@MainActor`: the character and its states belong to the main thread,
/// which is where the frame loop drives them.
@MainActor
final class StateMetadataTests: XCTestCase {
    func test_statesExposeExpectedClipKeys() {
        XCTAssertEqual(WalkState().clipKey, "walk")
        XCTAssertEqual(ClimbState().clipKey, "climb")
        XCTAssertEqual(WalkOnTopState().clipKey, "walk") // no dedicated clip in the manifest, reuses walk
        XCTAssertEqual(FallState().clipKey, "fall")
        XCTAssertEqual(LandState().clipKey, "land")
        XCTAssertEqual(MoveToState().clipKey, "walk") // no dedicated clip in the manifest, reuses walk
        XCTAssertEqual(PointState().clipKey, "point")
        XCTAssertEqual(TypeState().clipKey, "type")
        XCTAssertEqual(ListenState().clipKey, "listen")
        XCTAssertEqual(ReactClickState().clipKey, "react_click")
        XCTAssertEqual(ReactDragState().clipKey, "react_drag")
        XCTAssertEqual(ChaseBallState().clipKey, "walk") // no dedicated clip in the manifest, reuses walk
        XCTAssertEqual(KickBallState().clipKey, "kick")
    }
}
