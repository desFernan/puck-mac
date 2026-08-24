//
//  PendingPointTrackerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  A point_at that arrives before a previous one has started walking
//  supersedes it -- but the superseded caller's tool_result(ok) must still
//  fire, not be silently dropped until ToolExecutor's 15s timeout.
//

import XCTest
import CoreGraphics
@testable import Puck

final class PendingPointTrackerTests: XCTestCase {
    func test_replace_withNoPriorPending_returnsNil() {
        let tracker = PendingPointTracker()
        let superseded = tracker.replace(frame: CGRect(x: 0, y: 0, width: 10, height: 10)) {}
        XCTAssertNil(superseded)
    }

    func test_replace_withPriorPending_returnsItsCallback() {
        let tracker = PendingPointTracker()
        var firstCalled = false
        _ = tracker.replace(frame: CGRect(x: 0, y: 0, width: 10, height: 10)) { firstCalled = true }

        let superseded = tracker.replace(frame: CGRect(x: 20, y: 20, width: 10, height: 10)) {}

        superseded?()
        XCTAssertTrue(firstCalled)
    }

    func test_consumeIfPending_returnsFrameAndCallback_thenClears() {
        let tracker = PendingPointTracker()
        let frame = CGRect(x: 1, y: 2, width: 3, height: 4)
        var started = false
        _ = tracker.replace(frame: frame, onStarted: { started = true })

        let consumed = tracker.consumeIfPending()
        consumed?.onStarted()

        XCTAssertEqual(consumed?.frame, frame)
        XCTAssertTrue(started)
        XCTAssertNil(tracker.consumeIfPending(), "must clear after consuming once")
    }

    func test_consumeIfPending_withNothingPending_returnsNil() {
        XCTAssertNil(PendingPointTracker().consumeIfPending())
    }

    /// A cancelled point_at (ToolExecutor's timeout, or an explicit
    /// tool_cancel) must not leave a stale entry that a later arrival would
    /// still consume and reply to -- but unlike replace()'s "superseded"
    /// case, cancelling must NOT invoke the callback: ToolExecutor already
    /// replied .cancelled for this dispatch (found via review).
    func test_clearPending_removesTheEntryWithoutInvokingItsCallback() {
        let tracker = PendingPointTracker()
        var called = false
        _ = tracker.replace(frame: CGRect(x: 0, y: 0, width: 10, height: 10)) { called = true }

        tracker.clearPending()

        XCTAssertFalse(called)
        XCTAssertNil(tracker.consumeIfPending())
    }
}
