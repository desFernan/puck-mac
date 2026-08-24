//
//  UIElementSearch.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Depth- and time-limited DFS over an accessibility tree.
//
//  Split from the AXUIElement calls themselves so the traversal — the part
//  with the interesting rules — is testable without a live app or the
//  Accessibility permission, the same way WindowListWatcher.filter is split
//  from its CGWindowList fetch.
//

import CoreGraphics
import Foundation

/// One element of an accessibility tree, as much of it as find_ui_element
/// needs. Abstracted so tests can hand the search a tree they built.
protocol AXNode {
    var role: String? { get }
    var title: String? { get }
    var frame: CGRect? { get }
    var isEnabled: Bool? { get }
    /// Reading children costs an AX round trip, so the search asks only when
    /// it intends to descend.
    var childNodes: [AXNode] { get }
}

enum UIElementSearch {
    /// protocol section 4's find_ui_element parameters, minus the pid (which
    /// selects the tree rather than filtering within it).
    struct Query: Equatable {
        let role: String?
        let titleContains: String?
    }

    /// protocol section 4's `{role, title, frame}`, plus enabled, which F10
    /// wants before clicking something.
    struct Match: Equatable {
        let role: String?
        let title: String?
        let frame: CGRect?
        let isEnabled: Bool?
    }

    /// Depth limit and time budget are both mandatory (plan F4): a real tree
    /// can be enormous, and an unresponsive app makes every attribute read
    /// block, which would otherwise hang the whole tool call.
    static func firstMatch(in root: AXNode, query: Query, maxDepth: Int, budget: TimeInterval) -> Match? {
        let deadline = Date().addingTimeInterval(budget)
        return search(root, query: query, depth: 0, maxDepth: maxDepth, deadline: deadline)
    }

    private static func search(_ node: AXNode, query: Query, depth: Int, maxDepth: Int, deadline: Date) -> Match? {
        guard Date() < deadline else { return nil }

        if matches(node, query: query) {
            return Match(role: node.role, title: node.title, frame: node.frame, isEnabled: node.isEnabled)
        }

        guard depth < maxDepth else { return nil }
        for child in node.childNodes {
            if let found = search(child, query: query, depth: depth + 1, maxDepth: maxDepth, deadline: deadline) {
                return found
            }
        }
        return nil
    }

    private static func matches(_ node: AXNode, query: Query) -> Bool {
        // Something with no position can't be pointed at or clicked, which is
        // the only reason anything looks an element up.
        guard node.frame != nil else { return false }

        if let role = query.role, node.role != role {
            return false
        }
        if let needle = query.titleContains {
            guard let title = node.title,
                  title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            else {
                return false
            }
        }
        // A query with neither constraint would match the first framed node,
        // which is never what the caller meant.
        return query.role != nil || query.titleContains != nil
    }
}
