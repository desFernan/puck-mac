//
//  ToolTrustTests.swift
//  PuckTests
//
//  Saying yes to a tool for good, and taking it back.
//

import XCTest
@testable import Puck

@MainActor
final class ToolTrustStoreTests: XCTestCase {
    private var storageURL: URL!

    override func setUpWithError() throws {
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("trusted-tools.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
    }

    private func store() -> ToolTrustStore { ToolTrustStore(storageURL: storageURL) }

    func test_aToolIsAskedAboutUntilItIsTrusted() {
        let trust = store()

        XCTAssertFalse(trust.isTrusted(tool: "run_shell", workspaceId: "w1"))
        trust.trust(tool: "run_shell", workspaceId: "w1")

        XCTAssertTrue(trust.isTrusted(tool: "run_shell", workspaceId: "w1"))
    }

    /// The scope of the decision. Letting an agent run the build in a project
    /// you own says nothing about the next project.
    func test_trustIsPerWorkspaceAndDoesNotLeakToAnother() {
        let trust = store()

        trust.trust(tool: "run_shell", workspaceId: "w1")

        XCTAssertFalse(trust.isTrusted(tool: "run_shell", workspaceId: "w2"))
    }

    /// And per tool: allowing the build is not allowing everything.
    func test_trustingOneToolDoesNotTrustTheRest() {
        let trust = store()

        trust.trust(tool: "run_shell", workspaceId: "w1")

        XCTAssertFalse(trust.isTrusted(tool: "run_applescript", workspaceId: "w1"))
    }

    func test_itSurvivesARestart() {
        store().trust(tool: "run_shell", workspaceId: "w1")

        XCTAssertTrue(store().isTrusted(tool: "run_shell", workspaceId: "w1"))
    }

    func test_revokingOneLeavesTheRest() {
        let trust = store()
        trust.trust(tool: "run_shell", workspaceId: "w1")
        trust.trust(tool: "run_applescript", workspaceId: "w1")

        trust.revoke(tool: "run_shell", workspaceId: "w1")

        XCTAssertFalse(trust.isTrusted(tool: "run_shell", workspaceId: "w1"))
        XCTAssertTrue(trust.isTrusted(tool: "run_applescript", workspaceId: "w1"))
    }

    func test_everythingCanBeTakenBackAtOnce() {
        let trust = store()
        trust.trust(tool: "run_shell", workspaceId: "w1")
        trust.trust(tool: "click_element", workspaceId: "w2")

        trust.revokeAll()

        XCTAssertTrue(trust.entries.isEmpty)
        XCTAssertTrue(store().entries.isEmpty, "and stays taken back")
    }

    /// A workspace id is reused by nothing, so a decision left behind is a
    /// row nobody can find to revoke.
    func test_aDeletedWorkspaceTakesItsTrustWithIt() {
        let trust = store()
        trust.trust(tool: "run_shell", workspaceId: "w1")
        trust.trust(tool: "run_shell", workspaceId: "w2")

        trust.revokeAll(inWorkspace: "w1")

        XCTAssertFalse(trust.isTrusted(tool: "run_shell", workspaceId: "w1"))
        XCTAssertTrue(trust.isTrusted(tool: "run_shell", workspaceId: "w2"))
    }

    /// The list has to be stable to be readable.
    func test_theListIsSortedRatherThanInWhateverOrderTheyWereAdded() {
        let trust = store()
        trust.trust(tool: "run_shell", workspaceId: "w2")
        trust.trust(tool: "click_element", workspaceId: "w1")
        trust.trust(tool: "run_applescript", workspaceId: "w1")

        XCTAssertEqual(
            trust.entries.map { "\($0.workspaceId)/\($0.tool)" },
            ["w1/click_element", "w1/run_applescript", "w2/run_shell"]
        )
    }

    /// The gate reads this from inside a run, on whatever executor that turn
    /// is on -- it has to answer there without suspending.
    func test_itCanBeAskedFromOffTheMainThread() async {
        let trust = store()
        trust.trust(tool: "run_shell", workspaceId: "w1")

        let answer = await Task.detached { trust.isTrusted(tool: "run_shell", workspaceId: "w1") }.value

        XCTAssertTrue(answer)
    }
}
