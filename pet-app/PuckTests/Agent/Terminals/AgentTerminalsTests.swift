//
//  AgentTerminalsTests.swift
//  PuckTests
//
//  Shells the agent starts and keeps talking to.
//
//  Against real processes rather than a double: the whole reason this type
//  exists is that a process outlives the call that started it, and a fake
//  that returns immediately would be testing the opposite of the thing.
//

import XCTest
@testable import Puck

final class AgentTerminalsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Polls until `condition` holds, because the thing being waited on is a
    /// real child process writing to a real pipe -- a fixed sleep long enough
    /// on an idle machine is not long enough on a busy one.
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

    /// The whole point: `start` answers while the command is still running.
    func test_startingReturnsBeforeTheCommandFinishes() throws {
        let terminals = AgentTerminals()
        defer { terminals.stopAll() }

        let session = try terminals.start(command: "sleep 30", workingDirectory: directory.path)

        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.command, "sleep 30")
        XCTAssertFalse(session.id.isEmpty)
    }

    /// And what it says arrives as it says it, rather than at the end.
    func test_outputCanBeReadWhileItIsStillRunning() throws {
        let terminals = AgentTerminals()
        defer { terminals.stopAll() }
        let session = try terminals.start(
            command: "echo 처음; sleep 30",
            workingDirectory: directory.path
        )

        var seen = ""
        waitUntil { seen += ((try? terminals.read(id: session.id).read.text) ?? ""); return seen.contains("처음") }

        let summary = try terminals.read(id: session.id).summary
        XCTAssertTrue(summary.isRunning, "reading must not wait for the command to end")
    }

    /// stdout and stderr on one stream, because the order they were written
    /// in is the only thing that makes a log readable.
    func test_errorsAndOutputArriveInTheOrderTheyWereWritten() throws {
        let terminals = AgentTerminals()
        defer { terminals.stopAll() }
        let session = try terminals.start(
            command: "echo one; echo two >&2; echo three",
            workingDirectory: directory.path
        )

        var seen = ""
        waitUntil { seen += ((try? terminals.read(id: session.id).read.text) ?? ""); return seen.contains("three") }

        let lines = seen.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, ["one", "two", "three"])
    }

    /// A command that ends is still readable afterwards -- the last thing a
    /// crashed server said is the whole reason to look.
    func test_aFinishedSessionKeepsItsLastWords() throws {
        let terminals = AgentTerminals()
        defer { terminals.stopAll() }
        let session = try terminals.start(command: "echo 끝; exit 3", workingDirectory: directory.path)

        waitUntil { ((try? terminals.read(id: session.id).summary.isRunning) ?? true) == false }

        // 읽기 커서는 이미 소비했을 수 있으니 전체 목록으로 상태를 본다.
        let summary = try XCTUnwrap(terminals.list().first { $0.id == session.id })
        XCTAssertFalse(summary.isRunning)
        XCTAssertEqual(summary.exitCode, 3)
    }

    /// The command runs where the project is, not where the app happens to be.
    func test_aSessionStartsInTheDirectoryItWasGiven() throws {
        let terminals = AgentTerminals()
        defer { terminals.stopAll() }
        let session = try terminals.start(command: "pwd", workingDirectory: directory.path)

        var seen = ""
        waitUntil { seen += ((try? terminals.read(id: session.id).read.text) ?? ""); return !seen.isEmpty }

        // /var 와 /private/var 는 같은 곳이다.
        XCTAssertTrue(
            seen.contains(directory.lastPathComponent),
            "started somewhere else: \(seen)"
        )
    }

    /// Typing into one, which is what a prompt waiting for an answer needs.
    func test_aSessionCanBeTypedInto() throws {
        let terminals = AgentTerminals()
        defer { terminals.stopAll() }
        let session = try terminals.start(command: "read line; echo 받음:$line", workingDirectory: directory.path)

        try terminals.send(id: session.id, text: "안녕")

        var seen = ""
        waitUntil { seen += ((try? terminals.read(id: session.id).read.text) ?? ""); return seen.contains("받음:") }
        XCTAssertTrue(seen.contains("받음:안녕"), seen)
    }

    /// A model in a loop will start one per turn, so there is a cap.
    func test_thereIsALimitOnHowManyRunAtOnce() throws {
        let terminals = AgentTerminals()
        defer { terminals.stopAll() }
        for _ in 0..<AgentTerminals.maximumSessions {
            _ = try terminals.start(command: "sleep 30", workingDirectory: directory.path)
        }

        XCTAssertThrowsError(try terminals.start(command: "sleep 30", workingDirectory: directory.path)) { error in
            guard case AgentTerminalError.tooManySessions(let limit) = error else {
                return XCTFail("expected .tooManySessions, got \(error)")
            }
            XCTAssertEqual(limit, AgentTerminals.maximumSessions)
        }
    }

    /// And a finished one does not count against it: it holds no process.
    func test_aFinishedSessionDoesNotUseUpTheLimit() throws {
        let terminals = AgentTerminals(makeIdentifier: { UUID().uuidString })
        defer { terminals.stopAll() }
        for _ in 0..<AgentTerminals.maximumSessions {
            _ = try terminals.start(command: "true", workingDirectory: directory.path)
        }
        waitUntil { terminals.list().allSatisfy { !$0.isRunning } }

        XCTAssertNoThrow(try terminals.start(command: "sleep 30", workingDirectory: directory.path))
    }

    /// Stopping ends the process and leaves the output.
    func test_stoppingEndsItAndKeepsWhatItSaid() throws {
        let terminals = AgentTerminals()
        defer { terminals.stopAll() }
        let session = try terminals.start(command: "echo 살아있음; sleep 30", workingDirectory: directory.path)
        var seen = ""
        waitUntil { seen += ((try? terminals.read(id: session.id).read.text) ?? ""); return seen.contains("살아있음") }

        try terminals.stop(id: session.id)

        waitUntil { ((try? terminals.read(id: session.id).summary.isRunning) ?? true) == false }
        XCTAssertNoThrow(try terminals.read(id: session.id), "a stopped session is still readable")
    }

    /// An id nobody minted is a failure with a name, not a crash.
    func test_anUnknownSessionIsRefusedByName() {
        let terminals = AgentTerminals()

        XCTAssertThrowsError(try terminals.read(id: "없는-id")) { error in
            guard case AgentTerminalError.unknownSession = error else {
                return XCTFail("expected .unknownSession, got \(error)")
            }
        }
    }

    /// And typing into one that has ended says so rather than writing into a
    /// closed pipe.
    func test_typingIntoAFinishedSessionIsRefused() throws {
        let terminals = AgentTerminals()
        defer { terminals.stopAll() }
        let session = try terminals.start(command: "true", workingDirectory: directory.path)
        waitUntil { ((try? terminals.read(id: session.id).summary.isRunning) ?? true) == false }

        XCTAssertThrowsError(try terminals.send(id: session.id, text: "늦었어요")) { error in
            guard case AgentTerminalError.sessionEnded = error else {
                return XCTFail("expected .sessionEnded, got \(error)")
            }
        }
    }

    /// An empty command is refused before a shell is spawned to run nothing.
    func test_anEmptyCommandIsRefused() {
        let terminals = AgentTerminals()

        XCTAssertThrowsError(try terminals.start(command: "   ", workingDirectory: directory.path))
    }
}
