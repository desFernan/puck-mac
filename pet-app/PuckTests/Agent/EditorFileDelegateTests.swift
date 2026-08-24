//
//  EditorFileDelegateTests.swift
//  Puck
//
//  Covers EditorFileDelegate.readFile/openInEditor -- the read_file/
//  open_in_editor delegate bodies AgentRunner calls for these two tools.
//
//  EditorPaneStorePool.shared is a process-wide singleton with no eviction,
//  so every test uses its own freshly-generated workspaceId to avoid
//  cross-test collisions.
//

import XCTest
@testable import Puck

/// `@MainActor`: these reach into EditorPaneStorePool, which is the main
/// thread's -- the same actor the app's own callers are on.
@MainActor
final class EditorFileDelegateTests: XCTestCase {
    private func makeDelegate(resolveProjectPath: @escaping (String) -> String?) -> EditorFileDelegate {
        EditorFileDelegate(resolveProjectPath: resolveProjectPath)
    }

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("let x = 1".utf8).write(to: root.appendingPathComponent("main.swift"))
        return root
    }

    // MARK: - readFile

    func test_readFile_returnsContentAndMetadata() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceId = UUID().uuidString
        let delegate = makeDelegate(resolveProjectPath: { $0 == workspaceId ? root.path : nil })

        let result = await delegate.readFile(path: "main.swift", workspaceId: workspaceId)

        XCTAssertTrue(result.ok)
        guard case .object(let data)? = result.data else {
            return XCTFail("expected an object payload")
        }
        XCTAssertEqual(data["content"], .string("let x = 1"))
        XCTAssertEqual(data["language"], .string("swift"))
        XCTAssertEqual(data["readOnly"], .bool(false))
    }

    func test_readFile_noProjectBound_failsWithClearDetail() async {
        let delegate = makeDelegate(resolveProjectPath: { _ in nil })

        let result = await delegate.readFile(path: "main.swift", workspaceId: UUID().uuidString)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
        XCTAssertNotNil(result.detail)
    }

    func test_readFile_pathOutsideProject_fails() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceId = UUID().uuidString
        let delegate = makeDelegate(resolveProjectPath: { $0 == workspaceId ? root.path : nil })

        let result = await delegate.readFile(path: "../../etc/passwd", workspaceId: workspaceId)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
    }

    // MARK: - openInEditor

    func test_openInEditor_opensATabInThePoolsStore() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceId = UUID().uuidString
        let delegate = makeDelegate(resolveProjectPath: { $0 == workspaceId ? root.path : nil })

        let result = await delegate.openInEditor(path: "main.swift", workspaceId: workspaceId)

        XCTAssertTrue(result.ok)
        let store = EditorPaneStorePool.shared.existingStore(forWorkspace: workspaceId)
        XCTAssertEqual(store?.openTabs.map(\.path), ["main.swift"])
        XCTAssertEqual(store?.activeTabPath, "main.swift")
    }

    func test_openInEditor_noProjectBound_failsWithClearDetail() async {
        let delegate = makeDelegate(resolveProjectPath: { _ in nil })

        let result = await delegate.openInEditor(path: "main.swift", workspaceId: UUID().uuidString)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "execution_failed")
        XCTAssertNotNil(result.detail)
    }

    func test_openInEditor_reusesTheSameStoreAcrossCalls() async throws {
        let root = try makeProject()
        try Data("second file".utf8).write(to: root.appendingPathComponent("second.txt"))
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceId = UUID().uuidString
        let delegate = makeDelegate(resolveProjectPath: { $0 == workspaceId ? root.path : nil })

        _ = await delegate.openInEditor(path: "main.swift", workspaceId: workspaceId)
        _ = await delegate.openInEditor(path: "second.txt", workspaceId: workspaceId)

        let store = EditorPaneStorePool.shared.existingStore(forWorkspace: workspaceId)
        XCTAssertEqual(Set(store?.openTabs.map(\.path) ?? []), ["main.swift", "second.txt"], "both opens should land in the same store")
    }
}
