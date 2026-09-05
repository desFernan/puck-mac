//
//  AcpConnection.swift
//  Puck
//
//  NDJSON JSON-RPC over a pair of pipes. Port of what
//  @agentclientprotocol/sdk's ndJsonStream + client() did for
//  workspace/src/agent-host/acp-adapter.ts.
//
//  Transport only -- it knows about frames, ids and pending replies, not about
//  sessions or prompts. AcpCodeEditorSession owns that. Split because the
//  framing is the part worth testing against a scripted stream, with no
//  process involved.
//

import Foundation

/// One end of an ACP conversation. Reads are pushed in by the owner (whoever
/// is draining the pipe); writes go out through `send`.
final class AcpConnection {
    /// A request the agent made of us, awaiting our response.
    struct IncomingRequest {
        let id: JSONValue
        let method: String
        let params: JSONValue
    }

    private let send: (Data) -> Void
    private let lock = NSLock()
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Result<JSONValue, Error>, Never>] = [:]
    /// Guards `buffer` and the delivery of the lines split out of it. Its own
    /// lock, not the one above: `handle(line:)` calls out to `onNotification`
    /// and `onRequest`, whose handlers reach back in through `respond` -- and
    /// that takes `lock`. Two locks means neither path waits on itself.
    private let receiveLock = NSLock()
    private var buffer = Data()
    /// Set once the agent is gone. Guarded by the same lock as `pending`, so a
    /// request cannot be filed into a dictionary nobody will ever drain again.
    private var closeError: Error?

    /// Notifications from the agent (`session/update` above all).
    var onNotification: ((_ method: String, _ params: JSONValue) -> Void)?
    /// Requests from the agent (`session/request_permission`). The handler must
    /// eventually call `respond` -- nothing times these out here, because the
    /// only such request is an approval, which legitimately waits on a human.
    var onRequest: ((IncomingRequest) -> Void)?

    init(send: @escaping (Data) -> Void) {
        self.send = send
    }

    // MARK: - Reading

    /// Feeds raw bytes in. Splits on newlines and tolerates a chunk that ends
    /// mid-line, which is the normal case on a pipe.
    ///
    /// Locked, because two threads genuinely arrive here: the FileHandle's
    /// readability handler on its own queue, and the drain that runs when the
    /// process exits -- clearing a readability handler does not wait for a
    /// block already running in it. Unguarded, the append and the re-slice
    /// interleave, and the window is exactly process exit, which is when the
    /// final response to `session/prompt` arrives. A run that had completed
    /// would be reported as the agent having died, or the index arithmetic
    /// would trap.
    func receive(_ data: Data) {
        receiveLock.lock()
        defer { receiveLock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        guard !line.isEmpty,
              let frame = try? JSONDecoder().decode(AcpFrame.self, from: line)
        else {
            // A line we can't parse is the agent's problem, not a reason to
            // tear down a run that may still complete -- the TS client did the
            // same by ignoring malformed frames.
            return
        }

        if frame.isResponse, let id = frame.id?.numberValue.map({ Int($0) }) {
            let continuation = lock.withLock { pending.removeValue(forKey: id) }
            if let error = frame.error {
                continuation?.resume(returning: .failure(AcpError.agent(code: error.code, message: error.message)))
            } else {
                continuation?.resume(returning: .success(frame.result ?? .null))
            }
            return
        }

        if frame.isRequest, let id = frame.id, let method = frame.method {
            onRequest?(IncomingRequest(id: id, method: method, params: frame.params ?? .null))
            return
        }

        if frame.isNotification, let method = frame.method {
            onNotification?(method, frame.params ?? .null)
        }
    }

    // MARK: - Writing

    func request(method: String, params: JSONValue) async throws -> JSONValue {
        let id = lock.withLock { () -> Int in
            defer { nextRequestID += 1 }
            return nextRequestID
        }
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Result<JSONValue, Error>, Never>) in
            let closed = lock.withLock { () -> Error? in
                if let closeError { return closeError }
                pending[id] = continuation
                return nil
            }
            // The agent can die between `startAgent` and the first request --
            // a node process that throws at import time is gone in tens of
            // milliseconds. Registering after that put a continuation in a
            // dictionary that had already been drained, so nothing could ever
            // resume it and the caller waited forever.
            if let closed {
                continuation.resume(returning: .failure(closed))
                return
            }
            write(AcpOutgoing.request(id: id, method: method, params: params))
        }
        return try outcome.get()
    }

    func notify(method: String, params: JSONValue) {
        write(AcpOutgoing.notification(method: method, params: params))
    }

    func respond(to id: JSONValue, result: JSONValue) {
        write(AcpOutgoing.response(id: id, result: result))
    }

    private func write(_ value: JSONValue) {
        guard var data = try? JSONEncoder().encode(value) else { return }
        data.append(UInt8(ascii: "\n"))
        send(data)
    }

    /// Fails every in-flight request and closes the connection for good: an
    /// agent that has exited answers nothing, now or later, so every request
    /// from here on fails immediately instead of waiting out the tool's
    /// timeout. Called when the agent process dies.
    func failAllPending(with error: Error) {
        let continuations = lock.withLock { () -> [CheckedContinuation<Result<JSONValue, Error>, Never>] in
            closeError = closeError ?? error
            let all = Array(pending.values)
            pending.removeAll()
            return all
        }
        for continuation in continuations { continuation.resume(returning: .failure(error)) }
    }
}

enum AcpError: Error, Equatable {
    case agent(code: Int, message: String)
    /// The process exited before answering. `detail` carries the tail of its
    /// stderr, which is usually the only explanation there is.
    case processExited(detail: String)
    case cancelled
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
