//
//  ChatSessionTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  ChatSession.apply(_:) folds the same BridgeEvent stream EventRouter reads
//  for pet reactions into a chat timeline, per plan/02_pet-app.md F13's
//  "onTextChunk 스트리밍, onToolCallStart/Result를 id로 짝지은 접이식 타임라인".
//

import XCTest
@testable import Puck

final class ChatSessionTests: XCTestCase {
    private func makeSession() -> ChatSession {
        ChatSession(id: "s2", workspaceId: "w1", title: "Fix the bug", origin: .agent)
    }

    private func makeUnnamedSession() -> ChatSession {
        ChatSession(id: "s3", workspaceId: "w1", title: ChatSession.placeholderTitle, origin: .user)
    }

    // MARK: - Naming a chat after what it is about
    //
    // A sidebar of chats all called "새 대화" is a sidebar you cannot navigate.
    // The first thing said in one is what it turned out to be about, so that is
    // what names it -- no model call, nothing to wait for, and it is already on
    // screen by the time the agent starts answering.

    func test_theFirstUserMessage_namesAnUnnamedChat() {
        let session = makeUnnamedSession()

        session.appendUserMessage("사파리 켜줘")

        XCTAssertEqual(session.title, "사파리 켜줘")
    }

    /// A sidebar row is one line wide. A whole paragraph pasted into the
    /// composer has to become a name, not overflow one.
    func test_aLongFirstMessage_isTruncatedIntoATitle() {
        let session = makeUnnamedSession()

        session.appendUserMessage(String(repeating: "가", count: 80))

        XCTAssertLessThan(session.title.count, 40)
        XCTAssertTrue(session.title.hasSuffix("…"), "got \(session.title)")
    }

    func test_aMultiLineFirstMessage_isNamedAfterItsFirstLine() {
        let session = makeUnnamedSession()

        session.appendUserMessage("로그인 버그\n재현 순서는 아래와 같아요\n1. 앱을 켠다")

        XCTAssertEqual(session.title, "로그인 버그")
    }

    /// Renaming stops once the chat has a name: the second message is not what
    /// the chat is about any more than the fifth is.
    func test_laterMessages_doNotRenameTheChat() {
        let session = makeUnnamedSession()

        session.appendUserMessage("사파리 켜줘")
        session.appendUserMessage("아니 크롬으로")

        XCTAssertEqual(session.title, "사파리 켜줘")
    }

    /// A task session arrives already named by the agent that opened it
    /// (open_task_session takes a title), and moveTurnToTaskSession then feeds
    /// it the message that started it -- which must not overwrite that name.
    func test_aChatThatAlreadyHasAName_keepsIt() {
        let session = makeSession()

        session.appendUserMessage("사파리 켜줘")

        XCTAssertEqual(session.title, "Fix the bug")
    }

    // MARK: - The topic title, read off the first exchange

    func test_firstExchange_isNilUntilBothHalvesExist() {
        let session = makeUnnamedSession()
        XCTAssertNil(session.firstExchange)

        session.appendUserMessage("로그인이 안 돼")
        XCTAssertNil(session.firstExchange, "a question with no answer is not an exchange")

        session.apply(.textChunk(text: "재현 순서를 알려주세요"))
        XCTAssertEqual(session.firstExchange?.user, "로그인이 안 돼")
        XCTAssertEqual(session.firstExchange?.reply, "재현 순서를 알려주세요")
    }

    /// A run that only called tools has no prose to read a topic off.
    func test_firstExchange_ignoresARunThatOnlySaidNothing() {
        let session = makeUnnamedSession()
        session.appendUserMessage("파일 열어줘")
        session.apply(.toolCall(id: "t1", tool: "open_in_editor", args: nil, detail: nil))
        session.apply(.toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil))

        XCTAssertNil(session.firstExchange)
    }

    /// A tool-using run opens with a placeholder and says what it found at
    /// the end. Naming the chat off the opener titles every one of them after
    /// the throat-clearing.
    func test_firstExchange_takesTheAgentsLastWordNotItsFirst() {
        let session = makeUnnamedSession()
        session.appendUserMessage("로그인이 안 돼")
        session.apply(.textChunk(text: "확인해 볼게요"))
        session.apply(.toolCall(id: "t1", tool: "read_file", args: nil, detail: nil))
        session.apply(.toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil))
        session.apply(.textChunk(text: "세션 만료 처리에서 토큰을 지우고 있었어요"))

        XCTAssertEqual(session.firstExchange?.reply, "세션 만료 처리에서 토큰을 지우고 있었어요")
    }

    /// The second question starts a turn the title is not about.
    func test_firstExchange_stopsAtTheSecondQuestion() {
        let session = makeUnnamedSession()
        session.appendUserMessage("첫 질문")
        session.apply(.textChunk(text: "첫 답"))
        session.appendUserMessage("둘째 질문")
        session.apply(.textChunk(text: "둘째 답"))

        XCTAssertEqual(session.firstExchange?.user, "첫 질문")
        XCTAssertEqual(session.firstExchange?.reply, "첫 답")
    }

    func test_applyTopicTitle_renamesAnAutoNamedChat() {
        let session = makeUnnamedSession()
        session.appendUserMessage("로그인이 안 돼")

        session.applyTopicTitle("로그인 실패 원인")

        XCTAssertEqual(session.title, "로그인 실패 원인")
        XCTAssertTrue(session.hasTopicTitle)
    }

    /// The agent named its own task session; the model naming chats must not
    /// reach in and rename it.
    func test_applyTopicTitle_leavesAChatItDidNotName() {
        let session = makeSession()

        session.applyTopicTitle("무언가 다른 제목")

        XCTAssertEqual(session.title, "Fix the bug")
    }

    /// One title per chat: later runs are the same conversation, not a new one
    /// to pay for.
    func test_applyTopicTitle_onlyTakesTheFirstOne() {
        let session = makeUnnamedSession()
        session.appendUserMessage("로그인이 안 돼")

        session.applyTopicTitle("로그인 실패 원인")
        session.applyTopicTitle("전혀 다른 주제")

        XCTAssertEqual(session.title, "로그인 실패 원인")
    }

    func test_applyTopicTitle_ignoresAnEmptyTopic() {
        let session = makeUnnamedSession()
        session.appendUserMessage("로그인이 안 돼")

        session.applyTopicTitle("   ")

        XCTAssertEqual(session.title, "로그인이 안 돼", "the first-message name has to survive a failed rename")
        XCTAssertFalse(session.hasTopicTitle)
    }

    func test_applyTopicTitle_truncatesALongTopic() {
        let session = makeUnnamedSession()
        session.appendUserMessage("짧은 질문")

        session.applyTopicTitle(String(repeating: "가", count: 80))

        XCTAssertTrue(session.title.hasSuffix("…"), "got \(session.title)")
    }

    func test_initialState_isEmptyAndNotRunning() {
        let session = makeSession()
        XCTAssertEqual(session.timeline, [])
        XCTAssertFalse(session.isRunning)
        XCTAssertNil(session.pendingApproval)
    }

    func test_agentThinking_marksRunning_withNoTimelineEntry() {
        let session = makeSession()
        session.apply(.agentThinking)

        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.timeline, [])
    }

    func test_textChunk_appendsANewAssistantTextEntry() {
        let session = makeSession()
        session.apply(.textChunk(text: "Running "))

        XCTAssertEqual(session.timeline.count, 1)
        guard case .assistantText(_, let text) = session.timeline[0] else {
            return XCTFail("expected assistantText, got \(session.timeline[0])")
        }
        XCTAssertEqual(text, "Running ")
    }

    /// Streaming means successive chunks concatenate onto the same entry
    /// rather than each becoming its own timeline row.
    func test_consecutiveTextChunks_concatenateIntoTheSameEntry() {
        let session = makeSession()
        session.apply(.textChunk(text: "Running "))
        session.apply(.textChunk(text: "the tests now."))

        XCTAssertEqual(session.timeline.count, 1)
        guard case .assistantText(_, let text) = session.timeline[0] else {
            return XCTFail("expected assistantText, got \(session.timeline[0])")
        }
        XCTAssertEqual(text, "Running the tests now.")
    }

    /// A tool call interrupts the streaming text -- the next chunk (if any)
    /// after a tool call must start a fresh entry, not resume the old one.
    func test_toolCallBetweenTextChunks_startsAFreshTextEntryAfterward() {
        let session = makeSession()
        session.apply(.textChunk(text: "Let me check."))
        session.apply(.toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil))
        session.apply(.textChunk(text: "Done."))

        XCTAssertEqual(session.timeline.count, 3)
        guard case .assistantText(_, let first) = session.timeline[0] else { return XCTFail("expected assistantText") }
        XCTAssertEqual(first, "Let me check.")
        guard case .assistantText(_, let second) = session.timeline[2] else { return XCTFail("expected assistantText") }
        XCTAssertEqual(second, "Done.")
    }

    // MARK: - user's own sent messages (2026-07-29) -- ChatSession.apply(_:)
    // only ever folds in the *agent's* side of the conversation (BridgeEvent
    // is workspace -> pet-app only); without this, what the user typed would
    // never appear in their own chat view.

    func test_appendUserMessage_addsATimelineEntry() {
        let session = makeSession()
        session.appendUserMessage("hi there")

        XCTAssertEqual(session.timeline.count, 1)
        guard case .userMessage(_, let text) = session.timeline[0] else {
            return XCTFail("expected userMessage, got \(session.timeline[0])")
        }
        XCTAssertEqual(text, "hi there")
    }

    /// A user message must not be treated as the tail of a still-streaming
    /// assistant reply -- the next textChunk has to start a fresh entry.
    func test_textChunkAfterUserMessage_startsAFreshEntry_ratherThanMerging() {
        let session = makeSession()
        session.apply(.textChunk(text: "earlier reply"))
        session.appendUserMessage("interrupting question")
        session.apply(.textChunk(text: "new reply"))

        XCTAssertEqual(session.timeline.count, 3)
        guard case .assistantText(_, let last) = session.timeline[2] else { return XCTFail("expected assistantText") }
        XCTAssertEqual(last, "new reply")
    }

    func test_toolCall_appendsATimelineEntryWithItsArgs() {
        let session = makeSession()
        session.apply(.toolCall(id: "t1", tool: "run_shell", args: .object(["command": .string("npm test")]), detail: nil))

        XCTAssertEqual(
            session.timeline,
            [.toolCall(id: "t1", tool: "run_shell", args: .object(["command": .string("npm test")]))]
        )
    }

    func test_toolResult_appendsATimelineEntryCorrelatedById() {
        let session = makeSession()
        session.apply(.toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil))
        session.apply(.toolResult(id: "t1", ok: true, data: .object(["exit_code": .number(0)]), error: nil, detail: nil))

        XCTAssertEqual(session.timeline.count, 2)
        XCTAssertEqual(
            session.timeline[1],
            .toolResult(id: "t1", ok: true, data: .object(["exit_code": .number(0)]), error: nil, detail: nil)
        )
    }

    func test_awaitApproval_setsPendingApproval_andAppendsATimelineEntry() {
        let session = makeSession()
        session.apply(.awaitApproval(summary: "requesting to run rm -rf ./dist", approvalId: "a1"))

        XCTAssertEqual(session.pendingApproval?.approvalId, "a1")
        XCTAssertEqual(session.pendingApproval?.summary, "requesting to run rm -rf ./dist")
        XCTAssertEqual(session.timeline.count, 1)
    }

    /// The coding agent batches parallel tool calls, so two permission
    /// requests can be outstanding at once. A single slot dropped the first
    /// one: only the second could be answered, and the request behind the
    /// first waited until the tool timeout expired.
    func test_twoApprovalsInFlight_bothStayPending_oldestFirst() {
        let session = makeSession()
        session.apply(.awaitApproval(summary: "A", approvalId: "a1"))
        session.apply(.awaitApproval(summary: "B", approvalId: "a2"))

        XCTAssertEqual(session.pendingApprovals.map(\.approvalId), ["a1", "a2"])
        XCTAssertEqual(session.pendingApproval?.approvalId, "a1")
    }

    func test_answeringTheOldestApproval_promotesTheNextOne() {
        let session = makeSession()
        session.apply(.awaitApproval(summary: "A", approvalId: "a1"))
        session.apply(.awaitApproval(summary: "B", approvalId: "a2"))

        session.resolveApproval(approvalId: "a1")

        XCTAssertEqual(session.pendingApprovals.map(\.approvalId), ["a2"])
        XCTAssertEqual(session.pendingApproval?.approvalId, "a2")
    }

    /// The banner used to read "응답함" for every request as soon as any one of
    /// them was pending-cleared, so a still-blocking request looked answered.
    func test_approvalState_isPerRequest() {
        let session = makeSession()
        session.apply(.awaitApproval(summary: "A", approvalId: "a1"))
        session.apply(.awaitApproval(summary: "B", approvalId: "a2"))

        XCTAssertEqual(session.approvalState(for: "a1"), .actionable)
        XCTAssertEqual(session.approvalState(for: "a2"), .queued)

        session.resolveApproval(approvalId: "a1")

        XCTAssertEqual(session.approvalState(for: "a1"), .resolved)
        XCTAssertEqual(session.approvalState(for: "a2"), .actionable)
    }

    func test_repeatedAwaitApprovalForTheSameId_doesNotQueueItTwice() {
        let session = makeSession()
        session.apply(.awaitApproval(summary: "A", approvalId: "a1"))
        session.apply(.awaitApproval(summary: "A", approvalId: "a1"))

        XCTAssertEqual(session.pendingApprovals.map(\.approvalId), ["a1"])
    }

    func test_agentDone_clearsEveryPendingApproval() {
        let session = makeSession()
        session.apply(.awaitApproval(summary: "A", approvalId: "a1"))
        session.apply(.awaitApproval(summary: "B", approvalId: "a2"))

        session.apply(.agentDone(ok: false, summary: "stopped"))

        XCTAssertTrue(session.pendingApprovals.isEmpty)
        XCTAssertEqual(session.approvalState(for: "a2"), .resolved)
    }

    func test_agentDone_clearsRunningAndPendingApproval_andAppendsASummaryEntry() {
        let session = makeSession()
        session.apply(.agentThinking)
        session.apply(.awaitApproval(summary: "x", approvalId: "a1"))
        session.apply(.agentDone(ok: true, summary: "3 tests passed"))

        XCTAssertFalse(session.isRunning)
        XCTAssertNil(session.pendingApproval)
        guard case .done(_, let ok, let summary)? = session.timeline.last else {
            return XCTFail("expected a done entry, got \(String(describing: session.timeline.last))")
        }
        XCTAssertTrue(ok)
        XCTAssertEqual(summary, "3 tests passed")
    }

    /// The loading row is driven by isRunning, and it has to come up on the
    /// send rather than on the relayed agent_thinking -- otherwise the window
    /// shows nothing for the whole round trip (2026-08-12).
    func test_markWaitingForAgent_startsRunningBeforeAnyEventArrives() {
        let session = makeSession()
        XCTAssertFalse(session.isRunning)

        session.markWaitingForAgent()
        XCTAssertTrue(session.isRunning)

        // And the run ending still puts it away -- a spinner with no off
        // switch is the failure mode worth guarding.
        session.apply(.agentDone(ok: true, summary: "끝"))
        XCTAssertFalse(session.isRunning)
    }

    /// A session takes as many prompts as the user types, so agent_done lands
    /// once per run, not once per session. While `.done` had a fixed id, the
    /// second one collided with the first in the transcript's ForEach and the
    /// scroll jumped to the top of the list every time a run finished.
    func test_severalRunsInOneSession_produceDistinctDoneIds() {
        let session = makeSession()
        session.apply(.agentDone(ok: true, summary: "첫 번째"))
        session.apply(.agentDone(ok: true, summary: "두 번째"))

        let doneIds = session.timeline.compactMap { entry -> AnyHashable? in
            guard case .done = entry else { return nil }
            return entry.id
        }
        XCTAssertEqual(doneIds.count, 2)
        XCTAssertEqual(Set(doneIds).count, 2, "two finished runs must not share a row identity")
    }

    /// Every timeline entry needs a stable identity for SwiftUI's List --
    /// tool call/result reuse the protocol's own tool_use id (already
    /// unique), the rest get their own.
    func test_timelineEntries_haveUniqueIds() {
        let session = makeSession()
        session.apply(.textChunk(text: "a"))
        session.apply(.toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil))
        session.apply(.toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil))
        session.apply(.awaitApproval(summary: "x", approvalId: "a1"))
        session.apply(.agentDone(ok: true, summary: "done"))

        let ids = session.timeline.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - lastActivityAt / lastRunOk (v3 sidebar relative time + outcome)

    func test_lastActivityAt_isNilBeforeAnyEvent() {
        let session = makeSession()
        XCTAssertNil(session.lastActivityAt)
    }

    func test_lastActivityAt_advancesOnEveryAppliedEvent() {
        let session = makeSession()
        session.apply(.agentThinking)
        let first = session.lastActivityAt
        XCTAssertNotNil(first)
        session.apply(.textChunk(text: "hi"))
        XCTAssertNotNil(session.lastActivityAt)
        XCTAssertGreaterThanOrEqual(session.lastActivityAt!, first!)
    }

    func test_lastRunOk_isNilUntilARunCompletes() {
        let session = makeSession()
        XCTAssertNil(session.lastRunOk)
        session.apply(.agentThinking)
        XCTAssertNil(session.lastRunOk, "a run in progress has no outcome yet")
    }

    func test_lastRunOk_reflectsTheMostRecentDoneEntry() {
        let session = makeSession()
        session.apply(.agentDone(ok: false, summary: "실패"))
        XCTAssertEqual(session.lastRunOk, false)
        session.apply(.agentDone(ok: true, summary: "완료"))
        XCTAssertEqual(session.lastRunOk, true, "the newest done entry wins")
    }

    /// A re-broadcast approval is the same request arriving twice: one queued
    /// item, and one card. The transcript used to show two, of which only the
    /// first could be answered.
    func test_aRebroadcastApprovalIsNotASecondCard() {
        let session = ChatSession(id: "s", workspaceId: "w", title: "t", origin: .user)

        session.apply(.awaitApproval(summary: "rm -rf /", approvalId: "a1"))
        session.apply(.awaitApproval(summary: "rm -rf /", approvalId: "a1"))

        XCTAssertEqual(session.pendingApprovals.count, 1)
        XCTAssertEqual(session.timeline.filter { if case .approvalRequested = $0 { return true } else { return false } }.count, 1)
    }
    // MARK: - Every default name is replaced by what was said

    /// The always-present chat used to keep its name for good, so every
    /// workspace had a row called the same thing and the sidebar told you
    /// nothing about which was which.
    func test_theCasualChatIsNamedByItsFirstMessage() {
        let session = ChatSession(
            id: "default",
            workspaceId: "w1",
            title: ChatSession.casualTitle,
            origin: .user
        )

        session.appendUserMessage("섬 어깨 높이 좀 봐줘")

        XCTAssertEqual(session.title, "섬 어깨 높이 좀 봐줘")
    }

    func test_aSessionCreatedWithNoName_isNamedByItsFirstMessage() {
        let session = ChatSession(
            id: "s1",
            workspaceId: "w1",
            title: ChatSession.untitledTitle,
            origin: .user
        )

        session.appendUserMessage("빌드가 왜 깨졌지")

        XCTAssertEqual(session.title, "빌드가 왜 깨졌지")
    }

    /// A name the agent chose is not a default, and is left alone.
    func test_anAgentNamedSessionKeepsItsName() {
        let session = ChatSession(id: "s2", workspaceId: "w1", title: "섬 모양 다듬기", origin: .agent)

        session.appendUserMessage("이어서 하자")

        XCTAssertEqual(session.title, "섬 모양 다듬기")
    }

    /// And once a chat has earned a name, the second message does not
    /// rename it.
    func test_theSecondMessageDoesNotRenameIt() {
        let session = ChatSession(id: "s3", workspaceId: "w1", title: ChatSession.placeholderTitle, origin: .user)

        session.appendUserMessage("첫 질문")
        session.appendUserMessage("두 번째 질문")

        XCTAssertEqual(session.title, "첫 질문")
    }
}
