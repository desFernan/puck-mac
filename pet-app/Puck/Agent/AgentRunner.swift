//
//  AgentRunner.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The tool-use loop -- plan/04_ai-module.md section 3.2, in Swift.
//
//  "날씨 앱 켜줘" reaches here as `run`, the model answers with launch_app,
//  PetToolDispatcher puts that on bridge.sock, pet-app launches it and walks
//  the pet over.
//
//  ## Where this deviates from the plan, and why
//
//  plan/04_ai-module.md puts this loop in `ai-module` -- a TypeScript module
//  on the Claude API, injected into `workspace` (Electron). Three things
//  about that are no longer true on the ground: workspace and ai-module are
//  both empty repos, the chat client became a Swift app, and the key the team
//  has is OpenAI's. Rewriting the loop in TS later is a real possibility, so
//  everything that *is* contract is kept where the plan put it -- the tool
//  registry in protocol, the wire format in BridgeMessages, approval before
//  dispatch -- and only the loop itself is local. What a TS port would have
//  to redo is this file and GPTClient, not the contract around them.
//
//  ## Events are the output, not a side effect
//
//  Every step emits a BridgeEvent. The client applies them to the chat
//  timeline and broadcasts them to pet-app, which is what makes the pet think,
//  point, and celebrate -- ChatSession.apply and EventRouter.reaction already
//  handle the full set, so producing them is all the integration there is.
//

import Foundation

/// Emitted for every step of a run. The host decides what to do with them
/// (render, broadcast, log) -- the runner never touches UI or the socket.
///
/// - Parameter sessionId: the chat the event belongs to, named rather than
///   left for the host to guess. The host used to address every event to
///   whichever run started most recently, which is wrong whenever two runs
///   overlap -- and they do, because cancelling a turn only asks it to stop.
///   A superseded turn's last events landed in the chat that replaced it, and
///   the turn's own chat, never told its run had ended, held its spinner
///   forever.
typealias AgentEventSink = (_ event: BridgeEvent, _ sessionId: String) -> Void

/// Asks the user to approve a dangerous tool. Returns whether to proceed.
typealias AgentApprovalGate = (_ summary: String, _ approvalId: String) async -> Bool

/// Hands a coding task to workspace's agent and returns what it reported.
/// See CodeEditorDelegate for why this is a closure and not another entry in
/// PetToolDispatcher.
typealias AgentCodeEditorDelegation = (_ task: String) async -> DispatchedToolResult

/// Reads or opens a file in the client window's native editor pane. Not
/// dispatched via PetToolDispatcher either, for the same reason as
/// code_editor: both need the current run's workspaceId to resolve a
/// relative path against a specific project root, which a tool_dispatch's
/// bare `{path}` argument has no room for, and which pet-app's
/// process-wide ToolExecutor (Puck.app, not this app) has no way to reach
/// PuckClient's own editor-pane state to answer anyway.
typealias AgentFileDelegation = (_ path: String) async -> DispatchedToolResult

/// One stop of a code tour: highlight a line range in the editor pane and
/// send the pet to stand in front of it. Answers only once the pet has
/// arrived, which is what keeps a tour's stops in order -- the model cannot
/// start the next one until this one has actually happened.
typealias AgentCodeTourStop = (
    _ path: String, _ startLine: Int, _ endLine: Int, _ caption: String
) async -> DispatchedToolResult

/// Lists the active workspace's project files, optionally only those whose
/// path contains a given string. Which project is a property of the run, not
/// something the model chooses -- but *which files* has to be, or the answer
/// is a truncated list of whatever sorts first.
typealias AgentFileListing = (_ contains: String?) async -> DispatchedToolResult

/// Branches the casual conversation into its own task session; everything the
/// run emits after this is addressed to the new one.
///
/// - Returns: the id of the session it opened. The runner needs it to move the
///   conversation across: a task session is a continuation, and an agent that
///   arrives in it having forgotten what it was asked to do is worse than one
///   that never branched.
typealias AgentTaskSessionOpener = (_ title: String, _ brief: String) -> String

final class AgentRunner {
    private let client: any AgentLLMClient
    private let dispatcher: PetToolDispatcher
    private let approve: AgentApprovalGate
    /// Read per tool call rather than captured once: `/permissions` writes the
    /// setting mid-conversation, and the answer that matters is the one in
    /// force when the tool is about to run -- the same rule
    /// CodingAgentCLIClient.resolvePermission follows for the other gate.
    private let permissions: () -> AgentPermissionMode
    private let sink: AgentEventSink

    /// Every event names the chat it belongs to. `key` is the run's own
    /// session, captured when the run started -- never `sessionId`, which by
    /// the time an event is emitted may already belong to a newer run.
    private func emit(_ event: BridgeEvent, to key: String) {
        sink(event, key)
    }
    /// nil in the standalone case (no workspace to delegate to), and then
    /// code_editor is not offered to the model at all -- the same rule the
    /// pet-app-only tool list was already built on.
    private let delegateCodeEditor: AgentCodeEditorDelegation?
    /// Offered only alongside code_editor: with nowhere to delegate to, there
    /// is no long-running work to move out of the casual session, and a task
    /// session that only ever holds chat is just a confusing empty room.
    private let openTaskSession: AgentTaskSessionOpener?
    /// nil only in the standalone case (same rule as delegateCodeEditor) --
    /// unlike code_editor, these two don't depend on a workspace/ACP process
    /// being connected, only on the active workspace having a project bound.
    private let delegateReadFile: AgentFileDelegation?
    private let delegateOpenInEditor: AgentFileDelegation?
    /// Offered whenever read_file is: both answer from the same project root,
    /// and a model that can read a file but not find one is the situation this
    /// was added to fix.
    private let delegateListFiles: AgentFileListing?
    /// Offered on the same terms as read_file: a tour is only possible where
    /// there is a project bound and an editor pane to show it in.
    private let delegateShowCode: AgentCodeTourStop?
    /// protocol section 7's `src: "agent"` lines. Without them a failed call
    /// is an opaque uuid in pet-app's log with no tool name and no reason.
    private let logger: ToolExecutionLogging?
    private let toolSpecs: [GPTToolSpec]

    /// Conversation memory, one stack per chat. Per plan/04_ai-module.md 3.4
    /// this is in-memory only -- persistence is explicitly後순위.
    ///
    /// Was a single stack shared by every chat this app ever opened, because
    /// there is one AgentRunner for the whole process and nothing ever cleared
    /// it. A new chat therefore started with the previous one's conversation
    /// already in it: asked about a project, the model repeated an earlier
    /// chat's "No project folder is bound to it, so there are no files to read
    /// or list" -- a line that had been true of a different workspace.
    /// What the model has been told, per chat -- see AgentConversations.
    private let conversations = AgentConversations(systemPrompt: AgentRunner.systemPrompt)

    /// Guards every stored property below. `run` is async and this is a plain
    /// class, so its body resumes on whatever executor the API call came back
    /// on -- and runs genuinely overlap, because AgentRunHandle only *requests*
    /// cancellation and the superseded turn keeps going until it next checks
    /// `Task.isCancelled`. Two turns writing a Swift Dictionary at once is
    /// memory corruption, not a lost update. A serial queue rather than an
    /// NSLock because NSLock is unavailable from async contexts (an error in
    /// the Swift 6 language mode); the same choice BridgeServer and
    /// ToolExecutor already made.
    private let stateQueue = DispatchQueue(label: "Puck.AgentRunner.state")

    /// Which chat the next `run` belongs to. Set by the host before each run,
    /// like `workspaceContext`; the default keeps every existing call site and
    /// test working as a single conversation.
    var sessionId: String {
        get { stateQueue.sync { storedSessionId } }
        set { stateQueue.sync { storedSessionId = newValue } }
    }
    private var storedSessionId = "default"

    /// A chat's stack, seeded on first read.
    ///
    /// Every write below names its chat rather than reading `sessionId` at the
    /// time of the write. `sessionId` belongs to whichever run started most
    /// recently, and a run that is being replaced keeps executing until it
    /// notices -- reading it late is how a dying run's last answer would land
    /// in the chat that replaced it.
    private func conversation(_ key: String) -> [GPTMessage] {
        conversations.messages(in: key)
    }

    private func append(_ message: GPTMessage, to key: String) {
        conversations.append(message, to: key)
    }

    /// Gives `to` the conversation `from` has, for the one case where a new
    /// chat is a continuation rather than a beginning: the agent branching its
    /// work into a task session (openTaskSession).
    func carryConversation(from sourceSessionId: String, to sessionId: String) {
        conversations.carry(from: sourceSessionId, to: sessionId)
    }

    /// Drops the oldest turns once a chat is over the cap -- see
    /// AgentConversations.trim for what is kept and why.
    private func trimConversation(_ key: String) {
        conversations.trim(key)
    }

    /// Drops a deleted chat's conversation. The user threw it away; the model
    /// should not still be holding it.
    func forgetSession(_ sessionId: String) {
        conversations.forget(sessionId)
    }

    /// A model that keeps calling tools without concluding would otherwise
    /// loop until the API bill says stop. Ten is well past any sequence the
    /// case table describes (the longest is launch → find → point).
    private static let maxTurns = 10

    init(
        client: any AgentLLMClient,
        dispatcher: PetToolDispatcher,
        approve: @escaping AgentApprovalGate,
        permissions: @escaping () -> AgentPermissionMode = { AgentConfiguration.permissionMode() },
        emit: @escaping AgentEventSink,
        delegateCodeEditor: AgentCodeEditorDelegation? = nil,
        openTaskSession: AgentTaskSessionOpener? = nil,
        delegateReadFile: AgentFileDelegation? = nil,
        delegateOpenInEditor: AgentFileDelegation? = nil,
        delegateListFiles: AgentFileListing? = nil,
        delegateShowCode: AgentCodeTourStop? = nil,
        logger: ToolExecutionLogging? = nil
    ) {
        self.logger = logger
        self.client = client
        self.dispatcher = dispatcher
        self.approve = approve
        self.permissions = permissions
        self.sink = emit
        self.delegateCodeEditor = delegateCodeEditor
        self.openTaskSession = delegateCodeEditor == nil ? nil : openTaskSession
        self.delegateReadFile = delegateReadFile
        self.delegateOpenInEditor = delegateOpenInEditor
        self.delegateListFiles = delegateListFiles
        self.delegateShowCode = delegateShowCode
        toolSpecs = Self.petToolSpecs
            + (delegateCodeEditor == nil ? [] : [Self.codeEditorSpec])
            + (self.openTaskSession == nil ? [] : [Self.openTaskSessionSpec])
            + (delegateReadFile == nil ? [] : [Self.readFileSpec])
            + (delegateOpenInEditor == nil ? [] : [Self.openInEditorSpec])
            + (delegateListFiles == nil ? [] : [Self.listFilesSpec])
            + (delegateShowCode == nil ? [] : [Self.showCodeSpec])
    }

    /// Forgets every chat. Nothing in the app calls this -- chats are kept
    /// apart by `sessionId` and dropped by `forgetSession` -- but it stays as
    /// the way to hand the runner a clean slate.
    func reset() {
        conversations.forgetEverything()
    }

    /// Describes the workspace this run belongs to. Injected per run rather
    /// than baked into the system prompt: the user can switch workspaces
    /// between turns, and a prompt built at init would keep naming the first
    /// one forever.
    ///
    /// Without it the model had no idea a project was open at all. Asked to
    /// analyze "this directory" it reached for get_frontmost_window -- the
    /// only tool whose name sounded spatial -- got a window title back, and
    /// correctly concluded it had nothing to answer with.
    struct WorkspaceContext: Equatable {
        let name: String
        /// nil for a chat-only workspace.
        let projectPath: String?

        var promptLine: String {
            guard let projectPath else {
                return "Current workspace: \(name). No project folder is bound to it, so the file tools have nothing to read. "
                    + "If the user asks about code or files, say that this workspace has no project folder, and that they can switch "
                    + "to one that has a project in the sidebar or make one with "
                    + "\(Strings.text(.chatNewWorkspace)) -- never ask them to paste files to you."
            }
            return "Current workspace: \(name), bound to the project at \(projectPath). "
                + "\"this project\" / \"this directory\" / \"여기\" mean that folder. "
                + "Paths you pass to file tools are relative to it."
        }
    }

    /// Set by the host before each run. Kept as a property rather than a `run`
    /// parameter so the many existing call sites and tests stay untouched.
    var workspaceContext: WorkspaceContext? {
        get { stateQueue.sync { storedWorkspaceContext } }
        set { stateQueue.sync { storedWorkspaceContext = newValue } }
    }
    private var storedWorkspaceContext: WorkspaceContext?

    private func markAnnounced(_ context: WorkspaceContext, to key: String) -> Bool {
        conversations.markAnnounced(context, to: key)
    }

    /// What the transcript ends with when the user presses Stop. Not an error
    /// string: a stop the user asked for is an outcome, not a failure, so it
    /// never goes through the `catch` path that reports a reason.
    static var cancelledSummary: String { Strings.text(.agentCancelled) }

    /// - Parameters:
    ///   - session: the chat this run belongs to, and every event it emits is
    ///     addressed to. Passed by the host rather than read from `sessionId`
    ///     here: the host sets the property and then *starts a Task*, so a
    ///     second command submitted before this body first runs would have
    ///     already moved the property, and this run would write its whole
    ///     answer into the newer run's chat. Defaults to the property for the
    ///     call sites -- the tests, mostly -- that only ever have one run.
    ///   - workspace: which project this run's tools answer from, captured at
    ///     the same moment and for the same reason.
    func run(command: String, session: String? = nil, workspace: WorkspaceContext? = nil) async {
        // Captured once. Everything this run writes goes here even if a newer
        // run has already pointed `sessionId` somewhere else.
        var key = session ?? sessionId
        let context = workspace ?? workspaceContext
        if let context, markAnnounced(context, to: key) {
            append(.system(context.promptLine), to: key)
        }
        append(.user(command), to: key)
        trimConversation(key)
        emit(.agentThinking, to: key)

        for _ in 0..<Self.maxTurns {
            if Task.isCancelled {
                emitCancelled(from: key)
                return
            }
            let turn: GPTTurn
            do {
                // `key`, not the runner's current session: this turn belongs
                // to the chat it started in even after a newer one has moved
                // that property on.
                turn = try await client.send(messages: conversation(key), tools: toolSpecs, sessionId: key)
            } catch {
                // Checked before the error is described: a cancelled
                // `URLSession.data(for:)` surfaces as URLError(.cancelled)
                // rather than CancellationError, and reporting either one as
                // "요청이 취소되었습니다" would make the 중지 button look like a
                // network failure.
                if Task.isCancelled {
                    emitCancelled(from: key)
                    return
                }
                // The raw description -- which for GPTError.http carries the
                // provider's whole response body -- goes to the log, and only
                // there. Once. `agent_done(ok: false)` is the row that already
                // renders a failure (DoneRow's ✗), so emitting a text_chunk
                // too put the identical text in an assistant bubble directly
                // above it.
                AppLogger.shared.log(.error, "agent run failed: \(Self.rawFailureDescription(for: error))")
                emit(.agentDone(ok: false, summary: Self.failureSummary(for: error)), to: key)
                return
            }

            // Re-checked here, not only at the top of the loop: `send` is where
            // a run spends nearly all its time, so a replacement almost always
            // arrives while one is in flight. Without this the answer to a
            // command the user has already moved on from is emitted anyway.
            if Task.isCancelled {
                emitCancelled(from: key)
                return
            }

            if let text = turn.text, !text.isEmpty {
                emit(.textChunk(text: text), to: key)
            }

            guard !turn.toolCalls.isEmpty else {
                // No tools asked for: the model is answering, so the run ends
                // here. Its own text is the summary.
                append(.assistant(text: turn.text, toolCalls: [], reasoning: turn.reasoning), to: key)
                emit(.agentDone(ok: true, summary: turn.text ?? ""), to: key)
                return
            }

            append(.assistant(text: turn.text, toolCalls: turn.toolCalls, reasoning: turn.reasoning), to: key)
            for (index, call) in turn.toolCalls.enumerated() {
                // Between calls, not only between turns: a turn can ask for
                // several tools, and a stop pressed during the first one
                // should not still run the rest.
                if Task.isCancelled {
                    // Every call that will not run still needs an answer in
                    // the conversation. Both providers reject a stack whose
                    // last assistant message asks for tools nothing replied
                    // to -- OpenAI with "must be followed by tool messages",
                    // Anthropic with "tool_use ids found without tool_result"
                    // -- and nothing repairs it afterwards, so a chat stopped
                    // mid-tool used to reject every message sent in it from
                    // then on, forever.
                    answerUnrunCalls(turn.toolCalls[index...], in: key)
                    emitCancelled(from: key)
                    return
                }
                if let opened = await perform(call, in: key) {
                    // The rest of this turn belongs to the chat that was just
                    // opened, so its answers land there. The chat it branched
                    // out of keeps the assistant message that asked for them
                    // -- and that chat is deliberately kept, since the casual
                    // session is what this tool is documented to branch out of
                    // -- so it needs an answer for each of the calls it will
                    // never see run. Without them it holds a tool_use with no
                    // result, which both providers reject for the whole
                    // conversation rather than for that turn: every message
                    // typed in it afterwards fails, for good.
                    answerUnrunCalls(turn.toolCalls[(index + 1)...], in: key, content: Self.movedElsewhereAnswer)
                    key = opened
                }
            }
        }

        let hitCeiling = String(format: Strings.text(.agentToolCeilingFormat), "\(Self.maxTurns)")
        // Only the done event. A failed run's summary is what DoneRow renders,
        // so sending the same words as a text chunk first prints them twice --
        // the same mistake the reply echo was.
        emit(.agentDone(ok: false, summary: hitCeiling), to: key)
    }

    /// Answers tool calls that will never run, so the conversation stays
    /// something a provider will accept.
    ///
    /// A stack whose last assistant message asks for tools is only valid once
    /// every one of those calls has a reply. Cancelling in the middle leaves
    /// the rest unanswered, and neither provider tolerates that -- nor does
    /// anything here repair it later, since `trimConversation` only drops
    /// leading tool messages and `forgetSession` runs when a chat is deleted.
    private func answerUnrunCalls(
        _ calls: ArraySlice<GPTToolCall>,
        in key: String,
        content: String = "error: cancelled"
    ) {
        for call in calls {
            append(.tool(callId: call.id, content: content), to: key)
        }
    }

    /// What the chat a run branched out of is told about the calls that ran
    /// somewhere else. Not an error: nothing failed, the work simply moved,
    /// and this chat's model should say so if it is asked rather than
    /// apologise for a tool that did not break.
    private static let movedElsewhereAnswer = "ok -- 이어지는 작업은 새 작업 세션에서 처리했어요."

    /// The one exit a cancelled run takes. Emits `agent_done` like every other
    /// ending does, so the session leaves its running state instead of holding
    /// a spinner forever; `ok: false` because the turn did not finish what it
    /// was asked, and EventRouter deliberately gives a failed run no reaction
    /// (a "task_success" jump for a stop would be worse than none).
    /// Addressed to `key`, the run's own chat. This used to be silent unless
    /// the run was still the current one, because events went to whatever chat
    /// was active when they were emitted and a superseded run would announce
    /// its cancellation in a conversation the user never stopped. The cost was that
    /// the run's real chat never heard its run had ended and held a spinner
    /// forever; naming the session fixes both.
    private func emitCancelled(from key: String) {
        emit(.agentDone(ok: false, summary: Self.cancelledSummary), to: key)
    }

    /// - Returns: the task session this call opened, if it opened one -- the
    ///   rest of the run belongs to it.
    @discardableResult
    private func perform(_ call: GPTToolCall, in key: String) async -> String? {
        let arguments = JSONValue.decodeObject(from: call.argumentsJSON)

        // The one tool that never crosses the socket and never shows up as a
        // tool call in the transcript: it only moves where the rest of this
        // run is addressed (01_protocol.md section 4, 04_ai-module.md 3.7 --
        // "결과는 onSessionCreated 콜백 → session_create 이벤트로만 통지").
        // Emitting tool_call/tool_result for it would put plumbing in the
        // chat and make the pet react to a session switch as if it were work.
        if call.name == Self.openTaskSessionToolName, let openTaskSession {
            guard
                case .object(let args) = arguments,
                case .string(let title)? = args["title"], !title.isEmpty
            else {
                append(.tool(callId: call.id, content: "error: execution_failed -- title이 비어 있어요."), to: key)
                return nil
            }
            let brief = if case .string(let value)? = args["brief"] { value } else { "" }
            let opened = openTaskSession(title, brief)
            // The branch carries the conversation with it, so the agent lands
            // in the session it just opened still knowing the task.
            carryConversation(from: key, to: opened)
            let answer = "ok -- 새 작업 세션 \"\(title)\"으로 옮겼습니다."
            append(.tool(callId: call.id, content: answer), to: opened)
            // And to the chat it branched from, which is not always thrown
            // away: the casual session -- the one this tool is documented to
            // branch out of -- is deliberately kept by the window. Left with
            // the request and no answer, it would reject everything the user
            // typed in it afterwards.
            if key != opened { append(.tool(callId: call.id, content: answer), to: key) }
            return opened
        }

        let result = await invokeTool(
            name: call.name,
            arguments: arguments,
            argumentsText: call.argumentsJSON,
            callId: call.id,
            sessionId: key
        )
        append(
            .tool(
                callId: call.id,
                content: Self.toolResultText(ok: result.ok, data: result.data, error: result.error, detail: result.detail)
            ),
            to: key
        )
        return nil
    }

    /// Runs one tool the way a turn's own tool call is run: the approval gate,
    /// the three execution routes, and the tool_call/tool_result events the
    /// transcript and the pet react to. Returns the raw result and never
    /// touches `messages`.
    ///
    /// Internal, and the reason `perform` is now a thin wrapper: the coding
    /// CLI calls Puck's tools out of band, over the MCP server it is handed
    /// (PuckMCPServer), and its calls have to behave identically to the
    /// model's own -- same approval, same routes, same events. It keeps its
    /// own conversation inside the CLI, so nothing here may append to this
    /// one's `messages`; `perform` does that for the calls that belong to it.
    ///
    /// `argumentsText` is what the approval prompt shows. The model's own
    /// call passes the JSON it emitted verbatim; a caller that has only a
    /// parsed value can leave it out and get the re-encoded form.
    /// - Parameter sessionId: the chat to address this call's events to.
    ///   Defaults to the runner's current one, which is what an out-of-band
    ///   MCP call wants: it has no run of its own, it belongs to whichever
    ///   turn handed the CLI the server.
    func invokeTool(
        name: String,
        arguments: JSONValue,
        argumentsText: String? = nil,
        callId: String = UUID().uuidString,
        sessionId: String? = nil
    ) async -> DispatchedToolResult {
        let key = sessionId ?? self.sessionId
        // `perform` handles this one itself and never reaches here, because
        // opening a session moves the rest of the run into it: it carries the
        // conversation across and returns the new key. An out-of-band caller
        // has no run to move and no conversation to carry, so answering it
        // here would open a session the caller then talks past. MCPToolCatalog
        // withholds it for the same reason; this is the enforcement.
        if name == Self.openTaskSessionToolName {
            return DispatchedToolResult(
                ok: false,
                data: nil,
                error: "unknown_tool",
                detail: Strings.text(.toolTaskSessionUnavailable)
            )
        }

        emit(.toolCall(id: callId, tool: name, args: arguments, detail: nil), to: key)
        logger?.log(.agentToolCall(id: callId, tool: name, args: arguments))

        // `.auto` is the user having said "stop asking me" (AgentPermissionMode):
        // no prompt is emitted at all, rather than one emitted and answered
        // for them -- a banner that appears and resolves itself is a banner
        // the chat would leave sitting there unanswerable.
        if ToolRegistry.tool(named: name)?.requiresApproval == true, !permissions().approvesWithoutAsking {
            let summary = Self.approvalSummary(
                tool: name,
                arguments: argumentsText ?? arguments.jsonText ?? ""
            )
            emit(.awaitApproval(summary: summary, approvalId: callId), to: key)
            guard await approve(summary, callId) else {
                // Refusal is the model's to hear about, not an error to abort
                // on -- it should say so and offer something else. The code
                // never crosses the socket (docs/socket.md).
                let denied = DispatchedToolResult(ok: false, data: nil, error: "denied_by_user", detail: nil)
                reportEvents(callId: callId, result: denied, to: key)
                return denied            }
        }

        let result = await route(name: name, arguments: arguments)
        reportEvents(callId: callId, result: result, to: key)
        return result
    }

    /// Which of the three execution paths a tool takes: a delegate the host
    /// supplied, or PetToolDispatcher's tool_dispatch over bridge.sock.
    private func route(name: String, arguments: JSONValue) async -> DispatchedToolResult {
        if name == Self.codeEditorToolName, let delegateCodeEditor {
            // workspace's tool, so it never goes to PetToolDispatcher (which
            // would put a tool_dispatch pet-app can't execute on the socket).
            // project_path is deliberately dropped: workspace resolves the
            // path from the session's own workspace record and ignores what
            // the model sends, so passing it on would only invite the model
            // to think it decides.
            guard case .object(let args) = arguments, case .string(let task)? = args["task"], !task.isEmpty else {
                return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: Strings.text(.toolTaskIsEmpty))            }
            return await delegateCodeEditor(task)
        }
        if name == Self.readFileToolName, let delegateReadFile {
            guard let path = Self.pathArgument(from: arguments) else {
                return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: Strings.text(.toolPathIsEmpty))            }
            return await delegateReadFile(path)
        }
        if name == Self.openInEditorToolName, let delegateOpenInEditor {
            guard let path = Self.pathArgument(from: arguments) else {
                return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: Strings.text(.toolPathIsEmpty))            }
            return await delegateOpenInEditor(path)
        }
        if name == Self.showCodeToolName, let delegateShowCode {
            guard
                case .object(let args) = arguments,
                let path = Self.pathArgument(from: arguments),
                case .number(let start)? = args["start_line"],
                case .number(let end)? = args["end_line"],
                case .string(let caption)? = args["caption"]
            else {
                return DispatchedToolResult(
                    ok: false, data: nil, error: "execution_failed",
                    detail: Strings.text(.toolShowCodeNeedsEverything)
                )
            }
            return await delegateShowCode(path, Int(start), Int(end), caption)
        }
        if name == Self.listFilesToolName, let delegateListFiles {
            // Which project is a property of the run, so the only argument is
            // the optional filter, and a malformed one is simply no filter.
            guard case .object(let args) = arguments, case .string(let contains)? = args["contains"] else {
                return await delegateListFiles(nil)
            }
            return await delegateListFiles(contains)
        }
        return await dispatcher.execute(tool: name, arguments: arguments)
    }

    /// The UI and the log halves of a tool result -- everything `report` does
    /// except appending to this conversation, which a call made through the
    /// MCP server has no business doing.
    private func reportEvents(callId: String, result: DispatchedToolResult, to key: String) {
        // error is the model-facing vocabulary (may be "denied_by_user", which
        // never crosses the socket -- see ToolErrorCode's doc comment), so the
        // wire event only carries it when it's actually one of the closed
        // protocol codes.
        emit(.toolResult(
            id: callId,
            ok: result.ok,
            data: result.data,
            error: result.error.flatMap(ToolErrorCode.init(rawValue:)),
            detail: result.detail
        ), to: key)
        // detail rides along in the error field when there is one: the code
        // alone ("execution_failed") is never enough to act on, and this line
        // is the only place the reason survives after the chat scrolls away.
        let reason = [result.error, result.detail].compactMap { $0 }.joined(separator: " -- ")
        logger?.log(.agentToolResult(id: callId, ok: result.ok, error: reason.isEmpty ? nil : reason))    }

    /// What the model actually reads back. Errors keep their protocol code so
    /// the model can distinguish "not connected" from "you asked for a tool
    /// that doesn't exist" and say something useful about it
    /// (plan/04_ai-module.md 3.2).
    static func toolResultText(ok: Bool, data: JSONValue?, error: String?, detail: String?) -> String {
        if ok {
            guard let data, let encoded = data.jsonText else { return "ok" }
            return encoded
        }
        return ["error: \(error ?? "execution_failed")", detail].compactMap { $0 }.joined(separator: " -- ")
    }

    private static func approvalSummary(tool: String, arguments: String) -> String {
        switch tool {
        case "run_shell": return String(format: Strings.text(.approvalRunShellFormat), arguments)
        case "run_applescript": return String(format: Strings.text(.approvalRunAppleScriptFormat), arguments)
        case "click_element": return String(format: Strings.text(.approvalClickElementFormat), arguments)
        default: return String(format: Strings.text(.approvalRunToolFormat), tool, arguments)
        }
    }

    /// Shared by read_file/open_in_editor -- both take just {path: string}.
    /// Internal, not private: directly unit-tested (see AgentRunnerTests).
    static func pathArgument(from arguments: JSONValue) -> String? {
        guard case .object(let args) = arguments, case .string(let path)? = args["path"], !path.isEmpty else {
            return nil
        }
        return path
    }
}
