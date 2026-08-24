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

                let stderrQueue = DispatchQueue(label: "Puck.RunShellHandler.stderr")
                var stderrCapture = Capture()
                stderrQueue.async { stderrCapture = Self.drain(stderrHandle) }

                let stdoutCapture = Self.drain(stdoutHandle)
                stderrQueue.sync {} // barrier: stderrCapture is fully written past this point

                process.waitUntilExit()
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

    /// Reads `handle` to EOF and keeps at most `maximumCapturedBytes` of it:
    /// the first half from the front, the last half from the end.
    ///
    /// Reading to EOF regardless of the cap is not optional. The child blocks
    /// in `write()` once the OS pipe buffer fills, so a reader that stopped at
    /// its limit would hang the command it is running rather than truncate it.
    private static func drain(_ handle: FileHandle) -> Capture {
        let half = maximumCapturedBytes / 2
        // Kept up to the whole cap, not to half of it. Half was enough for
        // the truncated case, which only ever shows the first half -- and it
        // silently threw away the middle of every output between half the cap
        // and the cap, where nothing is truncated and everything is supposed
        // to be there.
        var head = Data()
        var tail = Data()
        var total = 0

        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            total += chunk.count
            if head.count < maximumCapturedBytes {
                head.append(chunk.prefix(maximumCapturedBytes - head.count))
            }
            tail.append(chunk)
            if tail.count > half { tail.removeFirst(tail.count - half) }
        }

        guard total > maximumCapturedBytes else {
            return Capture(text: String(decoding: head, as: UTF8.self), isTruncated: false)
        }
        let dropped = total - half - half
        // Decoded separately: the cut can land inside a multi-byte character,
        // and String(decoding:) turns that half into a replacement character
        // rather than losing the rest of the line.
        let text = String(decoding: head.prefix(half), as: UTF8.self)
            + "\n[... \(dropped) bytes of output dropped ...]\n"
            + String(decoding: tail, as: UTF8.self)
        return Capture(text: text, isTruncated: true)
    }
}
