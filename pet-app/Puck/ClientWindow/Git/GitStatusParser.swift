//
//  GitStatusParser.swift
//  Puck
//
//  `git status --porcelain=v2 --branch` and `git diff --numstat HEAD`, read
//  into a GitStatus.
//
//  Porcelain v2 rather than v1: it is the format git documents as stable for
//  programs, and it carries the branch and its ahead/behind in the same call
//  -- v1 would need a second one and still not say how far ahead the branch
//  is.
//

import Foundation

enum GitStatusParser {
    static func parse(status: String, numstat: String) -> GitStatus {
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var files: [GitFileChange] = []

        for line in status.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            if line.hasPrefix("# branch.head ") {
                let value = String(line.dropFirst("# branch.head ".count))
                // Detached HEAD reports "(detached)", which is not a branch.
                branch = value == "(detached)" ? nil : value
            } else if line.hasPrefix("# branch.upstream ") {
                upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let counts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                ahead = counts.first.flatMap { Int($0.dropFirst()) } ?? 0
                behind = counts.dropFirst().first.flatMap { Int($0.dropFirst()) } ?? 0
            } else if line.hasPrefix("? ") {
                files.append(GitFileChange(
                    indexStatus: "?",
                    worktreeStatus: "?",
                    path: String(line.dropFirst(2)),
                    addedLines: nil,
                    deletedLines: nil
                ))
            } else if let change = ordinaryChange(line) {
                files.append(change)
            }
        }

        let counts = numstatCounts(numstat)
        files = files.map { file in
            var file = file
            if let count = counts[file.path] {
                file.addedLines = count.added
                file.deletedLines = count.deleted
            }
            return file
        }
        // Path order, so the list does not reshuffle between reads.
        files.sort { $0.path < $1.path }
        return GitStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, files: files)
    }

    /// `1 <XY> ... <path>` for a change, `2 <XY> ... <path>\t<original>` for a
    /// rename. Everything between the status letters and the path is metadata this
    /// does not use, so the path is taken as the last field rather than by
    /// counting columns -- which is also what keeps a path containing spaces
    /// intact.
    private static func ordinaryChange(_ line: String) -> GitFileChange? {
        guard line.hasPrefix("1 ") || line.hasPrefix("2 ") else { return nil }
        let isRename = line.hasPrefix("2 ")
        let fields = line.split(separator: " ", maxSplits: isRename ? 9 : 8, omittingEmptySubsequences: false)
        guard fields.count >= 2 else { return nil }
        let letters = Array(fields[1])
        guard letters.count == 2, let path = fields.last.map(String.init), !path.isEmpty else { return nil }
        // A rename carries "new\told"; the new name is the one to show.
        let shown = path.components(separatedBy: "\t").first ?? path
        return GitFileChange(
            indexStatus: letters[0],
            worktreeStatus: letters[1],
            path: shown,
            addedLines: nil,
            deletedLines: nil
        )
    }

    /// `added<TAB>deleted<TAB>path`, with `-` for a binary file.
    private static func numstatCounts(_ numstat: String) -> [String: (added: Int, deleted: Int)] {
        var counts: [String: (added: Int, deleted: Int)] = [:]
        for line in numstat.components(separatedBy: "\n") where !line.isEmpty {
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 3, let added = Int(fields[0]), let deleted = Int(fields[1]) else { continue }
            counts[fields[2...].joined(separator: "\t")] = (added, deleted)
        }
        return counts
    }
}
