//
//  CodeBlockClipboardTests.swift
//  PuckTests
//
//  What the copy button on a code block actually does, checked against a
//  pasteboard of its own rather than the user's.
//

import AppKit
import XCTest

@testable import Puck

final class CodeBlockClipboardTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("PuckTests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    func test_theWholeBlockGoesOnThePasteboard() {
        let code = "func add(_ a: Int, _ b: Int) -> Int {\n    a + b\n}"

        XCTAssertTrue(CodeBlockClipboard.copy(code, to: pasteboard))

        XCTAssertEqual(pasteboard.string(forType: .string), code)
    }

    /// Cleared first: a pasteboard still holding the previous copy hands out
    /// whichever type an app asks for, which is how a paste comes back as
    /// something nobody copied.
    func test_theSecondCopyReplacesTheFirst() {
        CodeBlockClipboard.copy("first", to: pasteboard)
        CodeBlockClipboard.copy("second", to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "second")
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
    }

    /// Blank lines and indentation are the code, so they survive.
    func test_whitespaceIsPartOfTheCode() {
        let code = "  indented\n\n\ttabbed\n"

        CodeBlockClipboard.copy(code, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), code)
    }
}
