//
//  JSONValue+Access.swift
//  Puck
//
//  Read accessors for JSONValue. ACP replies are mostly free-form -- only a
//  handful of fields drive behaviour and the rest is passed through untouched
//  (see AcpMessages) -- so reaching into them needs optional-chaining accessors
//  rather than a Codable model per message.
//
//  Kept out of Bridge/JSONValue.swift on purpose: that file is a verbatim copy
//  of protocol/swift/JSONValue.swift, and a copy stops being a copy the moment
//  it grows a local edit.
//

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// `self["a"]["b"]` without unwrapping at every step. Non-objects and
    /// missing keys both yield nil rather than being distinguished -- no caller
    /// here treats "the agent sent something else" differently from "the agent
    /// sent nothing".
    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}
