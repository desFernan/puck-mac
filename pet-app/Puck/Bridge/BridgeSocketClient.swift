//
//  BridgeSocketClient.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  PuckClient's own connection to bridge.sock (2026-07-30) -- unlike
//  BridgeServer (which pet-app hosts), this is the client side: it dials
//  out, announces role .gui (protocol 3.7) once ready, and reconnects with
//  the same exponential backoff (1s -> 2s -> 4s, capped at 30s) documented
//  for workspace's own client behavior.
//

import Foundation
import Network

/// `@unchecked Sendable`: every mutable field is read and written on
/// `queue` and nowhere else, which is also what the reconnect timer and the
/// connection callbacks below rely on. The compiler cannot see a serial
/// queue as an isolation boundary; the code has treated it as one since it
/// was written.
final class BridgeSocketClient: @unchecked Sendable {
    /// Fires for every message the server relays to this connection
    /// (protocol 3.7 -- events, workspace_create, session_create,
    /// editor_view_ready, editor_view_unavailable).
    var onMessage: ((BridgeMessage) -> Void)?

    /// The connection dropped. Reconnection is handled here and needs no
    /// help, but anything waiting on a reply does: a tool_dispatch already on
    /// the wire can never be answered, because BridgeServer's relay sends
    /// replies back on the connection that received the dispatch and that
    /// connection is gone. Reconnecting does not recover it. Without this the
    /// dispatch waited out its full registry timeout -- 60s for run_shell --
    /// and reported "timeout" instead of "pet_app_disconnected".
    ///
    /// Fires on every drop, including the ones retried during startup before
    /// pet-app is up. That is harmless: failing nothing is a no-op.
    var onDisconnect: (() -> Void)?

    /// Fires once the socket is up and this client has announced itself --
    /// on the first connection and on every reconnection after.
    ///
    /// Reconnecting is not the same as starting: pet-app forgets the tank
    /// when the socket drops, and the client only reports it when it changes,
    /// so nothing would have told the pet where to live again. It stayed on
    /// the desktop until the window happened to be resized.
    var onConnect: (() -> Void)?

    private let socketURL: URL
    private let queue = DispatchQueue(label: "PuckClient.BridgeSocketClient")
    private var connection: BridgeConnection?
    /// Whether the connection has reached `.ready`. Distinct from having a
    /// connection object: a send before that is a send into something that
    /// may never open, and reporting it as delivered is how a message goes
    /// missing with the UI saying it was sent.
    private var isReady = false
    private var reconnectDelay: TimeInterval = 1
    private let maxReconnectDelay: TimeInterval = 30

    init(socketURL: URL = BridgeSocketPath.default) {
        self.socketURL = socketURL
    }

    func start() {
        queue.async { [weak self] in self?.connect() }
    }

    private func connect() {
        let nwConnection = NWConnection(to: .unix(path: socketURL.path), using: .tcp)
        let bridgeConnection = BridgeConnection(connection: nwConnection)
        bridgeConnection.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
        let secretURL = BridgeHandshakeSecret.fileURL(besideSocketAt: socketURL)
        bridgeConnection.onReady = { [weak self, weak bridgeConnection] in
            self?.reconnectDelay = 1
            self?.isReady = true
            // Read at connect time rather than cached: pet-app rotates it on
            // every start, and this client reconnects across those restarts.
            bridgeConnection?.send(
                .clientHello(
                    role: .gui,
                    // The secret beside *this* socket: a client pointed at a
                    // second bridge must present that bridge's token, not the
                    // default one.
                    token: BridgeHandshakeSecret.current(at: secretURL)
                )
            )
            self?.onConnect?()
        }
        bridgeConnection.onClose = { [weak self] in
            self?.isReady = false
            self?.onDisconnect?()
            self?.scheduleReconnect()
        }
        connection = bridgeConnection
        bridgeConnection.start(queue: queue)
    }

    private func scheduleReconnect() {
        connection = nil
        isReady = false
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }
}

extension BridgeSocketClient: UserInputTransport {
    // Uses queue.sync, same caveat as BridgeServer.currentConnections() --
    // must not be called from `queue` itself (never from inside onMessage,
    // which BridgeConnection delivers there).
    var hasConnectedClients: Bool {
        queue.sync { connection != nil && isReady }
    }

    @discardableResult
    func broadcast(_ message: BridgeMessage) -> Bool {
        queue.sync {
            guard let connection, isReady else { return false }
            // The connection's own answer, not an assumption: a message it
            // refuses (too large to frame, or one that will not encode) never
            // reaches the socket, and reporting that as sent is what left a
            // tool dispatch waiting out its whole timeout for a reply that
            // was never asked for.
            return connection.send(message)
        }
    }
}
