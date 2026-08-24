//
//  CodeTourDelegateTests.swift
//  Puck
//
//  show_code's body. Nothing here has an editor pane on screen, so the
//  point_at half is covered by its absence: the stop still succeeds, with a
//  reason, because the highlight is the part that always works.
//
//  EditorPaneStorePool.shared is a process-wide singleton with no eviction,
//  so every test uses its own freshly-generated workspaceId.
//

import XCTest
import CoreGraphics
@testable import Puck

final class CodeTourDelegateTests: XCTestCase {
    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("line1\nline2\nline3\n".utf8).write(to: root.appendingPathComponent("main.swift"))
        return root
    }

    /// A project with the shape that made the fallback necessary: the file
    /// the model names by bare name is buried, and another name is
    /// deliberately duplicated across two directories.
    private func makeNestedProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for directory in ["app/agent", "client"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try Data("a\nb\nc\n".utf8).write(to: root.appendingPathComponent("app/agent/Runner.swift"))
        try Data("a\nb\nc\n".utf8).write(to: root.appendingPathComponent("app/agent/AppDelegate.swift"))
        try Data("a\nb\nc\n".utf8).write(to: root.appendingPathComponent("client/AppDelegate.swift"))
        return root
    }

    func test_noProjectBound_failsWithAReason() async {
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in nil },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "a.swift", startLine: 1, endLine: 2, workspaceId: "w")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
        XCTAssertNotNil(result.detail)
    }

    /// A model that is a few lines off must not abort the tour.
    func test_lineNumbersPastTheEndAreClamped() {
        XCTAssertEqual(CodeTourDelegate.clamp(start: 1, end: 999, lineCount: 3), 1...3)
        XCTAssertEqual(CodeTourDelegate.clamp(start: 2, end: 2, lineCount: 3), 2...2)
        XCTAssertNil(CodeTourDelegate.clamp(start: 10, end: 12, lineCount: 3), "past the end entirely")
        XCTAssertEqual(CodeTourDelegate.clamp(start: 0, end: 2, lineCount: 3), 1...2, "1-indexed")
        XCTAssertEqual(CodeTourDelegate.clamp(start: 3, end: 1, lineCount: 3), 3...3, "end before start")
    }

    /// The stop opens the tab, shows the pane and publishes the range, even
    /// with no screen to point at.
    @MainActor
    func test_opensTheTabAndPublishesTheRange() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceId = UUID().uuidString
        var shownPanes: [String] = []
        let sut = CodeTourDelegate(
            resolveProjectPath: { $0 == workspaceId ? root.path : nil },
            showEditorPane: { workspace, _ in shownPanes.append(workspace) },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "main.swift", startLine: 2, endLine: 2, workspaceId: workspaceId)

        let store = try EditorPaneStorePool.shared.store(forWorkspace: workspaceId, root: root, onRootChanged: {})
        XCTAssertEqual(store.activeTabPath, "main.swift")
        XCTAssertEqual(store.pendingReveal?.lines, 2...2)
        XCTAssertEqual(shownPanes, [workspaceId])
        // No pane on screen in a test run, so the pet cannot be sent -- but
        // the code is highlighted, which is the half that matters.
        XCTAssertTrue(result.ok)
        XCTAssertNotNil(result.detail)
    }

    /// Naming a line the file does not have fails instead of pointing the pet
    /// at an arbitrary part of the file.
    @MainActor
    func test_startPastTheEndOfTheFileFails() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceId = UUID().uuidString
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in root.path },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "main.swift", startLine: 99, endLine: 100, workspaceId: workspaceId)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
    }

    @MainActor
    func test_missingFileFails() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in root.path },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "gone.swift", startLine: 1, endLine: 1, workspaceId: UUID().uuidString)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
    }

    /// The model guesses paths -- it called show_code with a bare
    /// "AgentRunner.swift" on the first live run -- so a not-found failure
    /// says what a path is supposed to look like instead of only that this
    /// one was wrong.
    @MainActor
    func test_missingFileSaysHowPathsWork() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in root.path },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "gone.swift", startLine: 1, endLine: 1, workspaceId: UUID().uuidString)

        let detail = try XCTUnwrap(result.detail)
        // The key, not the words: the test host is the Puck app, so it comes
        // up in whatever language the machine has saved.
        XCTAssertTrue(detail.contains(Strings.text(.toolPathIsRelativeHint)), detail)
        XCTAssertTrue(detail.contains("list_files"), detail)
    }

    /// Only for failures a different path would fix. Telling the model to
    /// check list_files about a file that is simply too large sends it
    /// looking in the wrong place.
    func test_onlyPathFailuresGetThePathHint() {
        let tooLarge = WorkspaceFileServiceError(code: .fileTooLarge, message: "파일이 너무 커요")
        XCTAssertEqual(tooLarge.agentDetail, "파일이 너무 커요")
    }

    /// The model names files by their bare name often enough to answer it
    /// (seen live), and list_files cannot rescue it in a big project -- that
    /// list truncates long before the file it wants.
    @MainActor
    func test_bareFileNameResolvesWhenOnlyOneFileHasIt() async throws {
        let root = try makeNestedProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceId = UUID().uuidString
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in root.path },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(path: "Runner.swift", startLine: 1, endLine: 2, workspaceId: workspaceId)

        XCTAssertTrue(result.ok)
        let store = try EditorPaneStorePool.shared.store(forWorkspace: workspaceId, root: root, onRootChanged: {})
        XCTAssertEqual(store.activeTabPath, "app/agent/Runner.swift")
        XCTAssertEqual(store.pendingReveal?.path, "app/agent/Runner.swift", "the reveal follows the resolved path")
    }

    /// Two files can share a name -- this repo has AppDelegate.swift twice.
    /// Picking one would put the pet in front of a file nobody asked about,
    /// so the model chooses, with the candidates already in hand.
    @MainActor
    func test_ambiguousFileNameFailsWithTheCandidates() async throws {
        let root = try makeNestedProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let sut = CodeTourDelegate(
            resolveProjectPath: { _ in root.path },
            showEditorPane: { _, _ in },
            point: { _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) }
        )

        let result = await sut.showCode(
            path: "AppDelegate.swift", startLine: 1, endLine: 1, workspaceId: UUID().uuidString
        )

        XCTAssertFalse(result.ok)
        let detail = try XCTUnwrap(result.detail)
        XCTAssertTrue(detail.contains("app/agent/AppDelegate.swift"), detail)
        XCTAssertTrue(detail.contains("client/AppDelegate.swift"), detail)
    }

    func test_candidatesMatchOnTheFileNameOnly() {
        let tree = [
            FileTreeEntry(name: "app", path: "app", kind: .directory, children: [
                FileTreeEntry(name: "Runner.swift", path: "app/Runner.swift", kind: .file, children: nil),
                FileTreeEntry(name: "Other.swift", path: "app/Other.swift", kind: .file, children: nil),
            ]),
        ]

        XCTAssertEqual(CodeTourDelegate.candidates(matching: "Runner.swift", in: tree), ["app/Runner.swift"])
        XCTAssertEqual(
            CodeTourDelegate.candidates(matching: "wherever/Runner.swift", in: tree),
            ["app/Runner.swift"],
            "a wrong directory with the right file name still resolves"
        )
        XCTAssertEqual(CodeTourDelegate.candidates(matching: "Missing.swift", in: tree), [])
    }
}
