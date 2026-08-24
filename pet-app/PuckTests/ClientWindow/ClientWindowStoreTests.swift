//
//  ClientWindowStoreTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  ClientWindowStore is the sidebar/session-list source of truth: workspace
//  switching, per-workspace session lists, and routing incoming chat events
//  to the right session (plan/02_pet-app.md F13, plan/01_protocol.md 3.4/3.5).
//

import Combine
import XCTest
@testable import Puck

private final class StubTransport: UserInputTransport {
    var hasConnectedClients = true
    private(set) var broadcasted: [BridgeMessage] = []

    @discardableResult
    func broadcast(_ message: BridgeMessage) -> Bool {
        broadcasted.append(message)
        return true
    }
}

final class ClientWindowStoreTests: XCTestCase {
    /// `.done` carries a per-entry UUID now (two runs in one session used to
    /// collide on a fixed id), so its rows are matched on content.
    private func doneSummary(_ session: ChatSession?) -> String? {
        guard case .done(_, _, let summary)? = session?.timeline.last else { return nil }
        return summary
    }

    private func makeStore() -> (ClientWindowStore, StubTransport) {
        let transport = StubTransport()
        let store = ClientWindowStore(sender: UserInputSender { transport })
        return (store, transport)
    }

    func test_init_seedsTheDefaultWorkspaceAndItsCasualSession() {
        let (store, _) = makeStore()

        XCTAssertEqual(store.workspaces.map(\.id), ["default"])
        XCTAssertEqual(store.activeWorkspaceId, "default")
        XCTAssertEqual(store.activeSessionId, "default")
        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default"])
        XCTAssertEqual(store.sessions(in: "default").first?.origin, .user)
    }

    /// plan/02_pet-app.md F13: "워크스페이스마다 session_id: default인 일상
    /// 대화 세션이 항상 존재" -- a newly created workspace gets its own
    /// casual session automatically, without a separate session_create.
    func test_workspaceCreate_appendsTheWorkspaceAndSeedsItsOwnCasualSession() {
        let (store, _) = makeStore()

        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: "/tmp/cat-house"))

        XCTAssertEqual(store.workspaces.map(\.id), ["default", "w2"])
        XCTAssertEqual(store.sessions(in: "w2").map(\.id), ["default"])
        // The default workspace's own casual session must be untouched.
        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default"])
    }

    /// Two different workspaces both having a session literally named
    /// "default" must not collide -- routing has to be keyed on the
    /// (workspace_id, session_id) pair, not session_id alone.
    func test_defaultSessionsInDifferentWorkspaces_areIndependent() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        store.handleChatEvent(.agentDone(ok: true, summary: "default workspace done"), workspaceId: "default", sessionId: "default")
        store.handleChatEvent(.agentDone(ok: true, summary: "w2 done"), workspaceId: "w2", sessionId: "default")

        XCTAssertEqual(doneSummary(store.session(workspaceId: "default", sessionId: "default")), "default workspace done")
        XCTAssertEqual(doneSummary(store.session(workspaceId: "w2", sessionId: "default")), "w2 done")
    }

    func test_sessionCreate_userOrigin_appendsWithoutSwitchingActive() {
        let (store, _) = makeStore()

        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s2", title: "new chat", origin: .user))

        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default", "s2"])
        XCTAssertEqual(store.activeSessionId, "default", "a user-requested new chat doesn't steal focus from what they were doing")
    }

    /// The agent branching a casual chat into a task
    /// session should immediately bring the user along.
    func test_sessionCreate_agentOrigin_switchesActiveWorkspaceAndSession() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s9", title: "fix the bug", origin: .agent))

        XCTAssertEqual(store.activeWorkspaceId, "w2")
        XCTAssertEqual(store.activeSessionId, "s9")
    }

    func test_workspaceCreate_withARealProjectPath_canOpenEditorImmediately() throws {
        let (store, _) = makeStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: root.path))

        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.editorAvailability, .ready(rootURL: URL(fileURLWithPath: root.path, isDirectory: true)))
        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.canOpenEditor, true)
    }

    func test_workspaceCreate_withAPathThatDoesNotExist_cannotOpenEditor() {
        let (store, _) = makeStore()

        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "ghost house", projectPath: "/nonexistent/\(UUID().uuidString)"))

        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.editorAvailability, .unavailable(.pathMissing))
        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.canOpenEditor, false)
    }

    func test_refreshEditorAvailability_picksUpAProjectFolderDeletedAfterCreation() throws {
        let (store, _) = makeStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: root.path))
        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.canOpenEditor, true)

        try FileManager.default.removeItem(at: root)
        store.refreshEditorAvailability(forWorkspace: "w2")

        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.editorAvailability, .unavailable(.pathMissing))
        XCTAssertEqual(store.workspaces.first { $0.id == "w2" }?.canOpenEditor, false)
    }

    /// A move,
    /// not a branch, so the chat the prompt was written in must not be left
    /// behind holding it.
    func test_moveTurnToTaskSession_closesTheChatItCameFromAndBringsTheMessage() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s-new", title: "새 채팅", origin: .user))

        store.moveTurnToTaskSession(
            workspaceId: "default",
            from: "s-new",
            to: "s-task",
            title: "hello.ts 주석 추가",
            userMessage: "hello.ts에 주석 달아줘"
        )

        let sessions = store.sessions(in: "default")
        XCTAssertEqual(sessions.map(\.id), ["default", "s-task"], "the source chat must be gone, not sitting empty")
        XCTAssertEqual(store.activeSessionId, "s-task")
        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "s-task")?.timeline.count, 1,
                       "the user's own message moves across -- otherwise the task session opens empty")
    }

    /// The casual session is the one exception: 02_pet-app.md F13 keeps
    /// `session_id: "default"` always present, and it holds conversation that
    /// has nothing to do with the task.
    func test_moveTurnToTaskSession_keepsTheCasualSession() {
        let (store, _) = makeStore()

        store.moveTurnToTaskSession(
            workspaceId: "default",
            from: "default",
            to: "s-task",
            title: "작업",
            userMessage: "고쳐줘"
        )

        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default", "s-task"])
        XCTAssertEqual(store.activeSessionId, "s-task")
    }

    /// The same session_create is announced on the socket and relayed straight
    /// back to this app, so it arrives after the local move already built the
    /// session. Re-creating it would wipe the message just moved in.
    func test_relayedSessionCreate_doesNotWipeTheSessionTheMoveAlreadyBuilt() {
        let (store, _) = makeStore()
        store.moveTurnToTaskSession(
            workspaceId: "default",
            from: "default",
            to: "s-task",
            title: "작업",
            userMessage: "고쳐줘"
        )

        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s-task", title: "작업", origin: .agent))

        XCTAssertEqual(store.sessions(in: "default").filter { $0.id == "s-task" }.count, 1)
        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "s-task")?.timeline.count, 1)
    }

    /// What the topBar's editor toggle is enabled by, and what
    /// ClientWindowView's workspace-switch fallback reads to decide whether
    /// to close the editor (F13 "화면 3분할", 2026-08-12).
    func test_canOpenEditor_falseForThePureChatDefaultWorkspace() {
        let (store, _) = makeStore()
        func workspace(_ id: String) -> ClientWorkspace? { store.workspaces.first { $0.id == id } }

        XCTAssertEqual(workspace("default")?.canOpenEditor, false)
    }

    func test_requestNewWorkspace_delegatesToSender() {
        let (store, transport) = makeStore()

        store.requestNewWorkspace(name: "cat house", projectPath: "/tmp/cat-house")

        XCTAssertEqual(transport.broadcasted, [.workspaceCreateRequest(name: "cat house", projectPath: "/tmp/cat-house")])
    }

    // MARK: - Deleting a chat
    //
    // Local-only, like the close in moveTurnToTaskSession: protocol 3.4 has no
    // "session deleted" message, and replayForNewClient replays workspaces but
    // never sessions, so a deleted chat does not come back on reconnect.

    func test_deleteSession_removesItFromItsWorkspace() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s9", title: "새 대화", origin: .user))

        XCTAssertTrue(store.deleteSession(workspaceId: "default", sessionId: "s9"))

        XCTAssertEqual(store.sessions(in: "default").map(\.id), ["default"])
        XCTAssertNil(store.session(workspaceId: "default", sessionId: "s9"))
    }

    /// Deleting the chat you are looking at has to leave you somewhere: the
    /// workspace's casual session is the one place guaranteed to still exist.
    func test_deleteSession_whileItIsOpen_fallsBackToTheCasualSession() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s9", title: "새 대화", origin: .user))
        store.activeSessionId = "s9"

        store.deleteSession(workspaceId: "default", sessionId: "s9")

        XCTAssertEqual(store.activeWorkspaceId, "default")
        XCTAssertEqual(store.activeSessionId, "default")
    }

    /// Protocol 3.4 keeps `session_id: "default"` present under every
    /// workspace, and the fallback above needs somewhere to land -- so the
    /// casual session is the one chat that cannot be deleted.
    func test_deleteSession_refusesTheCasualSession() {
        let (store, _) = makeStore()

        XCTAssertFalse(store.canDeleteSession(workspaceId: "default", sessionId: "default"))
        XCTAssertFalse(store.deleteSession(workspaceId: "default", sessionId: "default"))
        XCTAssertEqual(store.sessions(in: "default").count, 1)
    }

    /// The stop button lives inside the chat. Deleting one mid-run would leave
    /// the agent working with nothing left on screen to stop it.
    func test_deleteSession_refusesWhileTheAgentIsStillWorking() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s9", title: "새 대화", origin: .user))
        store.session(workspaceId: "default", sessionId: "s9")?.markWaitingForAgent()

        XCTAssertFalse(store.canDeleteSession(workspaceId: "default", sessionId: "s9"))
        XCTAssertFalse(store.deleteSession(workspaceId: "default", sessionId: "s9"))
        XCTAssertNotNil(store.session(workspaceId: "default", sessionId: "s9"))
    }

    /// Same reason the insert announces: the sidebar reads the session list
    /// through `sessions(in:)`, which is not `@Published`.
    func test_deleteSession_announcesTheChange() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s9", title: "새 대화", origin: .user))
        var announcements = 0
        let subscription = store.objectWillChange.sink { _ in announcements += 1 }
        defer { subscription.cancel() }

        store.deleteSession(workspaceId: "default", sessionId: "s9")

        XCTAssertGreaterThan(announcements, 0)
    }

    /// `sessionsByKey`/`sessionOrder` are not `@Published`, so an insert that
    /// does not announce itself leaves the sidebar drawing from a stale
    /// snapshot -- in the running app that showed as a workspace whose chats
    /// had vanished, with the selection highlight sitting under the wrong
    /// header. The removal in moveTurnToTaskSession already announces; every
    /// insert has to as well.
    func test_sessionCreate_announcesTheChange_soTheSidebarRedraws() {
        let (store, _) = makeStore()
        var announcements = 0
        let subscription = store.objectWillChange.sink { _ in announcements += 1 }
        defer { subscription.cancel() }

        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s9", title: "새 대화", origin: .user))

        XCTAssertGreaterThan(announcements, 0)
        XCTAssertEqual(store.sessions(in: "default").count, 2)
    }

    /// Pressing "새 대화" has to land the user *in* the chat it just made.
    /// The id is minted on the other side, so the switch cannot happen at
    /// request time -- the request arms it and the matching sessionCreate
    /// spends it.
    func test_requestNewSession_thenItsConfirmation_opensTheNewChat() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        store.requestNewSession(title: "새 대화", in: "w2")
        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s9", title: "새 대화", origin: .user))

        XCTAssertEqual(store.activeWorkspaceId, "w2")
        XCTAssertEqual(store.activeSessionId, "s9")
    }

    /// Only the request this window made switches. A user-origin session
    /// created from somewhere else arrives the same way, and yanking the view
    /// to it would move the chat out from under whoever is typing here.
    func test_sessionCreate_userOrigin_withNoRequestOfOurOwn_doesNotSwitch() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s9", title: "elsewhere", origin: .user))

        XCTAssertEqual(store.activeWorkspaceId, "default")
        XCTAssertEqual(store.activeSessionId, "default")
    }

    /// One press, one switch: the arming is spent by the session it asked for,
    /// so a later unrelated session does not drag the view along behind it.
    func test_requestNewSession_armsExactlyOneSwitch() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        store.requestNewSession(title: "새 대화", in: "w2")
        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s9", title: "새 대화", origin: .user))
        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s10", title: "elsewhere", origin: .user))

        XCTAssertEqual(store.activeSessionId, "s9")
    }

    /// A request that never left has no session coming, so it must not leave
    /// the switch armed for whatever session_create happens to arrive next.
    func test_requestNewSession_undelivered_armsNothing() {
        let (store, transport) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))
        transport.hasConnectedClients = false

        XCTAssertEqual(store.requestNewSession(title: "새 대화", in: "w2"), .notDelivered)
        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s9", title: "새 대화", origin: .user))

        XCTAssertEqual(store.activeSessionId, "default")
    }

    /// Two quick presses make two chats, and the user should land in the
    /// second -- with a single flag only the first arrival switched, leaving
    /// them in the older of the two they had just asked for.
    func test_twoPresses_landOnTheSecondChat() {
        let (store, _) = makeStore()

        store.requestNewSession(title: "새 대화", in: "default")
        store.requestNewSession(title: "새 대화", in: "default")
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s1", title: "새 대화", origin: .user))
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "s2", title: "새 대화", origin: .user))

        XCTAssertEqual(store.activeSessionId, "s2")
    }

    /// Picking a chat by hand puts down anything still armed. A request whose
    /// confirmation never arrived would otherwise stay armed indefinitely and
    /// jump the user out of the chat they chose.
    func test_choosingAChatByHand_disarmsAStaleRequest() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "existing", title: "이전 대화", origin: .user))

        store.requestNewSession(title: "새 대화", in: "default")   // confirmation never arrives
        store.selectSession(workspaceId: "default", sessionId: "existing")
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "elsewhere", title: "남의 대화", origin: .user))

        XCTAssertEqual(store.activeSessionId, "existing")
    }

    /// The chat a task session was branched out of is closed, so the agent's
    /// memory of it has to go too -- the branch was handed a copy.
    func test_moveTurnToTaskSession_announcesTheClosedChatAsDeleted() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.sessionCreate(workspaceId: "default", sessionId: "source", title: "출처", origin: .user))
        var forgotten: [String] = []
        store.onSessionDeleted = { _, sessionId in forgotten.append(sessionId) }

        store.moveTurnToTaskSession(
            workspaceId: "default", from: "source", to: "task", title: "작업", userMessage: "고쳐줘"
        )

        XCTAssertEqual(forgotten, ["source"])
    }

    func test_requestNewSession_delegatesToSender() {
        let (store, transport) = makeStore()

        store.requestNewSession(title: "new chat", in: "default")

        XCTAssertEqual(transport.broadcasted, [.sessionCreateRequest(workspaceId: "default", title: "new chat")])
    }

    /// sendMessage routes through whichever workspace/session is currently active.
    func test_sendMessage_usesTheActiveWorkspaceAndSession() {
        let (store, transport) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))
        store.handleClientUpdate(.sessionCreate(workspaceId: "w2", sessionId: "s9", title: "fix the bug", origin: .agent))

        store.sendMessage("go on", source: .text)

        XCTAssertEqual(transport.broadcasted, [.userInput(UserInput(text: "go on", source: .text, workspaceId: "w2", sessionId: "s9"))])
    }

    /// The input bar has to show a running state the moment the message
    /// leaves, not once the model's first chunk has crossed the socket and
    /// come back. Asserted on the store rather than on a view because the
    /// store is the one funnel every send goes through -- the previous caller
    /// was a chat view that got rewritten away, taking the feedback with it.
    func test_sendMessage_marksTheActiveSessionRunningBeforeAnyEventArrives() {
        let (store, _) = makeStore()

        store.sendMessage("사파리 켜줘", source: .text)

        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "default")?.isRunning, true)
    }

    /// The transcript is the only place a sent message survives: ChatInputBar
    /// clears its field the moment it sends, so a send that is not echoed here
    /// erases what the user typed outright. Asserted on the store for the same
    /// reason the running state is -- it is the one funnel every send goes
    /// through, and the chat view that used to echo got rewritten away.
    func test_sendMessage_echoesWhatTheUserTypedIntoTheTranscript() {
        let (store, _) = makeStore()

        store.sendMessage("사파리 켜줘", source: .text)

        let timeline = store.session(workspaceId: "default", sessionId: "default")?.timeline ?? []
        XCTAssertEqual(timeline.count, 1)
        guard case .userMessage(_, let text) = timeline.first else {
            return XCTFail("expected userMessage, got \(String(describing: timeline.first))")
        }
        XCTAssertEqual(text, "사파리 켜줘")
    }

    /// Same, on the in-process agent path the shipping app actually takes --
    /// its early `.sent` return must not skip the echo.
    func test_sendMessage_toTheLocalAgent_echoesWhatTheUserTyped() {
        let (store, _) = makeStore()
        store.onUserCommand = { _, _, _ in }

        store.sendMessage("사파리 켜줘", source: .text)

        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "default")?.timeline.count, 1)
    }

    /// An undelivered message still echoes. Unlike the running state -- which
    /// is withheld because no answer is coming -- the echo has nothing to wait
    /// for, and the composer has already cleared: dropping it too would lose
    /// the text with nothing on screen to show it ever existed.
    func test_sendMessage_undelivered_stillEchoesWhatTheUserTyped() {
        let (store, transport) = makeStore()
        transport.hasConnectedClients = false

        XCTAssertEqual(store.sendMessage("사파리 켜줘", source: .text), .notDelivered)

        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "default")?.timeline.count, 1)
    }

    /// Same, on the in-process agent path -- which is the one the shipping app
    /// actually takes, and the one whose deliberate `.sent` shortcut must not
    /// be mistaken for "nothing was delivered".
    func test_sendMessage_toTheLocalAgent_marksTheActiveSessionRunning() {
        let (store, _) = makeStore()
        var received: [String] = []
        store.onUserCommand = { text, _, _ in received.append(text) }

        XCTAssertEqual(store.sendMessage("사파리 켜줘", source: .text), .sent)

        XCTAssertEqual(received, ["사파리 켜줘"])
        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "default")?.isRunning, true)
    }

    /// A message that never left has no answer coming, so a spinner for it
    /// would never stop.
    func test_sendMessage_undelivered_leavesTheSessionIdle() {
        let (store, transport) = makeStore()
        transport.hasConnectedClients = false

        XCTAssertEqual(store.sendMessage("사파리 켜줘", source: .text), .notDelivered)

        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "default")?.isRunning, false)
    }

    /// Text typed into pet-app's quick-capture bubble
    /// has to show up here. It arrives as a user_input with no workspace/
    /// session (the bubble knows nothing about either), which means the
    /// default workspace's casual session.
    func test_showUserMessage_withoutIds_landsInTheDefaultCasualSession() {
        let (store, _) = makeStore()

        XCTAssertTrue(store.showUserMessage("사파리 켜줘", workspaceId: nil, sessionId: nil))

        XCTAssertEqual(store.session(workspaceId: "default", sessionId: "default")?.timeline.count, 1)
        XCTAssertEqual(store.activeWorkspaceId, "default")
        XCTAssertEqual(store.activeSessionId, "default")
    }

    func test_showUserMessage_switchesToTheSessionItWasSentTo() {
        let (store, _) = makeStore()
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w2", name: "cat house", projectPath: nil))

        XCTAssertTrue(store.showUserMessage("hi", workspaceId: "w2", sessionId: "default"))

        XCTAssertEqual(store.activeWorkspaceId, "w2")
        XCTAssertEqual(store.activeSessionId, "default")
    }

    /// Same rule as handleChatEvent: an unknown session is dropped, not
    /// fabricated -- PuckClient keys "should I bring the window up?" off
    /// this, and an empty window popping open for a dropped message is worse
    /// than nothing.
    func test_showUserMessage_forAnUnknownSession_isDropped() {
        let (store, _) = makeStore()

        XCTAssertFalse(store.showUserMessage("hi", workspaceId: "nope", sessionId: "nope"))
    }

    // themeStyle moved to being a
    // Puck Settings item (see SettingsStoreTests' clientThemeStyle cases),
    // externally set here by PuckClient's AppDelegate rather than persisted
    // by this store, so there's nothing left to round-trip or fire a
    // callback on at this layer.
    /// Two permission requests can be outstanding at once (the coding agent
    /// batches parallel tool calls). Both have to be answerable: an approvalId
    /// the UI can no longer produce an answer for leaves the agent blocked on
    /// it for the whole tool timeout.
    func test_respondToPendingApproval_answersEveryQueuedRequestInTurn() {
        let (store, _) = makeStore()
        var answered: [(String, Bool)] = []
        store.onApprovalResolved = { approvalId, approved in answered.append((approvalId, approved)) }
        store.handleChatEvent(.awaitApproval(summary: "A", approvalId: "a1"), workspaceId: "default", sessionId: "default")
        store.handleChatEvent(.awaitApproval(summary: "B", approvalId: "a2"), workspaceId: "default", sessionId: "default")
        guard let session = store.session(workspaceId: "default", sessionId: "default") else {
            return XCTFail("the default session is seeded at init")
        }

        store.respondToPendingApproval(in: session, approved: true)
        store.respondToPendingApproval(in: session, approved: false)

        XCTAssertEqual(answered.map(\.0), ["a1", "a2"])
        XCTAssertEqual(answered.map(\.1), [true, false])
        XCTAssertTrue(session.pendingApprovals.isEmpty)
    }

    /// Nothing queued is not an error, and must not answer the *next* request
    /// to arrive -- the buttons are still on screen for a moment after the
    /// last one is resolved.
    func test_respondToPendingApproval_withNothingQueued_answersNothing() {
        let (store, _) = makeStore()
        var answered = 0
        store.onApprovalResolved = { _, _ in answered += 1 }
        guard let session = store.session(workspaceId: "default", sessionId: "default") else {
            return XCTFail("the default session is seeded at init")
        }

        store.respondToPendingApproval(in: session, approved: true)

        XCTAssertEqual(answered, 0)
    }

    func test_themeStyle_defaultsToDark_untilExternallySet() {
        let (store, _) = makeStore()

        XCTAssertEqual(store.themeStyle, .dark)
    }
}
