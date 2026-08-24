//
//  DotEnv.swift
//  Puck
//
//  Reading and writing the `.env` files AgentConfiguration resolves settings
//  from. Split out of AgentConfiguration because it is a file format, not a
//  configuration: the settings window writes through it too.
//

import Foundation

/// A `.env` reader: `KEY=VALUE` lines, `#` comments, blank lines, optional
/// `export ` prefix and optional surrounding quotes. Deliberately not a full
/// shell parser -- no interpolation, no multi-line values. A key is one line.
enum DotEnv {
    static func parse(fileAt url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return parse(contents)
    }

    static func parse(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }

            // Split on the FIRST '=' only: an API key can contain one, and
            // splitting on all of them truncates the value.
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            values[key] = unquote(String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces))
        }
        return values
    }

    /// Sets one key in a `.env`, leaving every other line -- comments
    /// included -- exactly as it was. A rewrite-the-whole-file version would
    /// eat the template's comments the first time Settings saved anything.
    ///
    /// The file is created 0600 and re-chmod'd on every write: it holds an API
    /// key, and the default 0644 makes that readable by every process running
    /// as anyone on the machine.
    @discardableResult
    static func write(key: String, value: String?, to url: URL) -> Bool {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = existing.isEmpty ? [] : existing.components(separatedBy: "\n")
        let assignment = value.map { "\(key)=\($0)" }

        // Replace in place if the key is already assigned somewhere, so its
        // position (and any comment above it) is preserved.
        let index = lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { return false }
            let withoutExport = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst("export ".count)) : trimmed
            return withoutExport.split(separator: "=", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces) == key
        }
        switch (index, assignment) {
        case (let index?, let assignment?):
            lines[index] = assignment
        case (let index?, nil):
            lines.remove(at: index)
        case (nil, let assignment?):
            // Before the file's trailing newline, not after it. A `.env` that
            // ends the way text files end came back with a blank line in the
            // middle and no newline at the end, which is a diff on a file the
            // user also edits by hand.
            if lines.last?.isEmpty == true {
                lines.insert(assignment, at: lines.count - 1)
            } else {
                lines.append(assignment)
            }
        case (nil, nil):
            return true // asked to clear something that was never set
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            // After the write, not before: the atomic write replaces the file,
            // and with it any permissions set on the old one.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private static func unquote(_ value: String) -> String {
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
