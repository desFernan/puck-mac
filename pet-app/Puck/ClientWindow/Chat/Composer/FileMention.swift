//
//  FileMention.swift
//  Puck
//
//  `@` in the composer, and the path it turns into.
//
//  Naming a file to an agent used to mean typing the path by hand and hoping,
//  or describing it ("그 설정 파일") and watching the agent spend three tool
//  calls finding out which one. A path the user picked is one neither of them
//  has to guess at.
//
//  What is sent is the path itself, left in the message text. Not the file's
//  contents: every provider here has `read_file`, so a path is a thing the
//  agent can act on, and pasting a 2,000-line file into the prompt spends the
//  context window on something it may not even need to look at.
//
//  The mention being edited is taken as the last `@` token in the text rather
//  than from the caret, because SwiftUI's TextField does not say where the
//  caret is. In practice they are the same thing -- somebody typing a mention
//  is typing at the end of what they have written -- and the failure when they
//  are not is a suggestion list for the wrong token, which the next keystroke
//  corrects.
//

import Foundation

enum FileMention {
    /// The mention currently being typed, if any.
    ///
    /// - Returns: what follows the final `@`, or nil when there is no `@` to
    ///   complete -- one with a space in it is a finished mention (or an
    ///   email address), and one at the start of a word boundary is the only
    ///   shape worth completing.
    static func activeQuery(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        // Mid-word: `a@b` is an address, not a mention.
        if at != text.startIndex {
            let before = text[text.index(before: at)]
            guard before == " " || before == "\n" else { return nil }
        }
        let query = text[text.index(after: at)...]
        guard !query.contains(" "), !query.contains("\n") else { return nil }
        return String(query)
    }

    /// The text with the mention being typed replaced by `path`, ready for
    /// the next word.
    static func completing(_ text: String, with path: String) -> String {
        guard let at = text.lastIndex(of: "@") else { return text }
        return String(text[..<at]) + "@" + path + " "
    }

    /// The paths a finished message mentions, in the order they appear and
    /// without repeats.
    ///
    /// Deliberately loose about what a path looks like: whatever follows an
    /// `@` up to whitespace. Whether it exists is the caller's question --
    /// this one is only about what was written.
    static func mentionedPaths(in text: String) -> [String] {
        var found: [String] = []
        for token in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            guard token.hasPrefix("@"), token.count > 1 else { continue }
            let path = String(token.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:)]}"))
            guard !path.isEmpty, !found.contains(path) else { continue }
            found.append(path)
        }
        return found
    }
}
