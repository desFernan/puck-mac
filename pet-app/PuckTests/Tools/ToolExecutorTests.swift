//
//  ToolExecutorTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  tool_dispatch routing + per-call timeout, per protocol 3.1/4.
//

import XCTest
@testable import Puck

private final class StubHandler: ToolHandler {
    let toolName: String
    private(set) var cancelCallCount = 0
    private let behavior: (JSONValue, @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) -> Void

    init(toolName: String, behavior: @escaping (JSONValue, @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) -> Void) {
        self.toolName = toolName
        self.behavior = behavior
    }

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        behavior(args, completion)
    }

    func cancel(id _: String) {
        cancelCallCount += 1
    }
}

final class ToolExecutorTests: XCTestCase {
    func test_dispatchesToRegisteredHandler_andReturnsItsData() {
        let executor = ToolExecutor()
        executor.register(StubHandler(toolName: "launch_app") { _, completion in
            completion(.success(.object(["pid": .number(501)])))
        })

        let expectation = expectation(description: "completion called")
        executor.dispatch(ToolDispatch(id: "t1", tool: "launch_app", args: .object([:]))) { result in
            XCTAssertEqual(result.id, "t1")
            XCTAssertTrue(result.ok)
            XCTAssertEqual(result.data, .object(["pid": .number(501)]))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_handlerFailure_producesErrorCodeAndDetail() {
        let executor = ToolExecutor()
        executor.register(StubHandler(toolName: "run_shell") { _, completion in
            completion(.failure(.executionFailed("zsh exited 127")))
        })

        let expectation = expectation(description: "completion called")
        executor.dispatch(ToolDispatch(id: "t2", tool: "run_shell", args: .object([:]))) { result in
            XCTAssertFalse(result.ok)
            XCTAssertEqual(result.error, .executionFailed)
            // protocol 3.1: error carries only the standard code; detail is
            // the human-readable specifics, without which the actual failure
            // reason reaches neither the wire nor the logs.
            XCTAssertEqual(result.detail, "zsh exited 127")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_unregisteredTool_producesUnknownToolError() {
        let executor = ToolExecutor()

        let expectation = expectation(description: "completion called")
        executor.dispatch(ToolDispatch(id: "t3", tool: "does_not_exist", args: .object([:]))) { result in
            XCTAssertFalse(result.ok)
            // A tool that doesn't exist is a registry/agent mismatch, not an
            // execution failure -- the codes must be distinguishable so
            // ai-module can react differently (protocol 3.1).
            XCTAssertEqual(result.error, .unknownTool)
            XCTAssertEqual(result.detail, "unknown tool: does_not_exist")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    // MARK: - tool_cancel (protocol 3.1)

    func test_cancel_ofInFlightCall_producesCancelledResultAndCancelsHandler() {
        let executor = ToolExecutor()
        let handler = StubHandler(toolName: "slow") { _, _ in
            // never calls completion -- stays in flight until cancelled
        }
        executor.register(handler)

        let expectation = expectation(description: "completion called")
        executor.dispatch(ToolDispatch(id: "t9", tool: "slow", args: .object([:]))) { result in
            XCTAssertFalse(result.ok)
            XCTAssertEqual(result.error, .cancelled)
            expectation.fulfill()
        }

        executor.cancel(id: "t9")

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(handler.cancelCallCount, 1)
    }

    func test_cancel_ofUnknownId_isANoOp() {
        let executor = ToolExecutor()
        executor.cancel(id: "never_dispatched") // must not crash or complete anything
    }

    func test_cancel_afterCompletion_doesNotDoubleCompleteOrCancelHandler() {
        let executor = ToolExecutor()
        let handler = StubHandler(toolName: "fast") { _, completion in
            completion(.success(nil))
        }
        executor.register(handler)

        var completionCount = 0
        executor.dispatch(ToolDispatch(id: "t10", tool: "fast", args: .object([:]))) { _ in
            completionCount += 1
        }

        executor.cancel(id: "t10") // already finished -- must be ignored

        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(handler.cancelCallCount, 0)
    }

    func test_handlerExceedingTimeout_producesTimeoutError() {
        let executor = ToolExecutor()
        executor.register(StubHandler(toolName: "slow") { _, _ in
            // never calls completion
        })

        let expectation = expectation(description: "completion called")
        executor.dispatch(ToolDispatch(id: "t4", tool: "slow", args: .object([:])), timeout: 0.05) { result in
            XCTAssertFalse(result.ok)
            XCTAssertEqual(result.error, .timeout)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_lateCompletionAfterTimeout_isIgnored() {
        let executor = ToolExecutor()
        executor.register(StubHandler(toolName: "slow") { _, completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                completion(.success(nil)) // arrives after the timeout already fired
            }
        })

        var callCount = 0
        let firstCompletion = expectation(description: "timeout completion")
        let unexpectedSecondCompletion = XCTestExpectation(description: "late completion should be ignored")
        unexpectedSecondCompletion.isInverted = true

        executor.dispatch(ToolDispatch(id: "t5", tool: "slow", args: .object([:])), timeout: 0.05) { result in
            callCount += 1
            if callCount == 1 {
                XCTAssertEqual(result.error, .timeout)
                firstCompletion.fulfill()
            } else {
                unexpectedSecondCompletion.fulfill()
            }
        }

        wait(for: [firstCompletion, unexpectedSecondCompletion], timeout: 0.5)
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - Registry timeouts (protocol section 4)

    /// Dispatches `tool` with the timeout scheduler stubbed out and returns the
    /// delay the executor asked for, without waiting that long.
    private func scheduledTimeout(forTool tool: String) -> TimeInterval? {
        var scheduled: TimeInterval?
        let executor = ToolExecutor(scheduleTimeout: { delay, _ in scheduled = delay })
        executor.register(StubHandler(toolName: tool) { _, _ in
            // never completes -- the timeout is what's under test
        })
        executor.dispatch(ToolDispatch(id: "t", tool: tool, args: .object([:]))) { _ in }
        return scheduled
    }

    func test_dispatchWithoutExplicitTimeout_usesTheToolsRegistryTimeout() {
        // Regression: every tool was capped at the 15s default because the sole
        // caller (BridgeMessageRouter) never passed `timeout`, so run_shell and
        // run_applescript replied "timeout" at 15s of their allotted 60.
        XCTAssertEqual(scheduledTimeout(forTool: "run_shell"), 60)
        XCTAssertEqual(scheduledTimeout(forTool: "run_applescript"), 60)
        XCTAssertEqual(scheduledTimeout(forTool: "point_at"), 30)
        XCTAssertEqual(scheduledTimeout(forTool: "launch_app"), 15)
        XCTAssertEqual(scheduledTimeout(forTool: "list_running_apps"), 5)
        XCTAssertEqual(scheduledTimeout(forTool: "get_frontmost_window"), 5)
    }

    func test_toolAbsentFromTheMirror_fallsBackToTheRegistryDefault() {
        XCTAssertEqual(scheduledTimeout(forTool: "not_in_the_registry"), 15)
    }

    func test_explicitTimeout_stillOverridesTheRegistry() {
        var scheduled: TimeInterval?
        let executor = ToolExecutor(scheduleTimeout: { delay, _ in scheduled = delay })
        executor.register(StubHandler(toolName: "run_shell") { _, _ in })
        executor.dispatch(ToolDispatch(id: "t", tool: "run_shell", args: .object([:])), timeout: 0.05) { _ in }
        XCTAssertEqual(scheduled, 0.05)
    }
}
