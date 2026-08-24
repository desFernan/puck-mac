//
//  CodingAgentCLIClient.swift
//  Puck
//
//  An AgentLLMClient backed by `claude` or `codex`, driven over ACP through the
//  same sandboxed child process `code_editor` spawns. The child receives only
//  an explicitly configured setup-token or API key; interactive CLI login
//  state is deliberately not copied into its private HOME.
//
//  ## How it gets Puck's tools
//
//  ACP has no tool-call channel back to the host -- the CLI runs its own tools
//  in its own process and returns prose -- so a turn from here never comes
//  back carrying tool calls for AgentRunner to execute. It does not have to:
//  `session/new` takes an `mcpServers` array, and Puck puts its own tools
//  there as a loopback MCP server (PuckMCPServer) that lives exactly as long
//  as the turn. The CLI sees them as `mcp__puck__*` and calls them itself;
//  each call lands on `AgentRunner.invokeTool`, so approval, dispatch and the
//  pet's reaction are the same as under any other provider.
//
//  The prompt still overrides AgentRunner's tool instructions, but now to say
//  what is true: the tools are there under their MCP names, and `code_editor`
//  is the one that is not (on this provider the CLI *is* the coding agent it
//  would delegate to). If the server cannot be opened at all, the turn runs
//  without it and the prompt says *that* instead -- a model left believing it
//  can call `point_at` would narrate having pointed at something while the pet
//  stood still, which is the failure mode worth spending prompt on.
//
//  ## One process per turn
//
//  A conversation could instead keep one ACP session alive and send only the
//  newest message, which is what the CLI's own session model wants. It is not
//  what this does, for two reasons. `send` is handed the entire message array
//  every turn and has no session identity to key a long-lived child on -- the
//  runner owns the history, and a second copy of it inside the CLI could
//  disagree with the first. And an idle ACP child is a node process plus the
//  vendor's ~256MB native binary sitting there between turns; a chat that is
//  mostly idle would pay that continuously. So the whole transcript is
//  re-sent, the child lives exactly as long as the turn, and it is torn down
//  on every exit path.
//

import Foundation

enum CodingAgentCLIError: LocalizedError, Equatable {
    /// The agent could not be started -- no node, no CLI, missing bundle. The
    /// string is already the sentence to show (AcpAgentCommandError.summary).
    case unavailable(String)
    /// The turn started and then failed. Carries the ACP error plus whatever
    /// the CLI wrote to stderr, which is usually the only real explanation.
    case failed(String)
    case timedOut(seconds: Int)
    /// The turn ended cleanly but said nothing at all.
    case emptyReply(stopReason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable(let summary): return summary
        case .failed(let detail): return String(format: Strings.text(.cliErrorFormat), detail)
        case .timedOut(let seconds): return String(format: Strings.text(.cliTimedOutFormat), "\(seconds)")
        case .emptyReply(let stopReason): return String(format: Strings.text(.cliNoAnswerFormat), stopReason)
        case .cancelled: return Strings.text(.agentCancelled)
        }
    }
}

final class CodingAgentCLIClient: AgentLLMClient {
    /// Read per turn, not captured once: the CLI choice can change in Settings
    /// while the app is running, same as the key field.
    private let configuration: () -> AgentConfiguration
    /// Spawns the agent. Injected so a turn can be driven against a scripted
    /// stream with no node process involved.
    private let startAgent: (_ kind: CodingAgentKind, _ cwd: String) throws -> AcpAgentTransport
    /// Where `session/new` opens the agent. The active workspace's project when
    /// there is one -- a CLI asked about "this file" can then actually look --
    /// falling back to an app-owned directory for a chat-only workspace.
    private let workingDirectory: () -> String
    private let timeoutSeconds: TimeInterval
    /// Runs one of Puck's tools for the CLI. nil means there is no host to run
    /// them (the standalone tests), and then no MCP server is started and the
    /// prompt says the tools are unavailable rather than advertising an
    /// address nothing answers.
    private let invokeTool: AgentToolInvocation?

    /// Long enough for a real answer on a cold CLI start (the vendor binary is
    /// ~256MB and the first turn pays for loading it), short enough that a
    /// wedged child does not hold the chat until the app is quit.
    static let defaultTimeoutSeconds: TimeInterval = 180

    init(
        configuration: @escaping () -> AgentConfiguration,
        workingDirectory: @escaping () -> String = CodingAgentCLIClient.projectlessWorkingDirectory,
        timeoutSeconds: TimeInterval = CodingAgentCLIClient.defaultTimeoutSeconds,
        invokeTool: AgentToolInvocation? = nil,
        startAgent: @escaping (_ kind: CodingAgentKind, _ cwd: String) throws -> AcpAgentTransport
            = CodingAgentCLIClient.spawn
    ) {
        self.configuration = configuration
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.invokeTool = invokeTool
        self.startAgent = startAgent
    }

    /// A CLI session's project root is also its filesystem write boundary.
    /// Chat-only turns therefore use one narrow app-owned folder instead of
    /// accidentally granting the child write access to the entire home tree.
    static func projectlessWorkingDirectory() -> String {
        let directory = AgentConfiguration.supportDirectory
            .appendingPathComponent("ChatWorkspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path
    }

    /// The real spawn, identical to the one `code_editor` uses -- same command
    /// resolution, same trimmed child environment, same credential forwarding.
    static func spawn(kind: CodingAgentKind, cwd: String) throws -> AcpAgentTransport {
        let command = try AcpAgentCommandResolver.command(
            for: kind,
            scriptURL: AcpAgentCommandResolver.bundledScriptURL(for: kind),
            node: AcpAgentCommandResolver.resolveNode(),
            vendorCLI: AcpAgentCommandResolver.resolveVendorCLI(for: kind)
        )
        let process = AcpAgentProcess(
            command: command,
            projectPath: cwd,
            credentials: AgentConfiguration.load().codingAgentCredentials(for: kind)
        )
        try process.start()
        return process
    }

    func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
        let kind = configuration().codingAgent
        let cwd = workingDirectory()

        // Before the agent, because `session/new` has to carry the server's
        // address and the prompt has to say whether it came up. Torn down on
        // every exit path below -- success, failure, timeout, cancel -- so no
        // port is ever left open between turns.
        var mcpServer: PuckMCPServer?
        defer { mcpServer?.stop() }
        var mcpServers: [JSONValue] = []
        if let invokeTool {
            let server = PuckMCPServer(toolSpecs: tools, invoke: invokeTool)
            do {
                mcpServers = [try await server.start()]
                mcpServer = server
            } catch {
                // Not fatal: a turn that can only talk is worth more than no
                // turn at all, and the prompt below will say so rather than
                // letting the model discover it by having a call refused.
                server.stop()
                AppLogger.shared.log(
                    .error,
                    String(format: Strings.text(.cliNoToolsFallbackFormat), AgentRunner.rawFailureDescription(for: error))
                )
            }
        }
        let toolsAreReachable = mcpServer != nil

        let process: AcpAgentTransport
        do {
            process = try startAgent(kind, cwd)
        } catch {
            guard let error = error as? AcpAgentCommandError else {
                throw CodingAgentCLIError.unavailable(AcpAgentCommandError.unknownStartFailureSummary)
            }
            // A `codex` that is not installed has to fail here, plainly and
            // immediately, rather than hang: nothing was spawned, so there is
            // nothing to wait on.
            throw CodingAgentCLIError.unavailable(error.summary(purpose: Strings.text(.cliConversationPurpose), kind: kind))
        }

        let session = AcpTurnSession(
            connection: process.connection,
            cwd: cwd,
            mcpServers: mcpServers,
            resolvePermission: Self.resolvePermission,
            stderrTail: { [weak process] in process?.currentStderrTail() ?? "" }
        )
        let prompt = Self.prompt(for: messages, toolsAreReachable: toolsAreReachable)

        let server = mcpServer
        guard let outcome = await withDeadline(
            seconds: timeoutSeconds,
            // A tool call in flight is Puck working, not the CLI stalling --
            // and it may be sitting on an approval prompt the user has not
            // read yet. See withDeadline(seconds:suspendedWhile:work:).
            suspendedWhile: { server?.isServingToolCall ?? false },
            work: { await session.run(prompt: prompt) }
        ) else {
            session.cancel()
            Self.shutDown(process)
            throw CodingAgentCLIError.timedOut(seconds: Int(timeoutSeconds))
        }
        Self.shutDown(process)

        switch outcome {
        case .cancelled:
            throw CodingAgentCLIError.cancelled
        case .failed(let failure):
            throw CodingAgentCLIError.failed(failure.text)
        case .completed(let completion):
            guard !completion.text.isEmpty else {
                throw CodingAgentCLIError.emptyReply(stopReason: completion.stopReason)
            }
            // Still no tool calls to hand back: whatever the CLI needed it
            // already called, over MCP, and AgentRunner already emitted the
            // events and appended nothing to this conversation.
            return GPTTurn(text: completion.text, toolCalls: [])
        }
    }

    /// Answers the CLI's own `session/request_permission`.
    ///
    /// Allowed for Puck's MCP tools, refused for everything else. Both halves
    /// matter. Refusing a `mcp__puck__*` permission would deny the tool before
    /// it ever reached the host -- the user would see nothing at all and the
    /// model would be told it was refused -- which is why the default resolver
    /// (`false`) cannot be left in place once tools are attached. And allowing
    /// it here is not the same as skipping approval: the real gate is inside
    /// `AgentRunner.invokeTool`, which the call is about to reach, so an
    /// approval-requiring tool still puts the normal 승인 prompt in the chat and
    /// still cannot run until the user answers it. What the CLI wants to do
    /// itself -- write a file, run a command -- is `AgentPermissionMode`'s
    /// call, and its default is still the refusal a chat turn has always
    /// given. Read per request rather than captured at construction, so
    /// changing the setting takes effect on the next tool call instead of the
    /// next launch.
    static func resolvePermission(_ request: AcpPermissionRequest) async -> Bool {
        AgentConfiguration.permissionMode().allows(request, ownMCPServer: MCPToolCatalog.serverName)
    }

    /// SIGTERM, a moment, then SIGKILL -- `terminate()` alone is a request,
    /// and the transport is released as soon as this returns, so nothing would
    /// be left to escalate afterwards. Detached because the turn's answer is
    /// already in hand and must not wait on a child's exit.
    private static func shutDown(_ process: AcpAgentTransport) {
        Task {
            if process.isRunning { process.terminate() }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if process.isRunning { process.kill() }
        }
    }

    // MARK: - Prompt

    /// The whole conversation as one prompt, because a turn gets one.
    ///
    /// System messages first (AgentRunner's own prompt, plus the per-run
    /// workspace line), then the tool-availability override that corrects
    /// them, then the transcript. The override comes after the prompt it
    /// contradicts on purpose: the later instruction is the one models follow.
    static func prompt(for messages: [GPTMessage], toolsAreReachable: Bool) -> String {
        var systemLines: [String] = []
        var transcript: [String] = []

        for message in messages {
            switch message {
            case .system(let text):
                systemLines.append(text)
            case .user(let text):
                transcript.append("User: \(text)")
            case .assistant(let text, let toolCalls, _):
                if let text, !text.isEmpty { transcript.append("Assistant: \(text)") }
                // Turns taken under another provider can carry real tool
                // calls. Rendered as history rather than dropped, so a
                // conversation that switches providers mid-way still reads.
                for call in toolCalls {
                    transcript.append("Assistant (tool \(call.name)): \(call.argumentsJSON)")
                }
            case .tool(_, let content):
                transcript.append("Tool result: \(content)")
            }
        }

        var parts = systemLines
        // Read here rather than captured at construction, so `/effort` in the
        // chat lands on the next turn instead of the next launch.
        if let effort = AgentConfiguration.effort().promptLine { parts.append(effort) }
        parts.append(toolsAreReachable ? toolAvailabilityOverride : toolsUnavailableOverride)
        parts.append("Conversation so far:\n" + transcript.joined(separator: "\n"))
        parts.append("Reply to the last User message. Output only your reply.")
        return parts.joined(separator: "\n\n")
    }

    /// Corrects the host system prompt for this provider when the MCP server
    /// is up. Internal so a test can assert it is actually in the prompt --
    /// the honesty of this path rests entirely on it being there.
    static let toolAvailabilityOverride = """
    IMPORTANT -- TOOL AVAILABILITY ON THIS CONNECTION:
    You are running through a coding-agent CLI, and the host application's tools ARE connected to \
    you, as an MCP server named `puck`. They reach you under prefixed names: `mcp__puck__launch_app`, \
    `mcp__puck__find_ui_element`, `mcp__puck__point_at`, `mcp__puck__click_element`, \
    `mcp__puck__run_shell`, `mcp__puck__run_applescript`, `mcp__puck__read_file`, \
    `mcp__puck__open_in_editor`, `mcp__puck__list_files`, and so on. Wherever an instruction above \
    names a tool by its bare name, it means the `mcp__puck__` tool of that name -- call it.
    Prefer those over your own equivalents: they act on the machine the user is actually looking at, \
    the pet physically performs them, and the ones that need the user's permission ask through the \
    app's own approval prompt. `mcp__puck__run_shell` and `mcp__puck__run_applescript` will pause \
    until the user approves them, and come back with `denied_by_user` if the user says no -- when \
    that happens, say so and offer something else rather than retrying or working around it.
    The exceptions are `code_editor` and `open_task_session`: neither is available here, because on \
    this connection you are the coding agent they would have handed the task to. So when the user \
    asks for code to be written or changed, do it yourself with your own editing tools and say what \
    you changed. Ignore any instruction above telling you to open a task session first, to delegate \
    to code_editor, or that you never edit files.
    Never say or imply that you launched, opened, pointed at, clicked, or ran something unless an \
    `mcp__puck__` tool actually returned a successful result for it.
    """

    /// The same correction for a turn whose MCP server could not be opened.
    /// Rare, and the reason the honest version has to exist: telling the model
    /// the tools are there when nothing is listening would have it narrate
    /// actions that never happened.
    static let toolsUnavailableOverride = """
    IMPORTANT -- TOOL AVAILABILITY ON THIS CONNECTION:
    You are running through a coding-agent CLI, and the host application's tools could NOT be \
    connected to you on this turn. You cannot launch apps, point the pet at anything, click, run \
    shell commands on the user's behalf, read or open files in the editor pane, open a task \
    session, or hand work to code_editor. Any such tool named above is unavailable right now; \
    ignore those instructions.
    So: answer in words only. Never say or imply that you launched, opened, pointed at, clicked, \
    edited, or ran anything -- you did not. If the user asks for an action that needs those tools, \
    say plainly that it could not be connected this time and that trying again may work.
    """
}
