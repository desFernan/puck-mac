//
//  SkillFrontmatter.swift
//  Puck
//
//  The `---` block at the top of a SKILL.md.
//
//  A few keys out of YAML rather than a YAML parser: the frontmatter this
//  reads is written by hand to a documented shape, and a dependency that can
//  parse anchors and merge keys buys nothing for `name:` and `description:`.
//  What it does have to handle is the folded scalar those descriptions are
//  usually written as, since that is what wraps them across lines.
//

import Foundation

enum SkillFrontmatter {
    /// `name` and `description`, or nil when the file has no frontmatter at
    /// all. Missing keys come back empty rather than failing: a skill with no
    /// description is worth listing, and refusing to show it would hide it
    /// from the person trying to work out where it came from.
    static func parse(_ contents: String) -> (name: String, description: String)? {
        let lines = contents.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return nil
        }
        let block = Array(lines[1..<end])

        var values: [String: String] = [:]
        var index = 0
        while index < block.count {
            let line = block[index]
            index += 1
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            // `>-`, `>`, `|`, `|-`: the value is the indented lines below.
            if value.hasPrefix(">") || value.hasPrefix("|") {
                let folded = value.hasPrefix(">")
                var parts: [String] = []
                while index < block.count {
                    let next = block[index]
                    // An unindented line starts the next key.
                    guard next.hasPrefix(" ") || next.hasPrefix("\t") || next.trimmingCharacters(in: .whitespaces).isEmpty else { break }
                    parts.append(next.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                // Folded joins with spaces, literal keeps its line breaks.
                value = folded
                    ? parts.filter { !$0.isEmpty }.joined(separator: " ")
                    : parts.joined(separator: "\n")
            }
            values[key] = unquoted(value)
        }
        return (values["name"] ?? "", values["description"] ?? "")
    }

    /// Surrounding quotes come off; anything else is left alone. Not an
    /// escape-sequence decoder -- these are one-line human strings.
    private static func unquoted(_ value: String) -> String {
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
