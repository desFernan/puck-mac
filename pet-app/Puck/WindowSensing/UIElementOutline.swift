//
//  UIElementOutline.swift
//  Puck
//
//  An app's accessibility tree, written out so a model can read it.
//
//  `find_ui_element` answers "is there something with this role or this
//  title", which is only useful once you already know what to ask for. What
//  the model actually needs first is what is *there* -- and without it the
//  loop is guess, miss, guess again, which is what "이거 켜줘" turning into
//  four failed searches looks like.
//
//  Orca's `get-app-state` is the same idea, and the shape is borrowed from
//  it: one indented line per element, role and title and frame. What is
//  deliberately not borrowed is its element indices. Orca hands back `@e1`
//  refs and takes them in later calls, which means holding a table that goes
//  stale the moment the app redraws; Puck already speaks in frames --
//  `point_at` and `click_element` both take one -- so a line here can be used
//  directly, and nothing has to stay valid between calls.
//
//  Pure, against the same `AXNode` protocol `UIElementSearch` uses, so it can
//  be tested without a running app.
//

import CoreGraphics
import Foundation

enum UIElementOutline {
    /// How many lines one snapshot may be.
    ///
    /// A Safari window is thousands of elements and all of it would go
    /// straight into the model's context. 200 is enough to see a window's
    /// structure and pick the next thing to look at.
    static let maximumLines = 200

    /// Elements with no role, no title and no size are layout scaffolding --
    /// groups holding other groups. They are walked through but not printed:
    /// a tree that is nine tenths `AXGroup` is one nobody can read.
    static func isWorthPrinting(role: String?, title: String?, frame: CGRect?) -> Bool {
        guard let frame, frame.width > 1, frame.height > 1 else { return false }
        if let title, !title.isEmpty { return true }
        guard let role else { return false }
        // A role on its own is worth a line when it is something you can act
        // on. A bare group or an unnamed image is not.
        return !Self.silentRoles.contains(role)
    }

    /// Roles that say nothing without a title.
    static let silentRoles: Set<String> = [
        "AXGroup", "AXSplitGroup", "AXScrollArea", "AXUnknown", "AXLayoutArea",
        "AXLayoutItem", "AXImage", "AXStaticText",
    ]

    /// One element's line: the indent, the role, the title, and the frame the
    /// other tools take.
    static func line(depth: Int, role: String?, title: String?, frame: CGRect?, isEnabled: Bool?) -> String {
        var text = String(repeating: "  ", count: depth)
        text += role ?? "?"
        if let title, !title.isEmpty {
            // Bounded: an AXStaticText's title can be a whole paragraph, and
            // one element must not be able to spend the whole budget.
            let trimmed = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            text += " \"" + String(trimmed.prefix(80)) + (trimmed.count > 80 ? "…" : "") + "\""
        }
        if let frame {
            text += String(
                format: " [%.0f %.0f %.0f %.0f]",
                frame.origin.x, frame.origin.y, frame.width, frame.height
            )
        }
        if isEnabled == false { text += " (disabled)" }
        return text
    }

    /// The tree, depth-first, as text.
    ///
    /// - Parameters:
    ///   - maxDepth: how far down to walk. Deeper than `UIElementSearch` goes
    ///     is pointless; shallower misses the controls, which are always
    ///     leaves.
    ///   - budget: the same wall-clock bound the search uses, because the same
    ///     thing can go wrong -- one AX call against a busy app blocking for
    ///     as long as it likes.
    static func describe(
        _ root: AXNode,
        maxDepth: Int = 12,
        limit: Int = maximumLines,
        budget: TimeInterval = 5,
        now: () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) -> String {
        var lines: [String] = []
        let deadline = now() + budget
        var ranOut = false

        func walk(_ node: AXNode, depth: Int) {
            guard lines.count < limit else { return }
            guard now() < deadline else {
                ranOut = true
                return
            }
            let role = node.role
            let title = node.title
            let frame = node.frame
            // Printed or not, the walk continues: the useful controls are
            // usually under the groups that are not worth a line themselves.
            let printed = isWorthPrinting(role: role, title: title, frame: frame)
            if printed {
                lines.append(line(depth: depth, role: role, title: title, frame: frame, isEnabled: node.isEnabled))
            }
            guard depth < maxDepth else { return }
            for child in node.childNodes {
                walk(child, depth: printed ? depth + 1 : depth)
            }
        }
        walk(root, depth: 0)

        if lines.count >= limit {
            lines.append("… (\(limit) elements shown; narrow the search with find_ui_element)")
        } else if ranOut {
            lines.append("… (stopped early: the app took too long to answer)")
        }
        return lines.joined(separator: "\n")
    }
}
