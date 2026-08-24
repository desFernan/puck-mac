//
//  AcpConnectionTests.swift
//  PuckTests
//
//  The transport on its own: what happens to requests filed around the moment
//  the agent dies. Framing is covered from the session's side
//  (AcpCodeEditorSessionTests); this is about continuations that would
//  otherwise never be resumed at all.
//

import XCTest
@testable import Puck

final class AcpConnectionTests: XCTestCase {
    /// Answers `id` the way an agent would.
    private func reply(_ connection: AcpConnection, id: Int, result: JSONValue) {
        var data = try! JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .number(Double(id)), "result": result,
        ]))
        data.append(UInt8(ascii: "\n"))
        connection.receive(data)
    }

    func testARequestIsAnsweredByItsReply() async throws {
        let connection = AcpConnection(send: { _ in })
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            self.reply(connection, id: 1, result: .object(["stopReason": .string("end_turn")]))
        }

        let result = try await connection.request(method: AcpMethod.sessionPrompt, params: .null)

        XCTAssertEqual(result["stopReason"]?.stringValue, "end_turn")
    }

    func testInFlightRequestsFailWhenTheProcessDies() async {
        let connection = AcpConnection(send: { _ in })
        let failed = expectation(description: "the in-flight request is answered")
        Task {
            do {
                _ = try await connection.request(method: AcpMethod.sessionPrompt, params: .null)
                XCTFail("a request the agent can no longer answer must not succeed")
            } catch {
                XCTAssertEqual(error as? AcpError, .processExited(detail: "boom"))
            }
            failed.fulfill()
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        connection.failAllPending(with: AcpError.processExited(detail: "boom"))

        await fulfillment(of: [failed], timeout: 5)
    }

    /// The window this closes: `startAgent` returns, the node process dies at
    /// import time tens of milliseconds later, and only then does the run get
    /// as far as `initialize`. Registered into a dictionary that was already
    /// drained, that continuation had nothing left that would ever resume it.
    func testARequestMadeAfterTheProcessDiedFailsRatherThanHangingForever() async {
        let connection = AcpConnection(send: { _ in })
        connection.failAllPending(with: AcpError.processExited(detail: "Cannot find module"))

        let answered = expectation(description: "the late request is answered")
        Task {
            do {
                _ = try await connection.request(method: AcpMethod.initialize, params: .null)
                XCTFail("a request to a dead agent must not succeed")
            } catch {
                XCTAssertEqual(error as? AcpError, .processExited(detail: "Cannot find module"))
            }
            answered.fulfill()
        }

        await fulfillment(of: [answered], timeout: 5)
    }

    func testTheFirstCauseOfDeathIsTheOneReported() async {
        let connection = AcpConnection(send: { _ in })
        connection.failAllPending(with: AcpError.processExited(detail: "the real reason"))
        connection.failAllPending(with: AcpError.cancelled)

        let answered = expectation(description: "the late request is answered")
        Task {
            do {
                _ = try await connection.request(method: AcpMethod.initialize, params: .null)
                XCTFail("a request to a dead agent must not succeed")
            } catch {
                XCTAssertEqual(error as? AcpError, .processExited(detail: "the real reason"))
            }
            answered.fulfill()
        }

        await fulfillment(of: [answered], timeout: 5)
    }
}
