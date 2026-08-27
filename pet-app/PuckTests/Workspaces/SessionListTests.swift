//
//  SessionListTests.swift
//  PuckTests
//
//  Every chat the window knows about. The keying is the part worth pinning:
//  every workspace has its own chat called "default".
//

import XCTest
@testable import Puck

final class SessionListTests: XCTestCase {
    private func session(_ id: String, in workspace: String) -> ChatSession {
        ChatSession(id: id, workspaceId: workspace, title: id, origin: .user)
    }

    /// Protocol 3.4 keeps a session_id of "default" under every workspace, so
    /// a list keyed on the id alone has each workspace's casual chat
    /// overwriting the last one's.
    func test_twoWorkspacesCanEachHaveADefaultSession() {
        var list = SessionList()

        list.insert(session("default", in: "ws-1"))
        list.insert(session("default", in: "ws-2"))

        XCTAssertEqual(list.sessions(in: "ws-1").count, 1)
        XCTAssertEqual(list.sessions(in: "ws-2").count, 1)
        XCTAssertNotNil(list.session(workspaceId: "ws-1", sessionId: "default"))
        XCTAssertNotNil(list.session(workspaceId: "ws-2", sessionId: "default"))
    }

    /// pet-app replays its registry on connect and the agent announces a task
    /// session on the socket *and* opens it locally, so the same session
    /// legitimately arrives twice. Re-creating would wipe the messages
    /// already in it and duplicate the sidebar row.
    func test_insertingTheSameSessionTwiceKeepsTheFirst() {
        var list = SessionList()
        let original = session("chat", in: "ws-1")
        original.appendUserMessage("something already said")

        XCTAssertTrue(list.insert(original))
        XCTAssertFalse(list.insert(session("chat", in: "ws-1")), "and reports that nothing changed")

        XCTAssertTrue(list.session(workspaceId: "ws-1", sessionId: "chat") === original)
        XCTAssertEqual(list.sessions(in: "ws-1").count, 1)
    }

    /// Oldest first: the sidebar is a list of when things happened.
    func test_sessionsComeBackInTheOrderTheyArrived() {
        var list = SessionList()
        for id in ["first", "second", "third"] { list.insert(session(id, in: "ws-1")) }
        list.insert(session("elsewhere", in: "ws-2"))

        XCTAssertEqual(list.sessions(in: "ws-1").map(\.id), ["first", "second", "third"])
    }

    /// The change is reported so the caller knows whether to announce -- a
    /// removal of something that was not there must not redraw the sidebar.
    func test_removingReportsWhetherAnythingWasThere() {
        var list = SessionList()
        list.insert(session("chat", in: "ws-1"))

        XCTAssertTrue(list.remove(workspaceId: "ws-1", sessionId: "chat"))
        XCTAssertFalse(list.remove(workspaceId: "ws-1", sessionId: "chat"))
    }

    /// Removing from one workspace leaves the same id in another alone --
    /// the other half of the keying.
    func test_removingIsScopedToItsWorkspace() {
        var list = SessionList()
        list.insert(session("default", in: "ws-1"))
        list.insert(session("default", in: "ws-2"))

        list.remove(workspaceId: "ws-1", sessionId: "default")

        XCTAssertNil(list.session(workspaceId: "ws-1", sessionId: "default"))
        XCTAssertNotNil(list.session(workspaceId: "ws-2", sessionId: "default"))
    }

    /// A workspace that has gone takes its chats with it -- and nothing
    /// else's.
    func test_aDeletedWorkspaceTakesOnlyItsOwnChats() {
        var list = SessionList()
        for id in ["a", "b"] { list.insert(session(id, in: "doomed")) }
        list.insert(session("c", in: "kept"))

        XCTAssertTrue(list.removeAll(inWorkspace: "doomed"))

        XCTAssertTrue(list.sessions(in: "doomed").isEmpty)
        XCTAssertEqual(list.sessions(in: "kept").map(\.id), ["c"])
        XCTAssertFalse(list.removeAll(inWorkspace: "doomed"), "and doing it again is no news")
    }
}
