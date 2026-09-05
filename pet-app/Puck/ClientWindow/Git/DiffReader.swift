//
//  DiffReader.swift
//  Puck
//
//  Asks git what changed, and puts a file back.
//
//  Alongside GitStatusReader rather than inside it: that one answers "what is
//  the state of this repository", which the status bar asks constantly, and
//  this one answers "show me the change", which is asked when somebody opens
//  the review. They run the same binary and share nothing else.
//

import Foundation

enum DiffReader {
    /// Every uncommitted change in the project, staged and not.
    ///
    /// `HEAD` rather than the working tree alone, because the agent's edits
    /// may already be staged -- `code_editor` runs a vendor CLI that is free
    /// to `git add`, and a review that showed only unstaged changes would say
    /// "nothing changed" about a run that changed plenty.
    ///
    /// Untracked files are asked for separately and appended: `git diff` does
    /// not mention them at all, and a file the agent *created* is the change
    /// most worth seeing.
    static func changes(projectPath: String) -> [FileDiff] {
        guard let git = GitStatusReader.executable() else { return [] }
        let tracked = run(git, ["-C", projectPath, "diff", "HEAD", "--no-color", "--no-ext-diff"])
            .map(DiffParser.parse) ?? []
        return tracked + untracked(git: git, projectPath: projectPath)
    }

    /// A file git has never seen, diffed against nothing.
    ///
    /// `--no-index` against `/dev/null` is git's own way of doing this, so
    /// the output is the same format the rest of the parse already reads --
    /// rather than a second path that builds hunks by hand.
    private static func untracked(git: URL, projectPath: String) -> [FileDiff] {
        guard let listing = run(git, [
            "-C", projectPath, "ls-files", "--others", "--exclude-standard",
        ]) else {
            return []
        }
        return listing
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .flatMap { path -> [FileDiff] in
                // Non-zero exit is the normal answer here: `--no-index` exits
                // 1 precisely when there *is* a difference, which is always.
                let output = run(
                    git,
                    ["-C", projectPath, "diff", "--no-index", "--no-color", "/dev/null", path],
                    allowingFailure: true
                )
                return output.map(DiffParser.parse) ?? []
            }
    }

    /// Whether a project has a git repository at all.
    ///
    /// The review is only offered where it does: without one there is no
    /// "before" to compare against, and an agent's edit is indistinguishable
    /// from the file's own contents.
    static func isRepository(projectPath: String) -> Bool {
        guard let git = GitStatusReader.executable() else { return false }
        return run(git, ["-C", projectPath, "rev-parse", "--git-dir"]) != nil
    }

    /// Throws a file's changes away, back to what the last commit had.
    ///
    /// File at a time, not hunk at a time. A hunk revert writes a file that
    /// never existed -- half of the agent's change on top of half of yours --
    /// and getting the line arithmetic wrong there silently corrupts the file
    /// rather than failing. Whole files are `git checkout --`, which is git's
    /// own operation and cannot land halfway.
    ///
    /// A file git has never seen is deleted instead: there is no committed
    /// version to return it to, and leaving it while claiming to have undone
    /// the change would be a lie.
    ///
    /// - Returns: whether it was actually put back.
    @discardableResult
    static func revert(path: String, projectPath: String, isUntracked: Bool) -> Bool {
        guard let git = GitStatusReader.executable() else { return false }
        guard PathContainment.isInside(
            root: URL(fileURLWithPath: projectPath).standardizedFileURL.path,
            candidate: URL(fileURLWithPath: projectPath)
                .appendingPathComponent(path).standardizedFileURL.path
        ) else {
            // A path out of the project is a path this must not touch: the
            // name came out of git's own output, but a review that can delete
            // anything on the disk is one bad parse away from doing it.
            AppLogger.shared.log(.error, "refused to revert a path outside the project: \(path)")
            return false
        }
        if isUntracked {
            let url = URL(fileURLWithPath: projectPath).appendingPathComponent(path)
            do {
                try FileManager.default.removeItem(at: url)
                return true
            } catch {
                AppLogger.shared.log(.error, "could not delete \(path): \(error)")
                return false
            }
        }
        // `--` so a path that looks like a branch name is read as a path.
        return run(git, ["-C", projectPath, "checkout", "HEAD", "--", path]) != nil
    }

    /// Runs git and returns stdout, or nil when it failed.
    ///
    /// - Parameter allowingFailure: for the commands whose non-zero exit is
    ///   an answer rather than an error -- `diff --no-index` exits 1 when the
    ///   files differ, which is every time it is used here.
    private static func run(_ executable: URL, _ arguments: [String], allowingFailure: Bool = false) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        // Discarded for the reason GitStatusReader discards it: the exit
        // status is the only failure worth reacting to, and git's stderr
        // would otherwise reach the console of whoever launched the app.
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting: a diff larger than the pipe buffer blocks the
        // child in write() while this waits for it to exit, and neither ever
        // moves. GitStatusReader never hit this because `git status` is
        // short; a diff is exactly the thing that is not.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard allowingFailure || process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
