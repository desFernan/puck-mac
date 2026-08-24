//
//  BridgeServer.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Network.framework NWListener(UDS) at ~/Library/Application Support/Puck/bridge.sock
//

import Foundation
import Network

enum BridgeServerError: Error, Equatable {
    /// Another pet-app process already holds this socket (its lock file names
    /// a still-alive PID). Refuse to steal the socket out from under it.
    case alreadyRunning
}

/// Runs the JSON Lines Unix-domain-socket server pet-app exposes to workspace
/// (protocol repo section 2: "서버: pet-app (NWListener)"). workspace connects
/// as a client and reconnects with exponential backoff on its own; pet-app's
/// job is just to accept connections and stay a pure pet when none are open.
final class BridgeServer {
    static let defaultSocketURL: URL = BridgeSocketPath.default

    /// All access to `connections` (reads and writes) must go through `queue` —
    /// accept()/per-connection onClose already run there; `stop()` and any
    /// external read are the ones that must explicitly hop onto it too.
    private var connections: [BridgeConnection] = []
    private var listener: NWListener?
    private let socketURL: URL
    /// This launch's handshake secret, rotated by `start()`. Held rather than
    /// read per message so a client cannot be let in by a file written after
    /// it connected.
    private var handshakeSecret: String?
    /// Fires when a connection that has not authenticated sends anything but
    /// a hello -- worth logging, since the only thing that does it is a
    /// process that should not be there.
    var onUnauthenticatedMessage: ((BridgeMessage) -> Void)?
    private var lockFileURL: URL { socketURL.appendingPathExtension("lock") }
    private let queue = DispatchQueue(label: "Puck.BridgeServer")

    /// Called for every message from any connected client, along with which
    /// connection it came from (so a reply can be sent back to that client).
    var onMessage: ((BridgeMessage, BridgeConnection) -> Void)?

    /// Called if the listener fails to bind/listen, or drops into `.waiting`
    /// (e.g. permission denied) — NWListener reports these asynchronously via
    /// stateUpdateHandler; a successful `start()` return does NOT mean the
    /// socket is actually listening yet.
    var onFailure: ((Error) -> Void)?

    /// Forwarded from BridgeConnection.onMalformedLine -- a dropped line
    /// otherwise produced zero operational signal, indistinguishable from
    /// "the tool is just slow" until ToolExecutor's own timeout (found via
    /// review).
    var onMalformedLine: (() -> Void)?

    /// Fires when the number of gui-role connections transitions between
    /// zero and non-zero -- true on the first one connecting, false once the
    /// last one disconnects (protocol 3.7, 2026-07-30). NOT wired to
    /// pin/unpin the character: PuckClient is a Dock-resident app
    /// expected to stay running continuously, so tying the pin to "is a gui connected" would freeze
    /// the pet in place for as long as PuckClient is alive, not just
    /// while its window is actually being used. Pin/unpin stays with the
    /// local, in-process quick-capture bubble (Option+Shift+Space), which
    /// is the one truly momentary interaction pet-app can observe directly.
    var onGUIPresenceChanged: ((Bool) -> Void)?
    private var lastGUIPresence = false
    /// Open for as long as this process is the one serving the socket. See
    /// `acquireLock`.
    private var lockDescriptor: Int32 = -1

    init(socketURL: URL = BridgeServer.defaultSocketURL) {
        self.socketURL = socketURL
    }

    func start() throws {
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let lock = Self.acquireLock(at: lockFileURL) else {
            throw BridgeServerError.alreadyRunning
        }
        lockDescriptor = lock
        try? FileManager.default.removeItem(at: socketURL) // stale socket file from a previous (now-dead) run

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: socketURL.path)

        // Written only once NWListener construction has actually succeeded --
        // writing it earlier meant a throw here left a lock file naming this
        // still-alive process, permanently blocking every later start() call
        // in the same process with a false alreadyRunning.
        // Before binding, not after: NWListener creates the socket with the
        // process umask and the mode is only tightened once the listener
        // reaches .ready, which leaves a window where anything running as
        // another local user can connect. A directory nobody else can enter
        // closes the window rather than racing it.
        restrictSocketDirectoryPermissions()
        // Before the listener, not after: a client that connects between the
        // two would otherwise be checked against a secret that does not exist
        // yet, and "no secret" must never read as "any secret".
        handshakeSecret = BridgeHandshakeSecret.rotate(at: BridgeHandshakeSecret.fileURL(besideSocketAt: socketURL))
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            // The lock outlives a failed start otherwise, and this process
            // then refuses its own next attempt.
            releaseLock()
            throw error
        }
        listener.newConnectionHandler = { [weak self] newConnection in
            self?.accept(newConnection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.restrictSocketPermissions()
            }
            if let error = Self.failureError(for: state) {
                self?.onFailure?(error)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
        // NWListener.cancel() does not unlink the bound path, so the socket
        // file outlives the process unless removed here. start() also clears a
        // stale one, but only the *next* launch gets there — without this a
        // dead endpoint sits in Application Support after every quit, and a
        // client can connect to a path nothing is listening on.
        try? FileManager.default.removeItem(at: socketURL)
        releaseLock()
    }

    /// Sends to just the connections playing `role`, and reports whether
    /// there were any. Used to mirror the quick-capture bubble's text into
    /// PuckClient's chat view (2026-07-30).
    ///
    /// Same constraint as `currentConnections()`: never call this from
    /// `queue` (i.e. not from inside `onMessage`/`onGUIPresenceChanged`).
    @discardableResult
    func send(_ message: BridgeMessage, to role: ClientRole) -> Bool {
        let targets = connections(playing: role)
        targets.forEach { $0.send(message) }
        return !targets.isEmpty
    }

    /// Connections playing `role`, chosen on `queue`.
    ///
    /// The filtering has to happen inside the lock, not outside it: `role` is
    /// written on `queue` when a client_hello arrives, so a snapshot of the
    /// array taken under the lock and then filtered on the caller's thread
    /// reads that property with no synchronisation at all -- and the answer
    /// decides which process a message is delivered to.
    private func connections(playing role: ClientRole) -> [BridgeConnection] {
        queue.sync { connections.filter { $0.isAuthenticated && $0.role == role } }
    }

    /// Thread-safe snapshot of currently-open connections.
    ///
    /// Uses `queue.sync`, so it must not be called from `queue` itself — i.e.
    /// never from inside an `onMessage` handler, which is delivered there.
    func currentConnections() -> [BridgeConnection] {
        queue.sync { connections }
    }

    private func accept(_ nwConnection: NWConnection) {
        // Runs on `queue` (newConnectionHandler fires on the queue passed to
        // listener.start), same as onClose below — safe to mutate directly.
        let connection = BridgeConnection(connection: nwConnection)
        connection.onMessage = { [weak self, weak connection] message in
            guard let self, let connection else { return }
            if case .clientHello(let role, let token) = message {
                connection.role = role
                connection.isAuthenticated = BridgeHandshakeSecret.matches(token, expected: self.handshakeSecret)
                self.updateGUIPresence()
                return
            }
            // Everything a tool can do, pet-app does with its own privileges.
            // A connection that never proved it is the client we launched
            // gets to say hello and nothing else.
            guard connection.isAuthenticated else {
                self.onUnauthenticatedMessage?(message)
                return
            }
            self.relay(message, from: connection)
            self.onMessage?(message, connection)
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.connections.removeAll { $0 === connection }
            self.updateGUIPresence()
        }
        connection.onMalformedLine = { [weak self] in self?.onMalformedLine?() }
        connections.append(connection)
        connection.start(queue: queue)
    }

    /// Forwards a message to every currently-connected role it's addressed
    /// to (protocol 3.7) -- pet-app relays rather than handling everything
    /// in-process now that the gui side can be a separate process
    /// (PuckClient) from workspace.
    private func relay(_ message: BridgeMessage, from origin: BridgeConnection) {
        guard let targetRole = ClientRelay.targetRole(for: message) else { return }
        // Back to the sender too, deliberately. PuckClient hosts the agent and
        // draws the chat, and the two halves talk to each other through here:
        // a run's events are broadcast once and arrive back at the same
        // process, which is what moves the transcript on. Excluding the origin
        // left every turn running to completion with the chat still spinning.
        for connection in connections
        where connection.isAuthenticated && connection.role == targetRole {
            connection.send(message)
        }
    }

    /// Runs on `queue`, same as accept()/onClose -- only fires
    /// onGUIPresenceChanged on an actual zero<->non-zero transition, not
    /// every connect/disconnect (multiple gui connections are possible in
    /// principle, even if only one PuckClient is expected in practice).
    private func updateGUIPresence() {
        let hasGUI = connections.contains { $0.isAuthenticated && $0.role == .gui }
        guard hasGUI != lastGUIPresence else { return }
        lastGUIPresence = hasGUI
        onGUIPresenceChanged?(hasGUI)
    }

    // MARK: - Listener failure mapping (pure, testable independent of real bind failures)

    static func failureError(for state: NWListener.State) -> Error? {
        switch state {
        case .failed(let error), .waiting(let error):
            return error
        default:
            return nil
        }
    }

    // MARK: - Single-instance guard

    /// Takes an exclusive advisory lock on `lockFileURL`, or reports that
    /// someone else holds it.
    ///
    /// This used to read a PID out of the file and ask `kill(pid, 0)` whether
    /// it was alive. A pet-app that crashed left the file behind, and once the
    /// OS recycled that number onto any unrelated process -- which it does,
    /// PIDs wrap -- the answer became "still running" and the app refused to
    /// start, permanently, with nothing on screen naming the file to delete.
    ///
    /// The kernel releases a `flock` when the process holding it dies, however
    /// it dies, so a stale file is just a file. The PID is still written into
    /// it, now only for whoever is reading the directory by hand.
    static func acquireLock(at url: URL) -> Int32? {
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        ftruncate(descriptor, 0)
        let pid = Array(String(ProcessInfo.processInfo.processIdentifier).utf8)
        _ = pid.withUnsafeBufferPointer { write(descriptor, $0.baseAddress, $0.count) }
        return descriptor
    }

    /// Drops the lock and takes the file with it. Called from `stop()` and
    /// from the failure paths of `start()`; safe to call without one held.
    private func releaseLock() {
        guard lockDescriptor >= 0 else { return }
        flock(lockDescriptor, LOCK_UN)
        close(lockDescriptor)
        lockDescriptor = -1
        try? FileManager.default.removeItem(at: lockFileURL)
    }

    /// The socket had no peer authentication and default permissions
    /// (srwxr-xr-x) -- any other local-user-owned process could connect and
    /// dispatch run_shell/run_applescript, bypassing ai-module's upstream
    /// approval UI entirely (found via review). Restricting to owner-only
    /// read/write at least closes it off to every other local account.
    /// Owner-only on the directory the socket lives in. Belt and braces with
    /// `restrictSocketPermissions`, and the half that holds during the moment
    /// between bind and .ready.
    private func restrictSocketDirectoryPermissions() {
        let directory = socketURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func restrictSocketPermissions() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: socketURL.path)
    }
}

// MARK: - UserInputTransport

extension BridgeServer: UserInputTransport {
    /// Read live rather than remembered: BridgeConnection.onClose removes a
    /// connection as soon as the transport reports it gone, so this flips to
    /// false the moment the client goes away.
    ///
    /// This counted *non*-gui connections until 2026-08-15, because the thing
    /// that acted on user input was workspace and PuckClient was only a chat
    /// view. Deleting workspace inverted that: PuckClient hosts the agent now,
    /// so it is the only connection that can act on anything, and counting
    /// anything else would report the pet's bubble as delivered into a void.
    var hasConnectedClients: Bool {
        !agentFacingConnections().isEmpty
    }

    /// One PuckClient is expected, but sending to every gui connection keeps
    /// this correct if a second one ever attaches (and costs nothing when
    /// there is one).
    ///
    /// Returns whether there was anyone to send to, queried fresh at this
    /// exact call -- a caller that pre-checked `hasConnectedClients` earlier
    /// can still race a disconnect landing in between (BridgeConnection.onClose
    /// runs on this same queue), so the true answer is decided here, not there.
    @discardableResult
    func broadcast(_ message: BridgeMessage) -> Bool {
        let connections = agentFacingConnections()
        connections.forEach { $0.send(message) }
        return !connections.isEmpty
    }

    /// Connections that can act on user input -- gui ones, which is all that
    /// is left. A connection that has not sent client_hello yet has no role
    /// and does not count: it may never identify itself at all. Neither does
    /// one whose hello carried the wrong secret -- what goes out this way is
    /// the conversation itself, so an unproved listener is not given it.
    private func agentFacingConnections() -> [BridgeConnection] {
        connections(playing: .gui)
    }
}
