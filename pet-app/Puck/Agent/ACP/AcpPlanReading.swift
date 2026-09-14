//
//  AcpPlanReading.swift
//  Puck
//
//  An ACP `plan` update, read into the plan the rest of the app carries.
//
//  Filed with the protocol that produces it rather than with the type it
//  produces: AgentPlan crosses the socket and is stored with the transcript,
//  so it lives down in Bridge with the rest of the wire -- and nothing down
//  there should have to know what shape a coding agent's notification is.
//

import Foundation

extension AgentPlan {
    /// Reads an ACP `plan` update.
    ///
    /// - Returns: nil when the update carries no steps at all. An agent that
    ///   sends an empty plan is not reporting progress on nothing; it is
    ///   clearing what it said, and there is no row to draw for that.
    static func from(update raw: JSONValue) -> AgentPlan? {
        let update = raw["update"] ?? raw
        guard let entries = update["entries"]?.arrayValue else { return nil }
        let steps: [AgentPlanStep] = entries.compactMap { entry in
            // `content` is what the schema calls it. Falling back to `title`
            // costs one line and covers an agent that names it the way its
            // tool calls are named.
            let text = entry["content"]?.stringValue ?? entry["title"]?.stringValue
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return AgentPlanStep(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                status: AgentPlanStep.Status.parsed(entry["status"]?.stringValue)
            )
        }
        return steps.isEmpty ? nil : AgentPlan(steps: steps)
    }
}
