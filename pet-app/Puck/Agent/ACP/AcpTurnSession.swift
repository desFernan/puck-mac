//
//  AcpTurnSession.swift
//  Puck
//
//  One ACP prompt turn, protocol only: initialize -> session/new ->
//  session/prompt, accumulating agent_message_chunk text along the way and
//  answering session/request_permission.
//
//  Extracted from AcpCodeEditorSession when a second caller appeared. Both a
//  code_editor run and a CLI-backed chat turn are the same three requests over
//  the same connection; what differs is only what they do with the text and
//  how they report a failure. So the handshake lives here and the two callers
//  keep their own result types on top of it.
//
//  Takes an AcpConnection rather than making one, so a whole turn can be
//  exercised against a scripted stream with no node process involved.
//

import Foundation

/// How an approval request is answered. Returns false to refuse.
typealias AcpPermissionResolver = (AcpPermissionRequest) async -> Bool

final class AcpTurnSession {
    /// A turn the agent finished on its own.
    struct Completion: Equatable {
        /// `session/prompt`'s stopReason, defaulted to `end_turn` when the
        /// agent omitted one.
        let stopReason: String
        /// Every agent_message_chunk concatenated, trimmed.
        let text: String
    }

    /// Why a turn did not complete. Both cases are already rendered for a
    /// person -- the caller decides where to put the string, not how to build
    /// it, because the stderr tail that explains an ACP error is held here.
    enum Failure: Equatable {
        /// `session/new` answered without a sessionId.
        case noSessionID
        case detail(String)

        var text: String {
            switch self {
            case .noSessionID: return "session/new did not return a sessionId"
            case .detail(let detail): return detail
            }
        }
    }

    enum Outcome: Equatable {
        case completed(Completion)
        /// Either `cancel()` was called or the agent reported `cancelled`.
        case cancelled
        case failed(Failure)
    }

    private let connection: AcpConnection
    /// What `session/new` opens the agent on.
    private let cwd: String
    /// `session/new`'s `mcpServers`, passed through untouched. Empty for a
    /// code_editor run; the CLI-backed chat turn puts its own in-process MCP
    /// server here, which is how the agent reaches Puck's tools at all
    /// (PuckMCPServer).
    private let mcpServers: [JSONValue]
    private let onUpdate: (AcpSessionUpdate) -> Void
    private let resolvePermission: AcpPermissionResolver
    /// The agent's stderr so far, read only when a failure has to be explained.
    private let stderrTail: () -> String

    private let lock = NSLock()
    private var transcript = ""
    private var sessionID: String?
    private var isCancelled = false

    init(
        connection: AcpConnection,
        cwd: String,
        mcpServers: [JSONValue] = [],
        onUpdate: @escaping (AcpSessionUpdate) -> Void = { _ in },
        resolvePermission: @escaping AcpPermissionResolver = { _ in false },
        stderrTail: @escaping () -> String = { "" }
    ) {
        self.connection = connection
        self.cwd = cwd
        self.mcpServers = mcpServers
        self.onUpdate = onUpdate
        self.resolvePermission = resolvePermission
        self.stderrTail = stderrTail

        connection.onNotification = { [weak self] method, params in
            guard method == AcpMethod.sessionUpdate else { return }
            self?.applyUpdate(AcpSessionUpdate(raw: params))
        }
        connection.onRequest = { [weak self] request in
            guard let self else { return }
            guard request.method == AcpMethod.sessionRequestPermission else {
                // An agent request we don't implement is answered rather than
                // ignored: an unanswered JSON-RPC request stalls the agent for
                // the whole tool timeout.
                connection.respond(to: request.id, result: .object([:]))
                return
            }
            Task { await self.answerPermission(request) }
        }
    }

    /// Runs the turn to completion. Never throws -- both callers have to report
    /// *something*, so a failure is a value here rather than an error.
    func run(prompt: String) async -> Outcome {
        do {
            _ = try await connection.request(
                method: AcpMethod.initialize,
                params: .object([
                    "protocolVersion": .number(Double(acpProtocolVersion)),
                    "clientCapabilities": .object([:]),
                ])
            )

            let created = try await connection.request(
                method: AcpMethod.sessionNew,
                params: .object([
                    "cwd": .string(cwd),
                    "mcpServers": .array(mcpServers),
                ])
            )
            guard let sessionID = created["sessionId"]?.stringValue else {
                return .failed(.noSessionID)
            }
            store(sessionID: sessionID)

            if currentlyCancelled() {
                cancel()
                return .cancelled
            }

            let finished = try await connection.request(
                method: AcpMethod.sessionPrompt,
                params: .object([
                    "sessionId": .string(sessionID),
                    "prompt": .array([.object(["type": .string("text"), "text": .string(prompt)])]),
                ])
            )

            if currentlyCancelled() { return .cancelled }

            let stopReason = finished["stopReason"]?.stringValue ?? AcpStopReason.endTurn.rawValue
            if stopReason == AcpStopReason.cancelled.rawValue { return .cancelled }
            return .completed(Completion(stopReason: stopReason, text: currentText()))
        } catch {
            if currentlyCancelled() { return .cancelled }
            return .failed(.detail(detail(from: error)))
        }
    }

    /// Asks the agent to stop. Idempotent -- cancelling twice, or cancelling
    /// before session/new has returned, both do the right thing (the run()
    /// path re-checks after each await).
    func cancel() {
        lock.lock()
        isCancelled = true
        let sessionID = self.sessionID
        lock.unlock()
        guard let sessionID else { return }
        connection.notify(
            method: AcpMethod.sessionCancel,
            params: .object(["sessionId": .string(sessionID)])
        )
    }

    // MARK: - Internals

    private func applyUpdate(_ update: AcpSessionUpdate) {
        lock.lock()
        if !update.text.isEmpty { transcript += update.text }
        lock.unlock()
        onUpdate(update)
    }

    private func answerPermission(_ request: AcpConnection.IncomingRequest) async {
        let permission = AcpPermissionRequest(raw: request.params)
        // A cancelled run must not put an approval prompt in front of the
        // user for work that is already being abandoned.
        let approved = currentlyCancelled() ? false : await resolvePermission(permission)
        if approved, let option = permission.allowOption() {
            connection.respond(to: request.id, result: AcpPermissionRequest.outcome(selecting: option.id))
        } else if !approved, let option = permission.rejectOption() {
            connection.respond(to: request.id, result: AcpPermissionRequest.outcome(selecting: option.id))
        } else {
            connection.respond(to: request.id, result: AcpPermissionRequest.cancelledOutcome())
        }
    }

    /// Taken in a synchronous helper, like the two accessors below, rather
    /// than inline in `run`: NSLock is unavailable from an async context (an
    /// error in the Swift 6 language mode) precisely because a lock must not
    /// be held across an await, and a sync function cannot hold one across
    /// anything.
    private func store(sessionID: String) {
        lock.lock(); defer { lock.unlock() }
        self.sessionID = sessionID
    }

    private func currentlyCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return isCancelled
    }

    private func currentText() -> String {
        lock.lock(); defer { lock.unlock() }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func detail(from error: Error) -> String {
        switch error {
        case AcpError.agent(let code, let message):
            // An ACP-level error is often a one-liner whose explanation the
            // agent wrote to stderr instead ("-32000 Authentication required"
            // next to the CLI's own "Not logged in"). Reported without it, the
            // message names a symptom and nothing that leads to a cause.
            return Self.appending(stderrTail(), to: "ACP error \(code): \(message)")
        case AcpError.processExited(let detail):
            // Already the stderr tail (AcpAgentProcess passes it in).
            return detail.isEmpty ? Strings.text(.acpProcessExited) : detail
        default:
            return Self.appending(stderrTail(), to: String(describing: error))
        }
    }

    /// Appends the tail exactly as captured -- it is already bounded by
    /// AcpAgentProcess, and this goes to the model and the transcript, so
    /// nothing here may widen what a child process can put in front of them.
    private static func appending(_ tail: String, to message: String) -> String {
        let tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty, !message.contains(tail) else { return message }
        return message + "\n" + tail
    }
}
