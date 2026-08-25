//
//  ClientStatusBarViewTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class ClientStatusBarViewTests: XCTestCase {
    func test_dotStatus_noProject_isIdle() {
        XCTAssertEqual(dotStatus(for: .noProject), .idle)
    }

    func test_dotStatus_ready_isSuccess() {
        XCTAssertEqual(dotStatus(for: .ready(rootURL: URL(fileURLWithPath: "/tmp"))), .success)
    }

    func test_dotStatus_unavailable_isError() {
        XCTAssertEqual(dotStatus(for: .unavailable(.pathMissing)), .error)
        XCTAssertEqual(dotStatus(for: .unavailable(.notADirectory)), .error)
        XCTAssertEqual(dotStatus(for: .unavailable(.notReadable)), .error)
    }

    /// The dot is a colour and nothing else. These three strings are the
    /// whole of what a screen reader can be told about it, so each state has
    /// to have one and no two may be the same.
    func test_dotDescription_saysSomethingDifferentForEachState() {
        let descriptions = [
            dotDescription(for: .noProject),
            dotDescription(for: .ready(rootURL: URL(fileURLWithPath: "/tmp"))),
            dotDescription(for: .unavailable(.pathMissing)),
        ]
        XCTAssertEqual(Set(descriptions).count, 3, "two states read out the same")
        XCTAssertFalse(descriptions.contains(where: \.isEmpty))
    }

    func test_abbreviatedPath_replacesHomeWithTilde() {
        XCTAssertEqual(abbreviatedPath("/Users/x/dev/cat-house", home: "/Users/x"), "~/dev/cat-house")
    }

    func test_abbreviatedPath_leavesPathsOutsideHomeAlone() {
        XCTAssertEqual(abbreviatedPath("/opt/proj", home: "/Users/x"), "/opt/proj")
    }

    func test_abbreviatedPath_handlesHomeItself() {
        XCTAssertEqual(abbreviatedPath("/Users/x", home: "/Users/x"), "~")
    }

    func test_abbreviatedPath_doesNotAbbreviateAPrefixThatIsNotAPathBoundary() {
        XCTAssertEqual(abbreviatedPath("/Users/xyz/p", home: "/Users/x"), "/Users/xyz/p")
    }
}
