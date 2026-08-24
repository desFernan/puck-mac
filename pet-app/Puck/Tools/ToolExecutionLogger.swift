//
//  ToolExecutionLogger.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Records tool_exec_start/end in the protocol section 7 log format
//

import Foundation

enum ToolExecutionLogEvent: Equatable {
    case execStart(id: String)
    case execEnd(id: String, ok: Bool)

    // The `src: "agent"` half of protocol section 7 (2026-08-12). pet-app's
    // two lines carry only `id` and `ok`, which is what the spec asks of the
    // executor -- but with nothing logged from the agent side, a failed call
    // is an opaque uuid: no tool name, no error code, nothing to search for.
    // The spec's own example pairs each exec line with an agent line, and
    // that pairing is the whole point of the shared id.
    case agentToolCall(id: String, tool: String, args: JSONValue?)
    case agentToolResult(id: String, ok: Bool, error: String?)

    var source: String {
        switch self {
        case .execStart, .execEnd: "pet-app"
        case .agentToolCall, .agentToolResult: "agent"
        }
    }
}

protocol ToolExecutionLogging {
    func log(_ event: ToolExecutionLogEvent)
}

/// One JSON Lines entry, formatted per protocol repo section 7 (joinable
/// across agent/pet-app/workspace logs by `id`).
struct ToolExecutionLogLine: Encodable {
    let event: ToolExecutionLogEvent
    let timestamp: String

    private enum CodingKeys: String, CodingKey {
        case ts, src, kind, id, ok, tool, args, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .ts)
        try container.encode(event.source, forKey: .src)
        switch event {
        case .execStart(let id):
            try container.encode("tool_exec_start", forKey: .kind)
            try container.encode(id, forKey: .id)
        case .execEnd(let id, let ok):
            try container.encode("tool_exec_end", forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(ok, forKey: .ok)
        case .agentToolCall(let id, let tool, let args):
            try container.encode("tool_call", forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(tool, forKey: .tool)
            try container.encodeIfPresent(args, forKey: .args)
        case .agentToolResult(let id, let ok, let error):
            try container.encode("tool_result", forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(ok, forKey: .ok)
            try container.encodeIfPresent(error, forKey: .error)
        }
    }
}

/// Appends log lines to ~/Library/Application Support/Puck/logs/, one
/// file per day (UTC). Thin file-I/O wrapper — not unit tested beyond
/// ToolExecutionLogLine's pure formatting.
final class ToolExecutionLogger: ToolExecutionLogging {
    static let defaultLogDirectory = JSONLinesFileAppender.defaultLogDirectory

    private let appender: JSONLinesFileAppender

    init(directory: URL = ToolExecutionLogger.defaultLogDirectory) {
        appender = JSONLinesFileAppender(directory: directory, queueLabel: "Puck.ToolExecutionLogger")
    }

    func log(_ event: ToolExecutionLogEvent) {
        appender.append(ToolExecutionLogLine(event: event, timestamp: ISO8601DateFormatter().string(from: Date())))
    }
}
