//
//  GitStatusReaderTests.swift
//  PuckTests
//
//  Runs against real repositories in a temp directory rather than a fake
//  git: what is being checked is what git actually answers, and a fake would
//  only prove that the fake agrees with itself.
//

import XCTest

@testable import Puck

final class GitStatusReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try XCTSkipIf(GitStatusReader.executable() == nil, "no git on this machine")
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = try XCTUnwrap(GitStatusReader.executable())
        process.arguments = ["-C", (directory ?? root).path] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func write(_ contents: String, at relativePath: String) throws {
        let target = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
    }

    private func makeRepository(branch: String = "main") throws {
        try git(["init", "--initial-branch", branch])
        try git(["config", "user.email", "test@example.com"])
        try git(["config", "user.name", "Test"])
    }

    func test_branch_namesTheBranchTheProjectIsOn() throws {
        try makeRepository(branch: "feature/island")
        try write("x", at: "a.txt")
        try git(["add", "."])
        try git(["commit", "-m", "first"])

        XCTAssertEqual(GitStatusReader.branch(projectPath: root.path), "feature/island")
    }

    /// A directory that is not a repository has no branch, and saying so is
    /// the difference between "no branch" and "branch called HEAD".
    func test_branch_isNilOutsideARepository() throws {
        XCTAssertNil(GitStatusReader.branch(projectPath: root.path))
    }

    /// A detached HEAD answers "HEAD", which is not a name anybody wants
    /// drawn in a sidebar.
    func test_branch_isNilWhenHeadIsDetached() throws {
        try makeRepository()
        try write("x", at: "a.txt")
        try git(["add", "."])
        try git(["commit", "-m", "first"])
        let head = try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try git(["checkout", head])

        XCTAssertNil(GitStatusReader.branch(projectPath: root.path))
    }

    /// git answers in paths relative to the repository root. A workspace one
    /// directory down deals in its own, and the two have to be made to agree
    /// or nothing in the file tree matches.
    func test_read_reportsPathsRelativeToTheWorkspace() throws {
        try makeRepository()
        try write("one", at: "app/Sources/a.txt")
        try write("two", at: "docs/readme.md")
        try git(["add", "."])
        try git(["commit", "-m", "first"])
        try write("changed", at: "app/Sources/a.txt")
        try write("changed", at: "docs/readme.md")

        let status = try XCTUnwrap(GitStatusReader.read(projectPath: root.appendingPathComponent("app").path))

        XCTAssertEqual(status.files.map(\.path), ["Sources/a.txt"], "and what is outside the workspace is left out")
        XCTAssertEqual(status.branch, "main")
    }

    /// From the root itself the paths are already relative to the workspace,
    /// so nothing is stripped.
    func test_read_fromTheRepositoryRootKeepsWholePaths() throws {
        try makeRepository()
        try write("one", at: "app/Sources/a.txt")
        try git(["add", "."])
        try git(["commit", "-m", "first"])
        try write("changed", at: "app/Sources/a.txt")

        let status = try XCTUnwrap(GitStatusReader.read(projectPath: root.path))

        XCTAssertEqual(status.files.map(\.path), ["app/Sources/a.txt"])
    }

    func test_read_isNilOutsideARepository() {
        XCTAssertNil(GitStatusReader.read(projectPath: root.path))
    }
}
