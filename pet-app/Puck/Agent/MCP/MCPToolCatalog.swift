//
//  MCPToolCatalog.swift
//  Puck
//
//  Puck's own tools, rendered as MCP tool definitions for the CLI provider's
//  in-process MCP server.
//
//  Built from the `[GPTToolSpec]` the runner already hands every provider,
//  which is itself built from ToolRegistry plus the runner's description text.
//  That is the whole reason this takes specs rather than reading the registry
//  a second time: a second list of tool names is exactly the drift this
//  codebase keeps removing, and the descriptions -- which the registry
//  deliberately does not carry -- would have had to be duplicated with it.
//

import Foundation

enum MCPToolCatalog {
    /// The name the CLI sees the server under. Claude Code prefixes a tool
    /// with it (`mcp__puck__run_shell`), so it also decides what the prompt
    /// override has to tell the model to call.
    static let serverName = "puck"

    /// Not offered over MCP: on this provider the CLI *is* the coding agent
    /// code_editor would hand the task to, so exposing it hands the agent back
    /// to itself -- a second vendor process spawned inside the turn of the
    /// first, with the same tool available again at the bottom.
    ///
    /// `open_task_session` goes with it: its description tells the model to
    /// "call code_editor on the next turn", which on this provider is a tool
    /// that isn't there. Offering a handoff whose second half is missing is
    /// worse than not offering it -- the CLI does the editing itself here.
    static let excludedToolNames: Set<String> = ["code_editor", "open_task_session"]

    /// The `tools/list` payload.
    static func definitions(for specs: [GPTToolSpec]) -> [JSONValue] {
        specs
            .filter { !excludedToolNames.contains($0.name) }
            .map(definition(for:))
    }

    static func definition(for spec: GPTToolSpec) -> JSONValue {
        .object([
            "name": .string(spec.name),
            "description": .string(spec.description),
            "inputSchema": inputSchema(for: spec.parameters),
        ])
    }

    /// JSON Schema for one tool's arguments. `required` is omitted entirely
    /// when nothing is required -- an empty array is legal but reads to some
    /// validators as "required: none of these", and a no-parameter tool
    /// (list_running_apps) should carry no constraint at all.
    static func inputSchema(for parameters: [ToolRegistry.Parameter]) -> JSONValue {
        var properties: [String: JSONValue] = [:]
        var required: [JSONValue] = []
        for parameter in parameters {
            properties[parameter.name] = .object(["type": .string(parameter.type.rawValue)])
            if parameter.isRequired { required.append(.string(parameter.name)) }
        }
        var schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty { schema["required"] = .array(required) }
        return .object(schema)
    }
}
