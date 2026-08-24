//
//  ToolExecutor.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  protocol + tool_dispatch routing, timeout handling
//

import Foundation

/// protocol 3.1's standard tool_result error codes that pet-app itself can
/// produce (pet_app_disconnected is workspace-side, not ours).
enum ToolExecutionError: Error, Equatable {
    case timeout
    /// The dispatched tool isn't in the registry at all -- a registry/agent
    /// mismatch, distinguishable from a tool that exists but failed.
    case unknownTool(String)
    /// The caller abandoned the call via tool_cancel (protocol 3.1) -- e.g.
    /// the user pressed stop, or the agent run was aborted.
    case cancelled
    case notSupportedTarget
    case permissionDenied
    case executionFailed(String)

    var protocolErrorCode: ToolErrorCode {
        switch self {
        case .timeout: return .timeout
        case .unknownTool: return .unknownTool
        case .cancelled: return .cancelled
        case .notSupportedTarget: return .notSupportedTarget
        case .permissionDenied: return .permissionDenied
        case .executionFailed: return .executionFailed
        }
    }

    /// Human-readable specifics for tool_result's `detail` field -- the code
    /// alone reaches the wire otherwise and the actual failure reason is lost.
    var detail: String? {
        switch self {
        case .timeout, .cancelled, .notSupportedTarget, .permissionDenied:
            return nil
        case .unknownTool(let tool):
            return "unknown tool: \(tool)"
        case .executionFailed(let message):
            return message
        }
    }
}

/// One entry in the tool registry (protocol repo section 4). `toolName` must
/// match the registry's tool name exactly.
protocol ToolHandler: AnyObject {
    var toolName: String { get }

    /// - Parameter id: the dispatch this call belongs to. One handler instance
    ///   serves every dispatch of its tool, so anything a handler keeps for
    ///   `cancel` has to be keyed by this -- otherwise a slow call's timeout
    ///   tears down whatever call happens to be in flight when it fires, and
    ///   the call it was actually for is left running with nobody to collect
    ///   it. Handlers with nothing to tear down ignore it.
    /// `@Sendable` because it is: a handler answers from wherever its work
    /// finished -- a Process's reader queue, a global timeout, the main actor
    /// after a hop -- and the executor's own bookkeeping is behind a serial
    /// queue for exactly that reason.
    func execute(id: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void)

    /// Abandon what `execute` started for `id`, and nothing else. Called when
    /// that call times out or is cancelled — without it a timed-out run_shell
    /// leaves its process running forever with nobody to collect it. Unknown
    /// or already-finished ids are a no-op.
    func cancel(id: String)
}

extension ToolHandler {
    /// Most tools finish promptly and have nothing to tear down.
    func cancel(id: String) {}
}

/// Routes an incoming tool_dispatch to its registered ToolHandler and enforces
/// a per-call timeout — protocol 3.1: "타임아웃 기본 15초... 초과 시 수신 측이
/// 아닌 송신 측이 timeout 처리" means pet-app (the tool_dispatch *receiver*)
/// must not let a hung handler block a reply forever.
final class ToolExecutor {
    private var handlers: [String: ToolHandler] = [:]
    private let logger: ToolExecutionLogging?

    /// Called with the tool's name when a call fails for want of a
    /// permission. Wired by AppDelegate to the pet's guidance behaviour;
    /// unset everywhere else, including tests.
    var onPermissionDenied: ((String) -> Void)?
    // Guards each dispatch's completeOnce check-and-set: the timeout closure
    // (DispatchQueue.global()) and a handler's own completion (often fired
    // from a background queue, e.g. RunShellHandler/RunAppleScriptHandler)
    // can race on the same request's didComplete flag without this.
    private let completionQueue = DispatchQueue(label: "Puck.ToolExecutor.completion")
    /// In-flight dispatch id -> the action that abandons it. Guarded by
    /// `completionQueue`; entries are removed on any completion, so a cancel
    /// for an already-finished (or never-seen) id is a no-op.
    private var inFlightCancels: [String: () -> Void] = [:]

    /// How the timeout work item gets scheduled. Injected so tests can observe
    /// the resolved delay without actually waiting a tool's full timeout out.
    private let scheduleTimeout: (TimeInterval, DispatchWorkItem) -> Void

    init(
        logger: ToolExecutionLogging? = nil,
        scheduleTimeout: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.logger = logger
        self.scheduleTimeout = scheduleTimeout
    }

    /// tool_cancel (protocol 3.1): abandon an in-flight dispatch -- the
    /// handler's cancel() runs and the original id replies error="cancelled".
    /// Idempotent for unknown/completed ids.
    func cancel(id: String) {
        // Pop inside the queue, invoke outside it -- the action itself calls
        // completeOnce, which syncs on the same serial queue.
        let cancelAction: (() -> Void)? = completionQueue.sync {
            let action = inFlightCancels[id]
            inFlightCancels[id] = nil
            return action
        }
        cancelAction?()
    }

    func register(_ handler: ToolHandler) {
        handlers[handler.toolName] = handler
    }

    /// - Parameter timeout: seconds before this call is force-completed with a
    ///   timeout error. Defaults to the dispatched tool's registry
    ///   `timeout_sec` (ToolTimeouts) -- resolved here rather than asked of the
    ///   caller, because a caller that forgets silently caps every long tool
    ///   (run_shell/run_applescript 60s, point_at 30s) at the 15s default and
    ///   replies "timeout" while the sender is still legitimately waiting.
    ///   Pass a value only to override, e.g. in tests.
    func dispatch(_ request: ToolDispatch, timeout: TimeInterval? = nil, completion: @escaping (ToolResult) -> Void) {
        let timeout = timeout ?? ToolTimeouts.seconds(for: request.tool)
        logger?.log(.execStart(id: request.id))

        var didComplete = false
        let completeOnce: (Bool, JSONValue?, ToolExecutionError?) -> Void = { [logger, completionQueue, weak self] ok, data, error in
            let shouldComplete: Bool = completionQueue.sync {
                guard !didComplete else { return false }
                didComplete = true
                self?.inFlightCancels[request.id] = nil
                return true
            }
            guard shouldComplete else { return }
            logger?.log(.execEnd(id: request.id, ok: ok))
            if error == .permissionDenied {
                // The reply still goes back to the agent as normal; this is
                // the pet's cue to go and ask for the permission on screen,
                // where the user actually is (see PermissionGuidance).
                self?.onPermissionDenied?(request.tool)
            }
            completion(ToolResult(id: request.id, ok: ok, data: data, error: error?.protocolErrorCode, detail: error?.detail))
        }

        guard let handler = handlers[request.tool] else {
            completeOnce(false, nil, .unknownTool(request.tool))
            return
        }

        // A DispatchWorkItem rather than a bare asyncAfter closure so a fast
        // success can cancel it. Left uncancelled, every call held a queued
        // block for its full timeout — 600s in code_editor's case.
        let timeoutWork = DispatchWorkItem { [weak handler] in
            handler?.cancel(id: request.id)
            completeOnce(false, nil, .timeout)
        }
        completionQueue.sync {
            inFlightCancels[request.id] = { [weak handler] in
                timeoutWork.cancel()
                handler?.cancel(id: request.id)
                completeOnce(false, nil, .cancelled)
            }
        }
        scheduleTimeout(timeout, timeoutWork)

        handler.execute(id: request.id, args: request.args) { result in
            timeoutWork.cancel()
            switch result {
            case .success(let data):
                completeOnce(true, data, nil)
            case .failure(let error):
                completeOnce(false, nil, error)
            }
        }
    }
}
