//
//  ComposerAttachmentTests.swift
//  PuckTests
//
//  The composer can attach images now. Where the message goes decides what
//  happens to them: the socket carries attachments as attachments, and the
//  in-process agent -- which takes a prompt and nothing else -- gets their
//  paths in the message instead of losing them.
//

import XCTest
@testable import Puck

final class ComposerAttachmentTests: XCTestCase {
    func test_withNoAttachments_theMessageIsUnchanged() {
        XCTAssertEqual(ClientWindowStore.message("hello", carrying: []), "hello")
    }

    func test_attachedFiles_areNamedAfterTheMessage() {
        let carried = ClientWindowStore.message(
            "무슨 색이야?",
            carrying: [Attachment(path: "/tmp/shot.png")]
        )

        XCTAssertEqual(carried, "무슨 색이야?\n\nAttached file: /tmp/shot.png")
    }

    func test_severalFiles_areAllNamed() {
        let carried = ClientWindowStore.message(
            "",
            carrying: [Attachment(path: "/tmp/a.png"), Attachment(path: "/tmp/b.png")]
        )

        XCTAssertEqual(carried, "Attached file: /tmp/a.png\nAttached file: /tmp/b.png")
    }

    /// A picture on its own is a message. Nothing should be prefixed with a
    /// blank line it did not ask for.
    func test_anAttachmentWithNoText_isJustTheFiles() {
        let carried = ClientWindowStore.message("", carrying: [Attachment(path: "/tmp/a.png")])

        XCTAssertFalse(carried.hasPrefix("\n"))
    }
}
