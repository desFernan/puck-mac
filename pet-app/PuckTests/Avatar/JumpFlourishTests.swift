//
//  JumpFlourishTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  F3: "task_success SFX + 점프" (agent_done) and "detail.path
//  변경 시 짧은 점프" (code_editor) -- EventReaction.jump was decoded but
//  never actually animated anything (found via spec cross-check).
//

import XCTest
@testable import Puck

final class JumpFlourishTests: XCTestCase {
    func test_atZeroElapsed_offsetIsZero() {
        XCTAssertEqual(JumpFlourish.offset(elapsed: 0), 0)
    }

    func test_atDuration_offsetHasReturnedToZero() {
        XCTAssertEqual(JumpFlourish.offset(elapsed: JumpFlourish.duration), 0, accuracy: 0.001)
    }

    func test_pastDuration_offsetStaysZero() {
        XCTAssertEqual(JumpFlourish.offset(elapsed: JumpFlourish.duration + 1), 0)
    }

    func test_beforeStart_offsetIsZero() {
        XCTAssertEqual(JumpFlourish.offset(elapsed: -0.1), 0)
    }

    /// Y grows downward (GlobalScreenSpace/layer convention throughout this
    /// codebase) -- a jump is upward, i.e. negative.
    func test_midway_offsetIsUpward() {
        let midpoint = JumpFlourish.offset(elapsed: JumpFlourish.duration / 2)
        XCTAssertLessThan(midpoint, 0)
    }

    func test_midway_isThePeak() {
        let midpoint = JumpFlourish.duration / 2
        let peak = JumpFlourish.offset(elapsed: midpoint)
        let justBefore = JumpFlourish.offset(elapsed: midpoint - 0.01)
        let justAfter = JumpFlourish.offset(elapsed: midpoint + 0.01)
        XCTAssertLessThan(peak, justBefore)
        XCTAssertLessThan(peak, justAfter)
    }
}
