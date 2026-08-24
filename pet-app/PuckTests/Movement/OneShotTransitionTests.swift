//
//  OneShotTransitionTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//

import XCTest
@testable import Puck

final class OneShotTransitionTests: XCTestCase {
    func test_fire_requestsTheGivenKind() {
        var oneShot = OneShotTransition()
        var requested: [StateKind] = []

        oneShot.fire(.idle) { requested.append($0) }

        XCTAssertEqual(requested, [.idle])
    }

    func test_fire_onlyRequestsOnce() {
        var oneShot = OneShotTransition()
        var requested: [StateKind] = []

        oneShot.fire(.idle) { requested.append($0) }
        oneShot.fire(.idle) { requested.append($0) }

        XCTAssertEqual(requested, [.idle])
    }

    func test_hasFired_reflectsWhetherFireWasCalled() {
        var oneShot = OneShotTransition()
        XCTAssertFalse(oneShot.hasFired)

        oneShot.fire(.fall) { _ in }

        XCTAssertTrue(oneShot.hasFired)
    }

    func test_reset_allowsFiringAgain() {
        var oneShot = OneShotTransition()
        var requested: [StateKind] = []
        oneShot.fire(.idle) { requested.append($0) }

        oneShot.reset()
        oneShot.fire(.fall) { requested.append($0) }

        XCTAssertEqual(requested, [.idle, .fall])
        XCTAssertTrue(oneShot.hasFired)
    }
}
