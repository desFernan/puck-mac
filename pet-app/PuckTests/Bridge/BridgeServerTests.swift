//
//  BridgeServerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  End-to-end test over a real Unix domain socket (no mocks): starts a
//  BridgeServer on a temp path, connects a bare NWConnection client, and
//  verifies messages flow both ways.
//

import XCTest
import Network
@testable import Puck

final class BridgeServerTests: XCTestCase {
    private var socketURL: URL!
    private var server: BridgeServer!

    override func setUpWithError() throws {
        socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("bridge.sock")
        server = BridgeServer(socketURL: socketURL)
        try server.start()
    }

    override func tearDown() {
        server.stop()
        try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
    }

    /// The hello a client pet-app launched would send, with this server's own
    /// secret.
    private func sendAuthenticatedHello(on client: NWConnection) {
        let secret = BridgeHandshakeSecret.current(
            at: BridgeHandshakeSecret.fileURL(besideSocketAt: socketURL)
        )
        send(.clientHello(role: .gui, token: secret), on: client)
    }

    private func makeClient() -> NWConnection {
        NWConnection(to: .unix(path: socketURL.path), using: .tcp)
    }

    func test_serverReceivesMessageSentByClient() {
        let received = expectation(description: "server received the client's message")
        server.onMessage = { message, _ in
            guard case .userInput(let input) = message else { return }
            XCTAssertEqual(input.text, "hello")
            received.fulfill()
        }

        let client = makeClient()
        client.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                // Anything but a hello needs the handshake first now: pet-app
                // runs tools with its own privileges, so an unauthenticated
                // connection gets to say hello and nothing else.
                self?.sendAuthenticatedHello(on: client)
                var data = try! JSONEncoder().encode(BridgeMessage.userInput(UserInput(text: "hello", source: .text)))
                data.append(0x0A)
                client.send(content: data, completion: .contentProcessed { _ in })
            }
        }
        client.start(queue: .main)

        wait(for: [received], timeout: 5)
        client.cancel()
    }

    func test_clientReceivesReplySentThroughAcceptedConnection() {
        let clientReceived = expectation(description: "client received the server's reply")
        server.onMessage = { _, connection in
            connection.send(.toolResult(ToolResult(id: "t1", ok: true, data: nil, error: nil)))
        }

        let client = makeClient()
        var buffer = Data()
        client.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.sendAuthenticatedHello(on: client)
                var data = try! JSONEncoder().encode(BridgeMessage.userInput(UserInput(text: "ping", source: .text)))
                data.append(0x0A)
                client.send(content: data, completion: .contentProcessed { _ in })
            }
        }

        // Line by line, and looking for one message among several: the relay
        // sends this connection's own user_input back to it (see
        // test_event_comesBackToTheGUIConnectionThatSentIt), so the reply is
        // not the only thing on the wire and the buffer is not one message.
        func receiveLoop() {
            client.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                if let data { buffer.append(data) }
                while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<newlineIndex]
                    buffer.removeSubrange(...newlineIndex)
                    guard let message = try? JSONDecoder().decode(BridgeMessage.self, from: line),
                          case .toolResult(let result) = message
                    else { continue }
                    XCTAssertTrue(result.ok)
                    clientReceived.fulfill()
                    return
                }
                receiveLoop()
            }
        }
        receiveLoop()
        client.start(queue: .main)

        wait(for: [clientReceived], timeout: 5)
        client.cancel()
    }

    /// The real defect behind the stale-connection bug: AppDelegate cached a
    /// BridgeConnection forever, so it had no way to notice a disconnect.
    /// hasConnectedClients must track the live socket, not a remembered one.
    /// The client identifies itself first: since 2026-08-15 only a gui-role
    /// connection counts (it is the one that hosts the agent), and a
    /// connection that has not said client_hello yet has no role at all.
    func test_hasConnectedClients_followsTheClientLifecycle() {
        XCTAssertFalse(server.hasConnectedClients, "no client has connected yet")

        let client = makeClient()
        let connected = expectation(description: "server saw the client")
        server.onMessage = { _, _ in connected.fulfill() }
        client.stateUpdateHandler = { state in
            if case .ready = state {
                self.sendAuthenticatedHello(on: client)
                var data = try! JSONEncoder().encode(BridgeMessage.userInput(UserInput(text: "hi", source: .text)))
                data.append(0x0A)
                client.send(content: data, completion: .contentProcessed { _ in })
            }
        }
        client.start(queue: .main)
        wait(for: [connected], timeout: 5)
        XCTAssertTrue(server.hasConnectedClients)

        client.cancel()

        let disconnected = expectation(description: "server dropped the closed connection")
        pollUntilTrue(timeout: 5, expectation: disconnected) { !self.server.hasConnectedClients }
        wait(for: [disconnected], timeout: 6)
    }

    /// droppedLineCount was previously only ever read by JSONLinesDecoderTests
    /// -- nothing surfaced a drop happening on a live connection, so protocol
    /// drift or a hostile client produced zero operational signal (found via
    /// review).
    func test_onMalformedLine_firesWhenAClientSendsAnUndecodableLine() {
        let malformed = expectation(description: "server reported the malformed line")
        server.onMalformedLine = { malformed.fulfill() }

        let client = makeClient()
        client.stateUpdateHandler = { state in
            if case .ready = state {
                let data = Data("not json\n".utf8)
                client.send(content: data, completion: .contentProcessed { _ in })
            }
        }
        client.start(queue: .main)

        wait(for: [malformed], timeout: 5)
        client.cancel()
    }

    // The socket had no peer authentication and default permissions
    // (srwxr-xr-x) -- any other process running as the same local user could
    // connect and dispatch run_shell/run_applescript, bypassing ai-module's
    // upstream approval UI entirely (found via review). Restricting to owner
    // read/write closes that off for every other local user account at
    // least, even though same-user processes are still trusted by design.
    func test_socketFile_isNotAccessibleToOtherUsers() {
        let ready = expectation(description: "socket file exists with its final permissions")
        pollUntilTrue(timeout: 5, expectation: ready) {
            FileManager.default.fileExists(atPath: self.socketURL.path)
        }
        wait(for: [ready], timeout: 6)

        let attributes = try? FileManager.default.attributesOfItem(atPath: socketURL.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(permissions, 0o600)
    }

    // MARK: - Client role handshake + relay (protocol 3.7, 2026-07-30)
    //
    // The F13 client window moved out of pet-app's own process into
    // PuckClient, so bridge.sock now has two roles connected at once and
    // pet-app has to relay between them rather than just handling everything
    // itself in-process.

    private func send(_ message: BridgeMessage, on client: NWConnection) {
        var data = try! JSONEncoder().encode(message)
        data.append(0x0A)
        client.send(content: data, completion: .contentProcessed { _ in })
    }

    private final class ReceiveBuffer {
        var data = Data()
    }

    private func receiveOne(on client: NWConnection, into buffer: ReceiveBuffer, then handle: @escaping (BridgeMessage) -> Void) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
            if let data { buffer.data.append(data) }
            if let newlineIndex = buffer.data.firstIndex(of: 0x0A) {
                let line = buffer.data[..<newlineIndex]
                buffer.data.removeSubrange(...newlineIndex)
                if let message = try? JSONDecoder().decode(BridgeMessage.self, from: line) {
                    handle(message)
                    return
                }
            }
            self.receiveOne(on: client, into: buffer, then: handle)
        }
    }

    /// Was gui -> workspace; user_input's target flipped to gui on 2026-08-15,
    /// when PuckClient became the process that runs the agent. Two gui clients
    /// stand in for "the pet's bubble sent this, the chat window ran it".
    func test_userInput_relaysToGUIConnections() {
        let workspaceReceived = expectation(description: "the second gui connection received the relayed message")

        let workspaceClient = makeClient()
        let guiClient = makeClient()
        let workspaceBuffer = ReceiveBuffer()

        workspaceClient.stateUpdateHandler = { state in
            if case .ready = state { self.sendAuthenticatedHello(on: workspaceClient) }
        }
        guiClient.stateUpdateHandler = { state in
            if case .ready = state {
                self.sendAuthenticatedHello(on: guiClient)
            }
        }
        receiveOne(on: workspaceClient, into: workspaceBuffer) { message in
            guard case .userInput(let input) = message else { return }
            XCTAssertEqual(input.text, "hi")
            workspaceReceived.fulfill()
        }

        workspaceClient.start(queue: .main)
        guiClient.start(queue: .main)

        // A ready client has only connected to the socket; the server may not
        // have consumed its role handshake yet. Wait until both handshakes are
        // registered before sending the message whose routing depends on that
        // role, otherwise this test races the server queue under load.
        let bothRegistered = expectation(description: "both gui roles are registered")
        pollUntilTrue(timeout: 5, expectation: bothRegistered) {
            self.server.currentConnections().filter { $0.role == .gui }.count == 2
        }
        wait(for: [bothRegistered], timeout: 6)
        send(.userInput(UserInput(text: "hi", source: .text)), on: guiClient)

        wait(for: [workspaceReceived], timeout: 5)
        workspaceClient.cancel()
        guiClient.cancel()
    }

    func test_event_relaysToTheGUIConnection() {
        let guiReceived = expectation(description: "gui connection received the relayed event")

        let workspaceClient = makeClient()
        let guiClient = makeClient()
        let guiBuffer = ReceiveBuffer()

        guiClient.stateUpdateHandler = { state in
            if case .ready = state { self.sendAuthenticatedHello(on: guiClient) }
        }
        workspaceClient.stateUpdateHandler = { state in
            if case .ready = state {
                self.sendAuthenticatedHello(on: workspaceClient)
                self.send(.event(.agentThinking, workspaceId: "w1", sessionId: "s1"), on: workspaceClient)
            }
        }
        receiveOne(on: guiClient, into: guiBuffer) { message in
            guard case .event(let event, let workspaceId, let sessionId) = message else { return }
            XCTAssertEqual(event, .agentThinking)
            XCTAssertEqual(workspaceId, "w1")
            XCTAssertEqual(sessionId, "s1")
            guiReceived.fulfill()
        }

        guiClient.start(queue: .main)
        workspaceClient.start(queue: .main)

        wait(for: [guiReceived], timeout: 5)
        workspaceClient.cancel()
        guiClient.cancel()
    }

    /// PuckClient hosts the agent *and* draws the chat, and the two halves
    /// only meet through here: a run broadcasts its events once and the
    /// transcript moves when they come back. So the relay has to deliver a
    /// gui-addressed message to the gui connection that sent it. Excluding
    /// the origin -- which looks harmless, and is what a relay usually does
    /// -- left every turn finishing with the chat still spinning.
    func test_event_comesBackToTheGUIConnectionThatSentIt() {
        let bounced = expectation(description: "the sending gui connection received its own event back")

        let guiClient = makeClient()
        let guiBuffer = ReceiveBuffer()
        guiClient.stateUpdateHandler = { state in
            if case .ready = state {
                self.sendAuthenticatedHello(on: guiClient)
                self.send(.event(.agentDone(ok: true, summary: "done"), workspaceId: "w1", sessionId: "s1"), on: guiClient)
            }
        }
        receiveOne(on: guiClient, into: guiBuffer) { message in
            guard case .event(let event, _, let sessionId) = message else { return }
            XCTAssertEqual(event, .agentDone(ok: true, summary: "done"))
            XCTAssertEqual(sessionId, "s1")
            bounced.fulfill()
        }

        guiClient.start(queue: .main)

        wait(for: [bounced], timeout: 5)
        guiClient.cancel()
    }

    /// The quick-capture bubble's text is mirrored to PuckClient with
    /// Inverted on 2026-08-15. A gui connection used to be excluded from
    /// broadcast() and from hasConnectedClients, because the process that
    /// could act on user input was workspace and PuckClient was only a view.
    /// With workspace deleted, PuckClient hosts the agent, so it is the only
    /// thing broadcast() can reach -- and F6's offline bubble now means "the
    /// chat window is closed" rather than "workspace is down".
    func test_guiConnectionIsWhatBroadcastReaches() {
        let guiReceived = expectation(description: "gui connection received the mirrored user_input")
        let guiPresent = expectation(description: "server registered the gui role")
        server.onGUIPresenceChanged = { present in if present { guiPresent.fulfill() } }

        let guiClient = makeClient()
        let guiBuffer = ReceiveBuffer()
        guiClient.stateUpdateHandler = { state in
            if case .ready = state { self.sendAuthenticatedHello(on: guiClient) }
        }
        receiveOne(on: guiClient, into: guiBuffer) { message in
            guard case .userInput(let input) = message else { return }
            XCTAssertEqual(input.text, "사파리 켜줘")
            guiReceived.fulfill()
        }
        guiClient.start(queue: .main)
        wait(for: [guiPresent], timeout: 5)

        XCTAssertTrue(server.hasConnectedClients, "the gui client is the one that runs the agent now")
        XCTAssertTrue(
            server.broadcast(.userInput(UserInput(text: "사파리 켜줘", source: .text))),
            "the pet's bubble and push-to-talk reach the agent through exactly this"
        )

        wait(for: [guiReceived], timeout: 5)
        guiClient.cancel()
    }

    /// AppDelegate uses this to flush a mirrored bubble submission that had
    /// nowhere to go yet, once PuckClient (which it launched a moment
    /// earlier) finishes connecting.
    func test_onGUIPresenceChanged_firesOnFirstConnectAndLastDisconnect() {
        var presenceEvents: [Bool] = []
        let connected = expectation(description: "gui presence became true")
        let disconnected = expectation(description: "gui presence became false")
        server.onGUIPresenceChanged = { present in
            presenceEvents.append(present)
            if present { connected.fulfill() } else { disconnected.fulfill() }
        }

        let guiClient = makeClient()
        guiClient.stateUpdateHandler = { state in
            if case .ready = state { self.sendAuthenticatedHello(on: guiClient) }
        }
        guiClient.start(queue: .main)

        wait(for: [connected], timeout: 5)
        XCTAssertEqual(presenceEvents, [true])

        guiClient.cancel()
        wait(for: [disconnected], timeout: 5)
        XCTAssertEqual(presenceEvents, [true, false])
    }

    private func pollUntilTrue(timeout: TimeInterval, expectation: XCTestExpectation, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() {
                expectation.fulfill()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
    }

    /// The socket is created by NWListener with the process umask and only
    /// tightened once the listener is ready, so the directory has to be shut
    /// before it is bound -- otherwise there is a window in which another
    /// local user can connect and dispatch tools.
    func test_theSocketsDirectoryIsOwnerOnly() throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("bridge.sock")
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        let attributes = try FileManager.default.attributesOfItem(
            atPath: socketURL.deletingLastPathComponent().path
        )

        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o700)
    }

    /// pet-app holds the Accessibility and Automation grants, and the approval
    /// prompt lives in the *client* -- so anything that can put a
    /// `tool_dispatch` on this socket runs a shell command with Puck's
    /// privileges and no prompt. The socket's 0600 mode keeps out other
    /// accounts; it does not keep out another process running as the same
    /// person, and the path is not a secret.
    func test_aConnectionThatDidNotAuthenticateCannotDispatchATool() {
        let refused = expectation(description: "the dispatch was refused")
        var executed = false
        server.onMessage = { message, _ in
            if case .toolDispatch = message { executed = true }
        }
        server.onUnauthenticatedMessage = { message in
            if case .toolDispatch = message { refused.fulfill() }
        }

        let client = NWConnection(to: .unix(path: socketURL.path), using: .tcp)
        client.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let self else { return }
            // A hello with the wrong secret, then the thing it wanted.
            self.send(.clientHello(role: .gui, token: "not-the-secret"), on: client)
            self.send(
                .toolDispatch(ToolDispatch(id: "1", tool: "run_shell", args: .object(["command": .string("id")]))),
                on: client
            )
        }
        client.start(queue: .main)
        defer { client.cancel() }

        wait(for: [refused], timeout: 3)
        XCTAssertFalse(executed, "and it never reached the executor")
    }

    /// The client pet-app launched presents the secret and is served.
    func test_aConnectionThatAuthenticatedIsServed() {
        let dispatched = expectation(description: "the dispatch arrived")
        server.onMessage = { message, _ in
            if case .toolDispatch = message { dispatched.fulfill() }
        }

        let client = NWConnection(to: .unix(path: socketURL.path), using: .tcp)
        client.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let self else { return }
            self.sendAuthenticatedHello(on: client)
            self.send(
                .toolDispatch(ToolDispatch(id: "1", tool: "run_shell", args: .object(["command": .string("id")]))),
                on: client
            )
        }
        client.start(queue: .main)
        defer { client.cancel() }

        wait(for: [dispatched], timeout: 3)
    }
}
