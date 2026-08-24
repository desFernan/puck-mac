//
//  ClientTheme.swift
//  Puck
//
//  Design system v2 (2026-08-14) -- see docs/decisions.md. Colors
//  live in ClientPalette; this file is type/spacing/shape. Pruned to only
//  the tokens still actually consumed -- the 2026-08-13 chat-web migration
//  (docs/decisions.md) deleted ChatView.swift/ClientSidebarView.swift but
//  left their token definitions here; this rewrite removes them rather
//  than redesigning values nothing reads anymore.
//

import SwiftUI

enum ClientTheme {
    enum Typography {
        // Fixed sizes rather than text styles, all through.
        //
        // macOS's own scale is built for dense inspector panels: `.caption2`
        // is 10pt, `.footnote` 11, `.callout` 12. A whole window of chrome
        // built from those reads as something to squint at, which is what
        // this one did -- every list, tab and status line in it came out a
        // size or two below the text it was labelling. The numbers below are
        // that scale lifted a step, and stated outright so the relationships
        // between them are visible in one place instead of being inherited
        // from a table that was chosen for a different job.

        /// A settings section's title, and a sidebar group's.
        static let sectionHeader = Font.system(size: 13, weight: .semibold)
        /// A row's own name -- a workspace, a chat, a file.
        static let workspaceName = Font.system(size: 14, weight: .medium)
        /// What a row says about itself under its name.
        static let sessionTitle = Font.system(size: 13)
        static let toolLabel = Font.system(size: 13, weight: .medium)
        static let mono = Font.system(size: 12.5, design: .monospaced)
        /// The smallest thing here: a badge, a timestamp, a status letter.
        /// Not a size to set a list in.
        static let caption = Font.system(size: 12)

        // The agent's reply is read as a document rather than glanced at in a
        // balloon, so it gets its own scale instead of `.body` (13pt): 16pt
        // reads comfortably at arm's length on a Retina display, and the
        // transcript column was widened with it to keep the line ~75
        // characters. Fixed sizes rather
        // than text styles because the headings have to stay *above* the body
        // -- `.headline` is 13pt on macOS, i.e. smaller than this body.
        static let transcriptBody = Font.system(size: 16)
        static let transcriptCode = Font.system(size: 13.5, design: .monospaced)

        static func transcriptHeading(level: Int) -> Font {
            switch level {
            case 1: return .system(size: 23, weight: .semibold)
            case 2: return .system(size: 20, weight: .semibold)
            // Above the body, which is the whole point of the fixed sizes --
            // a heading at the body's own size is not a heading.
            default: return .system(size: 17, weight: .semibold)
            }
        }
    }

    enum Metrics {
        static let spacingSmall: CGFloat = 4
        static let spacingMedium: CGFloat = 8
        static let spacingLarge: CGFloat = 12
        /// Between one settings section and the next. Larger than the spacing
        /// inside a section, so the grouping is visible without a divider.
        static let sectionSpacing: CGFloat = 20
        /// Top and bottom of a settings window. Deliberately more than the
        /// horizontal padding: a short window reads as cramped long before a
        /// narrow one does, because the first and last rows sit against the
        /// title bar and the frame.
        static let windowEdgePadding: CGFloat = 20
        /// The transcript's text column. Every row in it -- message, tool
        /// card, approval banner -- is capped at this one measure and the
        /// column is centred, so widening the window adds margin instead of
        /// stretching the lines. ~75 characters at `transcriptBody`.
        ///
        /// Widened with the text: at 16pt the old 640 held about seventy
        /// characters, and the conversation is what the window is for. 760
        /// is a little past the classic measure on purpose -- code blocks and
        /// tool cards live in this column too, and they were the things being
        /// squeezed.
        static let transcriptColumnWidth: CGFloat = 760
        /// Kept outside the column, so the text never sits against the window
        /// chrome or the editor pane's divider. Fixed at every width -- the
        /// column is what gives way when the pane is narrow.
        ///
        /// 12 rather than the original 24: with the code column open the
        /// conversation is already narrow, and this was being paid twice --
        /// once on each side of it.
        static let transcriptHorizontalPadding: CGFloat = 12
        /// A floating panel's corners -- the island, the two sidebars.
        /// Rounded, not a capsule: a pill turns the ends into arcs and reads
        /// as a control, while these are panels with their corners taken off.
        static let panelCornerRadius: CGFloat = 14
        /// How far a floating panel sits from the window's edges and from its
        /// neighbours. One number, so the gaps between them all match.
        static let panelInset: CGFloat = 8
        /// v2: matches chat-web/workspace's shrunk --radius base (Task 6).
        static let cardCornerRadius: CGFloat = 6
        static let rowCornerRadius: CGFloat = 4
        // The window's floor depends on what it is showing, so there are two
        // of them (2026-08-15). One number cannot be right for both: it was
        // 960, which is generous for a chat and 160pt short of a chat plus an
        // editor -- the shortfall came out of the file tree, whose rows were
        // clipped rather than truncated at the smallest window.
        //
        // Both are derived from the panes rather than picked: each is the sum
        // of the minimum widths the views inside actually declare, plus the
        // splitters between them. Change a pane's minimum and change these.

        /// Sidebar (180) + chat column (380). The chat column's floor is what
        /// keeps the composer's placeholder on one line.
        static let windowMinWidth: CGFloat = 560
        /// The above, plus the file explorer on the right (200) and the code
        /// column a file click opens, which splits the chat's column
        /// rather than adding one at the edge: sidebar (180), conversation
        /// (320), code (300), explorer (200), three splitters.
        static let windowMinWidthWithCode: CGFloat = 1040
        /// The detached editor window: file tree (180) + code (360), without
        /// the chat's share of the split.
        static let editorWindowMinWidth: CGFloat = 540
        /// How much of the window's own colour sits over the blurred desktop.
        /// Enough that the theme still decides what the app looks like, thin
        /// enough that what is behind it reads as being behind it.
        static let windowTint: Double = 0.78
        static let windowMinHeight: CGFloat = 640
    }

    /// The shapes surfaces are cut to. Spelled once here rather than
    /// `RoundedRectangle(cornerRadius:style:)` at every call site.
    enum Shapes {
        static let card = RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        static let row = RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
    }
}
