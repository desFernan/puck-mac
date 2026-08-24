//
//  LoopbackHTTPServerTests.swift
//  PuckTests
//
//  The transport half, over a real socket. This is a listener on the user's
//  machine, so the properties worth pinning down are the security ones: who
//  can reach it, what a request without the token buys, and that it is
//  actually gone once the turn that opened it ends.
//

import Network
import XCTest
@testable import Puck

final class LoopbackHTTPServerTests: XCTestCase {

    private var server: LoopbackHTTPServer?

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    private func startEcho(
        answer: @escaping (Data) async -> Data? = { body in body }
    ) async throws -> LoopbackHTTPServer.Endpoint {
        let server = LoopbackHTTPServer(handler: answer)
        self.server = server
        return try await server.start()
    }

    private func post(
        to endpoint: LoopbackHTTPServer.Endpoint,
        body: Data = Data("{}".utf8),
        authorization: String?,
        method: String = "POST"
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: endpoint.url)!)
        request.httpMethod = method
        request.httpBody = method == "POST" ? body : nil
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 5
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }

    // MARK: - Address

    /// The OS picks the port, and it is on loopback. A fixed port would be a
    /// known address for anything else on the machine to try.
    func test_start_listensOnLoopbackWithAnEphemeralPort() async throws {
        let endpoint = try await startEcho()

        XCTAssertGreaterThan(endpoint.port, 0)
        XCTAssertEqual(endpoint.url, "http://127.0.0.1:\(endpoint.port)/mcp")
    }

    /// Two servers never share a token: one turn's credential is worthless in
    /// the next.
    func test_start_mintsAFreshTokenPerInstance() async throws {
        let first = try await startEcho()
        let firstServer = server
        let second = try await startEcho()
        firstServer?.stop()

        XCTAssertNotEqual(first.token, second.token)
        XCTAssertEqual(first.token.count, 64, "256 bits, hex")
    }

    // MARK: - Authentication

    func test_post_withTheToken_reachesTheHandler() async throws {
        let endpoint = try await startEcho(answer: { _ in Data("{\"ok\":true}".utf8) })

        let (status, body) = try await post(
            to: endpoint,
            authorization: endpoint.authorizationHeaderValue
        )

        XCTAssertEqual(status, 200)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "{\"ok\":true}")
    }

    /// Reaching the port must buy nothing: no token, no handler, no body read.
    func test_post_withoutAToken_is401AndNeverReachesTheHandler() async throws {
        let reached = UncheckedBox(false)
        let endpoint = try await startEcho(answer: { _ in
            reached.value = true
            return Data("{}".utf8)
        })

        let (status, _) = try await post(to: endpoint, authorization: nil)

        XCTAssertEqual(status, 401)
        XCTAssertFalse(reached.value)
    }

    func test_post_withTheWrongToken_is401() async throws {
        let reached = UncheckedBox(false)
        let endpoint = try await startEcho(answer: { _ in
            reached.value = true
            return Data("{}".utf8)
        })

        let (status, _) = try await post(
            to: endpoint,
            authorization: "Bearer " + String(repeating: "a", count: endpoint.token.count)
        )

        XCTAssertEqual(status, 401)
        XCTAssertFalse(reached.value)
    }

    /// Authentication comes before anything else is looked at, including the
    /// method -- an unauthenticated GET learns nothing about what is here.
    func test_get_withoutAToken_is401RatherThan405() async throws {
        let endpoint = try await startEcho()

        let (status, _) = try await post(to: endpoint, authorization: nil, method: "GET")

        XCTAssertEqual(status, 401)
    }

    /// The MCP client opens a GET when it wants a server-initiated stream.
    /// This server has none, and the spec has the client carry on after a 405.
    func test_get_withTheToken_is405() async throws {
        let endpoint = try await startEcho()

        let (status, _) = try await post(
            to: endpoint,
            authorization: endpoint.authorizationHeaderValue,
            method: "GET"
        )

        XCTAssertEqual(status, 405)
    }

    /// A notification has no response; the transport answers it with an empty
    /// 202 rather than a body the client would try to parse.
    func test_post_aHandlerThatSaysNothing_is202WithNoBody() async throws {
        let endpoint = try await startEcho(answer: { _ in nil })

        let (status, body) = try await post(
            to: endpoint,
            authorization: endpoint.authorizationHeaderValue
        )

        XCTAssertEqual(status, 202)
        XCTAssertTrue(body.isEmpty)
    }

    func test_constantTimeEquals_matchesOnlyTheSameBytes() {
        XCTAssertTrue(LoopbackHTTPServer.constantTimeEquals("abcd", "abcd"))
        XCTAssertFalse(LoopbackHTTPServer.constantTimeEquals("abcd", "abce"))
        XCTAssertFalse(LoopbackHTTPServer.constantTimeEquals("abcd", "abcde"))
        XCTAssertFalse(LoopbackHTTPServer.constantTimeEquals("", ""), "an absent header must never match")
    }

    // MARK: - Teardown

    /// The listener's lifetime is the turn's. Nothing may be left listening
    /// between turns.
    func test_stop_closesThePort() async throws {
        let endpoint = try await startEcho()
        _ = try await post(to: endpoint, authorization: endpoint.authorizationHeaderValue)

        server?.stop()

        do {
            _ = try await post(to: endpoint, authorization: endpoint.authorizationHeaderValue)
            XCTFail("the port must be closed once the turn is over")
        } catch {
            // A connection refused is exactly what is wanted here.
        }
    }

    func test_stop_isIdempotent() async throws {
        _ = try await startEcho()

        server?.stop()
        server?.stop()
    }
    /// The shape the token race produced: a connection accepted before the
    /// token existed compared against "", so a bare `Bearer ` was accepted.
    /// The token is minted before the listener opens now, and a session is
    /// refused outright without one.
    func test_post_withAnEmptyBearerToken_is401() async throws {
        let reached = UncheckedBox(false)
        let endpoint = try await startEcho(answer: { _ in
            reached.value = true
            return Data("{}".utf8)
        })

        let (status, _) = try await post(to: endpoint, authorization: "Bearer ")

        XCTAssertEqual(status, 401)
        XCTAssertFalse(reached.value)
    }

    // MARK: - Malformed framing

    /// `Content-Length: -1` cleared the size ceiling (it is below it) and then
    /// indexed the buffer backwards from the body's start, which traps: the
    /// whole app dies, not just the connection. URLSession will not send a
    /// header like that, so the request goes out over a raw socket.
    func test_post_withANegativeContentLength_is400AndTheServerLivesOn() async throws {
        let endpoint = try await startEcho(answer: { _ in Data("{\"ok\":true}".utf8) })

        let status = try await sendRaw(
            """
            POST /mcp HTTP/1.1\r
            Host: 127.0.0.1\r
            Authorization: \(endpoint.authorizationHeaderValue)\r
            Content-Length: -1\r
            Connection: close\r
            \r

            """,
            to: endpoint
        )

        XCTAssertEqual(status, 400)
        // The listener is what matters: a trap would have taken this process
        // with it, so a second request answering at all is the real assertion.
        let (second, _) = try await post(to: endpoint, authorization: endpoint.authorizationHeaderValue)
        XCTAssertEqual(second, 200)
    }

    /// Writes `request` verbatim and returns the status line's code.
    private func sendRaw(_ request: String, to endpoint: LoopbackHTTPServer.Endpoint) async throws -> Int {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: UInt16(endpoint.port))!,
            using: .tcp
        )
        defer { connection.cancel() }
        connection.start(queue: .global())

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = UncheckedBox(false)
            func finish(_ result: Result<Int, Error>) {
                guard !resumed.value else { return }
                resumed.value = true
                continuation.resume(with: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                        if let error { return finish(.failure(error)) }
                        let head = String(decoding: data ?? Data(), as: UTF8.self)
                        let code = head.split(separator: " ").dropFirst().first.flatMap { Int($0) }
                        finish(.success(code ?? -1))
                    }
                case .failed(let error):
                    finish(.failure(error))
                default:
                    break
                }
            }
        }
    }
}
