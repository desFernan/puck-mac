//
//  FuzzyPathMatch.swift
//  Puck
//
//  Ranking for "open quickly": type a few letters of a file's name and get
//  the file, from anywhere in the project.
//
//  The rule everyone expects from this kind of box is a subsequence match --
//  "eps" finds EditorPaneStore.swift -- ranked so that the obvious answer is
//  first. What makes it obvious is where the letters landed: together rather
//  than scattered, at the start of a word rather than inside one, and in the
//  file's own name rather than in the directories above it.
//

import Foundation

enum FuzzyPathMatch {
    /// Letters that land next to each other read as one word.
    private static let consecutiveBonus = 10
    /// A letter at the start of a path component or after a word break.
    private static let boundaryBonus = 8
    /// Everything the query matched was in the file's own name.
    private static let lastComponentBonus = 30

    /// The paths `query` matches, best first.
    ///
    /// An empty query is not "no matches" but "no filter yet": the box opens
    /// on the project's files rather than on nothing.
    static func matches(_ query: String, in paths: [String], limit: Int = 30) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(paths.prefix(limit)) }

        let scored = paths.compactMap { path -> (path: String, score: Int)? in
            guard let score = score(trimmed, against: path) else { return nil }
            return (path, score)
        }
        return scored
            // Ties broken by path, so the list does not reshuffle between
            // keystrokes that score the same.
            .sorted { $0.score == $1.score ? $0.path < $1.path : $0.score > $1.score }
            .prefix(limit)
            .map(\.path)
    }

    /// How well `path` answers `query`, or nil if it does not answer it at
    /// all. Case-insensitive: nobody types capitals into a box like this.
    static func score(_ query: String, against path: String) -> Int? {
        let needle = Array(query.lowercased())
        // The path with its capitals intact: a capital after a small letter
        // is a word boundary, and it is the one that makes "eps" mean
        // EditorPaneStore rather than EditorPaneView -- lowercase both and
        // the S of ".swift" scores just as well as the S of Store.
        let haystack = Array(path)
        guard !needle.isEmpty else { return 0 }

        var score = 0
        var needleIndex = 0
        var previousMatch: Int?
        var firstMatch: Int?

        for (index, character) in haystack.enumerated() {
            guard needleIndex < needle.count,
                  character.lowercased() == String(needle[needleIndex])
            else { continue }
            if let previous = previousMatch, previous == index - 1 {
                score += consecutiveBonus
            } else if isBoundary(haystack, at: index) {
                score += boundaryBonus
            } else {
                score += 1
            }
            if firstMatch == nil { firstMatch = index }
            previousMatch = index
            needleIndex += 1
        }

        guard needleIndex == needle.count else { return nil }

        // Entirely inside the file's own name, which is what was typed nine
        // times out of ten.
        if let firstMatch, let slash = haystack.lastIndex(of: "/"), firstMatch > slash {
            score += lastComponentBonus
        } else if !haystack.contains("/") {
            score += lastComponentBonus
        }

        // Shorter paths win among equals: a match that fills most of the name
        // is a better answer than the same letters lost in a long one.
        return score - haystack.count / 10
    }

    /// The start of a word: the first character, one after a separator, or a
    /// capital following a small letter. `.` is deliberately not a separator
    /// -- every file here ends in `.swift`, and counting that `s` as the start
    /// of a word made every Swift file answer to a query ending in one.
    private static func isBoundary(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        if previous == "/" || previous == "_" || previous == "-" || previous == " " { return true }
        return characters[index].isUppercase && previous.isLowercase
    }
}
