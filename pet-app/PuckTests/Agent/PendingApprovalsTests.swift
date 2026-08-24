//
//  PendingApprovalsTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Approval requests are answered by the run that owns them, not by whichever
//  run happens to finish.
//

import XCTest
@testable import Puck

final class PendingApprovalsTests: XCTestCase {
    func test_userAnswer_reachesTheRequest() {
        let approvals = PendingApprovals()
        var answer: Bool?
        approvals.add(id: "a", run: 1) { answer = $0 }

        approvals.resolve(id: "a", approved: true)

        XCTAssertEqual(answer, true)
    }

    func test_unknownId_isIgnored() {
        let approvals = PendingApprovals()
        approvals.resolve(id: "nobody", approved: true) // must not trap
    }

    /// The bug this type exists for. A superseded turn keeps executing until it
    /// next checks Task.isCancelled, so it reaches its end-of-run sweep while
    /// the turn that replaced it is already waiting on the user. Sweeping
    /// everything denied that live request out from under them.
    func test_aFinishedRunDoesNotDenyANewerRunsRequest() {
        let approvals = PendingApprovals()
        var oldAnswer: Bool?
        var newAnswer: Bool?
        approvals.add(id: "old", run: 1) { oldAnswer = $0 }
        approvals.add(id: "new", run: 2) { newAnswer = $0 }

        approvals.failAll(run: 1)

        XCTAssertEqual(oldAnswer, false, "the finished run's own request is released")
        XCTAssertNil(newAnswer, "the live request must still be waiting for the user")

        approvals.resolve(id: "new", approved: true)
        XCTAssertEqual(newAnswer, true)
    }

    /// 중지 is the user stopping what is on screen, so it releases everything --
    /// including anything an earlier turn stranded, which would otherwise leak
    /// a suspended continuation for the life of the process.
    func test_stopReleasesEveryRun() {
        let approvals = PendingApprovals()
        var answers: [Bool] = []
        approvals.add(id: "old", run: 1) { answers.append($0) }
        approvals.add(id: "new", run: 2) { answers.append($0) }

        approvals.failAll()

        XCTAssertEqual(answers, [false, false])
    }

    /// Every id handed to the UI is answered exactly once; a reused id must
    /// not leave the displaced caller suspended forever.
    func test_duplicateId_releasesTheDisplacedRequest() {
        let approvals = PendingApprovals()
        var first: Bool?
        var second: Bool?
        approvals.add(id: "a", run: 1) { first = $0 }
        approvals.add(id: "a", run: 2) { second = $0 }

        XCTAssertEqual(first, false, "the displaced request is denied rather than dropped")
        XCTAssertNil(second)

        approvals.resolve(id: "a", approved: true)
        XCTAssertEqual(second, true)
    }
}
