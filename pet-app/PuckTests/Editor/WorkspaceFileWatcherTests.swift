//
//  WorkspaceFileWatcherTests.swift
//  Puck
//

import CoreServices
import XCTest
@testable import Puck

final class WorkspaceFileWatcherTests: XCTestCase {
    private func flags(_ names: FSEventStreamEventFlags...) -> FSEventStreamEventFlags {
        names.reduce(0) { $0 | $1 }
    }

    private let isDir = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)
    private let removed = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)
    private let created = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
    private let modified = FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
    private let renamed = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
    private let rootChanged = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)

    func test_classify_fileCreated() {
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: flags(created)), .change(.add))
    }

    func test_classify_directoryCreated() {
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: flags(created, isDir)), .change(.addDir))
    }

    func test_classify_fileRemoved() {
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: flags(removed)), .change(.unlink))
    }

    func test_classify_directoryRemoved() {
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: flags(removed, isDir)), .change(.unlinkDir))
    }

    func test_classify_fileModified() {
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: flags(modified)), .change(.change))
    }

    func test_classify_fileRenamed() {
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: flags(renamed)), .change(.change))
    }

    func test_classify_directoryRenamed() {
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: flags(renamed, isDir)), .change(.addDir))
    }

    func test_classify_removedTakesPrecedenceOverCreated() {
        // Shouldn't happen in practice, but removal must win if both bits
        // are somehow set -- "gone" is the safer signal to act on.
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: flags(removed, created)), .change(.unlink))
    }

    func test_classify_rootChanged_takesPrecedenceOverEverything() {
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: flags(rootChanged, created)), .rootChanged)
    }

    func test_classify_noRecognizedBits_isIgnored() {
        XCTAssertEqual(WorkspaceFileWatcher.classify(flags: 0), .ignore)
    }

    // MARK: - Real stream smoke test

    func test_start_firesOnChangeForARealFileWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let expectation = expectation(description: "onChange fires for a new file")
        // One write is not one callback. FSEvents reports create and modify
        // separately and only coalesces them when they land inside the same
        // 0.1s window, so a second delivery is normal behaviour rather than
        // something to fail on -- and over-fulfilment is an outright test
        // failure by default, which is what made this flake.
        expectation.assertForOverFulfill = false
        let watcher = WorkspaceFileWatcher(
            root: root,
            onChange: { _ in expectation.fulfill() },
            onRootChanged: {}
        )
        watcher.start()
        defer { watcher.stop() }

        // FSEventStreamStart needs a moment to actually begin delivering
        // before the write below is guaranteed to be observed.
        Thread.sleep(forTimeInterval: 0.3)
        try Data("x".utf8).write(to: root.appendingPathComponent("new-file.txt"))

        // A real OS-level event, so a generous bound: under a full-suite run
        // with many other tests doing concurrent file I/O, FSEvents delivery
        // (plus this type's own 0.1s coalescing latency) can lag well past a
        // tight timeout without anything actually being wrong.
        wait(for: [expectation], timeout: 15)
    }
}
