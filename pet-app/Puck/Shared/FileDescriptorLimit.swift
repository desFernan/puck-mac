//
//  FileDescriptorLimit.swift
//  Puck
//
//  Raises how many files this process -- and everything it spawns -- may hold
//  open at once.
//
//  A GUI app does not get the shell's limit. launchd hands its children a
//  soft `RLIMIT_NOFILE` of 256, and a terminal only ever looks generous
//  because the shell raises its own on the way up. So an app launched from
//  Finder runs at 256 while the same binary run from a terminal runs at a
//  million, which is why this never shows up while developing.
//
//  256 is not many. The editor pane watches a project tree, the coding CLI
//  watches its own settings and every file it opens, and a vendored agent
//  spawns a node that does the same again -- children inherit this limit, and
//  what it produced was the agent dying on its own configuration:
//
//      Settings watcher error for ~/.claude/settings.json:
//      Error: EMFILE: too many open files, watch
//
//  Raised once at launch, before anything opens a file. The ceiling is the
//  kernel's own per-process cap rather than a number picked here: asking for
//  more than `kern.maxfilesperproc` fails outright, and asking for exactly it
//  is asking for what the machine is willing to give.
//

import Darwin
import Foundation

enum FileDescriptorLimit {
    /// What to ask for, given what the machine allows.
    ///
    /// - Parameters:
    ///   - current: the soft limit now.
    ///   - hard: the hard limit, which a process may not exceed without
    ///     privileges. Unlimited in practice, since the real ceiling is the
    ///     kernel's.
    ///   - kernelMaximum: `kern.maxfilesperproc`, the most any one process may
    ///     hold however generous its rlimit.
    /// - Returns: the new soft limit, or nil when it is already high enough
    ///   and there is nothing to do.
    ///
    /// Pure so the awkward cases are testable without root: a machine that
    /// already grants plenty, a hard limit lower than the kernel's cap, and
    /// the infinite hard limit macOS actually reports.
    static func target(current: rlim_t, hard: rlim_t, kernelMaximum: rlim_t) -> rlim_t? {
        // `RLIM_INFINITY` is not exposed to Swift, and it is what macOS
        // actually reports here -- the hard limit is unlimited and the cap
        // that matters is the kernel's. Compared as "at least as large as the
        // kernel would ever allow" rather than against the constant, which
        // means the same thing and does not need the constant.
        let ceiling = hard >= kernelMaximum ? kernelMaximum : hard
        guard ceiling > current else { return nil }
        return ceiling
    }

    /// What the kernel will allow one process, or a conservative stand-in when
    /// it cannot be read.
    ///
    /// 10,240 is macOS's own long-standing default for this cap and is far
    /// past anything here needs; it is the answer to a `sysctl` that failed,
    /// not a guess at the machine's real capacity.
    static func kernelMaximumFilesPerProcess() -> rlim_t {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.maxfilesperproc", &value, &size, nil, 0) == 0, value > 0 else {
            return 10_240
        }
        return rlim_t(value)
    }

    /// Raises the soft limit as far as the machine allows.
    ///
    /// Best effort: a process that cannot raise its own limit still runs, just
    /// with the ceiling it had. Reported to the log either way -- this is the
    /// kind of thing whose absence is only ever noticed as an unrelated
    /// failure somewhere else.
    @discardableResult
    static func raise() -> rlim_t? {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return nil }
        guard let target = target(
            current: limit.rlim_cur,
            hard: limit.rlim_max,
            kernelMaximum: kernelMaximumFilesPerProcess()
        ) else {
            return nil
        }
        let previous = limit.rlim_cur
        limit.rlim_cur = target
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            AppLogger.shared.log(
                .warning,
                "could not raise the open-file limit from \(previous); a coding agent may fail with EMFILE"
            )
            return nil
        }
        AppLogger.shared.log(.info, "open-file limit raised from \(previous) to \(target)")
        return target
    }
}
