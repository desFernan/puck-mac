//
//  WorkspaceRegistryTests.swift
//  PuckTests
//
//  Ports workspace/src/main/workspace-registry.test.ts, plus the cases that
//  only matter once pet-app owns the file itself (symlink resolution, a
//  missing project path, a corrupt store).
//

import XCTest
@testable import Puck

final class WorkspaceRegistryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkspaceRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func storageURL() -> URL {
        // Nested on purpose: persist() has to create intermediate directories,
        // the way the TS version's mkdir({recursive:true}) did.
        root.appendingPathComponent("data/workspaces.json")
    }

    private func makeProject(named name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Default workspace

    func testStartsWithADefaultWorkspace() throws {
        let registry = try WorkspaceRegistry(storageURL: storageURL())

        let workspaces = registry.list()

        XCTAssertEqual(workspaces.count, 1)
        XCTAssertEqual(workspaces.first?.id, "default")
        XCTAssertNil(workspaces.first?.projectPath)
    }

    func testDefaultWorkspaceCannotBeRemoved() throws {
        let registry = try WorkspaceRegistry(storageURL: storageURL())

        XCTAssertFalse(try registry.remove(id: "default"))
        XCTAssertEqual(registry.list().count, 1)
    }

    // MARK: - Persistence

    func testCreatedWorkspaceSurvivesAReload() throws {
        let project = try makeProject(named: "project")
        let created = try WorkspaceRegistry(storageURL: storageURL())
            .create(name: "puck", projectPath: project.path)

        let restored = try WorkspaceRegistry(storageURL: storageURL())

        let record = restored.get(id: created.id)
        XCTAssertEqual(record?.name, "puck")
        XCTAssertEqual(record?.projectPath, project.resolvingSymlinksInPath().path)
        XCTAssertEqual(restored.list().count, 2, "the default workspace is still there alongside it")
    }

    func testRemovalSurvivesAReload() throws {
        let storage = storageURL()
        let created = try WorkspaceRegistry(storageURL: storage).create(name: "temp", projectPath: nil)

        XCTAssertTrue(try WorkspaceRegistry(storageURL: storage).remove(id: created.id))

        XCTAssertNil(try WorkspaceRegistry(storageURL: storage).get(id: created.id))
    }

    func testACorruptStoreFallsBackToTheDefaultWorkspace() throws {
        let storage = storageURL()
        try FileManager.default.createDirectory(
            at: storage.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json at all".utf8).write(to: storage)

        // Must not throw: a store we can't read is not a reason to refuse to
        // start (the same independence principle BridgeServer's start follows).
        let registry = try WorkspaceRegistry(storageURL: storage)

        XCTAssertEqual(registry.list().map(\.id), ["default"])
    }

    func testAStoreFromAFutureVersionIsIgnoredRatherThanMisread() throws {
        let storage = storageURL()
        try FileManager.default.createDirectory(
            at: storage.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"version":2,"workspaces":[{"id":"x","name":"x","createdAt":0,"updatedAt":0}]}"#.utf8)
            .write(to: storage)

        let registry = try WorkspaceRegistry(storageURL: storage)

        XCTAssertEqual(registry.list().map(\.id), ["default"])
    }

    // MARK: - Project paths

    func testProjectPathIsResolvedThroughSymlinks() throws {
        let project = try makeProject(named: "real")
        let link = root.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: project)

        let record = try WorkspaceRegistry(storageURL: storageURL())
            .create(name: "linked", projectPath: link.path)

        XCTAssertEqual(record.realProjectPath, project.resolvingSymlinksInPath().path)
    }

    func testCreateRejectsAProjectPathThatDoesNotExist() throws {
        let registry = try WorkspaceRegistry(storageURL: storageURL())

        XCTAssertThrowsError(
            try registry.create(name: "gone", projectPath: root.appendingPathComponent("nope").path)
        ) { error in
            XCTAssertEqual(error as? WorkspaceRegistryError, .projectPathUnusable)
        }
    }

    func testCreateRejectsAProjectPathThatIsAFile() throws {
        let file = root.appendingPathComponent("a-file.txt")
        try Data("x".utf8).write(to: file)
        let registry = try WorkspaceRegistry(storageURL: storageURL())

        XCTAssertThrowsError(try registry.create(name: "file", projectPath: file.path)) { error in
            XCTAssertEqual(error as? WorkspaceRegistryError, .projectPathUnusable)
        }
    }

    func testBindProjectUpdatesPathAndTimestamp() throws {
        let project = try makeProject(named: "later")
        let registry = try WorkspaceRegistry(storageURL: storageURL())
        let created = try registry.create(name: "empty", projectPath: nil)

        let bound = try registry.bindProject(id: created.id, projectPath: project.path)

        XCTAssertEqual(bound.projectPath, project.resolvingSymlinksInPath().path)
        XCTAssertGreaterThanOrEqual(bound.updatedAt, created.updatedAt)
    }

    func testBindProjectOnAnUnknownWorkspaceThrows() throws {
        let project = try makeProject(named: "orphan")
        let registry = try WorkspaceRegistry(storageURL: storageURL())

        XCTAssertThrowsError(try registry.bindProject(id: "missing", projectPath: project.path)) { error in
            XCTAssertEqual(error as? WorkspaceRegistryError, .notFound)
        }
    }

    // MARK: - Naming

    func testABlankNameFallsBackRatherThanPersistingAnEmptyLabel() throws {
        let registry = try WorkspaceRegistry(storageURL: storageURL())

        let record = try registry.create(name: "   ", projectPath: nil)

        XCTAssertEqual(record.name, "Workspace")
    }

    /// Starting empty over a store we could not parse is survivable -- it is
    /// metadata, not files. Writing a fresh one *over* it is not: that is the
    /// only copy of every workspace the user had, and a store written by a
    /// newer build they might go back to reads as unparseable here too.
    func test_anUnreadableStoreIsKeptRatherThanOverwritten() throws {
        let url = storageURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ this is not the store }".utf8).write(to: url)

        let registry = try WorkspaceRegistry(storageURL: url)
        _ = try registry.create(name: "New", projectPath: nil)

        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        let kept = siblings.filter { $0.contains("unreadable-") }
        XCTAssertEqual(kept.count, 1, "the store that could not be read is kept beside the new one")
        let keptContents = try String(
            contentsOf: url.deletingLastPathComponent().appendingPathComponent(kept[0]),
            encoding: .utf8
        )
        XCTAssertEqual(keptContents, "{ this is not the store }")
        XCTAssertTrue(registry.list().map(\.name).contains("New"), "and the new one is usable")
    }

    /// Only once. A backup per save would fill the folder with copies of the
    /// same broken file.
    func test_onlyOneBackupIsKept() throws {
        let url = storageURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: url)

        let registry = try WorkspaceRegistry(storageURL: url)
        _ = try registry.create(name: "One", projectPath: nil)
        _ = try registry.create(name: "Two", projectPath: nil)

        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(siblings.filter { $0.contains("unreadable-") }.count, 1)
    }
}
