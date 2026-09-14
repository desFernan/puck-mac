//
//  ProjectFileIndex.swift
//  Puck
//
//  Every file in the project, as a flat list of relative paths, for anything
//  that has to offer them by name.
//
//  The file tree the editor draws is loaded a directory at a time, because
//  that is what a tree view needs. Naming a file in the composer is the other
//  question -- "which of everything is this" -- and answering it from a lazy
//  tree means walking the disk on every keystroke.
//
//  Bounded on purpose, in three ways. The walk skips the directories a build
//  tool owns (ProjectIgnoreList, shared with the walk that works out what a
//  run changed: a change in there is a by-product, and a *file* in there is
//  not one anybody means to talk about). It stops at `maximumFiles`, so a home
//  directory opened as a project cannot hang the composer. And it is read
//  once and kept, so typing is a search of an array rather than a walk of a
//  disk.
//

import Foundation

struct ProjectFileIndex {
    /// Where the walk gives up. Well past any real project -- this repository
    /// is a few thousand files -- and small enough that the array behind it
    /// stays cheap to search on every keystroke.
    static let maximumFiles = 20_000

    /// How many suggestions are worth offering. More than a handful and
    /// nobody reads them; they retype instead.
    static let maximumSuggestions = 8

    /// Relative paths, in the order the walk found them.
    let paths: [String]

    init(paths: [String]) {
        self.paths = paths
    }

    /// Walks `root`.
    ///
    /// Hidden files are kept -- `.github/workflows/ci.yml` and `.gitignore`
    /// are files people ask about by name -- but hidden *directories* on the
    /// ignore list are not walked into.
    static func build(root: URL, fileManager: FileManager = .default) -> ProjectFileIndex {
        guard let walk = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return ProjectFileIndex(paths: []) }

        var found: [String] = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in walk {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = url.lastPathComponent
            if isDirectory {
                if ProjectIgnoreList.directories.contains(name) { walk.skipDescendants() }
                continue
            }
            guard !ProjectIgnoreList.fileNames.contains(name) else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { continue }
            found.append(String(path.dropFirst(rootPath.count + 1)))
            if found.count >= maximumFiles { break }
        }
        return ProjectFileIndex(paths: found)
    }

    /// The paths worth offering for what has been typed so far.
    ///
    /// Ranked rather than merely filtered, because the answer people want is
    /// almost always the file whose *name* they are typing.
    ///
    /// In order: the file actually called that ("skill" finds `Skill.swift`
    /// before anything else), then names starting with it, then names
    /// containing it, then a match anywhere in the path -- a directory
    /// halfway up is the weakest reason to offer something. Ties go to the
    /// shorter path, which is the one nearer the top of the project.
    ///
    /// An empty query offers the first few paths rather than nothing: `@` on
    /// its own is somebody asking what there is.
    func suggestions(for query: String, limit: Int = maximumSuggestions) -> [String] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return Array(paths.prefix(limit)) }
        let matches = paths.compactMap { path -> (path: String, rank: Int)? in
            let lowered = path.lowercased()
            let name = (lowered as NSString).lastPathComponent
            let stem = (name as NSString).deletingPathExtension
            if stem == needle || name == needle { return (path, 0) }
            if name.hasPrefix(needle) { return (path, 1) }
            if name.contains(needle) { return (path, 2) }
            if lowered.contains(needle) { return (path, 3) }
            return nil
        }
        return matches
            .sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if $0.path.count != $1.path.count { return $0.path.count < $1.path.count }
                return $0.path < $1.path
            }
            .prefix(limit)
            .map(\.path)
    }
}
