//
//  ToolExecutionLoggerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  JSON Lines log formatting, per protocol/01_protocol.md section 7 -- the
//  shared log format the processes debug through.
//

import XCTest
@testable import Puck

final class ToolExecutionLoggerTests: XCTestCase {
    func test_execStart_formatsWithoutOkField() throws {
        let line = ToolExecutionLogLine(event: .execStart(id: "t1"), timestamp: "2026-07-26T12:00:00.000Z")

        let data = try JSONEncoder().encode(line)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["src"] as? String, "pet-app")
        XCTAssertEqual(json?["kind"] as? String, "tool_exec_start")
        XCTAssertEqual(json?["id"] as? String, "t1")
        XCTAssertEqual(json?["ts"] as? String, "2026-07-26T12:00:00.000Z")
        XCTAssertNil(json?["ok"])
    }

    func test_execEnd_includesOkField() throws {
        let line = ToolExecutionLogLine(event: .execEnd(id: "t1", ok: false), timestamp: "2026-07-26T12:00:00.100Z")

        let data = try JSONEncoder().encode(line)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["kind"] as? String, "tool_exec_end")
        XCTAssertEqual(json?["ok"] as? Bool, false)
    }

    /// The agent half of the join (2026-08-12). pet-app's exec lines carry
    /// only an id, so without the tool name here a failed call is an opaque
    /// uuid -- which is exactly what happened when a browser request failed
    /// and the log could not say which tool or why.
    func test_agentToolCall_namesTheToolAndItsArguments() throws {
        let line = ToolExecutionLogLine(
            event: .agentToolCall(id: "t1", tool: "launch_app", args: .object(["app_name": .string("Safari")])),
            timestamp: "2026-08-12T12:00:00.000Z"
        )

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as? [String: Any]

        XCTAssertEqual(json?["src"] as? String, "agent")
        XCTAssertEqual(json?["kind"] as? String, "tool_call")
        XCTAssertEqual(json?["tool"] as? String, "launch_app")
        XCTAssertEqual((json?["args"] as? [String: Any])?["app_name"] as? String, "Safari")
    }

    func test_agentToolResult_carriesTheFailureReason() throws {
        let line = ToolExecutionLogLine(
            event: .agentToolResult(id: "t1", ok: false, error: "execution_failed -- 앱을 찾을 수 없습니다"),
            timestamp: "2026-08-12T12:00:01.000Z"
        )

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as? [String: Any]

        XCTAssertEqual(json?["src"] as? String, "agent")
        XCTAssertEqual(json?["kind"] as? String, "tool_result")
        XCTAssertEqual(json?["ok"] as? Bool, false)
        XCTAssertEqual(json?["error"] as? String, "execution_failed -- 앱을 찾을 수 없습니다")
    }

    /// A successful call has no reason to carry an error key.
    func test_agentToolResult_success_omitsTheErrorField() throws {
        let line = ToolExecutionLogLine(
            event: .agentToolResult(id: "t1", ok: true, error: nil),
            timestamp: "2026-08-12T12:00:01.000Z"
        )

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as? [String: Any]

        XCTAssertEqual(json?["ok"] as? Bool, true)
        XCTAssertNil(json?["error"])
    }
}
