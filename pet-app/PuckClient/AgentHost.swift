//
//  AgentHost.swift
//  PuckClient
//
//  owner: 박해영 (Haeyoung Park)
//  Wires the agent loop to this app: the chat sends commands in, tool calls
//  go out over bridge.sock, and every step comes back as a BridgeEvent.
//
//  ## Events are broadcast, never applied locally
//
//  A BridgeEvent this app puts on the socket is relayed by pet-app to every
//  gui connection -- including this one, since BridgeServer.relay does not
//  exclude the sender -- while pet-app's own router turns it into the pet's
//  reaction. So broadcasting once makes the pet act *and* the transcript
//  update, through the same path events already took when the plan's
//  workspace process was going to produce them. Applying locally as well
//  would render everything twice.
//

import AppKit

final class AgentHost {
    private let broadcast: (BridgeMessage) -> Bool
    private let dispatcher: PetToolDispatcher
    /// code_editor runs here as of 2026-08-15. It used to be delegated over
    /// user_input to workspace's own agent (CodeEditorDelegate, deleted); now
    /// this app spawns the ACP agent itself, so the tool completes without a
    /// second process being alive.
    private let codeEditorRunner: CodeEditorRunner
    private let resolveProjectPath: (String) -> String?
    /// What to tell the model about the workspace a run belongs to.
    private let describeWorkspace: (String) -> AgentRunner.WorkspaceContext?
    /// read_file/open_in_editor's implementation -- see EditorFileDelegate.
    private let editorFileDelegate: EditorFileDelegate
    /// show_code's implementation. Assigned after `runner`, because it
    /// captures `self` to reach the pane and the point_at dispatcher.
    private var codeTourDelegate: CodeTourDelegate!
    private var runner: AgentRunner!

    /// The approval requests runs are blocked on. Run-scoped -- see
    /// PendingApprovals for why that matters.
    private let pendingApprovals = PendingApprovals()
    /// The workspace each chat this host has run in belongs to. A session id
    /// alone does not say which workspace to address an event to, and reading
    /// the active one is exactly the guess that misfiled a superseded run's
    /// events -- a wrong workspace makes the event unroutable, so the chat
    /// never hears its run ended and holds its spinner.
    private var sessionWorkspaces: [String: String] = [:]
    /// Which run is current. Bumped by `run`, recorded on every approval it
    /// registers. Guarded by `stateQueue`: `run` bumps it from main and
    /// `awaitApproval` reads it from inside the run, on whatever executor.
    private var runGeneration = 0
    /// The code_editor run the 중지 button would cancel, if any.
    private var activeCodeEditorRequestId: String?
    /// The agent turn the 중지 button cancels. Without it the turn outlived
    /// every other thing 중지 stops.
    private let activeRun = AgentRunHandle()
    /// Guards `activeCodeEditorRequestId`. A serial queue rather than an
    /// NSLock because the one writer is an async function (`runCodeEditor`),
    /// and NSLock's lock/unlock are unavailable from async contexts -- a
    /// warning today, an error in the Swift 6 language mode. The same choice
    /// AgentRunner, BridgeServer and ToolExecutor already made.
    private let stateQueue = DispatchQueue(label: "PuckClient.AgentHost.state")

    /// Re-read on every access rather than cached: the key can be typed into
    /// Puck's settings panel while this app is running, and the two are
    /// separate processes -- there is no change notification to subscribe to,
    /// only the file both of them read.
    var configuration: AgentConfiguration { .load() }

    /// Where the events of the current run are addressed. Captured when a run
    /// starts so results land in the session the command came from even if
    /// the user switches session mid-run.
    private var activeWorkspaceId = ClientWindowStore.defaultWorkspaceId
    private var activeSessionId = ClientWindowStore.defaultSessionId
    /// What the user typed for the current run, kept so open_task_session can
    /// carry it into the session it moves the turn to.
    private var activeCommand = ""

    /// Set by AppDelegate: reveal the editor pane on this workspace's file.
    /// Called when the agent opens a file for the user to look at, and for
    /// every file a code_editor run touches: asking to be shown code should
    /// put it on screen, and watching one get written should follow along.
    var onRevealInEditor: ((_ workspaceId: String, _ path: String) -> Void)?
    /// Fired once a run has fully finished, with the chat it belonged to.
    /// Naming a chat needs the agent's answer as well as the question, so it
    /// cannot happen when the message is sent -- this is the first moment both
    /// halves exist.
    var onRunFinished: ((_ workspaceId: String, _ sessionId: String) -> Void)?

    /// Set by AppDelegate: the local side of open_task_session, which has no
    /// socket message behind it (protocol 3.4 can create a session but not
    /// close one).
    var onTaskSessionOpened: ((
        _ workspaceId: String,
        _ sourceSessionId: String,
        _ sessionId: String,
        _ title: String,
        _ userMessage: String
    ) -> Void)?

    init(
        broadcast: @escaping (BridgeMessage) -> Bool,
        resolveProjectPath: @escaping (String) -> String?,
        describeWorkspace: @escaping (String) -> AgentRunner.WorkspaceContext? = { _ in nil }
    ) {
        self.broadcast = broadcast
        self.describeWorkspace = describeWorkspace
        self.dispatcher = PetToolDispatcher(send: broadcast)
        self.resolveProjectPath = resolveProjectPath
        self.editorFileDelegate = EditorFileDelegate(resolveProjectPath: resolveProjectPath)

        // Declared before `runner` so the closures below can capture it; the
        // approval gate and event sink are attached afterwards, once `self`
        // exists to weakly capture.
        var relayEvent: ((BridgeEvent, String) -> Void)?
        var revealInEditor: ((String, String) -> Void)?
        var askPermission: ((AcpPermissionRequest) async -> Bool)?
        self.codeEditorRunner = CodeEditorRunner(
            environment: CodeEditorRunnerEnvironment(
                startAgent: { kind, projectPath in
                    let command = try AcpAgentCommandResolver.command(
                        for: kind,
                        scriptURL: AcpAgentCommandResolver.bundledScriptURL(for: kind),
                        node: AcpAgentCommandResolver.resolveNode(),
                        vendorCLI: AcpAgentCommandResolver.resolveVendorCLI(for: kind)
                    )
                    let process = AcpAgentProcess(
                        command: command,
                        projectPath: projectPath,
                        credentials: AgentConfiguration.load().codingAgentCredentials(for: kind)
                    )
                    try process.start()
                    return process
                },
                credentials: { AgentConfiguration.load().codingAgentCredentials(for: $0) },
                codingAgent: { AgentConfiguration.load().codingAgent }
            ),
            onUpdate: { requestId, workspaceId, update in
                // Follow the agent file by file while it works. The path comes
                // from ACP's own tool_call locations, which is also what makes
                // the pet jump to a new file, so the editor and the pet stay
                // on the same one.
                if let path = AcpEventMapping.editedPath(in: update) {
                    revealInEditor?(workspaceId, path)
                }
                guard let event = AcpEventMapping.event(for: update, callID: requestId) else { return }
                relayEvent?(event, workspaceId)
            },
            resolvePermission: { request in await askPermission?(request) ?? false }
        )
        self.runner = AgentRunner(
            client: makeAgentLLMClient(
                { .load() },
                // Only the CLI provider reads this: its ACP session opens on
                // the workspace's project so a CLI asked about "this file" has
                // one to look at. Resolved per turn, not captured once -- the
                // user switches workspaces between turns.
                workingDirectory: { [weak self] in
                    guard let self else { return CodingAgentCLIClient.projectlessWorkingDirectory() }
                    return self.resolveProjectPath(self.activeWorkspaceId)
                        ?? CodingAgentCLIClient.projectlessWorkingDirectory()
                },
                // Only the CLI provider reads this too: it hands Puck's tools
                // to the CLI as an MCP server and calls back in here for each
                // one, so a tool the CLI invokes takes the same approval gate,
                // the same execution routes and emits the same events as one
                // the model asked for directly. `runner` is assigned by the
                // time any turn can run.
                invokeTool: { [weak self] name, arguments in
                    guard let self else {
                        return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                    }
                    return await self.runner.invokeTool(name: name, arguments: arguments)
                }
            ),
            dispatcher: dispatcher,
            approve: { [weak self] _, approvalId in
                await self?.awaitApproval(id: approvalId) ?? false
            },
            emit: { [weak self] event, sessionId in
                guard let self else { return }
                // Addressed to the run's own chat, which is not necessarily
                // the active one: a superseded turn keeps emitting until it
                // notices, and a run can move itself into a task session.
                _ = self.broadcast(.event(
                    event,
                    workspaceId: self.workspace(of: sessionId),
                    sessionId: sessionId
                ))
            },
            delegateCodeEditor: { [weak self] task in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                return await self.runCodeEditor(task: task)
            },
            openTaskSession: { [weak self] title, brief in
                self?.openTaskSession(title: title, brief: brief) ?? ""
            },
            delegateReadFile: { [weak self] path in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                return await self.editorFileDelegate.readFile(path: path, workspaceId: self.activeWorkspaceId)
            },
            delegateOpenInEditor: { [weak self] path in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                let result = await self.editorFileDelegate.openInEditor(path: path, workspaceId: self.activeWorkspaceId)
                // Opening a tab in a pane nobody can see is not "showing" it.
                if result.ok { self.onRevealInEditor?(self.activeWorkspaceId, path) }
                return result
            },
            delegateListFiles: { [weak self] contains in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                return await self.editorFileDelegate.listFiles(
                    workspaceId: self.activeWorkspaceId,
                    contains: contains
                )
            },
            delegateShowCode: { [weak self] path, startLine, endLine, caption in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                let workspaceId = self.activeWorkspaceId
                let result = await self.codeTourDelegate.showCode(
                    path: path, startLine: startLine, endLine: endLine, workspaceId: workspaceId
                )
                // Said after the stop answers, not before: showCode returns
                // when the pet has arrived, and a bubble raised at dispatch
                // time would have expired while it was still walking.
                if result.ok {
                    _ = self.broadcast(.event(
                        .petSays(text: caption),
                        workspaceId: workspaceId,
                        sessionId: self.activeSessionId
                    ))
                }
                return result
            },
            // Same directory Puck's executor writes to, so `id` joins the
            // agent's tool_call/tool_result with pet-app's exec lines in one
            // file (protocol section 7). Two processes appending to one file:
            // each line is a single small write, which append-mode keeps
            // whole -- interleaved order, never interleaved bytes.
            logger: ToolExecutionLogger()
        )

        codeTourDelegate = CodeTourDelegate(
            resolveProjectPath: resolveProjectPath,
            // The same reveal open_in_editor uses: a tour stop the user
            // cannot see is not a stop, and the pane publishes its rect only
            // once it is actually on screen.
            showEditorPane: { [weak self] workspaceId, path in
                self?.onRevealInEditor?(workspaceId, path)
            },
            point: { [weak self] frame, hold in
                guard let self else {
                    return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: nil)
                }
                return await self.dispatcher.execute(tool: "point_at", arguments: .object([
                    "frame": .object([
                        "x": .number(frame.minX), "y": .number(frame.minY),
                        "width": .number(frame.width), "height": .number(frame.height),
                    ]),
                    "hold_seconds": .number(hold),
                ]))
            }
        )

        // Now that `self` exists, close the two loops the runner was built
        // with placeholders for. Broadcast rather than applied locally, for
        // the reason this file's header gives.
        revealInEditor = { [weak self] workspaceId, path in
            guard let self else { return }
            Task { @MainActor in
                // Through the same delegate open_in_editor uses, so the tab
                // lands in the pane the user is looking at rather than a
                // second, disconnected store.
                _ = await self.editorFileDelegate.openInEditor(path: path, workspaceId: workspaceId)
                self.onRevealInEditor?(workspaceId, path)
            }
        }
        relayEvent = { [weak self] event, workspaceId in
            guard let self else { return }
            _ = self.broadcast(.event(event, workspaceId: workspaceId, sessionId: self.activeSessionId))
        }
        askPermission = { [weak self] request in
            guard let self else { return false }
            let approvalId = UUID().uuidString
            let summary = request.toolName.map { "코드 편집: \($0)" } ?? "코딩 에이전트가 승인을 요청했어요."
            _ = self.broadcast(.event(
                .awaitApproval(summary: summary, approvalId: approvalId),
                workspaceId: self.activeWorkspaceId,
                sessionId: self.activeSessionId
            ))
            return await self.awaitApproval(id: approvalId)
        }
    }

    /// One code_editor call. The workspace has to have a project directory --
    /// an agent with nowhere to edit is refused up front rather than started
    /// and left to fail on its first write.
    private func runCodeEditor(task: String) async -> DispatchedToolResult {
        let workspaceId = activeWorkspaceId
        guard let projectPath = resolveProjectPath(workspaceId) else {
            return DispatchedToolResult(
                ok: false,
                data: nil,
                error: "execution_failed",
                detail: "이 워크스페이스에는 프로젝트 폴더가 없어서 코드를 편집할 수 없어요."
            )
        }
        let requestId = UUID().uuidString
        stateQueue.sync { activeCodeEditorRequestId = requestId }
        defer {
            stateQueue.sync {
                if activeCodeEditorRequestId == requestId { activeCodeEditorRequestId = nil }
            }
        }

        let result = await codeEditorRunner.run(
            requestId: requestId,
            workspaceId: workspaceId,
            projectPath: projectPath,
            task: task
        )
        // "cancelled"/"timeout" are protocol codes of their own; everything
        // else the runner reports is vocabulary the model has no entry for.
        let passThroughCodes: Set<String> = ["cancelled", "timeout"]
        return DispatchedToolResult(
            ok: result.ok,
            data: result.ok ? .string(result.summary) : nil,
            error: result.ok ? nil : (passThroughCodes.contains(result.error ?? "") ? result.error : "execution_failed"),
            detail: result.reportedDetail
        )
    }

    /// The chat's 중지 button. Reaches the ACP agent through session/cancel,
    /// in-process, now that the agent is ours.
    func cancelActiveCodeEditor() {
        guard let requestId = stateQueue.sync(execute: { activeCodeEditorRequestId }) else { return }
        Task { _ = await codeEditorRunner.cancel(requestId: requestId) }
    }

    /// The app is quitting. An ACP child is a node process plus its vendor
    /// binary, and nothing else reaps it: closing the chat window terminates
    /// this app, which would otherwise leave a code_editor run orphaned.
    func endCodeEditorAgents() {
        codeEditorRunner.terminateAll()
    }

    /// Every tool_result off the socket, so the dispatcher can match it to
    /// the call waiting for it.
    func handle(_ result: ToolResult) {
        dispatcher.handle(result)
    }

    /// The agent decided this turn is real work and wants it out of the
    /// casual session (protocol 3.4 `session_create(origin=agent)`,
    /// 04_ai-module.md 3.7). Two things happen, in this order:
    ///
    /// 1. The session is announced. Like every other event this app produces,
    ///    it is broadcast rather than applied locally -- pet-app relays
    ///    session_create to every gui connection including this one, so the
    ///    sidebar entry and the automatic switch to it come from the same
    ///    path a workspace-created session would take (ClientWindowStore
    ///    already handles origin=agent by following the user along).
    /// 2. Everything the rest of the run emits is re-addressed to it, which
    ///    is the whole point: a 10-minute code_editor delegation, its
    ///    progress, and its 중지 button all belong to the task session, and
    ///    the casual conversation stays usable while it runs.
    @discardableResult
    private func openTaskSession(title: String, brief: String) -> String {
        let sessionId = UUID().uuidString
        let sourceSessionId = activeSessionId
        _ = broadcast(.sessionCreate(
            workspaceId: activeWorkspaceId,
            sessionId: sessionId,
            title: title,
            origin: .agent
        ))
        // The local half of the move -- the part the socket has no message
        // for. Carries the user's own message across and closes the chat it
        // was written in (see ClientWindowStore.moveTurnToTaskSession).
        onTaskSessionOpened?(activeWorkspaceId, sourceSessionId, sessionId, title, activeCommand)
        activeSessionId = sessionId
        runner.sessionId = sessionId
        // The task session belongs to the workspace the run that opened it
        // belongs to, so its events stay routable after the user moves on.
        stateQueue.sync { sessionWorkspaces[sessionId] = activeWorkspaceId }
        if !brief.isEmpty {
            _ = broadcast(.event(.textChunk(text: brief), workspaceId: activeWorkspaceId, sessionId: sessionId))
        }
        return sessionId
    }

    /// Every event off the socket. Nothing here consumes them any more: the
    /// one reader was CodeEditorDelegate, waiting on workspace's agent_done to
    /// finish a delegated edit. code_editor completes in-process now, so the
    /// chat timeline and the pet's reactions (fed elsewhere, AppDelegate.handle)
    /// are the only consumers left. Kept as a no-op rather than removed so the
    /// socket plumbing that calls it stays unchanged.
    func handle(_ event: BridgeEvent, sessionId: String) {}

    /// A chat was deleted, so its conversation goes with it.
    func forgetSession(_ sessionId: String) {
        runner.forgetSession(sessionId)
        stateQueue.sync { sessionWorkspaces[sessionId] = nil }
    }

    /// The workspace a chat belongs to. Falls back to the active one for a
    /// session this host has never run in -- there is nothing better to say,
    /// and it is what every event used before.
    private func workspace(of sessionId: String) -> String {
        stateQueue.sync { sessionWorkspaces[sessionId] } ?? activeWorkspaceId
    }

    /// pet-app went away: nothing in flight can be answered any more. Tool
    /// dispatch still crosses the socket, so it still has to be failed; the
    /// ACP agent does not, and keeps running.
    func socketDisconnected() {
        dispatcher.failAllInFlight()
    }

    func run(command: String, workspaceId: String, sessionId: String) {
        let configuration = configuration
        guard configuration.isConfigured else {
            // Said as a normal agent turn rather than an alert -- it belongs
            // in the transcript next to the message that couldn't be answered.
            // Names the actual paths that were searched rather than "check
            // your config" -- the search order is the answer to the question
            // this message provokes. Names every stable credential the
            // selected provider accepts; interactive CLI login state is
            // deliberately outside the child sandbox.
            let keyVariable = configuration.credentialEnvironmentVariables.joined(separator: " 또는 ")
            let searched = AgentConfiguration.defaultSearchPaths
                .map { $0.appendingPathComponent(".env").path }
                .joined(separator: "\n")
            let message = """
            \(configuration.provider.displayName) 인증 정보가 없어요. 아래 중 한 곳의 .env에 \(keyVariable)=... 를 넣어주세요.
            \(searched)
            """
            // Only the done event: DoneRow renders a failed run's summary, so
            // sending the same words as a text chunk first prints them twice.
            _ = broadcast(.event(.agentDone(ok: false, summary: message), workspaceId: workspaceId, sessionId: sessionId))
            return
        }

        activeWorkspaceId = workspaceId
        activeSessionId = sessionId
        activeCommand = command
        stateQueue.sync { sessionWorkspaces[sessionId] = workspaceId }
        // Which chat's conversation this run continues. One runner serves every
        // chat, so without this they would all share one context -- see
        // AgentRunner.conversations.
        runner.sessionId = sessionId
        // Before the run, not at init: which workspace is active changes
        // between turns, and the runner only re-announces it when it differs.
        let workspaceContext = describeWorkspace(workspaceId)
        runner.workspaceContext = workspaceContext
        let thisRun = stateQueue.sync {
            runGeneration += 1
            return runGeneration
        }

        activeRun.start { [weak self] in
            guard let self else { return }
            // Both named rather than left to the runner to read: setting the
            // properties above and starting this Task are two steps, and a
            // command submitted in between would move them before this body
            // ever ran.
            await self.runner.run(command: command, session: sessionId, workspace: workspaceContext)
            // Backstop for the invariant: every approvalId handed to the UI is
            // answered or explicitly failed. By the time the run returns
            // nothing legitimate is still awaiting one -- anything left is an
            // answer that can never arrive (the window closed, the transcript
            // moved on), and a continuation left suspended is a leak.
            // Scoped to this run: a superseded turn gets here while its
            // replacement is mid-approval.
            self.pendingApprovals.failAll(run: thisRun)
            // Addressed to the chat the run started in, not the active one: a
            // run can move itself into a task session, and the user can click
            // away to another chat while it works.
            await MainActor.run { self.onRunFinished?(workspaceId, sessionId) }
        }
    }

    /// The chat's 허용/거부 buttons land here.
    func resolveApproval(id: String, approved: Bool) {
        pendingApprovals.resolve(id: id, approved: approved)
    }

    /// Denies everything still waiting -- used when the run is cancelled, so
    /// a pending approval doesn't strand the loop forever. A code_editor run
    /// is stranded the same way (its own timeout is the only other way out,
    /// and it is 600s long), so 중지 has to release that too: the ACP agent is
    /// told to stop through session/cancel and then signalled.
    func cancelPendingApprovals() {
        // The turn first: everything below releases something the turn is
        // blocked on, and it has to already be cancelled when it wakes up or
        // it just carries on to the next tool call.
        activeRun.cancel()
        pendingApprovals.failAll()
        cancelActiveCodeEditor()
    }

    private func awaitApproval(id: String) async -> Bool {
        let run = stateQueue.sync { runGeneration }
        return await withCheckedContinuation { continuation in
            pendingApprovals.add(id: id, run: run) { continuation.resume(returning: $0) }
        }
    }

}
