//
//  HeldOnceTests.swift
//  PuckTests
//
//  Worked out on first use and kept -- which is only worth having if it is
//  actually once, and only safe if a failure is not what gets kept.
//

import XCTest
@testable import Puck

final class HeldOnceTests: XCTestCase {
    func test_theWorkHappensOnceHoweverOftenItIsAsked() {
        var calls = 0
        let held = HeldOnce<Int> {
            calls += 1
            return 7
        }

        XCTAssertEqual(held(), 7)
        XCTAssertEqual(held(), 7)
        XCTAssertEqual(held(), 7)
        XCTAssertEqual(calls, 1, "this exists so a wide PNG is not decoded per frame")
    }

    /// Nothing is asked for before there is a screen, so it must not run at
    /// all until somebody asks.
    func test_nothingHappensUntilItIsAsked() {
        var calls = 0
        _ = HeldOnce<Int> {
            calls += 1
            return 7
        }

        XCTAssertEqual(calls, 0)
    }

    /// The picture comes out of a folder people drop their own into.
    /// Remembering "there wasn't one" would make a bad read at launch a blank
    /// island until the app is quit.
    func test_aFailureIsNotWhatGetsKept() {
        var attempts = 0
        let held = HeldOnce<String> {
            attempts += 1
            return attempts < 3 ? nil : "found it"
        }

        XCTAssertNil(held())
        XCTAssertNil(held())
        XCTAssertEqual(held(), "found it")
        XCTAssertEqual(held(), "found it")
        XCTAssertEqual(attempts, 3, "and once found, it stops looking")
    }

    /// Asked from every thread at once, everybody gets the same answer -- the
    /// first one to arrive. Doing the work twice under contention is waste
    /// rather than a bug; handing back two different values would be the bug.
    func test_everyThreadGetsTheSameAnswer() {
        let held = HeldOnce<NSObject> { NSObject() }
        let answers = NSMutableArray()
        let guard_ = NSLock()

        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            let value = held()
            guard_.lock()
            answers.add(value as Any)
            guard_.unlock()
        }

        let distinct = Set(answers.map { ObjectIdentifier($0 as AnyObject) })
        XCTAssertEqual(distinct.count, 1, "got \(distinct.count) different values")
    }
}
