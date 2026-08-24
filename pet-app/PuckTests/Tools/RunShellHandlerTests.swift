//
//  RunShellHandlerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Argument validation + a real (harmless) command execution.
//

import XCTest
@testable import Puck

final class RunShellHandlerTests: XCTestCase {
    func test_missingCommand_failsWithExecutionFailed() {
        let handler = RunShellHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(id: "test", args: .object([:])) { result in
            switch result {
            case .success:
                XCTFail("expected failure")
            case .failure(let error):
                XCTAssertEqual(error, .executionFailed("run_shell requires a command string"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    /// The reported hang. A command that backgrounds anything leaves the
    /// grandchild holding the write end of both pipes, so EOF never comes --
    /// and the handler used to wait for EOF, not for the command. `npm run
    /// dev &` finished in milliseconds and was reported as a timeout a minute
    /// later, with a parked thread and a live call entry to show for it.
    func test_aCommandThatBackgroundsSomething_stillAnswersAtOnce() {
        let handler = RunShellHandler()

        let expectation = expectation(description: "completion called")
        // The backgrounded sleep outlives the shell by far more than the
        // three seconds this test is willing to wait.
        handler.execute(
            id: "test",
            args: .object(["command": .string("echo done; sleep 30 &")])
        ) { result in
            guard case .success(.object(let fields)?) = result else {
                XCTFail("expected success, got \(result)")
                return
            }
            XCTAssertEqual(fields["stdout"], .string("done\n"))
            XCTAssertEqual(fields["exit_code"], .number(0))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3)
    }

    func test_validCommand_returnsStdoutAndExitCode() {
        let handler = RunShellHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(id: "test", args: .object(["command": .string("echo hello")])) { result in
            switch result {
            case .success(let data):
                guard case .object(let fields)? = data else {
                    XCTFail("expected object result")
                    return
                }
                XCTAssertEqual(fields["stdout"], .string("hello\n"))
                XCTAssertEqual(fields["exit_code"], .number(0))
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    /// A child process writing more than the OS pipe buffer (64KB on macOS)
    /// blocks in write() until the parent drains the pipe. Waiting for exit
    /// before reading therefore deadlocks: the parent waits for a process that
    /// is waiting for the parent. Any real command the agent runs (a build, a
    /// test run, `git log`) clears 64KB easily.
    ///
    /// The whole stream is still read even though only the cap is kept -- the
    /// dropped count adding up to what was written is the proof.
    func test_outputLargerThanPipeBuffer_completesWithoutDeadlocking() {
        let handler = RunShellHandler()
        let byteCount = 200_000

        let expectation = expectation(description: "completion called")
        handler.execute(id: "test", args: .object(["command": .string("printf 'x%.0s' {1..\(byteCount)}")])) { result in
            switch result {
            case .success(let data):
                guard case .object(let fields)? = data else {
                    XCTFail("expected object result")
                    return
                }
                guard case .string(let stdout)? = fields["stdout"] else {
                    XCTFail("expected stdout string")
                    return
                }
                XCTAssertEqual(fields["truncated"], .bool(true))
                XCTAssertTrue(
                    stdout.contains("[... \(byteCount - RunShellHandler.maximumCapturedBytes) bytes of output dropped ...]"),
                    "every byte the command wrote should be accounted for"
                )
                XCTAssertEqual(fields["exit_code"], .number(0))
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
    }

    /// stderr fills its own pipe independently -- draining only stdout still
    /// deadlocks a command that is noisy on stderr.
    func test_stderrLargerThanPipeBuffer_completesWithoutDeadlocking() {
        let handler = RunShellHandler()
        let byteCount = 200_000

        let expectation = expectation(description: "completion called")
        handler.execute(id: "test", args: .object(["command": .string("printf 'e%.0s' {1..\(byteCount)} 1>&2")])) { result in
            switch result {
            case .success(let data):
                guard case .object(let fields)? = data, case .string(let stderr)? = fields["stderr"] else {
                    XCTFail("expected stderr string")
                    return
                }
                XCTAssertTrue(
                    stderr.contains("[... \(byteCount - RunShellHandler.maximumCapturedBytes) bytes of output dropped ...]")
                )
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
    }

    /// The gap the head buffer left: output longer than half the cap but
    /// shorter than the cap is not truncated, so all of it has to be there.
    /// It was not -- the middle was dropped and `truncated` said false.
    func test_outputUnderTheCap_isKeptWhole() {
        let handler = RunShellHandler()
        let byteCount = RunShellHandler.maximumCapturedBytes - 4096

        let expectation = expectation(description: "completion called")
        handler.execute(id: "test", args: .object(["command": .string("printf 'x%.0s' {1..\(byteCount)}")])) { result in
            guard case .success(.object(let fields)?) = result, case .string(let stdout)? = fields["stdout"] else {
                XCTFail("expected stdout string")
                return
            }
            XCTAssertEqual(stdout.count, byteCount)
            XCTAssertEqual(fields["truncated"], .bool(false))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 20)
    }

    /// What the cap is for: the answer travels over bridge.sock, which drops a
    /// message above 1 MiB outright -- so an uncapped `cat` of a large file did
    /// not arrive at all, and the dispatch sat there until it timed out.
    func test_hugeOutput_isKeptUnderTheBridgesMessageLimit() {
        let handler = RunShellHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(id: "test", args: .object(["command": .string("head -c 4000000 /dev/zero | tr '\\0' 'z'")])) { result in
            guard case .success(.object(let fields)?) = result, case .string(let stdout)? = fields["stdout"] else {
                XCTFail("expected stdout string")
                return
            }
            XCTAssertLessThan(stdout.utf8.count, BridgeConnection.maximumMessageBytes)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 20)
    }

    /// Head and tail, not head alone: a build log's errors are at the end, and
    /// keeping only the beginning would cut off the part the command was run
    /// for.
    func test_truncatedOutput_keepsBothEnds() {
        let handler = RunShellHandler()
        let filler = RunShellHandler.maximumCapturedBytes

        let expectation = expectation(description: "completion called")
        let command = "echo FIRST-LINE; printf 'x%.0s' {1..\(filler)}; echo; echo LAST-LINE"
        handler.execute(id: "test", args: .object(["command": .string(command)])) { result in
            guard case .success(.object(let fields)?) = result, case .string(let stdout)? = fields["stdout"] else {
                XCTFail("expected stdout string")
                return
            }
            XCTAssertTrue(stdout.hasPrefix("FIRST-LINE"), "the start of the output is kept")
            XCTAssertTrue(stdout.hasSuffix("LAST-LINE\n"), "so is the end, which is where errors are")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
    }

    /// A code review raised the concern that cancel() only terminates the
    /// direct zsh child, so a command that backgrounds a job (`sleep 30 &`)
    /// would survive as an orphan reparented to launchd. Verified false:
    /// Foundation's Process places its child in its own new process group,
    /// so terminate() (which signals that whole group, not just the one pid)
    /// already reaches jobs zsh backgrounded. This test is the regression
    /// guard for that verified behavior, not evidence of a bug that was fixed.
    func test_cancel_killsBackgroundedGrandchildProcesses() {
        let handler = RunShellHandler()
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck_test_bgpid_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        handler.execute(
            id: "test",
            args: .object(["command": .string("sleep 30 & echo $! > \(pidFile.path); sleep 30")])
        ) { _ in
            // Not expected to complete in this test -- cancelled instead.
        }

        guard let backgroundPID = Self.waitForPID(at: pidFile, timeout: 2) else {
            XCTFail("background job never reported its pid")
            return
        }
        XCTAssertEqual(kill(backgroundPID, 0), 0, "background job should still be alive before cancel")

        handler.cancel(id: "test")

        XCTAssertTrue(
            Self.waitUntilProcessDies(backgroundPID, timeout: 3),
            "cancel() must kill backgrounded child processes too, not just the direct zsh child"
        )
    }

    /// cancel() previously only sent SIGTERM (via Process.terminate()) with
    /// no escalation -- a command that traps/ignores SIGTERM survives
    /// indefinitely despite the caller already being told "cancelled" (found
    /// via review). This is the highest-privilege tool in the registry, so a
    /// cancel guarantee that a trap can defeat is worth closing.
    func test_cancel_escalatesToSIGKILL_whenTheProcessIgnoresSIGTERM() {
        let handler = RunShellHandler()
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck_test_trap_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        handler.execute(
            id: "test",
            args: .object(["command": .string("echo $$ > \(pidFile.path); trap '' TERM; sleep 30")])
        ) { _ in
            // Not expected to complete in this test -- killed instead.
        }

        guard let pid = Self.waitForPID(at: pidFile, timeout: 2) else {
            XCTFail("trap-resistant process never reported its pid")
            return
        }
        XCTAssertEqual(kill(pid, 0), 0, "process should still be alive before cancel")

        handler.cancel(id: "test")

        XCTAssertTrue(
            Self.waitUntilProcessDies(pid, timeout: 3),
            "cancel() must escalate to SIGKILL when the process ignores SIGTERM"
        )
    }

    /// terminate() on a Process that was never launched raises
    /// NSInvalidArgumentException, which in Swift is an uncatchable crash --
    /// so every path that leaves a stale Process behind is a crash waiting for
    /// the next cancel(). A failed run() is the reachable one: the handler is
    /// shared by every run_shell dispatch, so the stale process outlives the
    /// call that created it and a *later* call's timeout is what trips over it.
    func test_cancelAfterAFailedLaunch_doesNotTerminateAnUnlaunchedProcess() {
        let handler = RunShellHandler()

        RunShellHandler.shellPath = "/nonexistent/shell"
        defer { RunShellHandler.shellPath = "/bin/zsh" }

        let failed = expectation(description: "launch failed")
        handler.execute(id: "test", args: .object(["command": .string("true")])) { result in
            guard case .failure = result else {
                XCTFail("expected the launch to fail")
                return
            }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 5)

        // Nothing is in flight, so this must be a no-op rather than reaching
        // for the Process that never launched.
        handler.cancel(id: "test")
    }

    /// execute() publishes its Process before run() launches it, on a
    /// different queue. A cancel landing in that window used to crash on
    /// terminate(); it must instead still stop the child once it exists,
    /// because "cancelled" is reported to the agent either way and a
    /// still-running shell nobody can stop is the worst of both.
    func test_cancelBeforeTheProcessLaunches_stillKillsIt() {
        let handler = RunShellHandler()
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck_test_prelaunch_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        handler.execute(
            id: "test",
            args: .object(["command": .string("echo $$ > \(pidFile.path); sleep 30")])
        ) { _ in
            // Not expected to complete -- killed instead.
        }
        // No wait: the point is to race run(), so cancel goes out immediately.
        handler.cancel(id: "test")

        guard let pid = Self.waitForPID(at: pidFile, timeout: 2) else {
            return // never launched at all, which is also a stopped child
        }
        XCTAssertTrue(
            Self.waitUntilProcessDies(pid, timeout: 3),
            "a cancel that lands before launch must still stop the child"
        )
    }

    /// One handler instance serves every run_shell dispatch. Held as a single
    /// in-flight process, the second call overwrote the first, so a cancel
    /// meant for the first killed the second and left the first running with
    /// nobody able to reach it -- which is how a 60s timeout on an abandoned
    /// call took down a command the user was waiting on.
    func test_cancelOfOneCall_leavesAnotherCallsProcessAlone() {
        let handler = RunShellHandler()
        let directory = FileManager.default.temporaryDirectory
        let pidA = directory.appendingPathComponent("puck_test_a_\(UUID().uuidString).txt")
        let pidB = directory.appendingPathComponent("puck_test_b_\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: pidA)
            try? FileManager.default.removeItem(at: pidB)
        }

        let finishedA = expectation(description: "a replies")
        handler.execute(
            id: "a",
            args: .object(["command": .string("echo $$ > \(pidA.path); sleep 30")])
        ) { _ in finishedA.fulfill() }
        handler.execute(
            id: "b",
            args: .object(["command": .string("echo $$ > \(pidB.path); sleep 30")])
        ) { _ in
            // Not expected to complete -- outlives the test and is killed below.
        }

        guard
            let processA = Self.waitForPID(at: pidA, timeout: 2),
            let processB = Self.waitForPID(at: pidB, timeout: 2)
        else {
            XCTFail("both calls should have reported a pid")
            return
        }

        handler.cancel(id: "a")

        XCTAssertTrue(
            Self.waitUntilProcessDies(processA, timeout: 3),
            "the cancelled call's own process must die"
        )
        XCTAssertEqual(kill(processB, 0), 0, "the other call's process must be untouched")
        wait(for: [finishedA], timeout: 3)

        handler.cancel(id: "b")
        XCTAssertTrue(Self.waitUntilProcessDies(processB, timeout: 3))
    }

    private static func waitForPID(at file: URL, timeout: TimeInterval) -> pid_t? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: file, encoding: .utf8),
               let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            usleep(20_000)
        }
        return nil
    }

    private static func waitUntilProcessDies(_ pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            usleep(50_000)
        }
        return false
    }
}
