//
//  GitStatusReader.swift
//  Puck
//
//  Runs the two git commands GitStatusParser reads.
//
//  Two calls rather than one: porcelain v2 says what changed and the branch's
//  ahead/behind, and numstat says how much. Neither carries the other.
//

import Foundation

enum GitStatusReader {
    /// Where git usually is, in the order worth trying -- the same shape
    /// AcpAgentCommandResolver uses for node. A `Process` gets no login shell
    /// and so no PATH of the user's own.
    static let candidatePaths = ["/opt/homebrew/bin/git", "/usr/bin/git", "/usr/local/bin/git"]

    static func executable(fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
        candidatePaths.first(where: fileExists).map { URL(fileURLWithPath: $0) }
    }

    /// nil when the directory is not a repository, or git is not installed --
    /// both are "there is nothing to show here" rather than errors worth
    /// putting on screen.
    /// Just the branch, for the places that show which one a project is on
    /// without listing what changed -- the sidebar's workspace rows, the
    /// window's footer. `git status` walks the worktree; this does not, so it
    /// is cheap enough to ask once per workspace.
    static func branch(projectPath: String) -> String? {
        guard let git = executable() else { return nil }
        guard let name = run(git, ["-C", projectPath, "rev-parse", "--abbrev-ref", "HEAD"]) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A repository with no commits yet answers "HEAD"; so does a detached
        // one, and neither is a branch anybody wants shown as a name.
        return trimmed.isEmpty || trimmed == "HEAD" ? nil : trimmed
    }

    static func read(projectPath: String) -> GitStatus? {
        guard let git = executable() else { return nil }
        // `status.relativePaths=false` is not decoration. Run from a
        // subdirectory, git answers in paths relative to *that* directory --
        // `Sources/a.txt`, `../docs/readme.md` -- and whether it does depends
        // on a setting the user can change. Pinned off, the answer is always
        // relative to the repository root, which is the one thing `reroot`
        // below can turn into a workspace-relative path deterministically.
        guard let status = run(
            git,
            ["-C", projectPath, "-c", "status.relativePaths=false", "status", "--porcelain=v2", "--branch"]
        ) else {
            return nil
        }
        let numstat = run(git, ["-C", projectPath, "diff", "--numstat", "HEAD"]) ?? ""
        let parsed = GitStatusParser.parse(status: status, numstat: numstat)
        // git answers in paths relative to the repository root; everything
        // here deals in paths relative to the workspace, and the two are only
        // the same when the workspace *is* the root. Opening a changed file
        // from a workspace one directory down looked for it in the wrong
        // place, and the file tree could not match a single one of them.
        let prefix = (run(git, ["-C", projectPath, "rev-parse", "--show-prefix"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? parsed : Self.reroot(parsed, under: prefix)
    }

    /// Drops what is outside the workspace and makes the rest relative to it.
    static func reroot(_ status: GitStatus, under prefix: String) -> GitStatus {
        let files = status.files.compactMap { file -> GitFileChange? in
            guard file.path.hasPrefix(prefix) else { return nil }
            return GitFileChange(
                indexStatus: file.indexStatus,
                worktreeStatus: file.worktreeStatus,
                path: String(file.path.dropFirst(prefix.count)),
                addedLines: file.addedLines,
                deletedLines: file.deletedLines
            )
        }
        return GitStatus(
            branch: status.branch,
            upstream: status.upstream,
            ahead: status.ahead,
            behind: status.behind,
            files: files
        )
    }

    /// nil on a non-zero exit, which for these two means "not a repository".
    private static func run(_ executable: URL, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        // Discarded on purpose: the only failure worth reacting to is the
        // exit status, and git's stderr on a non-repository would otherwise
        // reach the console of whoever launched the app.
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
