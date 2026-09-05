//
//  FileDiff.swift
//  Puck
//
//  One file's changes, as hunks of lines.
//
//  The gap this fills: the agent edits files and reports which ones, and
//  until now that was the whole of it -- to see what it actually did you left
//  the app and ran `git diff`. Every editor with an agent in it (Zed, Orca,
//  Paseo) shows the change before you keep it, because an agent that edits
//  without a review is one you have to either trust completely or not use.
//
//  Parsed from `git diff`'s own unified output rather than diffed here. Two
//  reasons: git already knows what changed, including renames and what counts
//  as binary; and the thing being shown has to agree with what a commit would
//  take, which is git's opinion by definition.
//
//  Pure, and separate from the reading, because a unified diff is a format
//  with corners -- an empty file, a file with no trailing newline, "\ No
//  newline at end of file", a rename with no content change -- and every one
//  of them is a line somebody has to have written a test for.
//

import Foundation

/// One line of a diff, and what happened to it.
struct DiffLine: Equatable {
    enum Kind: Equatable {
        case context
        case added
        case removed
    }

    let kind: Kind
    let text: String
    /// Where this line sits in the file before the change, for a line that
    /// existed then.
    let oldLine: Int?
    /// And in the file after it.
    let newLine: Int?
}

/// A run of changed lines with a little unchanged either side, which is what
/// `@@` introduces in a unified diff.
struct DiffHunk: Equatable, Identifiable {
    /// The `@@ ... @@` line's own text, which usually names the enclosing
    /// function -- worth keeping because it is the one piece of context that
    /// says *where* in the file this is.
    let header: String
    let lines: [DiffLine]

    var id: String { header + "\(lines.count)" }

    var addedCount: Int { lines.filter { $0.kind == .added }.count }
    var removedCount: Int { lines.filter { $0.kind == .removed }.count }
}

/// One file, and everything that happened to it.
struct FileDiff: Equatable, Identifiable {
    let path: String
    /// Where it came from, for a rename. Nil otherwise.
    let previousPath: String?
    /// True when git will not show the contents -- an image, a compiled
    /// artefact. There is nothing to draw but the fact that it changed.
    let isBinary: Bool
    let hunks: [DiffHunk]

    var id: String { path }

    var addedCount: Int { hunks.reduce(0) { $0 + $1.addedCount } }
    var removedCount: Int { hunks.reduce(0) { $0 + $1.removedCount } }
    var isRename: Bool { previousPath != nil }

    /// A file git reported but produced no hunks for: a rename with no edits,
    /// a mode change, or a binary. Worth telling apart, because a file listed
    /// with nothing under it reads as a bug otherwise.
    var hasNoVisibleChange: Bool { hunks.isEmpty }
}

enum DiffParser {
    /// Splits `git diff`'s unified output into one entry per file.
    ///
    /// Written against the output rather than the plumbing: `git diff` is
    /// stable, older than anyone reading this, and the alternative
    /// (`--raw` plus a blob read per file) is three subprocesses per file to
    /// learn what one already said.
    static func parse(_ output: String) -> [FileDiff] {
        var files: [FileDiff] = []
        var path: String?
        var previousPath: String?
        var isBinary = false
        var hunks: [DiffHunk] = []
        var header: String?
        var lines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0

        func closeHunk() {
            guard let open = header else { return }
            hunks.append(DiffHunk(header: open, lines: lines))
            header = nil
            lines = []
        }

        func closeFile() {
            closeHunk()
            guard let open = path else { return }
            files.append(FileDiff(path: open, previousPath: previousPath, isBinary: isBinary, hunks: hunks))
            path = nil
            previousPath = nil
            isBinary = false
            hunks = []
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                closeFile()
                path = Self.path(fromDiffHeader: line)
                continue
            }
            // The b/ side is the truth for a rename: `diff --git` names both,
            // and the one being shown is where the file ended up.
            if line.hasPrefix("rename from ") {
                previousPath = String(line.dropFirst("rename from ".count))
                continue
            }
            if line.hasPrefix("rename to ") {
                path = String(line.dropFirst("rename to ".count))
                continue
            }
            if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                isBinary = true
                continue
            }
            if line.hasPrefix("@@") {
                closeHunk()
                header = line
                let starts = Self.lineNumbers(fromHunkHeader: line)
                oldLine = starts.old
                newLine = starts.new
                continue
            }
            guard header != nil else { continue }
            // Inside a hunk. A bare empty line is a context line whose
            // content is empty -- git writes it without the leading space,
            // and reading it as "not part of the hunk" drops real lines.
            if line.isEmpty {
                lines.append(DiffLine(kind: .context, text: "", oldLine: oldLine, newLine: newLine))
                oldLine += 1
                newLine += 1
                continue
            }
            let body = String(line.dropFirst())
            switch line.first {
            case "+":
                lines.append(DiffLine(kind: .added, text: body, oldLine: nil, newLine: newLine))
                newLine += 1
            case "-":
                lines.append(DiffLine(kind: .removed, text: body, oldLine: oldLine, newLine: nil))
                oldLine += 1
            case " ":
                lines.append(DiffLine(kind: .context, text: body, oldLine: oldLine, newLine: newLine))
                oldLine += 1
                newLine += 1
            case "\\":
                // "\ No newline at end of file" -- a note about the line
                // above, not a line of the file.
                continue
            default:
                continue
            }
        }
        closeFile()
        return files
    }

    /// The path from `diff --git a/x b/x`, taking the b side.
    ///
    /// Split on " b/" rather than on spaces: a path may contain them, and the
    /// b-side marker is the one thing that cannot appear in the a-side of a
    /// well-formed header.
    static func path(fromDiffHeader line: String) -> String? {
        guard let range = line.range(of: " b/", options: .backwards) else { return nil }
        let path = String(line[range.upperBound...])
        return path.isEmpty ? nil : path
    }

    /// The two starting line numbers from `@@ -12,7 +12,9 @@`.
    static func lineNumbers(fromHunkHeader line: String) -> (old: Int, new: Int) {
        var old = 1
        var new = 1
        for token in line.split(separator: " ") {
            guard token.count > 1, let sign = token.first, sign == "-" || sign == "+" else { continue }
            let digits = token.dropFirst().prefix { $0.isNumber }
            guard let value = Int(digits) else { continue }
            if sign == "-" { old = value } else { new = value }
        }
        return (old, new)
    }
}
