//
//  AcpBoundaryTests.swift
//  PuckTests
//
//  Ported from byeolki's workspace-side check (9c956c08) before that app was
//  deleted -- the Swift ACP port had no equivalent, and the two branches did
//  the same Electron removal in parallel.
//
//  Protocol-level defense in depth: AcpAgentProcess blocks outside writes with
//  an OS sandbox, while this mapping records write-shaped locations the agent
//  reports so an attempted escape is still visible in the tool result.
//

import XCTest
@testable import Puck

final class AcpBoundaryTests: XCTestCase {
    private let root = "/Users/x/project"

    private func update(kind: String, sessionUpdate: String = "tool_call", paths: [String]) -> AcpSessionUpdate {
        AcpSessionUpdate(raw: .object([
            "sessionId": .string("s-1"),
            "update": .object([
                "sessionUpdate": .string(sessionUpdate),
                "kind": .string(kind),
                "locations": .array(paths.map { .object(["path": .string($0)]) }),
            ]),
        ]))
    }

    func testAWriteInsideTheProjectIsNotFlagged() {
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", paths: ["/Users/x/project/src/main.swift"])
        )

        XCTAssertTrue(flagged.isEmpty)
    }

    func testAWriteOutsideTheProjectIsFlagged() {
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", paths: ["/Users/x/.ssh/authorized_keys"])
        )

        XCTAssertEqual(flagged, ["/Users/x/.ssh/authorized_keys"])
    }

    func testATraversalOutOfTheProjectIsResolvedBeforeComparing() {
        // The path is nominally under the root; only after standardizing is it
        // outside. Comparing the raw string would pass it.
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "delete", paths: ["/Users/x/project/../../etc/hosts"])
        )

        // /Users/x/project/../.. is /Users, so the traversal lands on
        // /Users/etc/hosts -- outside the project either way, which is the point.
        XCTAssertEqual(flagged, ["/Users/etc/hosts"])
    }

    func testASiblingDirectorySharingThePrefixIsOutside() {
        // /Users/x/project-secrets starts with the root's characters but is
        // not inside it -- the classic prefix-match bug.
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", paths: ["/Users/x/project-secrets/key.txt"])
        )

        XCTAssertEqual(flagged, ["/Users/x/project-secrets/key.txt"])
    }

    func testReadShapedOperationsAreNotFlagged() {
        // Reading outside the project is not what this looks for; only
        // operations that change the filesystem.
        for kind in ["read", "search", "execute", "think", "fetch"] {
            XCTAssertTrue(
                AcpEventMapping.writesOutside(root: root, in: update(kind: kind, paths: ["/etc/passwd"])).isEmpty,
                "\(kind) should not be flagged"
            )
        }
    }

    func testEveryWriteShapedKindIsChecked() {
        for kind in ["edit", "delete", "move"] {
            XCTAssertEqual(
                AcpEventMapping.writesOutside(root: root, in: update(kind: kind, paths: ["/tmp/elsewhere"])),
                ["/tmp/elsewhere"],
                "\(kind) should be flagged"
            )
        }
    }

    func testToolCallUpdatesAreCheckedToolNotJustTheInitialCall() {
        // An agent reports the location it settled on in the update, not
        // always in the first call.
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", sessionUpdate: "tool_call_update", paths: ["/tmp/elsewhere"])
        )

        XCTAssertEqual(flagged, ["/tmp/elsewhere"])
    }

    func testAnUpdateWithNoLocationsIsQuiet() {
        XCTAssertTrue(AcpEventMapping.writesOutside(root: root, in: update(kind: "edit", paths: [])).isEmpty)
    }

    func testARelativePathIsResolvedAgainstTheProjectNotThisProcess() {
        // The shim forwards the model's `file_path` verbatim, so a relative one
        // reaches here before the CLI rejects it. URL(fileURLWithPath:) would
        // resolve it against *this* process's cwd -- "/" for an app launched
        // from Finder -- turning "src/main.swift" into "/src/main.swift" and
        // failing the whole run on a file inside the project.
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", paths: ["src/main.swift"])
        )

        XCTAssertTrue(flagged.isEmpty, "got: \(flagged)")
    }

    func testARelativePathThatClimbsOutOfTheProjectIsStillFlagged() {
        let flagged = AcpEventMapping.writesOutside(
            root: root,
            in: update(kind: "edit", paths: ["../secrets/key.txt"])
        )

        XCTAssertEqual(flagged, ["/Users/x/secrets/key.txt"])
    }

    func testASymlinkedProjectRootIsNotAnEscape() throws {
        // /tmp is a symlink to /private/tmp on macOS: the user opens the
        // project as /tmp/<name> and the agent reports /private/tmp/<name>/...
        // standardizedFileURL does not resolve symlinks, so before this was
        // fixed every single edit in such a project failed the run.
        let name = "puck-acp-boundary-\(UUID().uuidString)"
        let symlinkedRoot = "/tmp/\(name)"
        try FileManager.default.createDirectory(atPath: symlinkedRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: symlinkedRoot) }
        let resolvedRoot = "/private/tmp/\(name)"
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: resolvedRoot),
            "/tmp is not a symlink to /private/tmp on this machine"
        )

        XCTAssertTrue(
            AcpEventMapping.writesOutside(
                root: symlinkedRoot,
                in: update(kind: "edit", paths: ["\(resolvedRoot)/src/main.swift"])
            ).isEmpty
        )
        // And the other way round: the project opened by its resolved name,
        // the agent reporting the symlinked one.
        XCTAssertTrue(
            AcpEventMapping.writesOutside(
                root: resolvedRoot,
                in: update(kind: "edit", paths: ["\(symlinkedRoot)/src/main.swift"])
            ).isEmpty
        )
    }

    func testASymlinkedRootDoesNotStopRealEscapesFromBeingFlagged() throws {
        let name = "puck-acp-boundary-\(UUID().uuidString)"
        let symlinkedRoot = "/tmp/\(name)"
        try FileManager.default.createDirectory(atPath: symlinkedRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: symlinkedRoot) }

        XCTAssertEqual(
            AcpEventMapping.writesOutside(
                root: symlinkedRoot,
                in: update(kind: "edit", paths: ["/Users/x/.ssh/authorized_keys"])
            ),
            ["/Users/x/.ssh/authorized_keys"]
        )
    }

    func testMessageChunksAreNotBoundaryEvents() {
        let chunk = AcpSessionUpdate(raw: .object([
            "update": .object([
                "sessionUpdate": .string("agent_message_chunk"),
                "content": .object(["type": .string("text"), "text": .string("/etc/passwd")]),
            ]),
        ]))

        XCTAssertTrue(AcpEventMapping.writesOutside(root: root, in: chunk).isEmpty)
    }
}

/// The child environment (2026-08-16). Deliberately minimal -- an ACP child
/// should not inherit every secret this process happens to hold -- but it was
/// trimmed past what the vendor CLIs need, and the symptom pointed the wrong
/// way: a logged-in `claude` reported "Not logged in", which arrived as ACP
/// error -32000 "Authentication required" and read like a missing API key.
final class AcpAgentEnvironmentTests: XCTestCase {
    private func environment(kind: CodingAgentKind = .claude, credentials: [String: String] = [:]) -> [String: String] {
        let process = AcpAgentProcess(
            command: AcpAgentCommand(
                executable: URL(fileURLWithPath: "/usr/bin/node"),
                arguments: ["/x/agent.mjs"],
                extraEnvironment: [kind.vendorCLIEnvironmentVariable: "/usr/local/bin/\(kind.vendorCLIName)"],
                stateDirectoryName: ".claude"
            ),
            projectPath: NSTemporaryDirectory(),
            credentials: credentials
        )
        return process.childEnvironment
    }

    func testUSERIsPassedSoTheVendorCLICanFindItsKeychainLogin() {
        XCTAssertEqual(environment()["USER"], NSUserName())
    }

    func testTheBasicsTheAgentNeedsToRunAtAllArePassed() {
        let environment = environment()
        XCTAssertNotNil(environment["PATH"])
        XCTAssertNotNil(environment["HOME"], "the agents write scratch state under HOME")
        XCTAssertEqual(environment["NODE_ENV"], "production")
    }

    func testTheVendorCLIPathIsPassed() {
        XCTAssertEqual(environment()["CLAUDE_CODE_EXECUTABLE"], "/usr/local/bin/claude")
    }

    /// launchd's PATH, which is what an app launched from Finder inherits.
    private static let launchdPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    private func childPath(
        node: String = "/opt/homebrew/bin/node",
        vendorCLI: String = "/Users/x/.local/bin/claude",
        parentPath: String = AcpAgentEnvironmentTests.launchdPath
    ) -> [String] {
        AcpAgentProcess.childSearchPath(
            for: AcpAgentCommand(
                executable: URL(fileURLWithPath: node),
                arguments: ["/x/agent.mjs"],
                extraEnvironment: ["CLAUDE_CODE_EXECUTABLE": vendorCLI],
                stateDirectoryName: ".claude"
            ),
            environment: ["PATH": parentPath, "HOME": "/Users/x"]
        ).components(separatedBy: ":")
    }

    func testTheChildCanFindTheNodeItIsRunningUnder() {
        // The parent's PATH is launchd's when the app was launched from Finder,
        // and names none of the directories node or the vendor CLI live in --
        // so the CLI's own `node`/`git`/`rg` lookups all failed.
        XCTAssertTrue(childPath().contains("/opt/homebrew/bin"), "got: \(childPath())")
    }

    func testTheChildCanFindTheVendorCLIsOwnDirectory() {
        XCTAssertTrue(childPath().contains("/Users/x/.local/bin"), "got: \(childPath())")
    }

    func testTheWellKnownInstallDirectoriesAreOnTheChildsPath() {
        let path = childPath()
        for directory in ["/Users/x/.npm-global/bin", "/Users/x/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"] {
            XCTAssertTrue(path.contains(directory), "\(directory) missing from \(path)")
        }
    }

    func testWhateverTheParentAlreadyHadIsKeptAndComesFirst() {
        let path = childPath(parentPath: "/custom/bin:/usr/bin")

        XCTAssertEqual(path.first, "/custom/bin", "a user who set their own PATH keeps their order")
        XCTAssertTrue(path.contains("/usr/bin"))
    }

    func testTheChildsPathHasNoDuplicates() {
        let path = childPath(node: "/usr/bin/node", vendorCLI: "/usr/bin/claude")

        XCTAssertEqual(path.count, Set(path).count, "got: \(path)")
    }

    func testTheSystemDirectoriesSurviveAnEmptyParentPath() {
        let path = childPath(parentPath: "")

        XCTAssertTrue(path.contains("/usr/bin"))
        XCTAssertTrue(path.contains("/bin"))
        XCTAssertFalse(path.contains(""), "got: \(path)")
    }

    func testOnlyTheSelectedAgentsCredentialsAreForwarded() {
        let environment = environment(credentials: ["ANTHROPIC_API_KEY": "sk-test"])

        XCTAssertEqual(environment["ANTHROPIC_API_KEY"], "sk-test")
        // The parent's whole environment is not handed over -- a subprocess
        // has no business seeing every secret this process happens to hold.
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertNil(environment["AWS_SECRET_ACCESS_KEY"])
    }
}
