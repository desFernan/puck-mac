//
//  ToolCancellationTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  A timed-out tool call replied `timeout` but left whatever it started
//  running: RunShellHandler's process kept going with nobody to collect it,
//  and the timeout work item itself stayed queued for the full duration even
//  after a fast success (600s for code_editor).
//

import XCTest
@testable import Puck

private final class SlowHandler: ToolHandler {
    let toolName = "slow"
    private(set) var cancelCount = 0
    private var stored: ((Result<JSONValue?, ToolExecutionError>) -> Void)?

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        stored = completion // never completes on its own
    }

    func cancel(id _: String) {
        cancelCount += 1
    }
}

private final class InstantHandler: ToolHandler {
    let toolName = "instant"
    private(set) var cancelCount = 0

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        completion(.success(nil))
    }

    func cancel(id _: String) {
        cancelCount += 1
    }
}

final class ToolCancellationTests: XCTestCase {
    private let request = ToolDispatch(id: "t1", tool: "slow", args: .object([:]))

    /// Without this the shell process behind a timed-out run_shell keeps
    /// running forever, holding its pipes and a thread.
    func test_timeoutCancelsTheHandler() {
        let handler = SlowHandler()
        let executor = ToolExecutor()
        executor.register(handler)

        let replied = expectation(description: "timeout reply")
        executor.dispatch(request, timeout: 0.1) { result in
            XCTAssertFalse(result.ok)
            XCTAssertEqual(result.error, .timeout)
            replied.fulfill()
        }

        wait(for: [replied], timeout: 2)
        XCTAssertEqual(handler.cancelCount, 1)
    }

    func test_successfulCallIsNeverCancelled() {
        let handler = InstantHandler()
        let executor = ToolExecutor()
        executor.register(handler)

        let replied = expectation(description: "reply")
        executor.dispatch(
            ToolDispatch(id: "t2", tool: "instant", args: .object([:])),
            timeout: 0.1
        ) { _ in replied.fulfill() }
        wait(for: [replied], timeout: 2)

        // Well past the timeout: the work item must have been cancelled, not
        // merely ignored by the completed-once guard.
        let settled = expectation(description: "past the deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertEqual(handler.cancelCount, 0)
    }

    func test_handlersNeedNotImplementCancel() {
        // Most tools finish promptly and have nothing to tear down; requiring
        // every one of them to write an empty cancel() would be noise.
        let executor = ToolExecutor()
        executor.register(ListRunningAppsHandler())

        let replied = expectation(description: "reply")
        executor.dispatch(
            ToolDispatch(id: "t3", tool: "list_running_apps", args: .object([:])),
            timeout: 5
        ) { result in
            XCTAssertTrue(result.ok)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 5)
    }
}
