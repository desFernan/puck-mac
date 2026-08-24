//
//  BridgeConnection.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  JSON Lines parsing/serialization, connection lifecycle management
//

import Foundation
import Network

/// Incrementally parses JSON Lines (newline-delimited JSON, protocol repo
/// section 2) from a byte stream that may arrive in arbitrarily-sized chunks.
/// Feed raw bytes via `feed(_:)`; it returns every complete, decodable message
/// found so far and buffers any trailing partial line for the next call.
/// Malformed lines are dropped (counted in `droppedLineCount`) without
/// breaking subsequent parsing. A line that never terminates and exceeds
/// `maxLineLength` is treated as abusive: the buffer is cleared and
/// `didOverflow` is reported so the caller can close the connection, instead
/// of letting a buggy/hostile client grow this buffer forever on a
/// long-lived, menu-bar-resident process.
struct JSONLinesDecoder {
    struct FeedResult {
        let messages: [BridgeMessage]
        let didOverflow: Bool
        /// How many lines this specific `feed()` call dropped -- distinct
        /// from `droppedLineCount`'s running total, so a caller can react
        /// (e.g. log) to a fresh drop without diffing the total itself.
        let droppedThisCall: Int
    }

    private var buffer = Data()
    private let decoder = JSONDecoder()
    private let maxLineLength: Int
    private(set) var droppedLineCount = 0

    init(maxLineLength: Int = 1_048_576) {
        self.maxLineLength = maxLineLength
    }

    mutating func feed(_ data: Data) -> FeedResult {
        buffer.append(data)

        var messages: [BridgeMessage] = []
        var droppedThisCall = 0
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty else { continue }
            if let message = try? decoder.decode(BridgeMessage.self, from: lineData) {
                messages.append(message)
            } else {
                droppedLineCount += 1
                droppedThisCall += 1
            }
        }

        guard buffer.count <= maxLineLength else {
            buffer.removeAll()
            return FeedResult(messages: messages, didOverflow: true, droppedThisCall: droppedThisCall)
        }
        return FeedResult(messages: messages, didOverflow: false, droppedThisCall: droppedThisCall)
    }
}

enum BridgeConnectionError: Error, Equatable {
    case encodingFailed
    /// One line over the limit the far side will accept -- see
    /// `BridgeConnection.maximumMessageBytes`.
    case messageTooLarge
}

/// Wraps a single NWConnection (one workspace client) and handles JSON Lines
/// framing on top of it via JSONLinesDecoder.
///
/// `@unchecked Sendable`: every stored property here is touched only from the
/// queue this connection was started on -- NWConnection delivers its state,
/// receive and send callbacks there, and `role`'s own note already spells out
/// that reading it anywhere else is a race over which process gets a message.
/// The promise is the queue, and it predates the annotation.
final class BridgeConnection: @unchecked Sendable {
    /// The largest line this will write, matching JSONLinesDecoder's own
    /// default ceiling for what it will read. One number for both directions,
    /// because the far side is another copy of this class.
    static let maximumMessageBytes = 1_048_576

    private let connection: NWConnection
    private var linesDecoder = JSONLinesDecoder()
    private var hasClosed = false

    /// Set once, from this connection's client_hello (protocol 3.7) --
    /// nil until then. BridgeServer uses it to decide which connections a
    /// given message relays to (ClientRelay.targetRole).
    ///
    /// Confined to BridgeServer's own queue, which is where client_hello is
    /// handled and where every reader has to do its filtering
    /// (`connections(playing:)`). Read from anywhere else it is a data race
    /// over which process gets the message.
    var role: ClientRole?

    /// Whether this connection presented the launch's handshake secret. Tools
    /// only run for connections that did: pet-app holds the Accessibility and
    /// Automation grants, and the approval prompt lives in the *client*, so a
    /// process that can dispatch a tool here runs it with Puck's privileges
    /// and no prompt at all.
    ///
    /// Queue-confined exactly like `role`, and for the same reason.
    var isAuthenticated = false

    var onMessage: ((BridgeMessage) -> Void)?
    /// Fires once the wrapped connection reaches .ready -- PuckClient's
    /// own outbound connection (2026-07-30) needs this to know when it's
    /// safe to send client_hello, which BridgeServer's accepted (server-side)
    /// connections never needed since they're only handed to onMessage/
    /// onClose once already open.
    var onReady: (() -> Void)?
    /// Fires exactly once per connection, regardless of whether the close was
    /// observed via stateUpdateHandler or the receive completion handler.
    var onClose: (() -> Void)?
    /// Fires when a message fails to encode, or the transport itself reports
    /// a send error — previously both were silently swallowed, leaving the
    /// agent side to time out with no diagnostic on our end.
    var onSendError: ((Error) -> Void)?
    /// Fires once per line JSONLinesDecoder drops -- droppedLineCount was
    /// previously only ever read by tests, so protocol drift or a hostile
    /// connection produced zero operational signal (found via review); the
    /// only symptom was a tool_result that never arrived, indistinguishable
    /// from "the tool is just slow" until ToolExecutor's own timeout.
    var onMalformedLine: (() -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.onReady?() }
            if Self.endsTheConnection(state) { self?.close() }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    /// - Returns: whether the message reached the socket. False means it was
    ///   refused here and there is nothing on the wire -- the caller has to
    ///   answer for it, because nothing else will. A `tool_dispatch` too big
    ///   to send used to be dropped silently while the caller was told it had
    ///   gone, and the tool then sat out its whole timeout waiting for a
    ///   reply nobody could send. A write that fails *after* this returns is
    ///   still reported through `onSendError` alone; by then the caller has
    ///   moved on.
    @discardableResult
    func send(_ message: BridgeMessage) -> Bool {
        // A local encoder, not a shared stored property: send() is called
        // from whatever queue each ToolHandler completes on (several hop to
        // their own background queue), so two in-flight tool_results on the
        // same connection could call encode() concurrently on one instance.
        guard var data = try? JSONEncoder().encode(message) else {
            onSendError?(BridgeConnectionError.encodingFailed)
            return false
        }
        // The same ceiling the reader enforces, applied to what we write.
        // Only one direction was capped, so a tool result big enough for the
        // far side to hang up on was still assembled, sent, and then dropped
        // there -- an error the sender never saw, on a line it had already
        // paid to encode.
        guard data.count <= Self.maximumMessageBytes else {
            onSendError?(BridgeConnectionError.messageTooLarge)
            return false
        }
        data.append(0x0A)
        connection.send(
            content: data,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.onSendError?(error)
                }
            }
        )
        return true
    }

    func cancel() {
        connection.cancel()
    }

    /// Which states mean this connection is over and the owner should retry.
    /// Pure so the classification is testable without a real socket, the same
    /// way BridgeServer.failureError(for:) is.
    ///
    /// `.waiting` counts (2026-08-15). NWConnection parks there when the peer
    /// is not listening yet -- connecting to a unix path with no socket file,
    /// which is exactly what PuckClient did when it won the race against
    /// pet-app binding bridge.sock. It does not leave `.waiting` on its own
    /// when the socket appears later, so treating it as "not closed" left the
    /// client parked forever: connected at the fd level, never sending
    /// client_hello, and invisible to the server, which then believed no gui
    /// was attached at all.
    static func endsTheConnection(_ state: NWConnection.State) -> Bool {
        switch state {
        case .cancelled, .failed, .waiting: return true
        case .setup, .preparing, .ready: return false
        @unknown default: return false
        }
    }

    private func close() {
        guard !hasClosed else { return }
        hasClosed = true
        // Cancel rather than just dropping the reference: a connection parked
        // in `.waiting` keeps its socket and its retries otherwise, and the
        // owner is about to start a fresh one.
        connection.cancel()
        onClose?()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let result = self.linesDecoder.feed(data)
                for message in result.messages {
                    self.onMessage?(message)
                }
                for _ in 0..<result.droppedThisCall {
                    self.onMalformedLine?()
                }
                if result.didOverflow {
                    self.cancel() // triggers stateUpdateHandler -> .cancelled -> close()
                    return
                }
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.receiveNext()
        }
    }
}
