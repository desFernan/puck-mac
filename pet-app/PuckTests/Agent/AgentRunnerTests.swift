//
//  AgentRunnerTests.swift
//  Puck
//
//  Covers AgentRunner.pathArgument, and one exercise of the turn loop itself
//  against a FakeLLMClient conforming to AgentLLMClient -- now that the loop
//  no longer requires the concrete GPTClient, network mocking is no longer
//  needed to construct a runner for a test.
//

import XCTest
@testable import Puck

final class AgentRunnerTests: XCTestCase {
    /// Conforms to AgentLLMClient only -- proves AgentRunner doesn't need the
    /// concrete GPTClient to run a turn.
    private final class FakeLLMClient: AgentLLMClient {
        var turns: [GPTTurn] = []
        private(set) var sendCount = 0

        func send(messages: [GPTMessage], tools: [GPTToolSpec], sessionId: String? = nil) async throws -> GPTTurn {
            sendCount += 1
            return turns.isEmpty ? GPTTurn(text: "done", toolCalls: []) : turns.removeFirst()
        }
    }

    /// Answers the first turn with tool calls and records what it is shown
    /// on every turn after that -- which is where an unanswered tool call
    /// shows up.
    private final class ToolThenRecordingClient: AgentLLMClient {
        var toolCalls: [GPTToolCall] = []
        private(set) var messagesPerTurn: [[GPTMessage]] = []

        func send(messages: [GPTMessage], tools: [GPTToolSpec], sessionId: String? = nil) async throws -> GPTTurn {
            messagesPerTurn.append(messages)
            guard messagesPerTurn.count == 1 else { return GPTTurn(text: "done", toolCalls: []) }
            return GPTTurn(text: nil, toolCalls: toolCalls)
        }
    }

    /// Records what the model was actually shown, which is the only way to
    /// see one chat's context leaking into another.
    private final class RecordingLLMClient: AgentLLMClient {
        private(set) var lastMessages: [GPTMessage] = []
        /// Sleeps inside `send`, so a test can replace the run while it is
        /// where a real run spends nearly all its time.
        var stallNanoseconds: UInt64 = 0

        func send(messages: [GPTMessage], tools: [GPTToolSpec], sessionId: String? = nil) async throws -> GPTTurn {
            lastMessages = messages
            if stallNanoseconds > 0 { try? await Task.sleep(nanoseconds: stallNanoseconds) }
            return GPTTurn(text: "ok", toolCalls: [])
        }

        var lastUserTexts: [String] {
            lastMessages.compactMap { if case .user(let t) = $0 { return t } else { return nil } }
        }

        var lastSystemTexts: [String] {
            lastMessages.compactMap { if case .system(let t) = $0 { return t } else { return nil } }
        }
    }

    private func makeRecordingRunner() -> (AgentRunner, RecordingLLMClient) {
        let client = RecordingLLMClient()
        let runner = AgentRunner(
            client: client,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { _, _ in }
        )
        return (runner, client)
    }

    // MARK: - One conversation per chat

    /// The bug this exists for: every chat in the app shared one message
    /// stack, so a new chat opened with the previous one's conversation
    /// already in it -- including another workspace's "no project folder is
    /// bound to it, so there are no files to read or list", which the model
    /// then repeated at a chat whose workspace did have one.
    func test_aSecondChat_doesNotSeeTheFirstOnesMessages() async {
        let (runner, client) = makeRecordingRunner()

        runner.sessionId = "chat-1"
        await runner.run(command: "첫 대화의 질문")

        runner.sessionId = "chat-2"
        await runner.run(command: "두 번째 대화의 질문")

        XCTAssertEqual(client.lastUserTexts, ["두 번째 대화의 질문"])
    }

    /// The other half: going back to a chat has to bring its own history with
    /// it, or the model contradicts the transcript the user is looking at.
    func test_returningToAChat_stillHasItsOwnHistory() async {
        let (runner, client) = makeRecordingRunner()

        runner.sessionId = "chat-1"
        await runner.run(command: "첫 질문")
        runner.sessionId = "chat-2"
        await runner.run(command: "다른 대화")
        runner.sessionId = "chat-1"
        await runner.run(command: "이어서")

        XCTAssertEqual(client.lastUserTexts, ["첫 질문", "이어서"])
    }

    /// The workspace line is per chat too -- it was announced once per runner,
    /// so a chat opened later under a different workspace never heard about
    /// its own.
    func test_eachChatHearsItsOwnWorkspaceLine() async {
        let (runner, client) = makeRecordingRunner()

        runner.sessionId = "chat-1"
        runner.workspaceContext = AgentRunner.WorkspaceContext(name: "기본 워크스페이스", projectPath: nil)
        await runner.run(command: "안녕")

        runner.sessionId = "chat-2"
        runner.workspaceContext = AgentRunner.WorkspaceContext(name: "치ㅑ", projectPath: "/tmp/cli")
        await runner.run(command: "이 프로젝트 분석해줘")

        let systems = client.lastSystemTexts
        XCTAssertTrue(systems.contains { $0.contains("/tmp/cli") }, "got \(systems)")
        XCTAssertFalse(
            systems.contains { $0.contains("No project folder is bound") },
            "the other workspace's line must not be in this chat: \(systems)"
        )
    }

    /// Announced once per chat, not once per turn.
    func test_theWorkspaceLine_isNotRepeatedEveryTurn() async {
        let (runner, client) = makeRecordingRunner()
        runner.sessionId = "chat-1"
        runner.workspaceContext = AgentRunner.WorkspaceContext(name: "puck", projectPath: "/tmp/puck")

        await runner.run(command: "하나")
        await runner.run(command: "둘")

        XCTAssertEqual(client.lastSystemTexts.filter { $0.contains("/tmp/puck") }.count, 1)
    }

    /// A task session is a branch of the conversation that opened it, not a
    /// fresh one -- the agent has to remember what it was asked to do.
    func test_carryConversation_movesTheHistoryIntoTheTaskSession() async {
        let (runner, client) = makeRecordingRunner()
        runner.sessionId = "casual"
        await runner.run(command: "이 버그 고쳐줘")

        runner.carryConversation(from: "casual", to: "task")
        runner.sessionId = "task"
        await runner.run(command: "계속")

        XCTAssertEqual(client.lastUserTexts, ["이 버그 고쳐줘", "계속"])
    }

    /// Deleting a chat has to take its conversation with it; otherwise the
    /// model keeps what the user just threw away.
    func test_forgetSession_dropsThatChatsConversation() async {
        let (runner, client) = makeRecordingRunner()
        runner.sessionId = "chat-1"
        await runner.run(command: "지워질 이야기")

        runner.forgetSession("chat-1")
        await runner.run(command: "새 이야기")

        XCTAssertEqual(client.lastUserTexts, ["새 이야기"])
    }

    /// A run keeps executing after it is cancelled until it next checks, and
    /// `sessionId` by then belongs to whichever chat replaced it. The dying
    /// run's answer must not land there.
    func test_aCancelledRun_doesNotWriteIntoTheChatThatReplacedIt() async {
        let (runner, client) = makeRecordingRunner()
        client.stallNanoseconds = 200_000_000

        runner.sessionId = "chat-1"
        let first = Task { await runner.run(command: "느린 질문") }
        try? await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()
        runner.sessionId = "chat-2"
        await runner.run(command: "두 번째 대화의 질문")
        await first.value

        XCTAssertEqual(client.lastUserTexts, ["두 번째 대화의 질문"])
    }

    /// Nothing trimmed the stack before, so a long chat grew every turn until
    /// it hit the model's context limit.
    func test_aLongChat_isTrimmedToACap() async {
        let (runner, client) = makeRecordingRunner()
        runner.sessionId = "chat-1"

        for i in 0..<80 { await runner.run(command: "질문 \(i)") }

        XCTAssertLessThan(client.lastMessages.count, 80)
        XCTAssertEqual(client.lastUserTexts.last, "질문 79")
    }

    /// Trimming keeps the system lines whatever their age: they are few, and
    /// dropping one silently un-tells the model something it was told once.
    func test_trimming_keepsTheWorkspaceLine() async {
        let (runner, client) = makeRecordingRunner()
        runner.sessionId = "chat-1"
        runner.workspaceContext = AgentRunner.WorkspaceContext(name: "puck", projectPath: "/tmp/puck")

        for i in 0..<80 { await runner.run(command: "질문 \(i)") }

        XCTAssertTrue(client.lastSystemTexts.contains { $0.contains("/tmp/puck") }, "got \(client.lastSystemTexts)")
    }

    func test_agentRunner_acceptsAnyAgentLLMClient() async throws {
        let fake = FakeLLMClient()
        fake.turns = [GPTTurn(text: "안녕하세요", toolCalls: [])]
        var events: [BridgeEvent] = []

        let runner = AgentRunner(
            client: fake,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { event, _ in events.append(event) }
        )

        await runner.run(command: "hi")

        XCTAssertEqual(fake.sendCount, 1)
        XCTAssertTrue(events.contains(.textChunk(text: "안녕하세요")))
        XCTAssertTrue(events.contains(.agentDone(ok: true, summary: "안녕하세요")))
    }

    /// Hangs inside the model call until the enclosing Task is cancelled,
    /// which is what a real 중지 during a slow completion looks like.
    private final class HangingLLMClient: AgentLLMClient {
        let started: XCTestExpectation

        init(started: XCTestExpectation) { self.started = started }

        func send(messages: [GPTMessage], tools: [GPTToolSpec], sessionId: String? = nil) async throws -> GPTTurn {
            started.fulfill()
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return GPTTurn(text: "answered after the stop", toolCalls: [])
        }
    }

    /// 중지 pressed while the model call is in flight. The run has to end, and
    /// it has to end as a stop rather than as the URLError(.cancelled) the
    /// cancelled request actually throws -- "요청이 취소되었습니다" in the
    /// transcript reads as a network failure the user didn't cause.
    func test_run_cancelledDuringTheModelCall_endsAsAStopNotAnError() async {
        let started = expectation(description: "model call in flight")
        let events = UncheckedBox([BridgeEvent]())
        let runner = AgentRunner(
            client: HangingLLMClient(started: started),
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { event, _ in events.value.append(event) }
        )

        let task = Task { await runner.run(command: "천천히 해줘") }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await task.value

        let emitted = events.value
        XCTAssertEqual(
            emitted.last,
            .agentDone(ok: false, summary: AgentRunner.cancelledSummary),
            "a cancelled run still has to finish, or the chat spins forever"
        )
        // The done event carries it and DoneRow renders it; a text chunk
        // saying the same thing would print the stop twice.
        XCTAssertFalse(emitted.contains(.textChunk(text: AgentRunner.cancelledSummary)))
        XCTAssertFalse(
            emitted.contains { event in
                if case .textChunk(let text) = event { return text.lowercased().contains("cancel") }
                return false
            },
            "the URLSession cancellation must never be reported as a failure"
        )
    }

    /// The stop has to leave the session coherent, not just stop producing:
    /// folding what a cancelled run emits must take the chat out of its
    /// running state and end the transcript with the stop.
    func test_cancelledRun_leavesTheSessionFinished() async {
        let started = expectation(description: "model call in flight")
        let events = UncheckedBox([BridgeEvent]())
        let runner = AgentRunner(
            client: HangingLLMClient(started: started),
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { event, _ in events.value.append(event) }
        )

        let task = Task { await runner.run(command: "천천히 해줘") }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await task.value

        let session = ChatSession(id: "default", workspaceId: "default", title: "t", origin: .user)
        session.markWaitingForAgent()
        for event in events.value { session.apply(event) }

        XCTAssertFalse(session.isRunning)
        guard case .done(_, _, let summary)? = session.timeline.last else {
            return XCTFail("the transcript must end with a done row")
        }
        XCTAssertEqual(summary, AgentRunner.cancelledSummary)
    }

    /// A turn can ask for several tools. Stopping during the first one must
    /// not let the rest of the turn run -- checking cancellation only between
    /// model calls would still execute every remaining call in the batch.
    func test_run_cancelledDuringATool_doesNotRunTheRestOfTheTurn() async {
        let fake = FakeLLMClient()
        fake.turns = [
            GPTTurn(
                text: nil,
                toolCalls: [
                    GPTToolCall(id: "call-1", name: "run_shell", argumentsJSON: "{\"command\":\"ls\"}"),
                    GPTToolCall(id: "call-2", name: "run_shell", argumentsJSON: "{\"command\":\"pwd\"}"),
                ]
            ),
        ]
        let events = UncheckedBox([BridgeEvent]())
        let approvals = UncheckedBox([String]())
        let runTask = UncheckedBox(Task<Void, Never>?.none)

        let runner = AgentRunner(
            client: fake,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, approvalId in
                approvals.value.append(approvalId)
                // 중지 while the first tool's approval banner is up.
                runTask.value?.cancel()
                return false
            },
            emit: { event, _ in events.value.append(event) }
        )

        // The gate exists so `runTask` is definitely set before the approval
        // gate reaches for it -- otherwise the cancel would be a no-op on some
        // runs and the test would only sometimes exercise the fix.
        let release = UncheckedBox(false)
        let task = Task {
            while !release.value { await Task.yield() }
            await runner.run(command: "두 개 해줘")
        }
        runTask.value = task
        release.value = true
        await task.value

        XCTAssertEqual(approvals.value, ["call-1"], "the second tool must never be asked about")
        XCTAssertEqual(events.value.last, .agentDone(ok: false, summary: AgentRunner.cancelledSummary))
        XCTAssertEqual(fake.sendCount, 1, "no further turn may be requested after a stop")
    }

    /// The stack a provider is handed has to answer every tool call in it.
    /// Stopping between two of them left the last assistant message asking
    /// for tools nothing replied to, and both providers reject that -- so
    /// every later message in that chat failed, permanently, with nothing in
    /// the app to repair it.
    func test_aStopBetweenToolCalls_leavesAConversationTheProviderWillAccept() async {
        let client = ToolThenRecordingClient()
        client.toolCalls = [
            GPTToolCall(id: "call-1", name: "run_shell", argumentsJSON: "{\"command\":\"ls\"}"),
            GPTToolCall(id: "call-2", name: "run_shell", argumentsJSON: "{\"command\":\"pwd\"}"),
        ]
        let runTask = UncheckedBox(Task<Void, Never>?.none)
        let runner = AgentRunner(
            client: client,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in
                runTask.value?.cancel()
                return false
            },
            emit: { _, _ in }
        )

        let release = UncheckedBox(false)
        let stopped = Task {
            while !release.value { await Task.yield() }
            await runner.run(command: "두 개 해줘")
        }
        runTask.value = stopped
        release.value = true
        await stopped.value

        // The same chat, used again afterwards -- which is what used to fail.
        await runner.run(command: "그래서, 뭐였지?")

        let shown = client.messagesPerTurn.last ?? []
        var answered: Set<String> = []
        var requested: [String] = []
        for message in shown {
            if case .assistant(_, let calls, _) = message { requested += calls.map(\.id) }
            if case .tool(let callId, _) = message { answered.insert(callId) }
        }
        XCTAssertEqual(requested.sorted(), ["call-1", "call-2"])
        for id in requested {
            XCTAssertTrue(answered.contains(id), "\(id) was asked for and never answered")
        }
    }

    /// The chat a turn belongs to travels with the turn. The CLI provider
    /// calls Puck's tools out of band over MCP, and those calls used to be
    /// addressed to whatever the runner's "current" chat happened to be by
    /// the time they arrived -- so a tool call from a still-running turn in
    /// chat A, including its approval prompt, appeared in chat B.
    func test_aTurnTellsTheClientWhichChatItBelongsTo() async {
        final class SessionRecordingClient: AgentLLMClient {
            private(set) var sessions: [String?] = []
            func send(
                messages: [GPTMessage],
                tools: [GPTToolSpec],
                sessionId: String? = nil
            ) async throws -> GPTTurn {
                sessions.append(sessionId)
                return GPTTurn(text: "ok", toolCalls: [])
            }
        }

        let client = SessionRecordingClient()
        let runner = AgentRunner(
            client: client,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in true },
            emit: { _, _ in }
        )

        await runner.run(command: "첫 채팅", session: "chat-a")
        await runner.run(command: "두 번째 채팅", session: "chat-b")

        XCTAssertEqual(client.sessions, ["chat-a", "chat-b"])
    }

    /// A run that is superseded by a command in *another* chat used to emit
    /// nothing at all: events were addressed to whichever chat was active when
    /// they were emitted, so announcing "중지했어요" would have said it in a
    /// conversation the user never stopped. The cost was that the run's own
    /// chat never heard its run had ended and held its spinner forever.
    /// Naming the session on every event settles both: the ending goes to the
    /// chat that was running, and nowhere else.
    func test_cancelledRun_reportsIntoItsOwnChat_notWhicheverIsActiveNow() async {
        let started = expectation(description: "model call in flight")
        let events = UncheckedBox([(event: BridgeEvent, sessionId: String)]())
        let runner = AgentRunner(
            client: HangingLLMClient(started: started),
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { event, sessionId in events.value.append((event, sessionId)) }
        )

        runner.sessionId = "chat-a"
        let task = Task { await runner.run(command: "첫 번째") }
        // Waited for, not slept on: the run has to have captured its own
        // session before the next line repoints it, or the test proves nothing.
        await fulfillment(of: [started], timeout: 2)
        // The user moves to another chat and starts a run there, which is what
        // repoints sessionId and cancels this one.
        runner.sessionId = "chat-b"
        task.cancel()
        await task.value

        let endings = events.value.filter {
            if case .agentDone = $0.event { return true }
            return false
        }
        XCTAssertEqual(
            endings.map(\.sessionId),
            ["chat-a"],
            "the run's ending belongs to the chat it ran in, so that chat can leave its running state"
        )
        XCTAssertFalse(
            events.value.contains { $0.sessionId == "chat-b" },
            "nothing may land in the chat that replaced it"
        )
    }

    /// Fails the turn with whatever it was handed -- a model call that throws
    /// is the only way into the failure path.
    private final class ThrowingLLMClient: AgentLLMClient {
        let error: Error

        init(error: Error) { self.error = error }

        func send(messages: [GPTMessage], tools: [GPTToolSpec], sessionId: String? = nil) async throws -> GPTTurn {
            throw error
        }
    }

    private func runFailing(with error: Error) async -> [BridgeEvent] {
        let events = UncheckedBox([BridgeEvent]())
        let runner = AgentRunner(
            client: ThrowingLLMClient(error: error),
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { event, _ in events.value.append(event) }
        )
        await runner.run(command: "안녕")
        return events.value
    }

    /// The failure used to be emitted twice -- once as a text_chunk, once as
    /// agent_done -- and the transcript showed the same text stacked in an
    /// assistant bubble and the done row.
    func test_failedRun_reportsTheReasonInExactlyOneRow() async {
        let events = await runFailing(with: GPTError.http(status: 401, body: Self.unauthorizedBody))

        let session = ChatSession(id: "default", workspaceId: "default", title: "t", origin: .user)
        session.markWaitingForAgent()
        for event in events { session.apply(event) }

        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.timeline.count, 1, "a failure is one row, not a bubble and a done row saying the same thing")
        guard case .done(_, let ok, let summary)? = session.timeline.last else {
            return XCTFail("the transcript must end with a done row")
        }
        XCTAssertFalse(ok)
        XCTAssertFalse(summary.isEmpty, "the done row is the only place the reason survives")
    }

    /// A bad key is ~20 lines of the provider's JSON, key prefix included.
    /// None of it belongs in the chat.
    func test_unauthorized_saysTheKeyIsWrongWithoutTheRawBody() async {
        let events = await runFailing(with: GPTError.http(status: 401, body: Self.unauthorizedBody))

        guard case .agentDone(_, let summary)? = events.last else {
            return XCTFail("a failed run must still finish")
        }
        XCTAssertEqual(summary, String(format: Strings.text(.agentBadAPIKeyFormat), Strings.text(.agentSettingsHint)))
        XCTAssertFalse(summary.contains("invalid_request_error"))
        XCTAssertFalse(summary.contains("cp_jUkL5"), "the body quotes the key back; it must not reach the transcript")
        XCTAssertFalse(summary.contains("{"))
    }

    /// ...but it does have to reach the log, or a genuinely odd 401 becomes
    /// undebuggable.
    func test_rawFailureDescription_keepsTheBodyForTheLog() {
        let raw = AgentRunner.rawFailureDescription(for: GPTError.http(status: 401, body: Self.unauthorizedBody))

        XCTAssertTrue(raw.contains("invalid_request_error"))
        XCTAssertTrue(raw.contains("401"))
    }

    func test_failureSummary_missingKeyPointsAtSettings() {
        XCTAssertEqual(
            AgentRunner.failureSummary(for: GPTError.notConfigured),
            String(format: Strings.text(.agentNoAPIKeyFormat), Strings.text(.agentSettingsHint))
        )
    }

    /// Every other kind of failure keeps its own words -- collapsing them into
    /// one friendly sentence would make "the model name is wrong" and "the
    /// server is down" indistinguishable.
    func test_failureSummary_distinguishesTheOtherKinds() {
        let summaries = [
            AgentRunner.failureSummary(for: GPTError.http(status: 404, body: "{}")),
            AgentRunner.failureSummary(for: GPTError.http(status: 429, body: "{}")),
            AgentRunner.failureSummary(for: GPTError.http(status: 503, body: "{}")),
            AgentRunner.failureSummary(for: GPTError.malformedResponse("no choices[0].message")),
        ]

        XCTAssertEqual(Set(summaries).count, summaries.count, "each failure kind needs its own text")
        XCTAssertEqual(summaries[0], Strings.text(.agentModelNotFound))
        XCTAssertTrue(summaries[2].contains("503"))
        XCTAssertTrue(summaries[3].contains("no choices[0].message"), "a decoding failure names what failed to decode")
    }

    /// A status with no advice of our own still says what the provider said,
    /// as one sentence rather than as the envelope it arrived in.
    func test_failureSummary_unmappedStatusQuotesTheProvidersOwnMessage() {
        let body = #"{"error": {"message": "Unsupported parameter: 'temperature'", "type": "invalid_request_error"}}"#

        let summary = AgentRunner.failureSummary(for: GPTError.http(status: 400, body: body))

        XCTAssertTrue(summary.contains("Unsupported parameter: 'temperature'"))
        XCTAssertFalse(summary.contains("invalid_request_error"))
    }

    func test_failureSummary_unmappedStatusWithAnUnreadableBodyFallsBackToTheStatus() {
        let summary = AgentRunner.failureSummary(for: GPTError.http(status: 418, body: "<html>nope</html>"))

        XCTAssertEqual(summary, String(format: Strings.text(.agentAPIErrorFormat), "418"))
        XCTAssertFalse(summary.contains("html"))
    }

    /// What OpenAI answers a bad key with, key prefix and all.
    private static let unauthorizedBody = """
    {
      "error": {
        "message": "Incorrect API key provided: cp_jUkL5***KGGb. You can find your API key at https://platform.openai.com/account/api-keys.",
        "type": "invalid_request_error",
        "param": null,
        "code": "invalid_api_key"
      }
    }
    """

    func test_pathArgument_extractsAPresentNonEmptyPath() {
        let arguments = JSONValue.object(["path": .string("src/main.swift")])

        XCTAssertEqual(AgentRunner.pathArgument(from: arguments), "src/main.swift")
    }

    func test_pathArgument_nilForMissingKey() {
        XCTAssertNil(AgentRunner.pathArgument(from: .object([:])))
    }

    func test_pathArgument_nilForEmptyString() {
        XCTAssertNil(AgentRunner.pathArgument(from: .object(["path": .string("")])))
    }

    func test_pathArgument_nilForWrongType() {
        XCTAssertNil(AgentRunner.pathArgument(from: .object(["path": .number(1)])))
    }

    func test_pathArgument_nilWhenArgumentsAreNotAnObject() {
        XCTAssertNil(AgentRunner.pathArgument(from: .string("not an object")))
    }

    // MARK: - invokeTool (the entry the coding CLI's MCP server lands on)

    private func makeRunner(
        client: any AgentLLMClient = RecordingLLMClient(),
        dispatched: UncheckedBox<[BridgeMessage]>? = nil,
        approve: @escaping AgentApprovalGate = { _, _ in false },
        emit: @escaping AgentEventSink = { _, _ in },
        delegateReadFile: AgentFileDelegation? = nil
    ) -> AgentRunner {
        AgentRunner(
            client: client,
            dispatcher: PetToolDispatcher(send: { message in
                dispatched?.value.append(message)
                // False on purpose: the tool answers immediately with
                // pet_app_disconnected instead of waiting out a reply nobody
                // is going to send.
                return false
            }),
            approve: approve,
            emit: emit,
            delegateReadFile: delegateReadFile
        )
    }

    /// The pet reacts to tool_call/tool_result, and the transcript is built
    /// from them. A call the CLI made through MCP has to produce the same pair
    /// as one the model made directly, or the pet stands still while work
    /// happens.
    func test_invokeTool_emitsTheSameToolCallAndResultPairAModelsOwnCallDoes() async {
        let events = UncheckedBox([BridgeEvent]())
        let runner = makeRunner(emit: { event, _ in events.value.append(event) })

        _ = await runner.invokeTool(
            name: "launch_app",
            arguments: .object(["app_name": .string("Weather")]),
            callId: "c-1"
        )

        XCTAssertTrue(events.value.contains(
            .toolCall(id: "c-1", tool: "launch_app", args: .object(["app_name": .string("Weather")]), detail: nil)
        ))
        XCTAssertTrue(events.value.contains { event in
            if case .toolResult(let id, _, _, _, _) = event { return id == "c-1" }
            return false
        })
    }

    /// The failure mode this must never have: an approval-requiring tool that
    /// runs without the user ever being asked.
    func test_invokeTool_asksBeforeRunningAnApprovalRequiringTool() async {
        let events = UncheckedBox([BridgeEvent]())
        let asked = UncheckedBox([String]())
        let dispatched = UncheckedBox([BridgeMessage]())
        let runner = makeRunner(
            dispatched: dispatched,
            approve: { summary, _ in
                asked.value.append(summary)
                return true
            },
            emit: { event, _ in events.value.append(event) }
        )

        _ = await runner.invokeTool(
            name: "run_shell",
            arguments: .object(["command": .string("ls")]),
            callId: "c-2"
        )

        XCTAssertEqual(asked.value.count, 1)
        XCTAssertTrue(asked.value.first?.hasPrefix(String(format: Strings.text(.approvalRunShellFormat), "")) == true)
        XCTAssertTrue(events.value.contains { event in
            if case .awaitApproval(_, let approvalId) = event { return approvalId == "c-2" }
            return false
        }, "the user has to see the normal in-chat approval prompt")
        XCTAssertEqual(dispatched.value.count, 1, "approved means it actually runs")
    }

    /// And the other one: silently denied, so the user sees nothing and the
    /// model is told it was refused. The refusal has to be the user's, and it
    /// has to reach the caller as denied_by_user.
    func test_invokeTool_refusedApprovalNeverDispatchesAndSaysWhy() async {
        let dispatched = UncheckedBox([BridgeMessage]())
        let runner = makeRunner(dispatched: dispatched, approve: { _, _ in false })

        let result = await runner.invokeTool(
            name: "run_shell",
            arguments: .object(["command": .string("rm -rf /")]),
            callId: "c-3"
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "denied_by_user")
        XCTAssertTrue(dispatched.value.isEmpty, "a refused tool must never reach the socket")
    }

    func test_invokeTool_dispatchesAPetAppToolOverTheSocket() async {
        let dispatched = UncheckedBox([BridgeMessage]())
        let runner = makeRunner(dispatched: dispatched)

        _ = await runner.invokeTool(name: "list_running_apps", arguments: .object([:]))

        XCTAssertEqual(dispatched.value.count, 1)
        if case .toolDispatch(let dispatch)? = dispatched.value.first {
            XCTAssertEqual(dispatch.tool, "list_running_apps")
        } else {
            XCTFail("a pet-app tool has to go out as tool_dispatch")
        }
    }

    /// The delegated route, not the socket: read_file is answered by the
    /// client's own editor pane.
    func test_invokeTool_takesTheDelegatedRouteForReadFile() async {
        let dispatched = UncheckedBox([BridgeMessage]())
        let read = UncheckedBox([String]())
        let runner = makeRunner(
            dispatched: dispatched,
            delegateReadFile: { path in
                read.value.append(path)
                return DispatchedToolResult(ok: true, data: .string("contents"), error: nil, detail: nil)
            }
        )

        let result = await runner.invokeTool(
            name: "read_file",
            arguments: .object(["path": .string("src/main.swift")])
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(read.value, ["src/main.swift"])
        XCTAssertTrue(dispatched.value.isEmpty, "a delegated tool must not cross the socket")
    }

    /// The CLI keeps its own conversation inside the CLI. Splicing its tool
    /// results into this one would leave a tool entry with no assistant call
    /// in front of it, which the other two providers reject outright.
    func test_invokeTool_neverAppendsToTheRunnersOwnConversation() async {
        let client = RecordingLLMClient()
        let runner = makeRunner(client: client, approve: { _, _ in true })

        _ = await runner.invokeTool(name: "list_running_apps", arguments: .object([:]))
        await runner.run(command: "안녕")

        let toolEntries = client.lastMessages.filter { message in
            if case .tool = message { return true }
            return false
        }
        XCTAssertTrue(toolEntries.isEmpty)
    }
    // MARK: - A run keeps the chat it was started for

    /// AgentHost sets `sessionId` and then starts a Task; those are two steps,
    /// and a second command submitted in between moves the property before the
    /// first run's body has read it. The run then wrote its whole answer --
    /// the user's message, the model's reply, agent_done -- into the chat that
    /// replaced it. Naming the session at the call closes that window.
    func test_aRunAddressesTheChatItWasStartedFor_evenIfTheRunnerMovesFirst() async {
        let events = EventLog()
        let runner = AgentRunner(
            client: RecordingLLMClient(),
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in false },
            emit: { event, session in events.append(event, session) }
        )
        runner.sessionId = "chat-1"

        let run = Task { await runner.run(command: "첫 질문", session: "chat-1") }
        // What the host's next submission does before this run's body runs.
        runner.sessionId = "chat-2"
        await run.value

        XCTAssertEqual(Set(events.sessions), ["chat-1"])
    }

    /// The same window for the workspace line: a run that read it late would
    /// tell the model it is in the project the *next* command chose.
    func test_aRunAnnouncesTheWorkspaceItWasStartedIn() async {
        let (runner, client) = makeRecordingRunner()
        runner.workspaceContext = AgentRunner.WorkspaceContext(name: "첫", projectPath: "/tmp/first")

        let started = AgentRunner.WorkspaceContext(name: "첫", projectPath: "/tmp/first")
        let run = Task { await runner.run(command: "여기 뭐 있어?", session: "chat-1", workspace: started) }
        runner.workspaceContext = AgentRunner.WorkspaceContext(name: "둘", projectPath: "/tmp/second")
        await run.value

        XCTAssertTrue(client.lastSystemTexts.contains { $0.contains("/tmp/first") })
        XCTAssertFalse(client.lastSystemTexts.contains { $0.contains("/tmp/second") })
    }

    /// Collects (event, session) pairs from whichever executor the run
    /// resumes on.
    private final class EventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var pairs: [(BridgeEvent, String)] = []

        func append(_ event: BridgeEvent, _ session: String) {
            lock.lock()
            defer { lock.unlock() }
            pairs.append((event, session))
        }

        var sessions: [String] {
            lock.lock()
            defer { lock.unlock() }
            return pairs.map(\.1)
        }
    }
}
