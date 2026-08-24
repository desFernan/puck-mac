//
//  TerminalRestartPolicyTests.swift
//  PuckTests
//

import XCTest

@testable import Puck

final class TerminalRestartPolicyTests: XCTestCase {
    /// The ordinary case: someone typed `exit` in a shell they had been
    /// working in, and wants another one.
    func test_aShellThatRanIsReplaced() {
        var policy = TerminalRestartPolicy()

        XCTAssertEqual(policy.shellExited(afterRunningFor: 600), .restart)
        XCTAssertFalse(policy.hasGivenUp)
    }

    /// One that dies at once might be a fluke -- a race with a directory
    /// being replaced, say -- so it gets replaced too, a couple of times.
    func test_theFirstQuickExitsAreStillReplaced() {
        var policy = TerminalRestartPolicy()

        XCTAssertEqual(policy.shellExited(afterRunningFor: 0.1), .restart)
        XCTAssertEqual(policy.shellExited(afterRunningFor: 0.1), .restart)
    }

    /// Three in a row is not a fluke, and forking shells as fast as the
    /// machine allows is the failure this rule exists to prevent.
    func test_itGivesUpAfterThreeQuickExitsInARow() {
        var policy = TerminalRestartPolicy()

        _ = policy.shellExited(afterRunningFor: 0.1)
        _ = policy.shellExited(afterRunningFor: 0.1)

        XCTAssertEqual(policy.shellExited(afterRunningFor: 0.1), .giveUp)
        XCTAssertTrue(policy.hasGivenUp)
    }

    /// A shell that ran properly clears the tally: two bad starts followed by
    /// a working session and two more bad starts is not three in a row.
    func test_aShellThatRanClearsTheTally() {
        var policy = TerminalRestartPolicy()

        _ = policy.shellExited(afterRunningFor: 0.1)
        _ = policy.shellExited(afterRunningFor: 0.1)
        _ = policy.shellExited(afterRunningFor: 30)

        XCTAssertEqual(policy.shellExited(afterRunningFor: 0.1), .restart)
        XCTAssertEqual(policy.shellExited(afterRunningFor: 0.1), .restart)
        XCTAssertEqual(policy.consecutiveEarlyExits, 2)
    }

    /// The boundary is a rule, not a guess: exactly at the threshold counts
    /// as having run.
    func test_theThresholdItselfCountsAsHavingRun() {
        var policy = TerminalRestartPolicy()

        _ = policy.shellExited(afterRunningFor: TerminalRestartPolicy.earlyExitSeconds)

        XCTAssertEqual(policy.consecutiveEarlyExits, 0)
    }
}
