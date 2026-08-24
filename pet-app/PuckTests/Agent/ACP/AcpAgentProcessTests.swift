//
//  AcpAgentProcessTests.swift
//  PuckTests
//
//  Two halves: the pure command resolution (always runs), and one integration
//  test that spawns the *real* vendored agent under the *real* node. The
//  integration test is what proves scripts/vendor-acp.sh produced something
//  that actually speaks ACP -- the scripted tests in
//  AcpCodeEditorSessionTests cannot, since they never leave the process.
//

import XCTest
@testable import Puck

final class AcpAgentCommandResolverTests: XCTestCase {
    func testNodeIsTakenFromPathBeforeAnyWellKnownLocation() {
        let found = AcpAgentCommandResolver.resolveNode(
            environment: ["PATH": "/custom/bin:/usr/bin", "HOME": "/Users/x"],
            fileExists: { $0 == "/custom/bin/node" || $0 == "/opt/homebrew/bin/node" },
            nvmVersions: { _ in [] }
        )

        XCTAssertEqual(found?.path, "/custom/bin/node")
    }

    func testHomebrewIsTriedWhenPathHasNoNode() {
        let found = AcpAgentCommandResolver.resolveNode(
            environment: ["PATH": "/usr/bin", "HOME": "/Users/x"],
            fileExists: { $0 == "/opt/homebrew/bin/node" },
            nvmVersions: { _ in [] }
        )

        XCTAssertEqual(found?.path, "/opt/homebrew/bin/node")
    }

    func testNvmFallsBackToItsNewestInstall() {
        let found = AcpAgentCommandResolver.resolveNode(
            environment: ["PATH": "/usr/bin", "HOME": "/Users/x"],
            fileExists: { $0.hasPrefix("/Users/x/.nvm/versions/node/") },
            nvmVersions: { _ in ["v18.20.0", "v22.11.0", "v20.9.0"] }
        )

        XCTAssertEqual(found?.path, "/Users/x/.nvm/versions/node/v22.11.0/bin/node")
    }

    func testNoNodeAnywhereIsReportedRatherThanGuessed() {
        let found = AcpAgentCommandResolver.resolveNode(
            environment: ["PATH": "/usr/bin", "HOME": "/Users/x"],
            fileExists: { _ in false },
            nvmVersions: { _ in [] }
        )

        XCTAssertNil(found)
    }

    func testMissingNodeFailsCommandBuilding() {
        XCTAssertThrowsError(
            try AcpAgentCommandResolver.command(
                for: .claude,
                scriptURL: URL(fileURLWithPath: "/x/acp-claude.mjs"),
                node: nil,
                vendorCLI: URL(fileURLWithPath: "/usr/bin/claude")
            )
        ) { XCTAssertEqual($0 as? AcpAgentCommandError, .nodeNotFound) }
    }

    func testMissingBundledScriptIsAPackagingErrorOfItsOwn() {
        XCTAssertThrowsError(
            try AcpAgentCommandResolver.command(
                for: .claude,
                scriptURL: nil,
                node: URL(fileURLWithPath: "/usr/bin/node"),
                vendorCLI: URL(fileURLWithPath: "/usr/bin/claude")
            )
        ) { XCTAssertEqual($0 as? AcpAgentCommandError, .agentScriptMissing(.claude)) }
    }

    func testTheBundledScriptIsRunUnderNode() throws {
        let command = try AcpAgentCommandResolver.command(
            for: .claude,
            scriptURL: URL(fileURLWithPath: "/x/acp-claude.mjs"),
            node: URL(fileURLWithPath: "/usr/bin/node"),
            vendorCLI: URL(fileURLWithPath: "/usr/bin/claude")
        )

        XCTAssertEqual(command.executable.path, "/usr/bin/node")
        XCTAssertEqual(command.arguments, ["/x/acp-claude.mjs"])
    }

    func testEachAgentIsPointedAtItsOwnVendorCLI() throws {
        // Neither shim is self-contained: each resolves a ~256MB native binary
        // out of a node_modules tree that does not exist inside Puck.app, and
        // does it lazily -- at session/new, long after initialize succeeds.
        let claude = try AcpAgentCommandResolver.command(
            for: .claude,
            scriptURL: URL(fileURLWithPath: "/x/acp-claude.mjs"),
            node: URL(fileURLWithPath: "/usr/bin/node"),
            vendorCLI: URL(fileURLWithPath: "/usr/local/bin/claude")
        )
        let codex = try AcpAgentCommandResolver.command(
            for: .codex,
            scriptURL: URL(fileURLWithPath: "/x/acp-codex.mjs"),
            node: URL(fileURLWithPath: "/usr/bin/node"),
            vendorCLI: URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        )

        XCTAssertEqual(claude.extraEnvironment["CLAUDE_CODE_EXECUTABLE"], "/usr/local/bin/claude")
        XCTAssertEqual(codex.extraEnvironment["CODEX_PATH"], "/opt/homebrew/bin/codex")
    }

    func testAnAgentWithoutItsVendorCLIIsRefusedRatherThanSpawnedToFail() {
        for kind in CodingAgentKind.allCases {
            XCTAssertThrowsError(
                try AcpAgentCommandResolver.command(
                    for: kind,
                    scriptURL: URL(fileURLWithPath: "/x/agent.mjs"),
                    node: URL(fileURLWithPath: "/usr/bin/node"),
                    vendorCLI: nil
                )
            ) { XCTAssertEqual($0 as? AcpAgentCommandError, .vendorCLINotFound(kind)) }
        }
    }

    func testTheVendorCLIOverrideVariableWins() {
        let found = AcpAgentCommandResolver.resolveVendorCLI(
            for: .claude,
            environment: ["CLAUDE_CODE_EXECUTABLE": "/custom/claude", "PATH": "/usr/bin"],
            fileExists: { $0 == "/custom/claude" || $0 == "/usr/bin/claude" }
        )

        XCTAssertEqual(found?.path, "/custom/claude", "a user who already set it keeps their choice")
    }

    func testTheVendorCLIIsFoundOnPath() {
        let found = AcpAgentCommandResolver.resolveVendorCLI(
            for: .codex,
            environment: ["PATH": "/usr/bin:/opt/bin"],
            fileExists: { $0 == "/opt/bin/codex" }
        )

        XCTAssertEqual(found?.path, "/opt/bin/codex")
    }

    func testTheVendorCLIFallsBackToNpmGlobal() {
        // Where `npm i -g @anthropic-ai/claude-code` lands when a prefix is set,
        // which PATH may not cover for a GUI app launched from Finder.
        let found = AcpAgentCommandResolver.resolveVendorCLI(
            for: .claude,
            environment: ["PATH": "/usr/bin", "HOME": "/Users/x"],
            fileExists: { $0 == "/Users/x/.npm-global/bin/claude" }
        )

        XCTAssertEqual(found?.path, "/Users/x/.npm-global/bin/claude")
    }

    func testTheVendorCLIFallsBackToTheOfficialInstallerLocation() {
        // ~/.claude/local/claude is where the official Claude Code installer
        // puts it, and it is on no default PATH.
        let found = AcpAgentCommandResolver.resolveVendorCLI(
            for: .claude,
            environment: ["PATH": "/usr/bin", "HOME": "/Users/x"],
            fileExists: { $0 == "/Users/x/.claude/local/claude" },
            nvmVersions: { _ in [] }
        )

        XCTAssertEqual(found?.path, "/Users/x/.claude/local/claude")
    }

    func testTheVendorCLIFallsBackToTheNewestNvmInstall() {
        // Installed with `npm i -g` under an nvm node: the CLI sits beside that
        // node, in a directory PATH names only once nvm's shell hook has run.
        let found = AcpAgentCommandResolver.resolveVendorCLI(
            for: .codex,
            environment: ["PATH": "/usr/bin", "HOME": "/Users/x"],
            fileExists: { $0.hasPrefix("/Users/x/.nvm/versions/node/") },
            nvmVersions: { _ in ["v18.20.0", "v22.11.0", "v20.9.0"] }
        )

        XCTAssertEqual(found?.path, "/Users/x/.nvm/versions/node/v22.11.0/bin/codex")
    }

    func testEachAgentNamesADistinctBundledScript() {
        let names = Set(CodingAgentKind.allCases.map(\.bundledScriptName))
        XCTAssertEqual(names.count, CodingAgentKind.allCases.count)
    }

    func testOnlyTheSelectedAgentsCredentialsAreNamed() {
        XCTAssertEqual(
            CodingAgentKind.claude.apiKeyEnvironmentVariables,
            ["CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY"]
        )
        XCTAssertEqual(CodingAgentKind.codex.apiKeyEnvironmentVariables, ["CODEX_API_KEY", "OPENAI_API_KEY"])
    }
}

/// What is still in the pipe when the child exits. Spawns a scripted `sh`
/// rather than node: the point is the exit/read race, and a shell reaches it
/// in milliseconds on any machine.
final class AcpAgentProcessOutputDrainTests: XCTestCase {
    private var scriptURL: URL!

    override func tearDownWithError() throws {
        if let scriptURL { try? FileManager.default.removeItem(at: scriptURL) }
    }

    private func agent(script: String) throws -> AcpAgentProcess {
        scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("acp-drain-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return AcpAgentProcess(
            command: AcpAgentCommand(executable: scriptURL, arguments: [], extraEnvironment: [:], stateDirectoryName: ".claude"),
            projectPath: NSTemporaryDirectory(),
            credentials: [:]
        )
    }

    /// The reply and the exit arrive together, and the reply is bigger than
    /// one pipeful -- so some of it is still unread when terminationHandler
    /// fires. Detaching the reader there and stopping used to throw that tail
    /// away, which failed the run's own `session/prompt` and reported a run
    /// that had actually succeeded as "the ACP process exited".
    func testTheReplyWrittenJustBeforeExitIsStillRead() async throws {
        let agent = try agent(script: """
        #!/bin/sh
        read line
        printf '{"jsonrpc":"2.0","id":1,"result":{"stopReason":"end_turn","pad":"'
        head -c 400000 /dev/zero | tr '\\0' x
        printf '"}}\\n'
        exit 0
        """)
        try agent.start()
        defer { agent.kill() }

        let result = try await agent.connection.request(
            method: AcpMethod.sessionPrompt,
            params: .object(["sessionId": .string("s-1")])
        )

        XCTAssertEqual(result["stopReason"]?.stringValue, "end_turn")
    }

    /// The other half of the same drain: an agent that explains itself on
    /// stderr on its way out still gets that explanation reported.
    func testStderrWrittenJustBeforeExitIsStillReported() async throws {
        let agent = try agent(script: """
        #!/bin/sh
        read line
        printf 'fatal: the agent could not start\\n' >&2
        exit 1
        """)
        let exited = expectation(description: "the process exits")
        var reported = ""
        agent.onExit = { _, tail in
            reported = tail
            exited.fulfill()
        }
        try agent.start()
        defer { agent.kill() }

        _ = try? await agent.connection.request(method: AcpMethod.initialize, params: .null)
        await fulfillment(of: [exited], timeout: 5)

        XCTAssertTrue(reported.contains("could not start"), "got: \(reported)")
    }
}

final class AcpAgentProcessSandboxTests: XCTestCase {
    /// The real HOME is what lets the CLI authenticate, so the whole safety
    /// argument now rests on the write rules. This is that argument, checked:
    /// a child that can read the user's home still cannot write into it.
    func testChildCannotWriteIntoTheRealHomeOutsideTheAgentsStateDirectory() async throws {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck-acp-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        // Removed either way: if the sandbox lets this through, the failure
        // should not also leave a file in the user's home.
        let probe = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("puck-sandbox-probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: probe) }

        let agent = AcpAgentProcess(
            command: AcpAgentCommand(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf probe > \"$1\"", "puck-sandbox-test", probe.path],
                extraEnvironment: [:],
                stateDirectoryName: ".claude"
            ),
            projectPath: project.path,
            credentials: [:]
        )
        let exited = expectation(description: "the child exits")
        agent.onExit = { _, _ in exited.fulfill() }

        try agent.start()
        await fulfillment(of: [exited], timeout: 5)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: probe.path),
            "the ACP child wrote into the user's home directory"
        )
    }

    func testChildCanWriteInsideProjectButNotToASiblingDirectory() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck-acp-sandbox-\(UUID().uuidString)", isDirectory: true)
        let project = parent.appendingPathComponent("project", isDirectory: true)
        let sibling = parent.appendingPathComponent("sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let inside = project.appendingPathComponent("inside.txt")
        let outside = sibling.appendingPathComponent("outside.txt")
        let agent = AcpAgentProcess(
            command: AcpAgentCommand(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c",
                    "printf inside > \"$1\"; printf outside > \"$2\"",
                    "puck-sandbox-test",
                    inside.path,
                    outside.path,
                ],
                extraEnvironment: [:],
                stateDirectoryName: ".claude"
            ),
            projectPath: project.path,
            credentials: [:]
        )
        let exited = expectation(description: "the child exits")
        agent.onExit = { _, _ in exited.fulfill() }

        // The real home, so the CLI can find the login the user already gave
        // it: on macOS that means the login keychain, which is only in the
        // search list when HOME points at the user's own directory. What
        // keeps that safe is the write restriction this test goes on to
        // prove, not a home the CLI cannot authenticate from.
        let childHome = try XCTUnwrap(agent.childEnvironment["HOME"])
        XCTAssertEqual(childHome, NSHomeDirectory())

        try agent.start()
        await fulfillment(of: [exited], timeout: 5)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: inside.path),
            "inside write failed: \(agent.currentStderrTail())"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outside.path),
            "the ACP child wrote outside its project root"
        )
    }

}

/// Spawns the real thing. Skips rather than fails when node is missing -- a
/// machine without node is a supported configuration (code_editor is simply
/// unavailable there), so this must not turn into a red suite.
final class AcpAgentProcessIntegrationTests: XCTestCase {
    func testTheVendoredClaudeAgentOpensARealSession() async throws {
        guard let node = AcpAgentCommandResolver.resolveNode() else {
            throw XCTSkip("no node on this machine; code_editor is unavailable here by design")
        }
        guard let vendorCLI = AcpAgentCommandResolver.resolveVendorCLI(for: .claude) else {
            throw XCTSkip("no claude CLI on this machine; the claude agent is unavailable here by design")
        }
        guard let script = AcpAgentCommandResolver.bundledScriptURL(for: .claude, in: Bundle(for: Self.self))
            ?? AcpAgentCommandResolver.bundledScriptURL(for: .claude) else {
            return XCTFail("acp-claude.mjs is not in the bundle -- run scripts/vendor-acp.sh")
        }

        let command = try AcpAgentCommandResolver.command(
            for: .claude, scriptURL: script, node: node, vendorCLI: vendorCLI
        )
        let agent = AcpAgentProcess(
            command: command,
            projectPath: NSTemporaryDirectory(),
            // No key on purpose: everything up to session/new works without
            // one, and only session/prompt needs real credentials -- which a
            // build machine has no reason to hold.
            credentials: [:]
        )
        try agent.start()
        defer { agent.kill() }

        let initialized = try await agent.connection.request(
            method: AcpMethod.initialize,
            params: .object([
                "protocolVersion": .number(Double(acpProtocolVersion)),
                "clientCapabilities": .object([:]),
            ])
        )
        XCTAssertEqual(initialized["protocolVersion"]?.numberValue, Double(acpProtocolVersion))
        XCTAssertEqual(initialized["agentInfo"]?["name"]?.stringValue, "@agentclientprotocol/claude-agent-acp")

        // session/new, not just initialize. This is where the shim resolves its
        // native binary, and an initialize-only assertion once passed against a
        // bundle that could not open a session at all.
        let session = try await agent.connection.request(
            method: AcpMethod.sessionNew,
            params: .object([
                "cwd": .string(NSTemporaryDirectory()),
                "mcpServers": .array([]),
            ])
        )
        XCTAssertNotNil(session["sessionId"]?.stringValue)
    }
}
