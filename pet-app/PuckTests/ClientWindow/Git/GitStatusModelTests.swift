//
//  GitStatusModelTests.swift
//  PuckTests
//
//  The rule this model exists to keep: one read at a time.
//
//  An agent writing a file at a time asks for a refresh per write, and each
//  read forks git over the whole worktree. Running them at once is slower and
//  pointless -- only the last answer is the true one.
//

import XCTest

@testable import Puck

@MainActor
final class GitStatusModelTests: XCTestCase {
    /// Lets a test hold a read open, so a second ask arrives while the first
    /// is still running -- which is the only case worth testing here.
    private final class Reader {
        private(set) var callCount = 0
        private var resume: CheckedContinuation<Void, Never>?

        func read(_ path: String) async -> GitStatus? {
            callCount += 1
            await withCheckedContinuation { continuation in
                resume = continuation
            }
            return GitStatus(branch: "main", upstream: nil, ahead: 0, behind: 0, files: [])
        }

        /// Lets the read in flight finish. Returns false when none is waiting.
        @discardableResult
        func finish() -> Bool {
            guard let resume else { return false }
            self.resume = nil
            resume.resume()
            return true
        }

        /// Waits for a read to be in flight. Bounded by *time*, so a model
        /// that never reads fails the test instead of hanging the suite --
        /// and so a machine running the whole suite at once does not fail it
        /// for being slow. A thousand yields was a budget of scheduler turns,
        /// which under load ran out before the read had started.
        func waitForPendingRead() async -> Bool {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if resume != nil { return true }
                await Task.yield()
                try? await Task.sleep(nanoseconds: 500_000)
            }
            return false
        }

        /// Waits for a read to be in flight, then lets it finish.
        @discardableResult
        func finishWhenReady() async -> Bool {
            guard await waitForPendingRead() else { return false }
            return finish()
        }
    }

    func test_asksThatArriveDuringAReadCollapseIntoOneMore() async {
        let reader = Reader()
        let model = GitStatusModel(read: reader.read)

        // Not awaited: the read is held open on purpose, and a test that
        // waits for it before releasing it is a test that hangs.
        Task { await model.reload(projectPath: "/tmp/project") }
        let started = await reader.waitForPendingRead()
        XCTAssertTrue(started, "the first read starts")
        // Three asks while the first read is open. They are the same question,
        // so they are worth exactly one more read between them.
        for _ in 0..<3 { await model.reload(projectPath: "/tmp/project") }

        XCTAssertEqual(reader.callCount, 1, "nothing runs alongside the read in flight")

        let finishedFirst = await reader.finishWhenReady()
        XCTAssertTrue(finishedFirst, "the first read finishes")
        let finishedSecond = await reader.finishWhenReady()
        XCTAssertTrue(finishedSecond, "the collapsed asks are answered by one more read")

        XCTAssertEqual(reader.callCount, 2, "and by exactly one more, not three")
        XCTAssertEqual(model.status?.branch, "main")
    }

    /// A workspace with no project is not a repository with no changes.
    func test_noProjectClearsTheStatusWithoutReading() async {
        let reader = Reader()
        let model = GitStatusModel(read: reader.read)

        await model.reload(projectPath: nil)

        XCTAssertEqual(reader.callCount, 0)
        XCTAssertNil(model.status)
        XCTAssertTrue(model.hasLoaded, "and it counts as having looked")
    }
}
