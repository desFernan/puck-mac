//
//  FindUIElementHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Returns F4 level-2 lookup results as {role,title,frame}
//
//  args: `{"pid": 501, "role": "AXButton", "title_contains": "허용"}`.
//  role and title_contains are both optional individually, but at least one
//  is needed or the query matches whatever comes first.
//

import CoreGraphics
import Foundation

final class FindUIElementHandler: ToolHandler {
    let toolName = "find_ui_element"

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let pid = args.extractPID() else {
            completion(.failure(.executionFailed("find_ui_element requires a numeric pid")))
            return
        }
        let role = args.extractString(key: "role")
        let titleContains = args.extractString(key: "title_contains")
        guard role != nil || titleContains != nil else {
            completion(.failure(.executionFailed("find_ui_element requires role or title_contains")))
            return
        }

        // The AX tree walk blocks on the target app, so keep it off the
        // caller's thread.
        DispatchQueue.global().async {
            do {
                guard let match = try UIElementInspector.findElement(pid: pid, role: role, titleContains: titleContains) else {
                    // No such element. Reported as success-with-null for the
                    // same reason get_frontmost_window does: "nothing there"
                    // is an answer, not an execution failure.
                    completion(.success(.null))
                    return
                }
                completion(.success(Self.encode(match)))
            } catch UIElementInspectorError.accessibilityNotTrusted {
                completion(.failure(.permissionDenied))
            } catch {
                completion(.failure(.executionFailed(String(describing: error))))
            }
        }
    }

    static func encode(_ match: UIElementSearch.Match) -> JSONValue {
        var fields: [String: JSONValue] = [
            "role": match.role.map(JSONValue.string) ?? .null,
            "title": match.title.map(JSONValue.string) ?? .null,
        ]
        if let frame = match.frame {
            fields["frame"] = .object([
                "x": .number(frame.origin.x),
                "y": .number(frame.origin.y),
                "width": .number(frame.width),
                "height": .number(frame.height),
            ])
        }
        if let isEnabled = match.isEnabled {
            fields["enabled"] = .bool(isEnabled)
        }
        return .object(fields)
    }
}
