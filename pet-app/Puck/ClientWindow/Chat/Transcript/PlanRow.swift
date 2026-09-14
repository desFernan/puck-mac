//
//  PlanRow.swift
//  Puck
//
//  The agent's plan, in the transcript, ticking itself off.
//
//  A long run used to be a spinner over a growing pile of tool rows: the only
//  way to tell step two of six from lost was to read tool names and guess.
//  The agent has been sending its plan the whole time -- see AgentPlan -- and
//  this is where it lands.
//
//  One row that rewrites itself rather than one per update, and collapsed to
//  the step being worked on once there are more than a few: what somebody
//  glancing at a running turn wants is "which part is it on", and the whole
//  list is one click away for when they want the rest.
//

import SwiftUI

struct PlanRow: View {
    @ObservedObject private var localization = Localization.shared
    let plan: AgentPlan

    /// Longer than this and the list opens folded. Chosen so an ordinary
    /// three-or-four-step plan is simply visible -- folding something you can
    /// read at a glance is a click charged for nothing.
    static let foldBeyond = 5

    @State private var isExpanded: Bool?

    private var showsEveryStep: Bool {
        isExpanded ?? (plan.steps.count <= Self.foldBeyond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { isExpanded = !showsEveryStep } label: { header }
                .buttonStyle(.plain)
            if showsEveryStep {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { _, step in
                        line(for: step)
                    }
                }
            } else if let current = plan.currentStep {
                line(for: current)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: showsEveryStep ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Image(systemName: "checklist")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text(.planHeader))
                .font(.system(size: 11, weight: .medium))
            Text(progress)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func line(for step: AgentPlanStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol(for: step.status))
                .font(.system(size: 10))
                .foregroundStyle(step.status == .completed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Text(step.text)
                .font(.system(size: 11))
                // Struck through and dimmed once done: a finished step is
                // still worth having on screen -- it is what the agent has
                // already covered -- but it is not what anybody is reading
                // the list for.
                .strikethrough(step.status == .completed, color: .secondary)
                .foregroundStyle(foreground(for: step.status))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func symbol(for status: AgentPlanStep.Status) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private func foreground(for status: AgentPlanStep.Status) -> AnyShapeStyle {
        switch status {
        case .completed: return AnyShapeStyle(.tertiary)
        case .pending: return AnyShapeStyle(.secondary)
        case .inProgress: return AnyShapeStyle(.primary)
        }
    }

    private var progress: String {
        "\(plan.completedCount)/\(plan.steps.count)"
    }

    /// One sentence rather than a list of ticks: read aloud, "계획 2/6, 지금:
    /// 테스트 고치기" is the whole of what the row says.
    private var accessibilityLabel: String {
        let current = plan.currentStep.map { ", \($0.text)" } ?? ""
        return "\(text(.planHeader)) \(progress)\(current)"
    }

    private func text(_ key: L10nKey) -> String {
        Strings.text(key, language: localization.language)
    }
}
