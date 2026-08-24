//
//  AgentSessionHistory.swift
//  Puck
//
//  Finding and summarising the CLI's transcripts.
//
//  Only the head of each file is read. A transcript is one JSON object per
//  line and grows with the conversation -- the ones on this machine reach
//  39MB -- while everything a list needs (which directory, what was asked
//  first, which model answered) is written near the top. Reading them whole
//  to fill a sidebar would mean hundreds of megabytes per refresh.
//

import Foundation

enum AgentSessionHistory {
    /// Where the CLI keeps them.
    static var projectsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    /// How much of a transcript is read looking for its summary. Generous
    /// enough for a long system prompt and the first exchange, small enough
    /// that a 39MB file costs the same as a 40KB one.
    static let headBytes = 256 * 1024

    /// Newest first, capped -- a sidebar shows what someone might click, and
    /// the tail of a year's transcripts is not that.
    static func discover(limit: Int = 40, fileManager: FileManager = .default) -> [AgentSession] {
        let projects = (try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var transcripts: [(url: URL, modified: Date)] = []
        for project in projects {
            let files = (try? fileManager.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                transcripts.append((file, modified))
            }
        }

        return transcripts
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .compactMap { summarise(transcript: $0.url, modifiedAt: $0.modified) }
    }

    /// nil for a file that carries nothing worth listing -- an empty
    /// transcript, or one whose head is not JSON lines at all.
    static func summarise(transcript url: URL, modifiedAt: Date) -> AgentSession? {
        guard let head = head(of: url) else { return nil }
        var workingDirectory = ""
        var title = ""
        var model: String?

        for line in head.components(separatedBy: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if workingDirectory.isEmpty, let cwd = object["cwd"] as? String { workingDirectory = cwd }
            let message = object["message"] as? [String: Any]
            if model == nil, let named = message?["model"] as? String { model = named }
            if title.isEmpty, object["type"] as? String == "user", let message {
                let candidate = Self.firstLine(of: message["content"])
                // Not a wrapper. A turn can arrive inside
                // `<local-command-caveat>` or `<command-name>`, which the CLI
                // put there and nobody typed -- as a title it says nothing
                // about the session and is the same on all of them.
                if !candidate.hasPrefix("<") { title = candidate }
            }
            if !workingDirectory.isEmpty, !title.isEmpty, model != nil { break }
        }

        guard !title.isEmpty || !workingDirectory.isEmpty else { return nil }
        return AgentSession(
            id: url.deletingPathExtension().lastPathComponent,
            transcriptPath: url.path,
            workingDirectory: workingDirectory,
            title: title,
            model: model,
            modifiedAt: modifiedAt
        )
    }

    /// A message's content is either a string or the block array the API
    /// takes. Only the text blocks are worth a title -- an attachment or a
    /// tool result says nothing about what was asked.
    static func firstLine(of content: Any?) -> String {
        var text = ""
        if let string = content as? String {
            text = string
        } else if let blocks = content as? [[String: Any]] {
            text = blocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
        }
        return text
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The first `headBytes`, cut back to the last complete line so a
    /// half-read object is never handed to the parser.
    private static func head(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headBytes), !data.isEmpty else { return nil }
        // The cut can land inside a multi-byte character, so up to three
        // trailing bytes may have to go. Dropping exactly three was a guess
        // that happened to fix the common case and left a transcript out of
        // the list entirely whenever an emoji straddled the boundary.
        guard let text = (0...3).lazy.compactMap({ String(data: data.dropLast($0), encoding: .utf8) }).first else {
            return nil
        }
        guard let lastNewline = text.lastIndex(of: "\n") else { return text }
        return String(text[..<lastNewline])
    }
}
