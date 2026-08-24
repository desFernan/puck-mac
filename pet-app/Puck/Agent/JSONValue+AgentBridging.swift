//
//  JSONValue+AgentBridging.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The two conversions between the model's world (JSON *text*, because that
//  is what OpenAI emits for tool arguments) and the socket's world
//  (JSONValue, protocol 3.1's `args` / `data`).
//
//  Kept out of Bridge/JSONValue.swift on purpose: that file is a hand-synced
//  mirror of protocol/swift/JSONValue.swift, and anything added to it has to
//  be added there too. These two helpers are the agent's, not the contract's.
//

import Foundation

extension JSONValue {
    /// Parses a tool call's `arguments` string into the object the socket
    /// wants. Anything unparseable becomes an empty object rather than a
    /// throw: the model occasionally emits `""` or a fragment for a
    /// no-parameter tool, and failing the whole call over that is worse than
    /// dispatching with no arguments and letting the executor complain.
    static func decodeObject(from jsonText: String) -> JSONValue {
        guard
            let data = jsonText.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object = decoded
        else {
            return .object([:])
        }
        return decoded
    }

    /// This value as compact JSON text, for feeding a tool_result back to the
    /// model.
    var jsonText: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
