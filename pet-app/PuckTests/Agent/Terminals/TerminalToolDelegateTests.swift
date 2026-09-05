//
//  TerminalToolDelegateTests.swift
//  PuckTests
//
//  The four terminal tools, as the model actually calls them.
//

import XCTest
@testable import Puck

final class TerminalToolDelegateTests: XCTestCase {
    private var directory: URL!
    private var terminals: AgentTerminals!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        terminals = AgentTerminals()
    }

    override func tearDown() {
        terminals.stopAll()
        try? FileManager.default.removeItem(at: directory)
    }

    private func delegate(project: String?) -> TerminalToolDelegate {
        TerminalToolDelegate(terminals: terminals, resolveProjectPath: { project })
    }

    private func waitUntil(
        timeout: TimeInterval = 10,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTFail("timed out waiting", file: file, line: line)
    }

    /// A start answers with the id and nothing that looks like output -- a
    /// first line in the answer would invite the model to treat it as the
    /// whole thing and never read again.
    func test_startingAnswersWithAnIdAndNotWithOutput() {
        let result = delegate(project: directory.path)
            .handle(tool: AgentRunner.terminalStartToolName, arguments: .object([
                "command": .string("echo 안녕; sleep 30"),
            ]))

        XCTAssertTrue(result.ok)
        guard case .object(let fields)? = result.data, case .string(let id)? = fields["id"] else {
            return XCTFail("no id in \(String(describing: result.data))")
        }
        XCTAssertFalse(id.isEmpty)
        XCTAssertNil(fields["output"], "a start is not a read")
    }

    /// A workspace with no project has nowhere to run one, and says so rather
    /// than starting a shell in whatever directory the app was launched from.
    func test_aWorkspaceWithNoProjectIsToldSo() {
        let result = delegate(project: nil)
            .handle(tool: AgentRunner.terminalStartToolName, arguments: .object([
                "command": .string("echo hi"),
            ]))

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
    }

    /// The read reports what is new, whether it is still running, and its
    /// exit code once it is not.
    func test_readingReportsOutputAndWhetherItIsStillRunning() {
        let tools = delegate(project: directory.path)
        let started = tools.handle(tool: AgentRunner.terminalStartToolName, arguments: .object([
            "command": .string("echo 처음; exit 7"),
        ]))
        guard case .object(let fields)? = started.data, case .string(let id)? = fields["id"] else {
            return XCTFail("no id")
        }

        var seen = ""
        var running = true
        var exitCode: Double?
        waitUntil {
            let read = tools.handle(tool: AgentRunner.terminalReadToolName, arguments: .object(["id": .string(id)]))
            guard case .object(let f)? = read.data else { return false }
            if case .string(let text)? = f["output"] { seen += text }
            if case .bool(let isRunning)? = f["running"] { running = isRunning }
            if case .number(let code)? = f["exit_code"] { exitCode = code }
            return !running
        }

        XCTAssertTrue(seen.contains("처음"), seen)
        XCTAssertEqual(exitCode, 7)
    }

    /// Reading with no id is a mistake worth naming rather than a crash.
    func test_readingWithoutAnIdIsRefused() {
        let result = delegate(project: directory.path)
            .handle(tool: AgentRunner.terminalReadToolName, arguments: .object([:]))

        XCTAssertFalse(result.ok)
    }

    /// Stopping with no id stops all of them: that is the shape the model
    /// needs at the end of a task, and making it name each one is a chance to
    /// leave one running.
    func test_stoppingWithoutAnIdStopsEveryone() {
        let tools = delegate(project: directory.path)
        for _ in 0..<3 {
            _ = tools.handle(tool: AgentRunner.terminalStartToolName, arguments: .object([
                "command": .string("sleep 30"),
            ]))
        }

        let result = tools.handle(tool: AgentRunner.terminalStopToolName, arguments: .object([:]))

        XCTAssertTrue(result.ok)
        waitUntil { terminals.list().allSatisfy { !$0.isRunning } }
    }

    /// A blank line is a real answer at a prompt, so `text` is allowed to be
    /// empty where `command` and `id` are not.
    func test_aBlankLineIsSomethingYouCanSend() {
        XCTAssertEqual(TerminalToolDelegate.string("text", in: .object(["text": .string("")]), allowingEmpty: true), "")
        XCTAssertNil(TerminalToolDelegate.string("command", in: .object(["command": .string("  ")])))
        XCTAssertNil(TerminalToolDelegate.string("id", in: .object([:])))
    }

    /// A name this delegate does not answer is an unknown tool, not a silent
    /// success.
    func test_aToolItDoesNotOwnIsRefused() {
        let result = delegate(project: directory.path).handle(tool: "run_shell", arguments: .object([:]))

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "unknown_tool")
    }
}
