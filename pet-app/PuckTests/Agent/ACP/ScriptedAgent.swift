//
//  ScriptedAgent.swift
//  PuckTests
//
//  Stands in for the ACP agent process: collects what the client wrote and
//  feeds back whatever the test scripts, line by line. Shared by every test
//  that drives a turn against a scripted NDJSON stream -- the code_editor
//  session, the turn session under it, and the CLI-backed chat client -- so
//  the framing they are all tested through is the same one.
//

import Foundation
@testable import Puck

/// Stands in for the agent process: collects what the client wrote and feeds
/// back whatever the test scripts, line by line.
final class ScriptedAgent {
    private(set) var written: [JSONValue] = []
    var connection: AcpConnection!
    /// Answers a request by method name. Returning nil means "stay silent",
    /// which is how the tests exercise a hang.
    var replies: [String: (JSONValue) -> JSONValue?] = [:]
    /// Answers a request with a JSON-RPC error instead of a result.
    var errorReplies: [String: (code: Int, message: String)] = [:]

    init() {
        connection = AcpConnection(send: { [weak self] data in
            guard let self,
                  let frame = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { return }
            self.written.append(frame)
            guard let method = frame["method"]?.stringValue, let id = frame["id"] else { return }
            if let failure = self.errorReplies[method] {
                self.push(.object([
                    "jsonrpc": .string("2.0"),
                    "id": id,
                    "error": .object([
                        "code": .number(Double(failure.code)),
                        "message": .string(failure.message),
                    ]),
                ]))
                return
            }
            guard let reply = self.replies[method]?(frame["params"] ?? .null) else { return }
            self.push(.object(["jsonrpc": .string("2.0"), "id": id, "result": reply]))
        })
    }

    /// Delivers one NDJSON line to the client.
    func push(_ value: JSONValue) {
        guard var data = try? JSONEncoder().encode(value) else { return }
        data.append(UInt8(ascii: "\n"))
        connection.receive(data)
    }

    func pushRaw(_ line: String) {
        connection.receive(Data((line + "\n").utf8))
    }

    func methodsWritten() -> [String] {
        written.compactMap { $0["method"]?.stringValue }
    }

    func params(forMethod method: String) -> JSONValue? {
        written.first { $0["method"]?.stringValue == method }?["params"]
    }

    /// The happy path every test needs before it gets to the interesting part.
    func stubHandshake(stopReason: String = "end_turn") {
        replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        replies["session/prompt"] = { _ in .object(["stopReason": .string(stopReason)]) }
    }
}
