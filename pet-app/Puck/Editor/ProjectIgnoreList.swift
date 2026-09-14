//
//  ProjectIgnoreList.swift
//  Puck
//
//  What a walk of somebody's project does not look inside.
//
//  Two walks want the same answer: the one that works out what a coding run
//  changed (ProjectChangeTracker) and the one that lists files to name in the
//  composer (ProjectFileIndex). The list started life with the first of them,
//  which put a build-tool fact up in the agent layer where the second could
//  not reach it without reaching upward.
//

import Foundation

enum ProjectIgnoreList {
    /// `.git` above all: a single commit rewrites hundreds of paths under it
    /// and none of them are the agent's edit. The rest are the same shape --
    /// directories a build tool owns, where a change is a by-product of the
    /// work rather than the work.
    ///
    /// This list is what keeps the walk cheap now that hidden files are *not*
    /// skipped wholesale. They used to be, which meant an agent asked to fix
    /// a CI workflow, a .env or a .gitignore reported changing nothing at
    /// all: the snapshot could not see the file, so the watcher was the only
    /// witness, and a coalesced burst there is unrecoverable.
    static let directories: Set<String> = [
        ".git", "node_modules", ".build", ".swiftpm", "DerivedData",
        ".next", ".venv", "__pycache__",
    ]

    /// Finder writes this into whichever folder someone looked at, which has
    /// nothing to do with the agent.
    static let fileNames: Set<String> = [".DS_Store"]
}
