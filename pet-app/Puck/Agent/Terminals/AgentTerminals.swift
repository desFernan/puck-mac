//
//  AgentTerminals.swift
//  Puck
//
//  Shells the agent starts and keeps talking to.
//
//  The one thing `run_shell` cannot do is the thing people actually want a
//  coding agent for: start something that does not finish. A dev server, a
//  test watcher, a build with a progress bar -- `run_shell` waits for the
//  process to exit, and these do not, so it hits its timeout and kills them.
//  What it can do instead is put a command in the background and lose the
//  output entirely, which is the same as not running it.
//
//  So a session here outlives the call that started it. The agent starts one,
//  reads what is new whenever it wants, types into it, and stops it. That is
//  the whole shape, and it is Orca's (`terminal create/read/send/stop`)
//  because Orca is right about it.
//
//  ## Pipes, not a pseudo-terminal
//
//  A PTY would make programs think they are interactive: colours, progress
//  bars that redraw, a TUI. Every one of those is noise on the far end of
//  this, which is a model reading text -- a progress bar is a thousand
//  repaints of the same line, and the escape codes that draw it cost more
//  context than the build log they are hiding. Pipes give the same output
//  these programs write to a file, which is what is worth reading.
//
//  The person who wants a real terminal already has one, in the editor
//  column, with a shell and colours and a keyboard.
//
//  ## What this is not
//
//  Not a sandbox. A shell here has the privileges Puck has, exactly like
//  `run_shell` -- the gate is the approval before it starts, not a boundary
//  around it afterwards.
//
//  `@unchecked Sendable`: every stored property is touched inside `lock`, and
//  a session's reader queue is the other thread that arrives.
//

import Foundation

enum AgentTerminalError: LocalizedError, Equatable {
    case unknownSession(String)
    case sessionEnded(String)
    case tooManySessions(Int)
    case couldNotStart(String)

    var errorDescription: String? {
        switch self {
        case .unknownSession(let id):
            return String(format: Strings.text(.terminalUnknownFormat), id)
        case .sessionEnded(let id):
            return String(format: Strings.text(.terminalEndedFormat), id)
        case .tooManySessions(let limit):
            return String(format: Strings.text(.terminalTooManyFormat), "\(limit)")
        case .couldNotStart(let reason):
            return String(format: Strings.text(.terminalCouldNotStartFormat), reason)
        }
    }
}

/// One session, as the agent is told about it.
struct AgentTerminalSummary: Equatable {
    let id: String
    let command: String
    /// Nil while it is still running.
    let exitCode: Int32?
    var isRunning: Bool { exitCode == nil }
}

final class AgentTerminals: @unchecked Sendable {
    /// How many sessions may be alive at once.
    ///
    /// A cap because each is a real process this app is holding open, and a
    /// model in a loop will happily start one per turn. Six is more than any
    /// project needs at once -- a server, a watcher, a build, and room to be
    /// wrong about that.
    static let maximumSessions = 6

    /// How long a stopped session's output is still readable.
    ///
    /// The last thing a crashed server said is the whole reason to look, and
    /// it is gone the instant the process is. Kept until the session is
    /// explicitly stopped or the app quits.
    private final class Session {
        let id: String
        let command: String
        let process: Process
        let input: FileHandle
        var buffer: TerminalOutputBuffer
        var exitCode: Int32?

        init(id: String, command: String, process: Process, input: FileHandle) {
            self.id = id
            self.command = command
            self.process = process
            self.input = input
            self.buffer = TerminalOutputBuffer()
        }
    }

    private let lock = NSLock()
    private var sessions: [String: Session] = [:]
    private var order: [String] = []

    /// The shell every session runs under.
    ///
    /// Spelled here rather than taken from `RunShellHandler`, which is the
    /// obvious place for it: that file is Puck's, and PuckClient -- where the
    /// agent lives and these actually run -- sources `Puck/Tools` one file at
    /// a time and does not take the handlers. It has to match what `run_shell`
    /// uses, so that a command which works there works here.
    static let defaultShellPath = "/bin/zsh"

    /// How long a stopped session gets to leave on its own before it is
    /// killed. The same half second `run_shell` allows, for the same reason: a
    /// command that traps SIGTERM must not outlive the app that started it.
    static let killGracePeriod: TimeInterval = 0.5

    private let shellPath: String
    private let makeIdentifier: () -> String

    init(
        shellPath: String = AgentTerminals.defaultShellPath,
        makeIdentifier: @escaping () -> String = { UUID().uuidString }
    ) {
        self.shellPath = shellPath
        self.makeIdentifier = makeIdentifier
    }

    // MARK: - Starting

    /// Starts a command and returns the session it is running in.
    ///
    /// Returns as soon as the process is launched, not when it finishes --
    /// that is the entire point.
    @discardableResult
    func start(command: String, workingDirectory: String) throws -> AgentTerminalSummary {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentTerminalError.couldNotStart("empty command") }

        try lock.withLock {
            // Finished sessions do not count against the cap: they hold no
            // process, only their last words.
            let running = sessions.values.filter { $0.exitCode == nil }.count
            guard running < Self.maximumSessions else {
                throw AgentTerminalError.tooManySessions(Self.maximumSessions)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", trimmed]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)

        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        // One stream, not two. The order the two were written in is the only
        // thing that makes a log readable, and reading them apart throws it
        // away -- a compiler error and the line that caused it arrive on
        // different pipes.
        process.standardError = output
        process.standardInput = input

        let id = makeIdentifier()
        let session = Session(id: id, command: trimmed, process: process, input: input.fileHandleForWriting)

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.lock.withLock { self.sessions[id]?.buffer.append(data) }
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            // What it wrote just before exiting is still in the pipe, and the
            // reader is about to be gone: a build's own last line is usually
            // the reason it ended.
            let remaining = output.fileHandleForReading.availableData
            output.fileHandleForReading.readabilityHandler = nil
            self.lock.withLock {
                if !remaining.isEmpty { self.sessions[id]?.buffer.append(remaining) }
                self.sessions[id]?.exitCode = process.terminationStatus
            }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw AgentTerminalError.couldNotStart(error.localizedDescription)
        }

        lock.withLock {
            sessions[id] = session
            order.append(id)
        }
        return AgentTerminalSummary(id: id, command: trimmed, exitCode: nil)
    }

    // MARK: - Talking to one

    /// Everything the session has said since it was last read.
    func read(id: String, maximumBytes: Int = 16 * 1024) throws -> (read: TerminalOutputBuffer.Read, summary: AgentTerminalSummary) {
        try lock.withLock {
            guard let session = sessions[id] else { throw AgentTerminalError.unknownSession(id) }
            let read = session.buffer.read(maximumBytes: maximumBytes)
            return (read, AgentTerminalSummary(id: id, command: session.command, exitCode: session.exitCode))
        }
    }

    /// Types into it. A newline is added when there is none: every use of
    /// this is answering a prompt, and an answer nobody pressed return on is
    /// a session that looks hung.
    func send(id: String, text: String) throws {
        let session: Session = try lock.withLock {
            guard let session = sessions[id] else { throw AgentTerminalError.unknownSession(id) }
            guard session.exitCode == nil else { throw AgentTerminalError.sessionEnded(id) }
            return session
        }
        let line = text.hasSuffix("\n") ? text : text + "\n"
        // Outside the lock: a write to a full pipe blocks until the child
        // reads, and holding the lock through that stops every other session.
        try? session.input.write(contentsOf: Data(line.utf8))
    }

    /// Ends it. The output stays readable -- what it said last is the reason
    /// anyone is asking.
    func stop(id: String) throws {
        let session: Session = try lock.withLock {
            guard let session = sessions[id] else { throw AgentTerminalError.unknownSession(id) }
            return session
        }
        Self.end(session.process)
    }

    func list() -> [AgentTerminalSummary] {
        lock.withLock {
            order.compactMap { id in
                sessions[id].map {
                    AgentTerminalSummary(id: id, command: $0.command, exitCode: $0.exitCode)
                }
            }
        }
    }

    /// Every session, ended. For quitting: these are real processes, and a
    /// dev server that outlives the app is one nobody can find to kill.
    func stopAll() {
        let running = lock.withLock { sessions.values.map(\.process) }
        for process in running { Self.end(process) }
    }

    /// SIGTERM, then SIGKILL if it is still there.
    ///
    /// The group, not the process: a shell running `npm run dev` is a shell
    /// whose child is the server, and killing the shell alone leaves the
    /// server holding the port. Foundation puts the child in its own group,
    /// which is what makes `-pid` reach the whole tree -- the same thing
    /// run_shell does for the same reason.
    private static func end(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + AgentTerminals.killGracePeriod) {
            guard process.isRunning else { return }
            kill(-pid, SIGKILL)
        }
    }
}

private extension NSLock {
    /// `withLock` taking a throwing body, which the standard one on this
    /// deployment target does not.
    func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        lock()
        defer { unlock() }
        return try body()
    }
}
