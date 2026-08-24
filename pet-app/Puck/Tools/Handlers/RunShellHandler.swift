//
//  RunShellHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Process + /bin/zsh -lc, returns stdout/stderr/exit code
//

import Foundation

/// args: `{"command": "..."}`. Approval-gated per the tool registry (except a
/// whitelist) — approval itself happens upstream in the agent core; this
/// handler only executes.
/// `@unchecked Sendable`: `calls` is guarded by `stateQueue` -- see its own
/// note about the three execution contexts that reach it -- and everything
/// else here is a constant.
final class RunShellHandler: ToolHandler, @unchecked Sendable {
    let toolName = "run_shell"

    /// How long a SIGTERM'd process gets before cancel() escalates to
    /// SIGKILL. Process.terminate() alone left a command that traps/ignores
    /// SIGTERM running forever despite the caller already being told
    /// "cancelled" (found via review) -- this is the highest-privilege tool
    /// in the registry, so its cancel guarantee shouldn't be defeatable by a
    /// trap.
    ///
    /// `nonisolated(unsafe)`: a knob two tests turn down so they do not wait
    /// half a second, read once per cancel from whichever queue that lands
    /// on. Nothing in the app writes it.
    nonisolated(unsafe) static var killGracePeriod: TimeInterval = 0.5

    /// How long the output collectors get after the command has exited.
    ///
    /// The exit and the last write race each other, so this is what stops the
    /// tail of the output being dropped. It is short because the usual answer
    /// is "already here": the only case that spends the whole of it is a
    /// command that left something running with the pipe still open, and
    /// there the wait is capped rather than endless.
    static let drainGraceAfterExit: TimeInterval = 0.2

    /// How much of one stream is kept, per call. Nothing capped this: the
    /// handler read both pipes to EOF, so `cat` on a large file or a `find /`
    /// grew a String as large as the output and then handed it on. Two things
    /// then went wrong at once -- BridgeConnection drops a message over
    /// `maximumMessageBytes` (1 MiB), so the answer never arrived and the
    /// dispatch waited out its full timeout instead; and what did fit went
    /// into the model's context whole.
    ///
    /// Head and tail rather than head alone: a build log's errors are at the
    /// end, and a truncation that always kept the beginning would cut off the
    /// part the command was run for.
    static let maximumCapturedBytes = 128 * 1024

    /// The shell every command runs under. A `var` only so a test can point it
    /// at something that cannot launch -- a failed `run()` is otherwise
    /// unreachable from outside, and it is the path that used to leave a
    /// never-launched Process behind for the next cancel() to crash on.
    /// `nonisolated(unsafe)` for the same reason as killGracePeriod above:
    /// written only by the test that points it at a shell that cannot
    /// launch, read on the queue the command runs from.
    nonisolated(unsafe) static var shellPath = "/bin/zsh"

    /// One dispatch's shell.
    ///
    /// `process` is published before `run()` launches it -- those happen on
    /// different queues -- so between the two it is a Process object with no
    /// child behind it. terminate() on one of those raises
    /// NSInvalidArgumentException, an ObjC exception, which in Swift is a
    /// crash the call site cannot catch, so `cancel` checks `isRunning` and
    /// leaves `isCancelled` behind instead; the launch side reads it and kills
    /// the child as soon as there is one. Without that a cancel landing in the
    /// window either crashed the app or was silently dropped, leaving the
    /// highest-privilege tool in the registry running with nobody able to
    /// stop it.
    private final class Call {
        var process: Process?
        var isCancelled = false
    }

    /// Keyed by dispatch id, because one handler instance serves every
    /// run_shell call. Held as a single in-flight process, a 60s timeout for
    /// call A fired `terminate` on whatever process call B had just started,
    /// and left A's own shell running unreachable.
    ///
    /// `execute` adds on whatever queue the caller runs on, the background
    /// block removes on completion, and `cancel` can arrive from ToolExecutor's
    /// own queue -- three different execution contexts, so access is guarded
    /// rather than a bare stored property.
    private let stateQueue = DispatchQueue(label: "Puck.RunShellHandler.state")
    private var calls: [String: Call] = [:]

    func cancel(id: String) {
        let process: Process? = stateQueue.sync {
            guard let call = calls[id] else { return nil }
            call.isCancelled = true
            return call.process
        }
        guard let process, process.isRunning else { return }
        terminate(process)
    }

    /// SIGTERM now, SIGKILL if it is still there after the grace period.
    private func terminate(_ process: Process) {
        process.terminate()

        // Foundation's Process places the child in its own new process
        // group, so signaling -pid reaches backgrounded grandchildren too
        // (same reasoning as terminate() itself, see RunShellHandlerTests).
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.killGracePeriod) {
            guard process.isRunning else { return }
            kill(-pid, SIGKILL)
        }
    }

    func execute(id: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let command = args.extractString(key: "command") else {
            completion(.failure(.executionFailed("run_shell requires a command string")))
            return
        }

        let process = Process()
        let call = Call()
        stateQueue.sync {
            call.process = process
            calls[id] = call
        }
        process.executableURL = URL(fileURLWithPath: Self.shellPath)
        process.arguments = ["-lc", command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        DispatchQueue.global().async {
            do {
                try process.run()
                // A cancel that landed while this was still queued could not
                // touch the process, so honour it here now that there is one.
                if self.stateQueue.sync(execute: { call.isCancelled }) {
                    self.terminate(process)
                }

                // Both pipes must be drained *while* the child runs, not after
                // it exits. A child writing past the OS pipe buffer (64KB on
                // macOS) blocks in write() until someone reads, so waiting for
                // exit first deadlocks — and stderr fills independently, so
                // draining only stdout deadlocks a stderr-noisy command just
                // the same. readDataToEndOfFile returns at EOF (child exit),
                // so reading both concurrently also serves as the wait.
                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                let stdoutCollector = StreamCollector(handle: stdoutHandle)
                let stderrCollector = StreamCollector(handle: stderrHandle)

                // The command is finished when the *command* exits, not when
                // its pipes reach EOF. Those are the same thing right up
                // until the command backgrounds something -- `npm run dev &`,
                // anything that daemonizes -- and then the grandchild holds
                // the write end open for as long as it lives. Waiting for EOF
                // there meant a command that succeeded in milliseconds was
                // reported as a timeout a minute later, with a thread and a
                // process entry parked until the background job happened to
                // end.
                process.waitUntilExit()
                // Whatever is still in flight has a moment to arrive: the
                // last write and the exit race each other, and the loser is
                // usually the tail of the output.
                stdoutCollector.waitForEnd(within: Self.drainGraceAfterExit)
                stderrCollector.waitForEnd(within: Self.drainGraceAfterExit)
                let stdoutCapture = stdoutCollector.finish()
                let stderrCapture = stderrCollector.finish()
                self.stateQueue.sync { self.calls[id] = nil }
                completion(
                    .success(
                        .object([
                            "stdout": .string(stdoutCapture.text),
                            "stderr": .string(stderrCapture.text),
                            "exit_code": .number(Double(process.terminationStatus)),
                            "truncated": .bool(stdoutCapture.isTruncated || stderrCapture.isTruncated),
                        ])
                    )
                )
            } catch {
                // Cleared on the failure path too: left behind, a Process that
                // never launched stays this call's "in-flight" one, and a
                // cancel for the same id would try to terminate it.
                self.stateQueue.sync { self.calls[id] = nil }
                completion(.failure(.executionFailed(error.localizedDescription)))
            }
        }
    }

    /// What one stream produced, and whether the middle of it was dropped.
    private struct Capture {
        var text = ""
        var isTruncated = false
    }

    /// Collects one stream while the command runs, keeping at most
    /// `maximumCapturedBytes` of it: the first half from the front, the last
    /// half from the end.
    ///
    /// Reading *while* it runs is not optional. The child blocks in `write()`
    /// once the OS pipe buffer fills (64KB on macOS), so a reader that waited
    /// for the exit first would hang the command it is running -- and both
    /// streams fill independently, so reading only one hangs a stderr-noisy
    /// command just the same.
    ///
    /// Event-driven rather than a thread blocked in `availableData`: that
    /// thread only comes back at EOF, and EOF is exactly what a backgrounded
    /// grandchild withholds. A readability handler can simply be dropped.
    ///
    /// `@unchecked Sendable`: everything mutable is behind `lock`, which the
    /// handler's queue and the caller's both take.
    private final class StreamCollector: @unchecked Sendable {
        private let handle: FileHandle
        private let lock = NSLock()
        private var head = Data()
        private var tail = Data()
        private var total = 0
        private let ended = DispatchSemaphore(value: 0)
        private var didSignalEnd = false

        init(handle: FileHandle) {
            self.handle = handle
            handle.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self else { return }
                if chunk.isEmpty {
                    self.signalEnd()
                } else {
                    self.append(chunk)
                }
            }
        }

        /// Waits for the stream's own end, but not indefinitely -- see the
        /// class comment for who holds a pipe open past the command's exit.
        func waitForEnd(within seconds: TimeInterval) {
            _ = ended.wait(timeout: .now() + seconds)
        }

        /// Stops collecting and returns what was collected. Ordered so the
        /// handler is gone before the descriptor is: closing a FileHandle
        /// with a live readability handler is a crash, not a tidy-up.
        func finish() -> Capture {
            handle.readabilityHandler = nil
            try? handle.close()
            lock.lock()
            defer { lock.unlock() }
            guard total > maximumCapturedBytes else {
                return Capture(text: String(decoding: head, as: UTF8.self), isTruncated: false)
            }
            let half = maximumCapturedBytes / 2
            let dropped = total - half - half
            // Decoded separately: the cut can land inside a multi-byte
            // character, and String(decoding:) turns that half into a
            // replacement character rather than losing the rest of the line.
            let text = String(decoding: head.prefix(half), as: UTF8.self)
                + "\n[... \(dropped) bytes of output dropped ...]\n"
                + String(decoding: tail, as: UTF8.self)
            return Capture(text: text, isTruncated: true)
        }

        private func append(_ chunk: Data) {
            let half = maximumCapturedBytes / 2
            lock.lock()
            defer { lock.unlock() }
            total += chunk.count
            // Kept up to the whole cap, not to half of it. Half was enough
            // for the truncated case, which only ever shows the first half --
            // and it silently threw away the middle of every output between
            // half the cap and the cap, where nothing is truncated and
            // everything is supposed to be there.
            if head.count < maximumCapturedBytes {
                head.append(chunk.prefix(maximumCapturedBytes - head.count))
            }
            tail.append(chunk)
            if tail.count > half { tail.removeFirst(tail.count - half) }
        }

        private func signalEnd() {
            lock.lock()
            let shouldSignal = !didSignalEnd
            didSignalEnd = true
            lock.unlock()
            if shouldSignal { ended.signal() }
        }
    }
}
