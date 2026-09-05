//
//  AcpAgentProcess.swift
//  Puck
//
//  Spawns a vendored ACP agent under node and wires its stdio to an
//  AcpConnection. The process half of workspace/src/agent-host/acp-adapter.ts.
//
//  Environment is deliberately minimal, same as the TS version: PATH,
//  NODE_ENV, whatever the selected agent needs to find its credentials, and
//  nothing else. Handing an agent the full parent environment would give a
//  subprocess every secret this app happens to be holding.
//

import Foundation
import Darwin

/// What CodeEditorRunner needs from a running agent. Exists so the queue and
/// cancellation logic can be tested against a scripted stream -- spawning node
/// to prove that two runs on one workspace serialise would be testing the
/// wrong thing, slowly.
protocol AcpAgentTransport: AnyObject {
    var connection: AcpConnection { get }
    var isRunning: Bool { get }
    func terminate()
    func kill()
    /// The bounded tail of the child's stderr. Whatever explains a failure --
    /// a login prompt, a stack trace -- is written here rather than sent over
    /// the protocol, so a failure reported without it is usually unreadable.
    func currentStderrTail() -> String
}

extension AcpAgentTransport {
    func currentStderrTail() -> String { "" }
}

final class AcpAgentProcess: AcpAgentTransport {
    private let process = Process()
    private let sandboxTemporaryDirectory: URL
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stderrLock = NSLock()
    private var stderrTail = ""
    /// Everything that takes output out of the two pipes runs here, one at a
    /// time -- the readers and the drain the exit does. Not for the tail's own
    /// safety, which the lock covers, but so that reading a pipe and doing
    /// something with what came out cannot be split in half.
    ///
    /// It could be: the reader took the child's last words out of the pipe,
    /// and before it had added them to the tail the exit ran, found the pipe
    /// empty and the tail empty, and reported a child that died silently. On
    /// this machine that window is microseconds and on a loaded CI runner it
    /// is not.
    private let outputQueue = DispatchQueue(label: "com.speaki-e.puck.acp.output")

    let connection: AcpConnection
    /// What the child was given. Exposed so the trimming can be asserted --
    /// too little breaks the vendor CLI's login, too much hands a subprocess
    /// secrets it has no business seeing.
    private(set) var childEnvironment: [String: String] = [:]

    /// Fires once, when the process exits for any reason. Carries the tail of
    /// stderr, which is what turns "it died" into something diagnosable.
    var onExit: ((_ status: Int32, _ stderrTail: String) -> Void)?

    init(command: AcpAgentCommand, projectPath: String, credentials: [String: String]) {
        let projectRoot = URL(
            fileURLWithPath: Self.canonicalPath(projectPath),
            isDirectory: true
        )
        let temporaryRoot = URL(
            fileURLWithPath: Self.canonicalPath(FileManager.default.temporaryDirectory.path),
            isDirectory: true
        )
        sandboxTemporaryDirectory = temporaryRoot
            .appendingPathComponent("puck-acp-\(UUID().uuidString)", isDirectory: true)
        connection = AcpConnection(send: { [stdinPipe] data in
            // The agent can exit between our decision to write and the write
            // itself; a closed pipe raises SIGPIPE through FileHandle, and an
            // agent that already died is not worth crashing over.
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
        })

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = [
            "-p",
            Self.sandboxProfile(
                projectRoot: projectRoot,
                temporaryDirectory: sandboxTemporaryDirectory,
                stateDirectoryName: command.stateDirectoryName
            ),
            command.executable.path,
        ] + command.arguments
        process.currentDirectoryURL = projectRoot
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = [
            "PATH": Self.childSearchPath(for: command),
            "NODE_ENV": "production",
            // The user's real home, not a private one. A coding CLI is
            // offered as a provider precisely because the user already logged
            // into it, and on macOS that login is a Keychain item reached
            // through the login keychain -- which is listed in
            // ~/Library/Preferences. Point HOME elsewhere and
            // `security list-keychains` returns the System keychain alone, so
            // the CLI cannot see its own credentials and answers
            // "Authentication required".
            //
            // This gives away less than it looks like. The profile below
            // already allows reads everywhere, so a private HOME never hid
            // anything from the child -- it only changed where the CLI
            // looked. What the sandbox actually enforces is writes, and those
            // stay limited to the project, a scratch directory, and the CLI's
            // own state directory.
            "HOME": NSHomeDirectory(),
            // Some vendor subprocesses use this when naming account-scoped
            // state. It is identity metadata, not a filesystem permission;
            // HOME and the seatbelt profile still determine writable paths.
            "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
            // A private, explicitly allowed scratch directory keeps vendor
            // temporary files working without opening all of /tmp for writes.
            "TMPDIR": sandboxTemporaryDirectory.path,
        ]
        environment.merge(command.extraEnvironment) { _, new in new }
        environment.merge(credentials) { _, new in new }
        process.environment = environment
        childEnvironment = environment
    }

    /// The ACP adapter and every process it launches inherit this seatbelt
    /// profile. Reads, network access and subprocesses remain available, but
    /// filesystem writes are limited to the selected project, a private temp
    /// directory. HOME also points into that private directory, so vendor
    /// session state remains writable without opening the user's real home.
    private static func sandboxProfile(
        projectRoot: URL,
        temporaryDirectory: URL,
        stateDirectoryName: String
    ) -> String {
        let writableSubpaths = [
            canonicalPath(projectRoot.path),
            canonicalPath(temporaryDirectory.deletingLastPathComponent().path)
                + "/" + temporaryDirectory.lastPathComponent,
            // The CLI's own state directory under the real HOME. It is the
            // same one the user's own runs of the CLI write, which is the
            // point: session state and a refreshed token belong to the login
            // being reused, not to this app's copy of it. Everything else
            // under HOME stays read-only.
            canonicalPath(NSHomeDirectory()) + "/" + stateDirectoryName,
        ]
        let subpathRules = writableSubpaths
            .map { "(subpath \"\(sandboxEscaped($0))\")" }
            .joined(separator: "\n        ")
        return """
        (version 1)
        (deny default)
        (import "system.sb")
        (allow file-read*)
        (allow process*)
        (allow network*)
        (allow file-write*
            \(subpathRules))
        ; The vendor CLI's login is a Keychain item, and reaching the
        ; Keychain means talking to securityd. Without this, every Security
        ; call fails before it starts -- `security list-keychains` under this
        ; profile answers "SecKeychainCopySearchList: One or more parameters
        ; passed to a function were not valid", and the CLI reports
        ; "Authentication required" for a login that is present and valid.
        ; One named service, not `(allow mach-lookup)`: the narrowest rule
        ; that restores it.
        (allow mach-lookup (global-name "com.apple.SecurityServer"))
        """
    }

    private static func sandboxEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Foundation's `resolvingSymlinksInPath()` leaves `/var` untouched on
    /// current macOS even though the sandbox compares it as `/private/var`.
    /// `realpath` gives the kernel spelling that seatbelt rules actually use.
    private static func canonicalPath(_ path: String) -> String {
        guard let resolved = Darwin.realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// What the child gets as PATH.
    ///
    /// Not simply the parent's: an app launched from Finder inherits launchd's
    /// PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), not the user's shell one. The
    /// vendor CLI shells out to node, git and rg, which live in none of those
    /// four directories, so a child handed the parent's PATH cannot find the
    /// tools it was resolved with -- including the node it is running under.
    ///
    /// Whatever the parent had comes first, so a user who set their own PATH
    /// keeps their order; the directories the command was actually resolved
    /// from are appended, then the usual install locations.
    static func childSearchPath(
        for command: AcpAgentCommand,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        var directories: [String] = []
        var seen: Set<String> = []
        func add(_ directory: String) {
            let trimmed = directory.count > 1 && directory.hasSuffix("/")
                ? String(directory.dropLast())
                : directory
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            directories.append(trimmed)
        }

        for directory in (environment["PATH"] ?? "").split(separator: ":") { add(String(directory)) }
        add(command.executable.deletingLastPathComponent().path)
        // The vendor CLI's own directory: extraEnvironment carries its full
        // path, and the CLI resolves its siblings relative to PATH, not to
        // itself. Sorted so the result does not depend on dictionary order.
        for path in command.extraEnvironment.values.sorted() where path.hasPrefix("/") {
            add(URL(fileURLWithPath: path).deletingLastPathComponent().path)
        }
        for directory in AcpAgentCommandResolver.wellKnownBinDirectories(environment: environment) {
            add(directory)
        }
        for directory in ["/usr/bin", "/bin", "/usr/sbin", "/sbin"] { add(directory) }
        return directories.joined(separator: ":")
    }

    func start() throws {
        do {
            try FileManager.default.createDirectory(
                at: sandboxTemporaryDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: sandboxTemporaryDirectory.appendingPathComponent("home", isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            try? FileManager.default.removeItem(at: sandboxTemporaryDirectory)
            throw error
        }
        // The read itself is inside the queue, not just what follows it: a
        // handler that has taken data out of the pipe but not yet accounted
        // for it is the one state the exit path cannot see.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [connection, outputQueue] handle in
            outputQueue.sync {
                let data = handle.availableData
                guard !data.isEmpty else { return }
                connection.receive(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.outputQueue.sync {
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self.appendStderr(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.stdoutPipe.fileHandleForReading.readabilityHandler = nil
            self.stderrPipe.fileHandleForReading.readabilityHandler = nil
            // What the child wrote just before exiting is still sitting in the
            // pipe when this fires, and the reader is now gone. Left unread it
            // is usually the reply that finished the run, so a run that
            // succeeded would be reported as "the process exited".
            // On the queue, so a reader already holding the child's last
            // words finishes putting them somewhere before the tail is read.
            self.outputQueue.sync { self.drainRemainingOutput() }
            try? FileManager.default.removeItem(at: self.sandboxTemporaryDirectory)
            let tail = self.currentStderrTail()
            self.connection.failAllPending(with: AcpError.processExited(detail: tail))
            self.onExit?(process.terminationStatus, tail)
        }
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: sandboxTemporaryDirectory)
            throw error
        }
    }

    private func appendStderr(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        stderrLock.lock()
        // Bounded the same way the TS version bounded it: the last 8KB is
        // enough to explain a crash, and an agent that logs in a loop must
        // not grow this without limit.
        stderrTail = String((stderrTail + text).suffix(8_192))
        stderrLock.unlock()
    }

    /// Everything both pipes still hold, after the readers are detached.
    private func drainRemainingOutput() {
        drainBuffered(stdoutPipe.fileHandleForReading) { [connection] data in connection.receive(data) }
        drainBuffered(stderrPipe.fileHandleForReading) { [weak self] data in self?.appendStderr(data) }
    }

    /// Reads what is already buffered, without blocking. Non-blocking on
    /// purpose: the child has exited so everything it wrote is in the pipe
    /// already, while a blocking read to EOF would wait on any grandchild that
    /// inherited the write end -- the vendor CLI the agent spawns is exactly
    /// that -- and never come back.
    private func drainBuffered(_ handle: FileHandle, into sink: (Data) -> Void) {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else { return }
        defer { _ = fcntl(descriptor, F_SETFL, flags) }

        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                sink(Data(buffer[0..<count]))
            } else if count == -1 && errno == EINTR {
                continue
            } else {
                return
            }
        }
    }

    func currentStderrTail() -> String {
        stderrLock.lock()
        defer { stderrLock.unlock() }
        return stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isRunning: Bool { process.isRunning }

    /// SIGTERM to the whole group, not just the child.
    ///
    /// The child is `sandbox-exec`, which runs node, which spawns the vendor
    /// CLI -- a ~256MB binary that is the grandchild here. Signalling the one
    /// pid orphans it, which is the opposite of what every caller of this
    /// wants: CodeEditorRunner.shutDown and LiveAgentProcesses.endAll exist
    /// precisely so quitting does not leave one of those running. Foundation
    /// puts a child in its own process group, so `-pid` reaches the whole
    /// tree and nothing else (the same reasoning RunShellHandler.terminate
    /// spells out, and its tests demonstrate).
    func terminate() {
        guard process.isRunning else { return }
        Foundation.kill(-process.processIdentifier, SIGTERM)
    }

    /// SIGKILL, to the group for the same reason as `terminate`. Only for the
    /// case where `session/cancel` plus SIGTERM did not end it -- see
    /// AcpCodeEditorSession's cancel path.
    func kill() {
        guard process.isRunning else { return }
        Foundation.kill(-process.processIdentifier, SIGKILL)
    }
}
