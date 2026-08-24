//
//  GitStatus.swift
//  Puck
//
//  What `git status` says about the project, as a value.
//
//  Read-only. Showing what has changed is the part that answers "what did the
//  agent just do to my repository"; committing and pushing from a sidebar is
//  a different kind of action and is deliberately not here.
//

import Foundation

struct GitFileChange: Identifiable, Equatable {
    /// Git's own two letters: index state then worktree state, `?` for
    /// untracked. Kept as the letters rather than an enum because that is
    /// what a reader of `git status` already knows how to read.
    let indexStatus: Character
    let worktreeStatus: Character
    let path: String
    /// nil when git could not count them -- a binary file, or a change that
    /// only `git status` knows about (an untracked file has no diff).
    var addedLines: Int?
    var deletedLines: Int?

    var id: String { path }

    var isUntracked: Bool { indexStatus == "?" }
    var isStaged: Bool { indexStatus != "." && indexStatus != "?" }

    /// The single letter a list shows. The index wins when both moved, since
    /// that is what a commit would take.
    var displayStatus: String {
        if isUntracked { return "A" }
        return String(isStaged ? indexStatus : worktreeStatus)
    }
}

struct GitStatus: Equatable {
    let branch: String?
    let upstream: String?
    /// Commits this branch has that its upstream does not, and the reverse.
    let ahead: Int
    let behind: Int
    let files: [GitFileChange]

    var addedLines: Int { files.compactMap(\.addedLines).reduce(0, +) }
    var deletedLines: Int { files.compactMap(\.deletedLines).reduce(0, +) }

    static let clean = GitStatus(branch: nil, upstream: nil, ahead: 0, behind: 0, files: [])
}
