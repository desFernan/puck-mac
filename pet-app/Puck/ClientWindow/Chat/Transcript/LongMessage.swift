//
//  LongMessage.swift
//  Puck
//
//  When a sent message is too long to be a bubble, and what to show instead.
//
//  A pasted log, a stack trace, a whole file: the transcript drew all of it,
//  in a tinted bubble, and one message pushed the conversation it belongs to
//  off the top of the window. The message itself is fine -- the model reads
//  all of it and always has -- so nothing here changes what is sent. This
//  only decides how much of it is drawn.
//
//  Pure, and separate from the view, because the two interesting cases are
//  boundaries: a message just over the line, and one whose length is all in a
//  single unbroken line rather than in many.
//

import Foundation

enum LongMessage {
    /// How many lines are shown before a message is folded.
    ///
    /// Twelve is about a third of the transcript at a usual window height --
    /// enough to recognise what was pasted without it becoming the window.
    static let previewLines = 12

    /// And how many characters, for the message that is long without being
    /// tall. One 4,000-character paragraph wraps to a wall of text and has a
    /// single newline in it, so a line count alone would let it through.
    static let previewCharacters = 700

    /// Whether `text` is drawn folded.
    static func isLong(_ text: String) -> Bool {
        text.count > previewCharacters || lineCount(text) > previewLines
    }

    /// The part shown while it is folded.
    ///
    /// Cut at whichever limit it crosses first, and at a line boundary
    /// wherever one is close: a preview that stops mid-word reads as damage,
    /// and a preview that stops mid-line reads as a decision.
    static func preview(of text: String) -> String {
        guard isLong(text) else { return text }
        let byLines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(previewLines)
            .joined(separator: "\n")
        let clipped = String(byLines.prefix(previewCharacters))
        // Back to the last line break, but only if that leaves most of the
        // preview: a first line longer than the whole budget has none to go
        // back to, and cutting to nothing is worse than cutting mid-word.
        guard let lastBreak = clipped.lastIndex(of: "\n"),
              clipped.distance(from: clipped.startIndex, to: lastBreak) > previewCharacters / 2
        else {
            return clipped
        }
        return String(clipped[clipped.startIndex..<lastBreak])
    }

    /// How much was folded away, as the line says it: lines and kilobytes,
    /// which is how someone recognises the thing they pasted.
    static func summary(of text: String) -> String {
        let lines = lineCount(text)
        let bytes = text.utf8.count
        let size = bytes >= 1024
            ? String(format: "%.1f KB", Double(bytes) / 1024)
            : "\(bytes) B"
        return String(format: Strings.text(.chatLongMessageFormat), "\(lines)", size)
    }

    /// A name for the file this message is written out to.
    ///
    /// Stamped with the time rather than a UUID: these land in a folder
    /// somebody opens, and a list of timestamps is one they can read.
    static func fileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "message-\(formatter.string(from: now)).txt"
    }

    /// Counts lines the way a person does: a trailing newline does not add an
    /// empty last line.
    static func lineCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let trimmed = text.hasSuffix("\n") ? String(text.dropLast()) : text
        return trimmed.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
