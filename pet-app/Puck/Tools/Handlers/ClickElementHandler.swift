//
//  ClickElementHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Delegates to F10 SyntheticClick; approval itself is gated by the agent core
//
//  TODO(F4 level 2): classifying "is this target a system security dialog"
//  (to return not_supported_target instead of clicking, per protocol section
//  4) needs UIElementInspector's AX role/owner inspection, which doesn't
//  exist yet. Until then this always attempts the click.

import CoreGraphics

final class ClickElementHandler: ToolHandler {
    let toolName = "click_element"

    /// Injectable so the permission branch is testable without the real TCC
    /// state of whoever runs the suite.
    var isAccessibilityTrusted: () -> Bool = { AccessibilityPermission.isTrusted(prompt: false) }

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let frame = args.extractFrame() else {
            completion(.failure(.executionFailed("click_element requires a frame {x,y,width,height}")))
            return
        }

        // Posting a synthetic event into another app needs Accessibility.
        // Without it CGEvent.post silently does nothing, so the tool used to
        // report success for a click that never happened -- and the agent
        // would then tell the user it had clicked something.
        guard isAccessibilityTrusted() else {
            completion(.failure(.permissionDenied))
            return
        }

        SyntheticClick.click(at: CGPoint(x: frame.midX, y: frame.midY))
        completion(.success(nil))
    }
}
