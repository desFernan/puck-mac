//
//  EditorLiveUpdateTests.swift
//  PuckTests
//
//  Watching the agent write (2026-08-15). Two behaviours meet here and pull
//  opposite ways: a file changing under an open tab is a conflict to warn
//  about when the user typed into it, and the whole point when they are
//  watching a code_editor run they asked for. `isDirty` is the line between
//  them, and these pin it down.
//

import XCTest
@testable import Puck

@MainActor
final class EditorLiveUpdateTests: XCTestCase {
    private var root: URL!
    private var file: URL!
    private var store: EditorPaneStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EditorLiveUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        file = root.appendingPathComponent("main.swift")
        try Data("before".utf8).write(to: file)
        store = try EditorPaneStore(workspaceId: "w-\(UUID().uuidString)", root: root, onRootChanged: {})
        store.open(path: "main.swift")
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: root)
    }

    /// Hands the store the change its watcher would have delivered. The
    /// watcher itself is WorkspaceFileWatcherTests' subject; what is under
    /// test here is what the store does with the change.
    private func deliverChange(_ kind: FileSystemChangeKind) {
        store.handleFileSystemChanges([FileSystemChange(kind: kind, path: file.resolvingSymlinksInPath().path)])
    }

    func testAnUntouchedTabFollowsTheFile() throws {
        XCTAssertEqual(store.openTabs.first?.content, "before")
        try Data("after".utf8).write(to: file)

        deliverChange(.change)

        XCTAssertEqual(store.openTabs.first?.content, "after", "a tab the user is only watching should show what the agent wrote")
        XCTAssertEqual(store.openTabs.first?.diskChanged, false, "and not ask about a conflict that isn't one")
        XCTAssertEqual(store.openTabs.first?.isDirty, false)
    }

    func testATabTheUserEditedIsNotOverwritten() throws {
        store.updateDraft(path: "main.swift", content: "my own edit")
        XCTAssertEqual(store.openTabs.first?.isDirty, true)
        try Data("agent wrote this".utf8).write(to: file)

        deliverChange(.change)

        XCTAssertEqual(store.openTabs.first?.content, "my own edit", "typing is never silently replaced")
        XCTAssertEqual(store.openTabs.first?.diskChanged, true, "the conflict banner is still how that is resolved")
    }

    func testADeletedFileRaisesTheBannerRatherThanEmptyingTheTab() throws {
        try FileManager.default.removeItem(at: file)

        deliverChange(.unlink)

        XCTAssertEqual(store.openTabs.first?.content, "before", "a deletion is not new content to adopt")
        XCTAssertEqual(store.openTabs.first?.diskChanged, true)
    }

    func testAnUnchangedFileIsLeftAlone() {
        // Our own just-completed save fires the same event; re-reading and
        // comparing revisions is what stops it flagging itself.
        deliverChange(.change)

        XCTAssertEqual(store.openTabs.first?.diskChanged, false)
        XCTAssertEqual(store.openTabs.first?.content, "before")
    }
}

final class EditorRevealRequestTests: XCTestCase {
    @MainActor
    func testEachRevealIsItsOwnRequest() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        let before = store.editorRevealRequests

        store.revealInEditor(workspaceId: ClientWindowStore.defaultWorkspaceId)
        store.revealInEditor(workspaceId: ClientWindowStore.defaultWorkspaceId)

        // A counter rather than a flag: two files in a row are two requests,
        // and the second still has to re-open a pane closed in between.
        XCTAssertEqual(store.editorRevealRequests, before + 2)
    }

    @MainActor
    func testRevealingSwitchesToTheFilesWorkspace() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "other", projectPath: nil))
        store.activeWorkspaceId = ClientWindowStore.defaultWorkspaceId

        store.revealInEditor(workspaceId: "w2")

        XCTAssertEqual(store.activeWorkspaceId, "w2", "the pane can only show the active workspace")
    }

    @MainActor
    func testRevealingAnUnknownWorkspaceLeavesTheSelectionAlone() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))

        store.revealInEditor(workspaceId: "never-heard-of-it")

        XCTAssertEqual(store.activeWorkspaceId, ClientWindowStore.defaultWorkspaceId)
    }
}

/// Transcript grouping (2026-08-16). What starts a new exchange is a display
/// rule, but it is derived from the timeline rather than guessed at in the
/// view, so it is worth pinning down.
final class ChatTimelineGroupingTests: XCTestCase {
    func testWhatAPersonOrTheAgentSaysStartsANewTurn() {
        XCTAssertTrue(ChatTimelineEntry.userMessage(id: UUID(), text: "hi").startsNewTurn)
        XCTAssertTrue(ChatTimelineEntry.assistantText(id: UUID(), text: "ok").startsNewTurn)
    }

    func testTheMachineryOfARunDoesNot() {
        // A call, its result, the approval it needed and the line that ends
        // the run all belong to the turn that produced them.
        XCTAssertFalse(ChatTimelineEntry.toolCall(id: "t1", tool: "read_file", args: nil).startsNewTurn)
        XCTAssertFalse(ChatTimelineEntry.toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil).startsNewTurn)
        XCTAssertFalse(ChatTimelineEntry.approvalRequested(id: UUID(), approvalId: "a1", summary: "쉘 실행").startsNewTurn)
        XCTAssertFalse(ChatTimelineEntry.done(id: UUID(), ok: true, summary: "완료").startsNewTurn)
    }
}
