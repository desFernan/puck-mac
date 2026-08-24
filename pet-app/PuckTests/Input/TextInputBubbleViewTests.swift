//
//  TextInputBubbleViewTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Enter -> onSubmit(text) + clears the field; Escape -> onCancel.
//

import XCTest
import AppKit
@testable import Puck

final class TextInputBubbleViewTests: XCTestCase {
    private func makeView() -> TextInputBubbleView {
        TextInputBubbleView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
    }

    func test_enter_firesOnSubmitWithCurrentText_andClearsField() throws {
        let view = makeView()
        let textField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
        textField.stringValue = "hello"

        var submitted: String?
        view.onSubmit = { submitted = $0 }

        let handled = view.control(textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(handled)
        XCTAssertEqual(submitted, "hello")
        XCTAssertEqual(textField.stringValue, "")
    }

    func test_escape_firesOnCancel() throws {
        let view = makeView()
        let textField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)

        var cancelled = false
        view.onCancel = { cancelled = true }

        let handled = view.control(textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertTrue(handled)
        XCTAssertTrue(cancelled)
    }

    func test_unrelatedCommand_isNotHandled() throws {
        let view = makeView()
        let textField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)

        let handled = view.control(textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveLeft(_:)))

        XCTAssertFalse(handled)
    }

    // MARK: - Message mode (F6: "워크스페이스 꺼져있음")

    /// Sending user input with no workspace connected must show a notice, not
    /// re-open the input field — the old code called back into the same
    /// "show input bubble" path, so typing while workspace was off just
    /// reopened the bubble forever instead of ever telling the user why.
    func test_messageMode_displaysTheText() throws {
        let view = TextInputBubbleView(frame: CGRect(x: 0, y: 0, width: 240, height: 40))

        view.showMessage("워크스페이스가 꺼져 있어요")

        let textField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(textField.stringValue, "워크스페이스가 꺼져 있어요")
        XCTAssertFalse(textField.isEditable, "a notice must not be typed into")
    }

    func test_messageMode_doesNotAcceptInput() throws {
        let view = TextInputBubbleView(frame: CGRect(x: 0, y: 0, width: 240, height: 40))
        var submitted: String?
        view.onSubmit = { submitted = $0 }

        view.showMessage("워크스페이스가 꺼져 있어요")
        let textField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
        let handled = view.control(
            textField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        XCTAssertFalse(handled, "a notice bubble has nothing to submit")
        XCTAssertNil(submitted)
    }

    func test_returningToInputMode_acceptsInputAgain() throws {
        let view = TextInputBubbleView(frame: CGRect(x: 0, y: 0, width: 240, height: 40))
        var submitted: String?
        view.onSubmit = { submitted = $0 }

        view.showMessage("워크스페이스가 꺼져 있어요")
        view.showInput()
        let textField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
        textField.stringValue = "테스트 돌려줘"
        _ = view.control(
            textField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        XCTAssertEqual(submitted, "테스트 돌려줘")
    }

    // MARK: - F14 attachment capture (2026-08-01)

    func test_attachButton_firesOnAttachRequested() throws {
        let view = makeView()
        var requested = false
        view.onAttachRequested = { requested = true }

        let button = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first)
        button.performClick(nil)

        XCTAssertTrue(requested)
    }

    func test_setAttachmentThumbnail_showsAndHidesTheThumbnail() throws {
        let view = makeView()
        let thumbnail = try XCTUnwrap(view.subviews.compactMap { $0 as? NSImageView }.first)
        XCTAssertTrue(thumbnail.isHidden, "no attachment yet")

        let image = NSImage(size: NSSize(width: 4, height: 4))
        view.setAttachmentThumbnail(image)
        XCTAssertFalse(thumbnail.isHidden)
        XCTAssertEqual(thumbnail.image, image)

        view.setAttachmentThumbnail(nil)
        XCTAssertTrue(thumbnail.isHidden)
    }

    func test_clickingTheThumbnail_firesOnRemoveAttachment() throws {
        let view = makeView()
        view.setAttachmentThumbnail(NSImage(size: NSSize(width: 4, height: 4)))

        var removed = false
        view.onRemoveAttachment = { removed = true }

        let thumbnail = try XCTUnwrap(view.subviews.compactMap { $0 as? NSImageView }.first)
        let gesture = try XCTUnwrap(thumbnail.gestureRecognizers.first as? NSClickGestureRecognizer)
        _ = NSApp.sendAction(try XCTUnwrap(gesture.action), to: gesture.target, from: gesture)

        XCTAssertTrue(removed)
    }

    func test_showInput_resetsAnyPreviousAttachment() throws {
        let view = makeView()
        view.setAttachmentThumbnail(NSImage(size: NSSize(width: 4, height: 4)))

        view.showInput()

        let thumbnail = try XCTUnwrap(view.subviews.compactMap { $0 as? NSImageView }.first)
        XCTAssertTrue(thumbnail.isHidden)
    }
}
