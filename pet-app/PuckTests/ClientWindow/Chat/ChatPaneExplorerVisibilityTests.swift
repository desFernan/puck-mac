//
//  ChatPaneExplorerVisibilityTests.swift
//  PuckTests
//
//  The file list and the toolbar picker that switches its tabs appear
//  together or not at all.
//

import XCTest
@testable import Puck

final class ChatPaneExplorerVisibilityTests: XCTestCase {
    func testShowsExplorerWhenEditorIsAttachedAndHasAStore() {
        XCTAssertTrue(ChatPaneView.showsExplorer(editorAttached: true, hasEditorStore: true))
    }

    func testHidesExplorerWhenTheEditorIsClosed() {
        XCTAssertFalse(ChatPaneView.showsExplorer(editorAttached: false, hasEditorStore: true))
    }

    /// The workspace has no usable project: the pane shows why instead of a
    /// file list, and there are no tabs to switch between.
    func testHidesExplorerWithoutAStore() {
        XCTAssertFalse(ChatPaneView.showsExplorer(editorAttached: true, hasEditorStore: false))
    }
}
