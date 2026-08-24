//
//  UIElementInspector.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  AXUIElement tree DFS (depth-limited/timeout), backs find_ui_element
//
//  Thin AXUIElement wrapper: it turns a live app into AXNodes and lets
//  UIElementSearch do the traversal. Not unit tested — every call here talks
//  to a real app through the Accessibility API, which needs the permission
//  and another running process. The rules worth testing live in
//  UIElementSearch.
//

import ApplicationServices
import CoreGraphics
import Foundation

enum UIElementInspectorError: Error, Equatable {
    case accessibilityNotTrusted
}

/// An AXUIElement seen as an AXNode. Attribute reads are lazy: the search
/// only pays for what it inspects.
private struct AXUIElementNode: AXNode {
    let element: AXUIElement

    var role: String? { copyAttribute(kAXRoleAttribute) as? String }
    var title: String? {
        // Buttons in system dialogs often carry their label as the AX
        // description rather than the title.
        (copyAttribute(kAXTitleAttribute) as? String)
            ?? (copyAttribute(kAXDescriptionAttribute) as? String)
    }
    var isEnabled: Bool? { copyAttribute(kAXEnabledAttribute) as? Bool }

    var frame: CGRect? {
        guard
            let positionValue = copyAttribute(kAXPositionAttribute),
            let sizeValue = copyAttribute(kAXSizeAttribute),
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        guard
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    var childNodes: [AXNode] {
        guard let children = copyAttribute(kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return children.map { AXUIElementNode(element: $0) }
    }

    private func copyAttribute(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}

enum UIElementInspector {
    /// Deep enough for a real settings pane, shallow enough to stay bounded.
    static let maxDepth = 12
    /// Comfortably inside find_ui_element's 15s registry timeout.
    static let searchBudget: TimeInterval = 5

    /// Finds the first element of `pid`'s app matching the query.
    /// Frames come back in global Quartz coordinates, as protocol section 4
    /// expects for anything that later feeds point_at or click_element.
    static func findElement(
        pid: pid_t,
        role: String?,
        titleContains: String?
    ) throws -> UIElementSearch.Match? {
        guard AccessibilityPermission.isTrusted(prompt: false) else {
            throw UIElementInspectorError.accessibilityNotTrusted
        }

        let rootElement = AXUIElementCreateApplication(pid)
        // The deadline `budget` passed to UIElementSearch is only checked
        // between node visits -- a single AX IPC call against an unresponsive
        // target app can itself hang indefinitely and defeat it entirely.
        // This caps each individual call at the same budget.
        AXUIElementSetMessagingTimeout(rootElement, Float(searchBudget))
        let root = AXUIElementNode(element: rootElement)
        return UIElementSearch.firstMatch(
            in: root,
            query: .init(role: role, titleContains: titleContains),
            maxDepth: maxDepth,
            budget: searchBudget
        )
    }
}
