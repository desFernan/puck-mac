//
//  AgentEffort.swift
//  Puck
//
//  How much thinking the user wants per turn, set from the chat with
//  `/effort` (or `/fast`, which is the low end by another name).
//
//  Carried in the prompt rather than as an API parameter. The provider people
//  actually run here is a coding CLI driven over ACP, and ACP has no field
//  for this -- but the CLI reads its instructions, so a line of them is a
//  lever that works today. OpenAI's own `reasoning_effort` is a different
//  mechanism for a different provider, and only some models accept it.
//

import Foundation

enum AgentEffort: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    static let environmentVariable = "AGENT_EFFORT"

    /// What a turn does when nothing has been chosen: no instruction at all,
    /// leaving the agent's own judgement alone.
    static let fallback: AgentEffort = .medium

    static func resolved(fromRawValue raw: String?) -> AgentEffort {
        raw.flatMap { AgentEffort(rawValue: $0.lowercased()) } ?? fallback
    }

    var displayName: String {
        switch self {
        case .low: return Strings.text(.effortLow)
        case .medium: return Strings.text(.effortMedium)
        case .high: return Strings.text(.effortHigh)
        }
    }

    /// The line added to the agent's instructions, or nil for the default --
    /// saying "think normally" is noise, and the absence of an instruction is
    /// what the agent is already tuned for.
    var promptLine: String? {
        switch self {
        case .medium: return nil
        case .low:
            return "Effort: low. Answer directly and briefly. Prefer the shortest path to a "
                + "correct answer; do not explore alternatives or explain your reasoning unless asked."
        case .high:
            return "Effort: high. Take the time to be thorough: check the code rather than "
                + "recalling it, consider the cases that could break, and say what you verified."
        }
    }
}
