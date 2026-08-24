//
//  PetToolDispatcher.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The `petAppProxy` executor of plan/04_ai-module.md section 3.1, in Swift:
//  turns one tool call into a tool_dispatch on bridge.sock and waits for the
//  tool_result carrying the same id (protocol 3.1).
//
//  The socket is one shared stream with no request/response framing of its
//  own, so correlation is this type's whole job: it keeps a table of
//  in-flight ids and hands each reply back to the continuation waiting on it.
//
//  Timeouts are the *sender's* to enforce (docs/socket.md), and the bound
//  comes from ToolTimeouts rather than a constant here -- pet-app's executor
//  runs its own defensive timer, and two hardcoded numbers drift.
//

import Foundation

/// What the agent gets back, already normalized to the protocol's error
/// vocabulary so the loop never has to care where a failure came from.
struct DispatchedToolResult {
    let ok: Bool
    let data: JSONValue?
    let error: String?
    let detail: String?
}

/// `@unchecked` because the compiler cannot see what the header describes:
/// `pending` is reached from socket reads, the agent's task and timeout
/// timers, and every access goes through `lock`. Without the conformance the
/// timeout closure -- which is `@Sendable` and captures self -- warns on every
/// build, 33 times over the targets that compile this file.
final class PetToolDispatcher: @unchecked Sendable {
    /// Sends one message on the socket; false when nothing is connected.
    private let send: (BridgeMessage) -> Bool
    private let timeoutSeconds: (String) -> TimeInterval

    /// id -> the continuation waiting for that id's tool_result. Touched from
    /// several queues (socket reads, the agent's task, timeout timers), so
    /// every access goes through `lock`.
    private var pending: [String: CheckedContinuation<DispatchedToolResult, Never>] = [:]
    private let lock = NSLock()

    init(
        send: @escaping (BridgeMessage) -> Bool,
        timeoutSeconds: @escaping (String) -> TimeInterval = ToolTimeouts.seconds(for:)
    ) {
        self.send = send
        self.timeoutSeconds = timeoutSeconds
    }

    /// Feed every tool_result the socket delivers in here. Ids that aren't
    /// waiting (a late reply after a timeout, a reply to someone else) are
    /// dropped -- docs/socket.md requires exactly that rather than an error.
    func handle(_ result: ToolResult) {
        lock.lock()
        let continuation = pending.removeValue(forKey: result.id)
        lock.unlock()
        continuation?.resume(returning: DispatchedToolResult(
            ok: result.ok,
            data: result.data,
            error: result.error?.rawValue,
            detail: result.detail
        ))
    }

    /// Fails everything in flight. Called when the socket drops: pet-app may
    /// still be running the tool, but the reply can no longer reach us, so
    /// waiting out the full timeout would just stall the run.
    func failAllInFlight(error: String = "pet_app_disconnected") {
        lock.lock()
        let waiting = pending
        pending.removeAll()
        lock.unlock()
        for (_, continuation) in waiting {
            continuation.resume(returning: DispatchedToolResult(ok: false, data: nil, error: error, detail: nil))
        }
    }

    func execute(tool: String, arguments: JSONValue, id: String = UUID().uuidString) async -> DispatchedToolResult {
        guard ToolRegistry.tool(named: tool) != nil else {
            // The registry and the model's tool list are built from the same
            // data, so this means they've drifted -- worth its own code
            // (docs/socket.md) rather than looking like an execution failure.
            return DispatchedToolResult(ok: false, data: nil, error: "unknown_tool", detail: tool)
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            // Nothing in the app reuses an id -- they are UUIDs -- but if one
            // ever did, overwriting the entry would strand the earlier
            // continuation and hang whoever was awaiting it forever. A
            // displaced waiter is told instead.
            let displaced = pending.updateValue(continuation, forKey: id)
            lock.unlock()
            displaced?.resume(returning: DispatchedToolResult(
                ok: false, data: nil, error: "execution_failed", detail: "dispatch id reused: \(id)"
            ))

            guard send(.toolDispatch(ToolDispatch(id: id, tool: tool, args: arguments))) else {
                // Nothing is connected. Answer immediately rather than after
                // the timeout -- protocol's "disconnected behavior" is an
                // immediate pet_app_disconnected, no round trip.
                resolve(id: id, with: DispatchedToolResult(ok: false, data: nil, error: "pet_app_disconnected", detail: nil))
                return
            }

            let deadline = timeoutSeconds(tool)
            DispatchQueue.global().asyncAfter(deadline: .now() + deadline) { [weak self] in
                guard let self else { return }
                let timedOut = resolve(id: id, with: DispatchedToolResult(
                    ok: false, data: nil, error: "timeout", detail: "\(tool) exceeded \(Int(deadline))s"
                ))
                // Protocol 3.1 makes the timeout the sender's, and tool_cancel
                // is how the sender says so. Giving up quietly leaves pet-app
                // running a handler whose answer nobody is waiting for --
                // run_shell would go on holding a process for as long as it
                // takes. Only when the timeout is what ended the wait: if a
                // real reply got there first the work is already done, and
                // cancelling it would be a message about nothing.
                if timedOut { _ = send(.toolCancel(id: id)) }
            }
        }
    }

    /// Resumes `id`'s continuation if it is still waiting, and reports
    /// whether it was. Safe to call twice -- the second caller (usually the
    /// timeout firing after a real reply) finds nothing and does nothing,
    /// which is what keeps a continuation from being resumed twice and
    /// trapping. The timeout path reads the result to decide whether there is
    /// still anything worth cancelling.
    @discardableResult
    private func resolve(id: String, with result: DispatchedToolResult) -> Bool {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(returning: result)
        return continuation != nil
    }
}
