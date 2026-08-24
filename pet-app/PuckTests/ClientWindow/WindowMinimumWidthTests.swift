//
//  WindowMinimumWidthTests.swift
//  PuckTests
//
//  The window's floor has to be at least what the panes inside it declare.
//  It wasn't: the editor pane needed 540 while the window allowed 960 total
//  against a chat that wanted 480, and the missing 60+ came out of the file
//  tree, whose rows were clipped instead of truncated.
//
//  These numbers are duplicated from the view layer on purpose -- that is the
//  point. If someone widens a pane's minimum without revisiting the window's,
//  the arithmetic here stops adding up and says so.
//

import XCTest
@testable import Puck

final class WindowMinimumWidthTests: XCTestCase {
    /// The detached editor window's own HSplitView: file tree + code column.
    private let fileTreeMinimum: CGFloat = 180
    private let editorPaneMinimum: CGFloat = 540
    private let codeColumnMinimum: CGFloat = 300
    /// The file list on the right of the main window.
    private let explorerMinimum: CGFloat = 200
    /// The session list inside the chat pane's own split.
    private let sidebarMinimum: CGFloat = 180
    /// The conversation beside an open file.
    private let conversationMinimum: CGFloat = 320

    /// The original defect in one assertion: the pane declared 360 while its
    /// own two columns needed 540 between them, so it could be handed less
    /// width than it could actually draw. Only the detached window keeps that
    /// shape now.
    func testTheDetachedEditorFloorCoversWhatIsInsideIt() {
        XCTAssertGreaterThanOrEqual(editorPaneMinimum, fileTreeMinimum + codeColumnMinimum)
        XCTAssertGreaterThanOrEqual(ClientTheme.Metrics.editorWindowMinWidth, editorPaneMinimum)
    }

    /// The editor is no longer one pane beside the chat: the file list is a
    /// column on the right and a file's contents split the conversation.
    /// Attaching reserves room for both, because the code column arrives on a
    /// click the floor cannot react to in time.
    func testTheAttachedFloorFitsEveryColumnAtOnce() {
        XCTAssertGreaterThanOrEqual(
            ClientTheme.Metrics.windowMinWidthWithCode,
            sidebarMinimum + conversationMinimum + codeColumnMinimum + explorerMinimum,
            "opening a file must not push one of the four columns under its own minimum"
        )
    }

    func testTheChatOnlyFloorFitsItsOwnTwoColumns() {
        XCTAssertGreaterThanOrEqual(ClientTheme.Metrics.windowMinWidth, sidebarMinimum + conversationMinimum)
    }

    func testOpeningTheEditorRaisesTheFloorRatherThanSharingOne() {
        // One number for both modes is what forced the compromise: generous
        // for a chat, short for a chat plus an editor.
        XCTAssertGreaterThan(
            ClientTheme.Metrics.windowMinWidthWithCode,
            ClientTheme.Metrics.windowMinWidth
        )
    }

    func testTheFloorsAreNotAbsurdlyLargeForATypicalDisplay() {
        // A floor wider than a small laptop's screen is unusable, not safe.
        // 1280 is the narrowest built-in display Apple currently ships.
        XCTAssertLessThanOrEqual(ClientTheme.Metrics.windowMinWidthWithCode, 1280)
    }
}
