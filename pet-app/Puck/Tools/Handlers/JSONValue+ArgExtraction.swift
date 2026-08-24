//
//  JSONValue+ArgExtraction.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Shared tool_dispatch argument extraction, used by multiple handlers.
//

import CoreGraphics

extension JSONValue {
    /// args: `{"frame": {"x":_, "y":_, "width":_, "height":_}}` (protocol section 4).
    func extractFrame(key: String = "frame") -> CGRect? {
        guard case .object(let fields) = self, case .object(let frameFields) = fields[key] else {
            return nil
        }
        guard
            case .number(let x)? = frameFields["x"],
            case .number(let y)? = frameFields["y"],
            case .number(let width)? = frameFields["width"],
            case .number(let height)? = frameFields["height"],
            x.isFinite, y.isFinite, width.isFinite, height.isFinite
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// args: `{"<key>": "..."}` — a single required top-level string field.
    /// Both halves already exist as JSONValue accessors; this name is what the
    /// handlers read against the tool registry's argument spec.
    func extractString(key: String) -> String? {
        self[key]?.stringValue
    }
}

extension JSONValue {
    /// pids arrive as JSON numbers (protocol section 4's find_ui_element).
    func extractPID(key: String = "pid") -> pid_t? {
        guard case .object(let fields) = self, case .number(let value)? = fields[key] else { return nil }
        // pid_t is Int32 on Darwin -- Int32(Double) traps (crashes the whole
        // process) for non-finite or out-of-range values, and an arbitrary
        // tool_dispatch can send any JSON number here.
        guard value.isFinite, let pid = Int32(exactly: value.rounded()) else { return nil }
        return pid
    }
}
