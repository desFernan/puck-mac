//
//  CodeEditorRunnerTests.swift
//  PuckTests
//
//  Ports the queue and cancellation cases from
//  workspace/src/agent-host/code-editor-queue.test.ts, against a scripted
//  agent rather than a spawned one -- proving that two runs on one workspace
//  serialise does not need a real node.
//

import XCTest
@testable import Puck

/// A transport that answers the handshake and holds `session/prompt` open
/// until the test releases it, so overlap is observable.
/// `@unchecked` because the test drives it from one place at a time and the
/// counters are only read after the work being tested has finished -- the same
/// claim the real transports make, and the reason the compiler cannot check
/// it: a test double has no lock to point at.
private final class FakeAgent: AcpAgentTransport, @unchecked Sendable {
    let connection: AcpConnection
    private(set) var isRunning = true
    private(set) var terminateCount = 0
    private(set) var killCount = 0
    /// Set by the test to observe ordering.
    var onPrompt: (() -> Void)?
    /// Whether the run has got as far as its prompt.
    private(set) var sawPrompt = false
    private var release: CheckedContinuation<Void, Never>?
    private let holdsPrompt: Bool
    /// A child that stays alive through SIGTERM, which is the case the
    /// escalation to SIGKILL exists for.
    private let ignoresTerminate: Bool
    private var promptID: JSONValue?

    init(holdsPrompt: Bool = false, ignoresTerminate: Bool = false) {
        self.holdsPrompt = holdsPrompt
        self.ignoresTerminate = ignoresTerminate
        var deliver: ((JSONValue) -> Void)!
        let connection = AcpConnection(send: { data in
            guard let frame = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
            deliver(frame)
        })
        self.connection = connection
        deliver = { [weak self] frame in
            guard let self, let method = frame["method"]?.stringValue, let id = frame["id"] else { return }
            switch method {
            case "initialize":
                self.reply(id: id, result: .object(["protocolVersion": .number(1)]))
            case "session/new":
                self.reply(id: id, result: .object(["sessionId": .string("s-1")]))
            case "session/prompt":
                self.sawPrompt = true
                self.onPrompt?()
                if self.holdsPrompt {
                    self.promptID = id
                } else {
                    self.reply(id: id, result: .object(["stopReason": .string("end_turn")]))
                }
            default:
                break
            }
        }
    }

    private func reply(id: JSONValue, result: JSONValue) {
        var data = try! JSONEncoder().encode(
            JSONValue.object(["jsonrpc": .string("2.0"), "id": id, "result": result])
        )
        data.append(UInt8(ascii: "\n"))
        connection.receive(data)
    }

    /// Lets a held prompt finish.
    func finishPrompt(stopReason: String = "end_turn") {
        guard let promptID else { return }
        self.promptID = nil
        reply(id: promptID, result: .object(["stopReason": .string(stopReason)]))
    }

    func terminate() {
        terminateCount += 1
        if !ignoresTerminate { isRunning = false }
    }

    func kill() { killCount += 1; isRunning = false }
}

private func makeEnvironment(
    agent: @escaping (CodingAgentKind, String) throws -> AcpAgentTransport,
    kind: CodingAgentKind = .claude
) -> CodeEditorRunnerEnvironment {
    CodeEditorRunnerEnvironment(
        startAgent: agent,
        credentials: { _ in [:] },
        codingAgent: { kind }
    )
}

final class CodeEditorRunnerTests: XCTestCase {
    private var project: URL!

    override func setUpWithError() throws {
        project = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CodeEditorRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: project)
    }

    // MARK: - Happy path

    func testASingleRunCompletes() async {
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in FakeAgent() }))

        let result = await runner.run(
            requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
        )

        XCTAssertTrue(result.ok)
    }

    func testTheAgentProcessIsTerminatedWhenTheRunEnds() async {
        let agent = FakeAgent()
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in agent }))

        _ = await runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go")

        XCTAssertEqual(agent.terminateCount, 1, "an agent left running would outlive the app's interest in it")
    }

    func testADuplicateRequestIdIsRefused() async {
        let held = FakeAgent(holdsPrompt: true)
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in held }))

        async let first = runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "a")
        try? await Task.sleep(nanoseconds: 100_000_000)
        let second = await runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "b")

        XCTAssertEqual(second.error, "duplicate_request")
        held.finishPrompt()
        _ = await first
    }

    // MARK: - Queueing

    func testTwoRunsOnOneWorkspaceDoNotOverlap() async {
        let firstAgent = FakeAgent(holdsPrompt: true)
        let secondAgent = FakeAgent()
        var order: [String] = []
        firstAgent.onPrompt = { order.append("first-started") }
        secondAgent.onPrompt = { order.append("second-started") }
        var handed = 0
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in
            handed += 1
            return handed == 1 ? firstAgent : secondAgent
        }))

        async let first = runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "a")
        try? await Task.sleep(nanoseconds: 150_000_000)
        async let second = runner.run(requestId: "r2", workspaceId: "w1", projectPath: project.path, task: "b")
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(order, ["first-started"], "the second run must not start while the first holds the workspace")

        firstAgent.finishPrompt()
        _ = await first
        _ = await second
        XCTAssertEqual(order, ["first-started", "second-started"])
    }

    func testDifferentWorkspacesRunInParallel() async {
        let firstAgent = FakeAgent(holdsPrompt: true)
        let secondAgent = FakeAgent()
        var order: [String] = []
        firstAgent.onPrompt = { order.append("first-started") }
        secondAgent.onPrompt = { order.append("second-started") }
        var handed = 0
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in
            handed += 1
            return handed == 1 ? firstAgent : secondAgent
        }))

        async let first = runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "a")
        try? await Task.sleep(nanoseconds: 150_000_000)
        let second = await runner.run(requestId: "r2", workspaceId: "w2", projectPath: project.path, task: "b")
        XCTAssertTrue(second.ok, "a different workspace has nothing to contend over")
        XCTAssertEqual(order, ["first-started", "second-started"])

        firstAgent.finishPrompt()
        _ = await first
    }

    // MARK: - Cancellation

    func testCancellingAQueuedRunNeverStartsAnAgent() async {
        let firstAgent = FakeAgent(holdsPrompt: true)
        var handed = 0
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in
            handed += 1
            return handed == 1 ? firstAgent : FakeAgent()
        }))

        async let first = runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "a")
        try? await Task.sleep(nanoseconds: 150_000_000)
        async let second = runner.run(requestId: "r2", workspaceId: "w1", projectPath: project.path, task: "b")
        try? await Task.sleep(nanoseconds: 100_000_000)
        let cancelled = await runner.cancel(requestId: "r2")

        XCTAssertTrue(cancelled)
        firstAgent.finishPrompt()
        _ = await first
        let secondResult = await second
        XCTAssertEqual(secondResult.error, "cancelled")
        XCTAssertEqual(handed, 1, "the cancelled run should never have been handed an agent")
    }

    func testCancellingAnUnknownRequestReportsSo() async {
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in FakeAgent() }))

        let cancelled = await runner.cancel(requestId: "nope")

        XCTAssertFalse(cancelled)
    }

    // MARK: - Unavailable agent

    func testAMissingNodeIsReportedAsAToolResultRatherThanACrash() async {
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in
            throw AcpAgentCommandError.nodeNotFound
        }))

        let result = await runner.run(
            requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "agent_unavailable")
        XCTAssertTrue(result.summary.contains("Node.js"))
    }

    /// What the tool actually reports is `reportedDetail`, and an unavailable
    /// agent's whole point is the sentence telling the user what to install --
    /// a result that carries only `vendorCLINotFound(...)` is the failure the
    /// user sees as nothing happening at all.
    func testAnUnavailableAgentReportsItsInstallInstructionToTheTool() async {
        let runner = CodeEditorRunner(environment: makeEnvironment(
            agent: { _, _ in throw AcpAgentCommandError.vendorCLINotFound(.claude) },
            kind: .claude
        ))

        let result = await runner.run(
            requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
        )

        let reported = result.reportedDetail ?? ""
        XCTAssertTrue(reported.contains(result.summary), "reported: \(reported)")
        XCTAssertEqual(reported.split(separator: "\n").first.map(String.init), result.summary)
    }

    func testAMissingVendorCLINamesTheOneToInstall() async {
        for kind in CodingAgentKind.allCases {
            let runner = CodeEditorRunner(environment: makeEnvironment(
                agent: { _, _ in throw AcpAgentCommandError.vendorCLINotFound(kind) },
                kind: kind
            ))

            let result = await runner.run(
                requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
            )

            XCTAssertFalse(result.ok)
            XCTAssertTrue(
                result.summary.contains(kind.vendorCLIName),
                "the message has to name the missing CLI, not just say something failed"
            )
        }
    }

    // MARK: - Changed files

    func testFilesWrittenDuringTheRunAreReported() async {
        let agent = FakeAgent(holdsPrompt: true)
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in agent }))
        agent.onPrompt = { [project] in
            try? Data("edited".utf8).write(to: project!.appendingPathComponent("edited.txt"))
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { agent.finishPrompt() }
        }

        let result = await runner.run(
            requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
        )

        XCTAssertEqual(result.changedFiles, ["edited.txt"])
    }

    // MARK: - Timeout

    /// The child is alive but wedged -- a stalled network call, a permission
    /// request nobody answered -- so `session/prompt` never gets a reply and
    /// nothing else here would ever give up. Unbounded, this is a chat that
    /// spins until the app is quit.
    func testARunThatIsNeverAnsweredGivesUpAtTheToolsTimeout() async {
        let agent = FakeAgent(holdsPrompt: true)
        let runner = CodeEditorRunner(
            environment: makeEnvironment(agent: { _, _ in agent }),
            timeoutSeconds: 0.3
        )

        // Through an expectation rather than awaited directly: without the
        // bound this never returns at all, and a hung test says less than a
        // failing one.
        let returned = expectation(description: "code_editor returns")
        var result: CodeEditorResult?
        Task {
            result = await runner.run(
                requestId: "r1", workspaceId: "w1", projectPath: self.project.path, task: "go"
            )
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 10)

        XCTAssertEqual(result?.error, "timeout")
        XCTAssertFalse(result?.ok ?? true)
    }

    func testATimedOutRunTakesItsAgentDownWithIt() async {
        let agent = FakeAgent(holdsPrompt: true, ignoresTerminate: true)
        let runner = CodeEditorRunner(
            environment: makeEnvironment(agent: { _, _ in agent }),
            timeoutSeconds: 0.3
        )

        let returned = expectation(description: "code_editor returns")
        Task {
            _ = await runner.run(
                requestId: "r1", workspaceId: "w1", projectPath: self.project.path, task: "go"
            )
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 10)

        let killed = await eventually { agent.killCount == 1 }
        XCTAssertTrue(killed, "a timed-out run must not leave its child behind")
    }

    /// A workspace is only free once its predecessor is finished, timeout
    /// included -- letting the next run start against a child that is still
    /// being killed is the interleaving the queue exists to prevent.
    func testTheQueueMovesOnAfterATimeout() async {
        let stuck = FakeAgent(holdsPrompt: true)
        let second = FakeAgent()
        var handed = 0
        let runner = CodeEditorRunner(
            environment: makeEnvironment(agent: { _, _ in
                handed += 1
                return handed == 1 ? stuck : second
            }),
            timeoutSeconds: 0.3
        )

        let returned = expectation(description: "both runs return")
        returned.expectedFulfillmentCount = 2
        var results: [CodeEditorResult] = []
        Task {
            let first = await runner.run(
                requestId: "r1", workspaceId: "w1", projectPath: self.project.path, task: "a"
            )
            results.append(first)
            returned.fulfill()
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        Task {
            let next = await runner.run(
                requestId: "r2", workspaceId: "w1", projectPath: self.project.path, task: "b"
            )
            results.append(next)
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 10)

        XCTAssertEqual(results.map(\.error), ["timeout", nil])
    }

    // MARK: - The child is never left behind

    /// SIGTERM is a request, not a guarantee, and the transport is released as
    /// soon as the run finishes -- so if nothing escalates here, nothing ever
    /// will, and the run leaves a node process plus its vendor binary behind.
    func testAnAgentThatIgnoresSIGTERMIsKilledWhenTheRunEnds() async {
        let agent = FakeAgent(ignoresTerminate: true)
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in agent }))

        _ = await runner.run(requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go")

        XCTAssertEqual(agent.terminateCount, 1, "the polite signal comes first")
        let killed = await eventually { agent.killCount == 1 }
        XCTAssertTrue(killed, "a child that outlived SIGTERM has to be killed")
    }

    /// Closing the chat window quits the app mid-edit. Synchronous by
    /// necessity: applicationWillTerminate has nothing to await with.
    func testQuittingTheAppEndsAnAgentThatIsStillRunning() async {
        let agent = FakeAgent(holdsPrompt: true, ignoresTerminate: true)
        let runner = CodeEditorRunner(environment: makeEnvironment(agent: { _, _ in agent }))

        async let running = runner.run(
            requestId: "r1", workspaceId: "w1", projectPath: project.path, task: "go"
        )
        let started = await eventually { agent.isRunning && agent.sawPrompt }
        XCTAssertTrue(started)

        runner.terminateAll()

        XCTAssertEqual(agent.killCount, 1, "the child must not outlive the app that spawned it")
        XCTAssertFalse(agent.isRunning)
        agent.finishPrompt()
        _ = await running
    }

    // MARK: - Helpers

    /// Polls, because the escalation from SIGTERM to SIGKILL is deliberately
    /// on a delay -- what matters is that it happens, not when.
    private func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    // MARK: - The deadline is on silence, not on length

    /// A turn that keeps reporting progress is a turn that is working, and a
    /// budget for the whole turn cut off exactly those: a coding CLI three
    /// minutes into real work was stopped with "180초 안에 답하지 않아".
    func testAnAgentThatKeepsTalkingIsNotTimedOut() async {
        let progress = AgentProgress()
        let done = expectation(description: "work finished")

        let result = await withDeadline(seconds: 0.3, progress: progress) { () async -> String in
            // Six ticks of work, each one shorter than the deadline but four
            // times it in total.
            for _ in 0..<6 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                progress.note()
            }
            done.fulfill()
            return "finished"
        }

        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(result, "finished")
    }

    /// And one that has genuinely stopped talking is still given up on --
    /// which is the whole reason there is a deadline.
    func testAnAgentThatGoesQuietIsStillTimedOut() async {
        let progress = AgentProgress()

        let result: String? = await withDeadline(seconds: 0.2, progress: progress) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return "should not arrive"
        }

        XCTAssertNil(result)
    }

    /// The counter answers "since you last asked", so a burst of updates is
    /// one reset rather than a credit to spend later.
    func testProgressIsReportedOncePerAsk() {
        let progress = AgentProgress()

        XCTAssertFalse(progress.consume(), "nothing has happened yet")
        progress.note()
        progress.note()
        XCTAssertTrue(progress.consume())
        XCTAssertFalse(progress.consume(), "the same two notes must not count twice")
    }
}
