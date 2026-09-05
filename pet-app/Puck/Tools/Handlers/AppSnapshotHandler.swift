//
//  AppSnapshotHandler.swift
//  Puck
//
//  What is in an app's window, as a list the model can read.
//
//  `find_ui_element` answers a question you can only ask once you know what
//  to ask for. This is the one that comes before it -- and without it the
//  loop was guess a role, miss, guess a title, miss, give up, which is what a
//  request like "설정에서 이거 켜줘" actually looked like.
//
//  The rules live in UIElementOutline, which is pure and tested; this is the
//  wrapper that gets a live tree to hand it.
//

import ApplicationServices
import CoreGraphics
import Foundation

final class AppSnapshotHandler: ToolHandler {
    let toolName = "app_snapshot"

    /// Injectable so the permission branch is testable without the real TCC
    /// state of whoever runs the suite -- same reason ClickElementHandler has
    /// one.
    var isAccessibilityTrusted: () -> Bool = { AccessibilityPermission.isTrusted(prompt: false) }

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let pid = args.extractPID() else {
            completion(.failure(.executionFailed("app_snapshot requires a numeric pid")))
            return
        }
        guard isAccessibilityTrusted() else {
            completion(.failure(.permissionDenied))
            return
        }

        // Off the caller's thread for the reason find_ui_element is: walking
        // the tree blocks on the target app answering.
        DispatchQueue.global().async {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, Float(UIElementInspector.searchBudget))
            let outline = UIElementOutline.describe(
                UIElementInspector.node(for: element),
                maxDepth: UIElementInspector.maxDepth,
                budget: UIElementInspector.searchBudget
            )
            guard !outline.isEmpty else {
                // An app with nothing readable is an answer, not a failure --
                // the same rule find_ui_element follows for no match. It
                // usually means the app draws its own UI (a game, a canvas)
                // and has no accessibility tree to speak of.
                completion(.success(.null))
                return
            }
            completion(.success(.object(["elements": .string(outline)])))
        }
    }
}
