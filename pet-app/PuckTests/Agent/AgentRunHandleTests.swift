//
//  AgentRunHandleTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The handle AgentHost keeps on the running turn so 중지 can cancel it.
//  Before it existed the turn was started with a fire-and-forget `Task {}`
//  and nothing could reach it again.
//

import XCTest
@testable import Puck

final class AgentRunHandleTests: XCTestCase {
    func test_cancel_cancelsTheRunItIsHolding() async {
        let handle = AgentRunHandle()
        let started = expectation(description: "run started")
        let observed = UncheckedBox(false)

        let task = handle.start {
            started.fulfill()
            // Long enough that only a real cancellation ends it.
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            observed.value = Task.isCancelled
        }
        await fulfillment(of: [started], timeout: 2)

        handle.cancel()
        await task.value

        XCTAssertTrue(observed.value, "the run must be able to see that it was cancelled")
        XCTAssertFalse(handle.isRunning)
    }

    /// Nothing to cancel is not an error -- 중지 is reachable in states where
    /// no turn is running (a pending approval left over from one, say).
    func test_cancel_withNothingRunning_doesNothing() {
        let handle = AgentRunHandle()

        handle.cancel()

        XCTAssertFalse(handle.isRunning)
    }

    func test_isRunning_goesFalseWhenTheRunFinishesOnItsOwn() async {
        let handle = AgentRunHandle()

        let task = handle.start {}
        await task.value
        // The handle clears itself from inside the task, which can land after
        // `await task.value` returns.
        for _ in 0..<100 where handle.isRunning {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertFalse(handle.isRunning)
    }

    /// A second command replaces the first: one session answers one thing at
    /// a time, and the handle must end up holding the new run, not the old.
    func test_start_cancelsAPreviousRunAndHoldsTheNewOne() async {
        let handle = AgentRunHandle()
        let firstStarted = expectation(description: "first started")
        let firstCancelled = UncheckedBox(false)

        let first = handle.start {
            firstStarted.fulfill()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            firstCancelled.value = Task.isCancelled
        }
        await fulfillment(of: [firstStarted], timeout: 2)

        let secondStarted = expectation(description: "second started")
        let secondCancelled = UncheckedBox(false)
        let second = handle.start {
            secondStarted.fulfill()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            secondCancelled.value = Task.isCancelled
        }
        await fulfillment(of: [secondStarted], timeout: 2)
        await first.value

        XCTAssertTrue(firstCancelled.value)
        XCTAssertTrue(handle.isRunning, "the new run must still be cancellable")

        handle.cancel()
        await second.value
        XCTAssertTrue(secondCancelled.value)
    }
}

/// Shared by the cancellation tests: a value written inside a Task and read
/// after it, with no actor to route it through.
final class UncheckedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}
