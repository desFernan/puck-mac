//
//  LoopbackHTTPServer.swift
//  Puck
//
//  A single-purpose HTTP/1.1 listener for the MCP server the CLI provider
//  hands its coding agent. Network.framework, no dependency: what is needed is
//  one POST endpoint, and an HTTP stack for that is a package to keep updated.
//
//  ## This is a server on a user's machine, so:
//
//  - It binds to 127.0.0.1 only, over the loopback interface only. Nothing off
//    the machine can reach it even on a shared network.
//  - The port is the OS's choice, per instance. A fixed port would be a known
//    address for anything else on the machine to try.
//  - Every request must carry `Authorization: Bearer <token>` with the token
//    generated for *this* instance, compared in constant time. Reaching the
//    port is not access: a request without it gets 401 and nothing else, and
//    the body is never even parsed.
//  - The listener lives exactly as long as the turn that started it. `stop()`
//    is idempotent and the turn calls it on every exit path.
//

import Foundation
import Network
import Security

/// `@unchecked Sendable`: every stored property is read and written inside
/// `stateQueue`, which is what the type's own comments have said all along --
/// the annotation is that promise written where the compiler can see it. The
/// listener's callbacks arrive on `queue`, which is why the discipline exists.
final class LoopbackHTTPServer: @unchecked Sendable {
    /// Where the server ended up, and what it takes to talk to it.
    struct Endpoint: Equatable {
        let port: UInt16
        let token: String

        var url: String { "http://127.0.0.1:\(port)/mcp" }
        var authorizationHeaderValue: String { "Bearer \(token)" }
    }

    enum StartFailure: LocalizedError, Equatable {
        case listenerFailed(String)
        case noPort

        var errorDescription: String? {
            switch self {
            case .listenerFailed(let detail): return String(format: Strings.text(.mcpCouldNotOpenFormat), detail)
            case .noPort: return Strings.text(.mcpNoPort)
            }
        }
    }

    /// Answers one request body. nil means "accepted, nothing to say", which
    /// becomes a 202 with no content.
    typealias Handler = (Data) async -> Data?

    /// Bodies larger than this are refused unread. Nothing legitimate here is
    /// close to it -- a tools/call is a few hundred bytes -- and an unbounded
    /// read on a socket anything local can connect to is a memory bomb.
    static let maximumBodyBytes = 1 << 20

    private let handler: Handler
    private let queue = DispatchQueue(label: "com.speaki-e.puck.mcp.http")
    /// Guards the mutable state below. Deliberately *not* `queue`: that one
    /// runs the listener's and connections' callbacks, and `accept`/`forget`
    /// are called from it -- taking it synchronously from inside its own
    /// callback would deadlock. A queue rather than an NSLock because `start`
    /// is async, and NSLock is unavailable from async contexts (an error in
    /// the Swift 6 language mode).
    private let stateQueue = DispatchQueue(label: "com.speaki-e.puck.mcp.http.state")
    private var listener: NWListener?
    /// Held for as long as the socket is open. The session owns the escaping
    /// read/write closures, and nothing else refers to it -- dropped here it
    /// would be deallocated the moment `accept` returned, and every request on
    /// that socket would go unanswered.
    private var sessions: [ObjectIdentifier: HTTPConnection] = [:]
    private var isStopped = false
    private var endpoint: Endpoint?
    /// Minted before the listener opens, not after it is ready. `endpoint` is
    /// only complete once the OS has assigned a port, and a connection
    /// accepted before that read the token as "" -- against which a request
    /// carrying a bare `Authorization: Bearer ` authenticated. The window was
    /// short, but it was the whole listener, open to anything on the machine
    /// that found the port.
    private var tokenValue = ""

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    // MARK: - Lifecycle

    /// Opens the listener and returns once it is actually accepting. Throws
    /// rather than returning a half-open server: the caller has to put a
    /// reachable URL into `session/new`, and a URL for a port nothing is
    /// listening on would fail later, inside the agent, as an MCP error nobody
    /// can read.
    /// A loopback listener on an OS-chosen port is ready in milliseconds;
    /// this only exists so an unreachable state cannot stall a turn.
    private static let readyTimeout: TimeInterval = 5

    func start() async throws -> Endpoint {
        let token = Self.makeToken()
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Both, deliberately: the required endpoint decides what the socket is
        // bound to (127.0.0.1, never 0.0.0.0), the interface type decides what
        // it will accept.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        parameters.requiredInterfaceType = .loopback

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw StartFailure.listenerFailed(String(describing: error))
        }

        let accepted: Bool = stateQueue.sync {
            guard !isStopped else { return false }
            self.listener = listener
            self.tokenValue = token
            return true
        }
        guard accepted else {
            listener.cancel()
            throw StartFailure.listenerFailed("stopped before start")
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        let ready = ResumeOnce<Result<Void, Error>>()
        let outcome: Result<Void, Error> = await withCheckedContinuation { continuation in
            ready.arm(continuation)
            // Bounded, because `default: break` is a state machine we do not
            // own: NWListener can sit in `.waiting` (a port it cannot take
            // yet) without ever reaching `.ready` or `.failed`, and this await
            // has no other way out. A turn that hangs here shows "생각 중"
            // forever with nothing spawned and nothing logged. Failing instead
            // is safe -- the caller falls back to a text-only turn.
            queue.asyncAfter(deadline: .now() + Self.readyTimeout) {
                ready.resolve(.failure(StartFailure.listenerFailed("did not become ready in time")))
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    ready.resolve(.success(()))
                case .failed(let error):
                    ready.resolve(.failure(StartFailure.listenerFailed(String(describing: error))))
                case .cancelled:
                    ready.resolve(.failure(StartFailure.listenerFailed("cancelled")))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        do {
            try outcome.get()
        } catch {
            stop()
            throw error
        }

        guard let port = listener.port?.rawValue, port != 0 else {
            stop()
            throw StartFailure.noPort
        }
        let endpoint = Endpoint(port: port, token: token)
        stateQueue.sync { self.endpoint = endpoint }
        return endpoint
    }

    /// Closes the listener and every connection still open on it. Idempotent:
    /// the turn's success, failure, timeout and cancel paths all call it, and
    /// two of them can run.
    func stop() {
        // Torn down outside the lock: cancelling a listener and closing
        // sessions runs their callbacks, which come back through `accept`
        // and `forget`.
        let torn: (listener: NWListener?, sessions: [HTTPConnection])? = stateQueue.sync {
            guard !isStopped else { return nil }
            isStopped = true
            let listener = self.listener
            let sessions = Array(self.sessions.values)
            self.listener = nil
            self.sessions.removeAll()
            return (listener, sessions)
        }
        guard let torn else { return }

        torn.listener?.stateUpdateHandler = nil
        torn.listener?.newConnectionHandler = nil
        torn.listener?.cancel()
        for session in torn.sessions { session.close() }
    }

    deinit { stop() }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let session: HTTPConnection? = stateQueue.sync {
            guard !isStopped else { return nil }
            // An empty one would authenticate a bare "Bearer ", so there is
            // no connection to serve without it. Unreachable now that the
            // token is set before the listener opens; kept as the invariant.
            guard !tokenValue.isEmpty else { return nil }
            let session = HTTPConnection(
                connection: connection,
                token: tokenValue,
                handler: handler,
                onClose: { [weak self] in self?.forget(connection) }
            )
            sessions[ObjectIdentifier(connection)] = session
            return session
        }
        guard let session else {
            connection.cancel()
            return
        }

        session.start(on: queue)
    }

    private func forget(_ connection: NWConnection) {
        stateQueue.sync { _ = sessions.removeValue(forKey: ObjectIdentifier(connection)) }
    }

    // MARK: - Token

    /// 256 bits from the system CSPRNG, hex-encoded. Per instance, never
    /// stored: it exists for the lifetime of one turn's listener.
    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Compares without leaking where two tokens first differ. Length is
    /// compared up front, which is unavoidable and not secret.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count, !left.isEmpty else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}

/// Resumes a continuation exactly once, whichever state update gets there
/// first. NWListener reports `.failed` after `.ready` on a listener that dies,
/// and resuming twice traps.
/// `@unchecked` for the usual reason and with the usual justification: every
/// access to the two stored properties goes through `lock`, which the compiler
/// cannot see. Without it, arming this from a `@Sendable` closure warns.
/// `Value: Sendable` because it crosses: the value is produced on the
/// listener's queue and handed to a continuation awaiting on another.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var isDone = false

    func arm(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock(); self.continuation = continuation; lock.unlock()
    }

    func resolve(_ value: Value) {
        lock.lock()
        let waiting = isDone ? nil : continuation
        isDone = true
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }
}

/// One accepted connection: reads requests, authenticates them, and writes
/// answers. Persistent by default -- an MCP client sends initialize,
/// tools/list and every tool call down the same socket.
/// `@unchecked Sendable` for the same reason as the server above: one
/// connection's state is only touched from the queue its NWConnection
/// callbacks arrive on.
private final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let token: String
    private let handler: LoopbackHTTPServer.Handler
    private let onClose: () -> Void

    private var buffer = Data()
    private var isClosed = false

    init(
        connection: NWConnection,
        token: String,
        handler: @escaping LoopbackHTTPServer.Handler,
        onClose: @escaping () -> Void
    ) {
        self.connection = connection
        self.token = token
        self.handler = handler
        self.onClose = onClose
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                if self.buffer.count > LoopbackHTTPServer.maximumBodyBytes {
                    self.respond(status: 413, headers: [:], body: Data(), thenClose: true)
                    return
                }
                self.consume()
                return
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.receive()
        }
    }

    /// Parses whatever whole request is in the buffer. A chunk that ends
    /// mid-header or mid-body is normal on a socket, so anything short just
    /// goes back to reading.
    private func consume() {
        let separator = Data("\r\n\r\n".utf8)
        guard let headEnd = buffer.range(of: separator) else {
            receive()
            return
        }
        let head = String(decoding: buffer[buffer.startIndex..<headEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            respond(status: 400, headers: [:], body: Data(), thenClose: true)
            return
        }
        let method = requestLine.split(separator: " ").first.map(String.init) ?? ""
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        // Authentication before anything else is looked at -- including the
        // body, which used to be buffered in full first. Reaching the port
        // must buy nothing, and "nothing" has to include making this process
        // hold a megabyte for an unauthenticated caller.
        let presented = headers["authorization"] ?? ""
        guard LoopbackHTTPServer.constantTimeEquals(presented, "Bearer \(token)") else {
            respond(
                status: 401,
                headers: ["WWW-Authenticate": "Bearer"],
                body: Data(),
                thenClose: true
            )
            return
        }

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        // Negative as well as too large. A `Content-Length: -1` passed the
        // ceiling check, then indexed the buffer backwards from the body's
        // start -- a trap, which takes the whole app down with it, not just
        // this connection.
        guard contentLength >= 0 else {
            respond(status: 400, headers: [:], body: Data(), thenClose: true)
            return
        }
        guard contentLength <= LoopbackHTTPServer.maximumBodyBytes else {
            respond(status: 413, headers: [:], body: Data(), thenClose: true)
            return
        }
        let bodyStart = headEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= contentLength else {
            receive()
            return
        }
        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = Data(buffer[bodyStart..<bodyEnd])
        buffer = Data(buffer[bodyEnd...])

        let wantsClose = headers["connection"]?.lowercased() == "close"

        guard method == "POST" else {
            // GET is the client asking to open a server-initiated SSE stream
            // and DELETE is it ending a session; this server has neither, and
            // the MCP spec has the client carry on when they are refused.
            respond(status: 405, headers: ["Allow": "POST"], body: Data(), thenClose: wantsClose)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard let answer = await self.handler(body) else {
                self.respond(status: 202, headers: [:], body: Data(), thenClose: wantsClose)
                return
            }
            self.respond(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: answer,
                thenClose: wantsClose
            )
        }
    }

    private func respond(status: Int, headers: [String: String], body: Data, thenClose: Bool) {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        head += "Content-Length: \(body.count)\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += thenClose ? "Connection: close\r\n" : "Connection: keep-alive\r\n"
        head += "\r\n"

        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            guard let self, !self.isClosed else { return }
            if thenClose {
                self.close()
            } else {
                // Whatever arrived behind this request is already buffered.
                self.consume()
            }
        })
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose()
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "Error"
        }
    }
}
