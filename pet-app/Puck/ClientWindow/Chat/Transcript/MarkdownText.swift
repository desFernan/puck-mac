//
//  MarkdownText.swift
//  Puck
//
//  Agent replies arrive as markdown and used to render as literal syntax.
//  `AttributedString(markdown:)` alone only covers inline spans, and an
//  agent answer is mostly block content -- headings, lists, fenced code --
//  so the blocks are parsed here and the inline spans inside each one are
//  handed to Foundation.
//
//  This renders text produced by a model, i.e. untrusted input: the parser
//  is a single non-recursive pass with no unbounded work per line, an
//  unterminated fence ends at EOF instead of running away, nesting is
//  clamped, and inline parsing falls back to the raw string whenever it
//  would drop characters. Losing text is always worse than losing styling.
//

import AppKit
import SwiftUI

// MARK: - Model

struct MarkdownListItem: Equatable {
    /// Indent depth, clamped -- a pathological document cannot indent the
    /// column off the right edge of the window.
    var level: Int
    /// The author's own number for an ordered item; nil for a bullet.
    var ordinal: Int?
    var text: String
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([MarkdownListItem])
    case codeBlock(language: String?, code: String)
    case quote(String)
    case rule
}

// MARK: - Block parsing

/// The deepest indent a list item is allowed to claim.
private let maxListLevel = 5

func parseMarkdownBlocks(_ source: String) -> [MarkdownBlock] {
    let lines = source
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")

    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var quote: [String] = []
    var items: [MarkdownListItem] = []

    func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
    }
    func flushQuote() {
        guard !quote.isEmpty else { return }
        blocks.append(.quote(quote.joined(separator: "\n")))
        quote = []
    }
    func flushList() {
        guard !items.isEmpty else { return }
        blocks.append(.list(items))
        items = []
    }
    func flushAll() {
        flushParagraph()
        flushQuote()
        flushList()
    }

    var index = 0
    while index < lines.count {
        let line = lines[index]
        let indent = leadingIndentWidth(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let fence = fenceOpener(trimmed) {
            flushAll()
            index += 1
            var body: [String] = []
            while index < lines.count {
                if closesFence(lines[index].trimmingCharacters(in: .whitespaces), fence) {
                    index += 1
                    break
                }
                body.append(dropIndent(lines[index], upTo: indent))
                index += 1
            }
            // An unterminated fence simply ends at EOF: everything after it
            // is still shown, as code, rather than swallowed.
            blocks.append(.codeBlock(language: fence.language, code: body.joined(separator: "\n")))
            continue
        }

        if trimmed.isEmpty {
            flushAll()
            index += 1
            continue
        }

        if isThematicBreak(trimmed) {
            flushAll()
            blocks.append(.rule)
            index += 1
            continue
        }

        if indent < 4, let heading = atxHeading(trimmed) {
            flushAll()
            blocks.append(.heading(level: heading.level, text: heading.text))
            index += 1
            continue
        }

        if trimmed.hasPrefix(">") {
            flushParagraph()
            flushList()
            quote.append(stripQuoteMarker(trimmed))
            index += 1
            continue
        }

        if let item = listItem(line) {
            flushParagraph()
            flushQuote()
            items.append(item)
            index += 1
            continue
        }

        // An indented, non-blank line under a list item continues that item
        // rather than starting a paragraph that would break the list apart.
        if !items.isEmpty && indent >= 2 {
            items[items.count - 1].text += "\n" + trimmed
            index += 1
            continue
        }

        flushQuote()
        flushList()
        paragraph.append(trimmed)
        index += 1
    }

    flushAll()
    return blocks
}

private struct Fence {
    var character: Character
    var length: Int
    var language: String?
}

private func fenceOpener(_ trimmed: String) -> Fence? {
    guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
    let run = trimmed.prefix { $0 == first }
    guard run.count >= 3 else { return nil }
    let info = trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
    // A backtick in the info string is not a fence at all in CommonMark.
    if first == "`" && info.contains("`") { return nil }
    let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
    return Fence(character: first, length: run.count, language: language)
}

private func closesFence(_ trimmed: String, _ fence: Fence) -> Bool {
    guard let first = trimmed.first, first == fence.character else { return false }
    let run = trimmed.prefix { $0 == fence.character }
    guard run.count >= fence.length else { return false }
    return trimmed.dropFirst(run.count).allSatisfy { $0 == " " || $0 == "\t" }
}

private func isThematicBreak(_ trimmed: String) -> Bool {
    guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else { return false }
    var count = 0
    for character in trimmed {
        if character == first { count += 1 } else if character != " " && character != "\t" { return false }
    }
    return count >= 3
}

private func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
    guard trimmed.hasPrefix("#") else { return nil }
    let hashes = trimmed.prefix { $0 == "#" }
    guard hashes.count <= 6 else { return nil }
    let rest = trimmed.dropFirst(hashes.count)
    guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
    var text = rest.trimmingCharacters(in: .whitespaces)
    // A closing run of hashes ("## Title ##") is decoration, not content.
    if text.hasSuffix("#") {
        let closing = text.reversed().prefix { $0 == "#" }.count
        let withoutClosing = String(text.dropLast(closing))
        if withoutClosing.isEmpty || withoutClosing.hasSuffix(" ") {
            text = withoutClosing.trimmingCharacters(in: .whitespaces)
        }
    }
    return (min(hashes.count, 6), text)
}

private func stripQuoteMarker(_ trimmed: String) -> String {
    var rest = Substring(trimmed).dropFirst()
    if rest.first == " " { rest = rest.dropFirst() }
    return String(rest)
}

private func listItem(_ line: String) -> MarkdownListItem? {
    let indent = leadingIndentWidth(line)
    var rest = Substring(line.drop { $0 == " " || $0 == "\t" })
    guard let marker = rest.first else { return nil }

    var ordinal: Int?
    if marker == "-" || marker == "*" || marker == "+" {
        rest = rest.dropFirst()
    } else if marker.isNumber {
        let digits = rest.prefix { $0.isNumber }
        // Bounded so a 400-digit "number" is prose, not a list marker.
        guard digits.count <= 9 else { return nil }
        let after = rest.dropFirst(digits.count)
        guard let delimiter = after.first, delimiter == "." || delimiter == ")" else { return nil }
        ordinal = Int(digits) ?? 1
        rest = after.dropFirst()
    } else {
        return nil
    }

    // The marker has to be followed by space -- "*bold* text" is a paragraph.
    guard let next = rest.first, next == " " || next == "\t" else { return nil }
    let text = rest.trimmingCharacters(in: .whitespaces)
    return MarkdownListItem(level: min(indent / 2, maxListLevel), ordinal: ordinal, text: text)
}

private func leadingIndentWidth(_ line: String) -> Int {
    var width = 0
    for character in line {
        if character == " " { width += 1 } else if character == "\t" { width += 4 } else { break }
    }
    return width
}

private func dropIndent(_ line: String, upTo width: Int) -> String {
    var remaining = width
    var index = line.startIndex
    while remaining > 0, index < line.endIndex {
        let character = line[index]
        if character == " " { remaining -= 1 } else if character == "\t" { remaining -= 4 } else { break }
        index = line.index(after: index)
    }
    return String(line[index...])
}

// MARK: - Inline parsing

/// URL schemes a rendered link is allowed to keep. Anything else keeps its
/// label and loses its link: this text comes from a model, and a transcript
/// is not a place to hand it an arbitrary scheme to hand to `openURL`.
private let allowedLinkSchemes: Set<String> = ["http", "https", "mailto"]

/// Inline markdown (`**bold**`, `` `code` ``, `[label](url)`) for one block's
/// worth of text, falling back to the literal string whenever the parse would
/// change what the text *says* rather than how it looks.
func markdownInline(_ source: String) -> AttributedString {
    let plain = AttributedString(source)
    guard !source.isEmpty else { return plain }

    // `<...>` would otherwise be parsed as raw HTML and dropped whole, which
    // is how a generic type in prose disappears. Escaped, it stays literal.
    let escaped = source.replacingOccurrences(of: "<", with: "\\<")

    var options = AttributedString.MarkdownParsingOptions()
    options.interpretedSyntax = .inlineOnlyPreservingWhitespace
    options.failurePolicy = .returnPartiallyParsedIfPossible
    options.allowsExtendedAttributes = false

    guard var parsed = try? AttributedString(markdown: escaped, options: options) else { return plain }

    // Checked before the links below are pruned -- a destination this view
    // declines to make clickable is a display choice, not lost content.
    guard markdownWordCount(parsed) >= wordCharacterCount(source) else { return plain }

    // Ranges collected before anything is written back: mutating the string
    // while walking its own runs is not something to rely on.
    let disallowed = parsed.runs.compactMap { run -> Range<AttributedString.Index>? in
        guard let link = run.link else { return nil }
        guard !allowedLinkSchemes.contains(link.scheme?.lowercased() ?? "") else { return nil }
        return run.range
    }
    for range in disallowed { parsed[range].link = nil }

    // `code` spans carry only a presentation *intent*; SwiftUI's Text draws
    // them in the body font unless the font is set here, which made
    // `identifier` and prose indistinguishable once the backticks were gone.
    let codeRanges = parsed.runs.compactMap { run -> Range<AttributedString.Index>? in
        run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
    }
    for range in codeRanges { parsed[range].font = ClientTheme.Typography.transcriptCode }

    return parsed
}

/// Letters and digits only: the one thing the renderer must never lose. Syntax
/// characters, escapes and whitespace all differ between the source and the
/// rendered form by design, so counting them would reject valid markdown.
private func wordCharacterCount(_ string: String) -> Int {
    string.unicodeScalars.reduce(0) { CharacterSet.alphanumerics.contains($1) ? $0 + 1 : $0 }
}

/// The same count for a parsed result, with link destinations included -- a
/// link's URL leaves the visible text but is still carried by the run.
private func markdownWordCount(_ attributed: AttributedString) -> Int {
    var total = wordCharacterCount(String(attributed.characters))
    for run in attributed.runs {
        if let link = run.link { total += wordCharacterCount(link.absoluteString) }
    }
    return total
}

// MARK: - View

/// Renders one markdown document as flowing text. Every block is selectable;
/// fenced code keeps its whitespace and is never markdown-parsed.
struct MarkdownText: View {
    let markdown: String

    private var blocks: [MarkdownBlock] { parseMarkdownBlocks(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingMedium) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(markdownInline(text))
                .font(ClientTheme.Typography.transcriptHeading(level: level))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ClientTheme.Metrics.spacingSmall)

        case .paragraph(let text):
            Text(markdownInline(text))
                .font(ClientTheme.Typography.transcriptBody)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .list(let items):
            VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingSmall) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)

        case .quote(let text):
            Text(markdownInline(text))
                .font(ClientTheme.Typography.transcriptBody)
                .foregroundStyle(.secondary)
                .padding(.leading, ClientTheme.Metrics.spacingLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 3)
                }

        case .rule:
            Divider()
        }
    }

    private func listRow(_ item: MarkdownListItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ClientTheme.Metrics.spacingMedium) {
            Text(item.ordinal.map { "\($0)." } ?? "•")
                .font(ClientTheme.Typography.transcriptBody)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(markdownInline(item.text))
                .font(ClientTheme.Typography.transcriptBody)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(item.level) * ClientTheme.Metrics.spacingLarge)
    }
}

/// A fenced block, with the two things anyone reading code in a chat wants:
/// an edge so it is clearly not prose, and a way to take it.
///
/// The button is always there, dimmed until the pointer is over the block. It
/// tried appearing only on hover, which keeps it out of the way of the first
/// line -- and makes it a button nobody knows about until they happen to
/// sweep the mouse across the code.
private struct CodeBlockView: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let language: String?
    let code: String

    @State private var isHovering = false
    @State private var hasCopied = false

    var body: some View {
        Text(code)
            .font(ClientTheme.Typography.transcriptCode)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ClientTheme.Metrics.spacingMedium)
            .background(.quaternary.opacity(0.4), in: ClientTheme.Shapes.card)
            .overlay {
                ClientTheme.Shapes.card.strokeBorder(palette.surfaceBorder, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) { copyButton }
            .onHover { isHovering = $0 }
    }

    private var copyButton: some View {
        Button(action: copy) {
            Label(
                    hasCopied ? Strings.text(.codeBlockCopied) : Strings.text(.codeBlockCopy),
                    systemImage: hasCopied ? "checkmark" : "doc.on.doc"
                )
            .labelStyle(.iconOnly)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(hasCopied ? palette.accent : palette.textSecondary)
            .frame(width: 22, height: 20)
            .background(palette.surface, in: ClientTheme.Shapes.row)
            .overlay {
                ClientTheme.Shapes.row.strokeBorder(palette.surfaceBorder, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isHovering || hasCopied ? 1 : 0.4)
        .padding(6)
        .accessibilityLabel(Strings.text(.codeBlockCopy))
        .help(Strings.text(.codeBlockCopy))
    }

    private func copy() {
        CodeBlockClipboard.copy(code)
        // Said by the button itself rather than a banner: the answer to "did
        // that work" belongs where the click was.
        hasCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { hasCopied = false }
    }
}

/// Putting a code block on the pasteboard, apart from the view that offers
/// it -- so what the button does can be checked without a window, a pointer
/// and a hover state.
enum CodeBlockClipboard {
    /// Cleared first: a pasteboard still holding the last thing copied would
    /// otherwise hand out whichever type an app asked for, which is how a
    /// paste comes back as something nobody copied.
    @discardableResult
    static func copy(_ code: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(code, forType: .string)
    }
}
