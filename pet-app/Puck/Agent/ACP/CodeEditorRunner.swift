//
//  CodeEditorRunner.swift
//  Puck
//
//  Runs code_editor: one queue per workspace, one ACP agent process per run.
//  Folds together workspace/src/agent-host/{index,code-editor-queue,
//  run-registry,run-cancellation}.ts -- four files that were separate because
//  a process boundary (Electron main <-> utility process) ran through the
//  middle of them. With that boundary gone, so is the reason to split.
//
//  Serial per workspace, parallel across workspaces: two agents editing the
//  same project at once would interleave writes to the same files, while two
//  different projects have nothing to contend over. Same rule the TS queue
//  enforced.
//

import Foundation

/// What the runner needs from the outside world, injected so tests can drive a
/// scripted agent instead of spawning node.
struct CodeEditorRunnerEnvironment {
    /// Builds the transport for one run. Returning nil means the agent cannot
    /// be started at all (no node, no codex CLI, missing bundle).
    var startAgent: (_ kind: CodingAgentKind, _ projectPath: String) throws -> AcpAgentTransport
    var credentials: (_ kind: CodingAgentKind) -> [String: String]
    var codingAgent: () -> CodingAgentKind
}

/// The agent processes that are alive right now, reachable without awaiting
/// the actor. `applicationWillTerminate` gets no chance to await anything, and
/// a child left behind is a node process plus its ~256MB vendor binary with
/// nothing on screen to point at it.
final class LiveAgentProcesses {
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: AcpAgentTransport] = [:]

    func add(_ process: AcpAgentTransport) {
        lock.lock(); processes[ObjectIdentifier(process)] = process; lock.unlock()
    }

    func remove(_ process: AcpAgentTransport) {
        lock.lock(); processes.removeValue(forKey: ObjectIdentifier(process)); lock.unlock()
    }

    /// TERM then KILL, with no wait in between: by the time this runs there is
    /// nobody left to escalate later, so the guarantee has to be immediate.
    func endAll() {
        lock.lock()
        let all = Array(processes.values)
        processes.removeAll()
        lock.unlock()
        for process in all where process.isRunning {
            process.terminate()
            process.kill()
        }
    }
}

/// Runs `work` under a deadline. Returns nil when the deadline won.
///
/// The loser is abandoned rather than awaited -- a task group would wait for
/// it, and what it is waiting on is exactly what the deadline exists to escape
/// (a stalled network call, an approval nobody will ever answer). Killing the
/// agent is what actually unblocks it, and that happens at the call site.
/// Internal rather than private: CodingAgentCLIClient bounds its own ACP turn
/// the same way, for the same reason, and a second copy of a
/// resume-exactly-once race is the kind of thing that only stays correct in
/// one of its copies.
func withDeadline<Value>(
    seconds: TimeInterval,
    work: @escaping () async -> Value
) async -> Value? {
    await withDeadline(seconds: seconds, suspendedWhile: { false }, work: work)
}

/// The same deadline, but one that does not run while `suspendedWhile` holds.
///
/// A CLI chat turn calls Puck's tools through an MCP server, and a tool can
/// sit on an approval prompt for as long as the user takes to read it. Charged
/// against the turn's own deadline, a slow reader would see the chat give up
/// on the CLI at the moment they pressed 허용. Time spent serving the agent is
/// not time spent waiting on it, so it is not counted.
func withDeadline<Value>(
    seconds: TimeInterval,
    suspendedWhile isSuspended: @escaping () -> Bool,
    work: @escaping () async -> Value
) async -> Value? {
    let outcome = FirstOutcome<Value?>()
    return await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
        outcome.arm(continuation)
        Task { outcome.resolve(await work()) }
        Task {
            // Ticked rather than slept in one go, because the budget only
            // advances while nothing is suspending it. The tick also ends the
            // timer task once `work` has answered, so a 180s deadline does not
            // leave a task alive for 180s after every turn.
            let tick: TimeInterval = 0.05
            var spent: TimeInterval = 0
            while spent < seconds {
                try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
                if outcome.isResolved { return }
                if !isSuspended() { spent += tick }
            }
            outcome.resolve(nil)
        }
    }
}

/// Resumes exactly once, for whichever racer arrives first.
private final class FirstOutcome<Value> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var resolved = false

    /// Called before either racer starts, so there is no window in which a
    /// result arrives with nothing to hand it to.
    func arm(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock(); self.continuation = continuation; lock.unlock()
    }

    var isResolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved
    }

    func resolve(_ value: Value) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        resolved = true
        lock.unlock()
        waiting?.resume(returning: value)
    }
}

actor CodeEditorRunner {
    /// A run that is queued or in flight.
    private struct Run {
        let requestId: String
        let workspaceId: String
        var session: AcpCodeEditorSession?
        var process: AcpAgentTransport?
        var cancelled = false
    }

    private let environment: CodeEditorRunnerEnvironment
    /// The registry's bound for this tool (ToolTimeouts). Nothing else here
    /// ever gives up: a child that is alive but wedged -- a stalled network
    /// call, a permission request nobody answers -- leaves `session/prompt`
    /// with no reply, and the chat spins until the app is quit. Bounds one
    /// run's own work rather than the whole queue: a run still waiting its
    /// turn is bounded by its predecessors, each of which is bounded by this.
    private let timeoutSeconds: TimeInterval
    private let onUpdate: (_ requestId: String, _ workspaceId: String, _ update: AcpSessionUpdate) -> Void
    private let resolvePermission: AcpPermissionResolver

    /// Shared with `terminateAll`, which cannot await this actor.
    nonisolated let liveProcesses = LiveAgentProcesses()

    /// workspaceId -> the tail of that workspace's queue, so a new run can
    /// await its predecessor without a lock or a polling loop.
    private var queueTails: [String: Task<Void, Never>] = [:]
    private var runs: [String: Run] = [:]

    init(
        environment: CodeEditorRunnerEnvironment,
        timeoutSeconds: TimeInterval = ToolTimeouts.seconds(for: "code_editor"),
        onUpdate: @escaping (_ requestId: String, _ workspaceId: String, _ update: AcpSessionUpdate) -> Void = { _, _, _ in },
        resolvePermission: @escaping AcpPermissionResolver = { _ in false }
    ) {
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.onUpdate = onUpdate
        self.resolvePermission = resolvePermission
    }

    /// - Returns: the tool result. Never throws -- code_editor's caller is a
    ///   tool executor that has to report something back to the model.
    func run(
        requestId: String,
        workspaceId: String,
        projectPath: String,
        task: String
    ) async -> CodeEditorResult {
        guard runs[requestId] == nil else {
            return CodeEditorResult(
                ok: false, summary: Strings.text(.toolDuplicateRequest), changedFiles: [],
                error: "duplicate_request", detail: requestId
            )
        }
        runs[requestId] = Run(requestId: requestId, workspaceId: workspaceId)

        // The tail has to represent "this run's *work* is finished", not "this
        // run has been admitted". Chaining bare gates that only await their own
        // predecessor lets every run through at once: each gate completes as
        // soon as the one before it does, which is immediately.
        let predecessor = queueTails[workspaceId]
        let work = Task<CodeEditorResult, Never> { [weak self] in
            _ = await predecessor?.value
            guard let self else { return .cancelled() }
            return await self.executeIfStillWanted(
                requestId: requestId, workspaceId: workspaceId, projectPath: projectPath, task: task
            )
        }
        let tail = Task<Void, Never> { _ = await work.value }
        queueTails[workspaceId] = tail

        let result = await work.value
        runs.removeValue(forKey: requestId)
        // Only clear the tail if nobody queued behind us.
        if queueTails[workspaceId] == tail { queueTails.removeValue(forKey: workspaceId) }
        return result
    }

    /// The queue admitted this run; honour a cancel that arrived while it
    /// waited rather than spawning an agent for work nobody wants.
    private func executeIfStillWanted(
        requestId: String,
        workspaceId: String,
        projectPath: String,
        task: String
    ) async -> CodeEditorResult {
        if runs[requestId]?.cancelled == true { return .cancelled() }
        return await execute(requestId: requestId, workspaceId: workspaceId, projectPath: projectPath, task: task)
    }

    /// Idempotent, and safe before the run has started: a run cancelled while
    /// still queued never spawns an agent at all.
    func cancel(requestId: String) -> Bool {
        guard var run = runs[requestId] else { return false }
        run.cancelled = true
        runs[requestId] = run
        run.session?.cancel()
        // Give session/cancel a moment to land before falling back to
        // signals -- the TS adapter used the same two seconds.
        //
        // The run's own path shuts the same process down when it returns, and
        // both firing is normal rather than a bug: a cancel arrives while the
        // run is still awaiting, and whichever gets there first is the one
        // that ends the process. `shutDown` is idempotent for that reason.
        if let process = run.process { shutDown(process, cancelGrace: 2) }
        return true
    }

    /// The app is going away. Synchronous because the only caller
    /// (applicationWillTerminate) has nothing to await with.
    nonisolated func terminateAll() {
        liveProcesses.endAll()
    }

    /// The one way a run's agent is ended: SIGTERM, a moment to leave on its
    /// own, then SIGKILL. `terminate()` alone is a request, not a guarantee,
    /// and the transport is released as soon as the run finishes, so nothing
    /// would be left to escalate afterwards.
    private func shutDown(_ process: AcpAgentTransport, cancelGrace: TimeInterval) {
        Task {
            if cancelGrace > 0 {
                try? await Task.sleep(nanoseconds: UInt64(cancelGrace * 1_000_000_000))
            }
            if process.isRunning { process.terminate() }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if process.isRunning { process.kill() }
            liveProcesses.remove(process)
        }
    }

    // MARK: - Internals

    private func execute(
        requestId: String,
        workspaceId: String,
        projectPath: String,
        task: String
    ) async -> CodeEditorResult {
        let kind = environment.codingAgent()
        let tracker = ProjectChangeTracker(root: URL(fileURLWithPath: projectPath, isDirectory: true))
        tracker.start()

        let process: AcpAgentTransport
        do {
            process = try environment.startAgent(kind, projectPath)
        } catch {
            return CodeEditorResult(
                ok: false,
                summary: Self.unavailableSummary(for: error, kind: kind),
                changedFiles: tracker.finish(),
                error: "agent_unavailable",
                detail: String(describing: error)
            )
        }
        liveProcesses.add(process)

        let session = AcpCodeEditorSession(
            connection: process.connection,
            projectPath: projectPath,
            onUpdate: { [onUpdate] update in onUpdate(requestId, workspaceId, update) },
            resolvePermission: resolvePermission,
            stderrTail: { [weak process] in process?.currentStderrTail() ?? "" }
        )
        runs[requestId]?.session = session
        runs[requestId]?.process = process
        // A cancel that arrived while the agent was starting has to be honoured
        // here, or it would be lost between the queue check and the first await.
        if runs[requestId]?.cancelled == true {
            session.cancel()
            process.kill()
            liveProcesses.remove(process)
            return .cancelled(changedFiles: tracker.finish())
        }

        guard var result = await withDeadline(seconds: timeoutSeconds, work: { await session.run(task: task) }) else {
            session.cancel()
            shutDown(process, cancelGrace: 0)
            return CodeEditorResult(
                ok: false,
                summary: String(format: Strings.text(.toolCodeEditTimedOutFormat), "\(Int(timeoutSeconds))"),
                changedFiles: tracker.finish(),
                error: "timeout",
                detail: "code_editor exceeded \(Int(timeoutSeconds))s"
            )
        }
        shutDown(process, cancelGrace: 0)
        result.changedFiles = tracker.finish()
        return result
    }

    private static func unavailableSummary(for error: Error, kind: CodingAgentKind) -> String {
        guard let error = error as? AcpAgentCommandError else {
            return AcpAgentCommandError.unknownStartFailureSummary
        }
        return error.summary(purpose: Strings.text(.toolCodeEditPurpose), kind: kind)
    }
}
