//
//  SFXDecisionMakerTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Pure trigger -> action decision, per F5: unmapped keys
//  are silent, loop sounds keep playing until a *different* loop key arrives
//  (at which point the old one fades — SFXPlayer's job, not this decision),
//  one-shots never touch the currently-looping sound.
//

import XCTest
@testable import Puck

final class SFXDecisionMakerTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/sounds/footstep.wav")

    func test_unmappedKey_isSilent_regardlessOfLoopFlag() {
        XCTAssertEqual(
            SFXDecisionMaker.decide(key: "walk", loop: true, resolvedURL: nil, currentLoopKey: nil),
            .silent
        )
        XCTAssertEqual(
            SFXDecisionMaker.decide(key: "react_click", loop: false, resolvedURL: nil, currentLoopKey: nil),
            .silent
        )
    }

    func test_oneShotTrigger_playsRegardlessOfCurrentLoop() {
        XCTAssertEqual(
            SFXDecisionMaker.decide(key: "react_click", loop: false, resolvedURL: url, currentLoopKey: "walk"),
            .playOneShot(url: url)
        )
    }

    func test_loopTrigger_forANewKey_startsLoop() {
        XCTAssertEqual(
            SFXDecisionMaker.decide(key: "walk", loop: true, resolvedURL: url, currentLoopKey: nil),
            .startLoop(url: url)
        )
        XCTAssertEqual(
            SFXDecisionMaker.decide(key: "walk", loop: true, resolvedURL: url, currentLoopKey: "climb"),
            .startLoop(url: url)
        )
    }

    func test_loopTrigger_forTheSameAlreadyPlayingKey_isNoOp() {
        XCTAssertEqual(
            SFXDecisionMaker.decide(key: "walk", loop: true, resolvedURL: url, currentLoopKey: "walk"),
            .alreadyLooping
        )
    }
}
