//
//  AgentPlan.swift
//  Puck
//
//  What the agent says it is going to do, and how far through it is.
//
//  A coding CLI asked for anything real answers with a plan first and then
//  works through it, reporting each step as it starts and finishes. Puck
//  threw all of that away -- `AcpEventMapping` dropped `plan` updates on the
//  floor -- so a ten-minute run showed a spinner and a growing pile of tool
//  rows, and the only way to know whether it was on step two of six or lost
//  was to read the tool names and guess.
//
//  The plan is the one thing in the stream that answers "how much of this is
//  left", which is the question anybody watching a long run is actually
//  asking.
//
//  Kept as a list rather than merged into the transcript row by row: the
//  agent rewrites the whole plan on every update -- steps get added, split and
//  reworded as it learns what the work is -- so the last one it sent is the
//  plan, and an append-only log of them would be six copies of the same list.
//
//  Down here with the wire rather than up with the agent, because it crosses
//  bridge.sock and is stored with the transcript, and both of those layers sit
//  below the one that produces it. Reading an ACP notification into one is
//  AcpPlanReading's job, up where knowing what ACP is belongs.
//

import Foundation

/// One step of the agent's own plan.
struct AgentPlanStep: Equatable, Codable {
    /// How far along this step is. Unknown names decode as `.pending` rather
    /// than failing the whole update: a newer agent inventing a fourth state
    /// should cost the checklist one wrong tick, not the plan.
    enum Status: String, Codable {
        case pending
        case inProgress = "in_progress"
        case completed

        static func parsed(_ raw: String?) -> Status {
            guard let raw, let status = Status(rawValue: raw) else { return .pending }
            return status
        }
    }

    let text: String
    let status: Status
}

/// The plan as it stands.
struct AgentPlan: Equatable, Codable {
    let steps: [AgentPlanStep]

    var isEmpty: Bool { steps.isEmpty }

    /// How many steps are finished, for the one-line summary a collapsed plan
    /// shows.
    var completedCount: Int { steps.filter { $0.status == .completed }.count }

    /// The step being worked on, which is what the pet and a collapsed row
    /// have room to say.
    var currentStep: AgentPlanStep? {
        steps.first { $0.status == .inProgress } ?? steps.first { $0.status == .pending }
    }
}
