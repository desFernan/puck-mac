//
//  StatusDotView.swift
//  Puck
//
//  Design system v2 (2026-08-14) -- the status-color vocabulary
//  needs one shared visual it's rendered as: a small
//  filled circle. `.active`
//  pulses (an ongoing, not-yet-resolved state deserves motion the other
//  three don't -- idle/success/error are all settled states).
//

import SwiftUI

enum DotStatus {
    case idle, active, success, error

    func color(in palette: ClientPalette) -> Color {
        switch self {
        case .idle: return palette.statusIdle
        case .active: return palette.statusActive
        case .success: return palette.statusSuccess
        case .error: return palette.statusError
        }
    }
}

struct StatusDotView: View {
    let status: DotStatus
    let palette: ClientPalette
    var diameter: CGFloat = 6
    /// Whether `.active` animates. False for states that persist indefinitely --
    /// an unsaved file stays unsaved until the user acts, and a dot pulsing for
    /// minutes reads as ongoing activity that isn't happening. See the v3 layout
    /// spec's session-row section for the distinction.
    var pulses: Bool = true
    /// What this dot means here, for a screen reader. A colour is the whole of
    /// what it says, so without one it says nothing at all -- and the meaning
    /// is the caller's: the same amber dot is "unsaved" on a tab and "running"
    /// in a list. nil hides it instead, which is right where the text beside
    /// it already carries the state.
    var label: String?

    @State private var isPulsing = false

    /// A dot that pulses forever is small, but it is also the one thing on
    /// screen that never stops -- exactly what this setting is turned on to
    /// be rid of. The colour still says everything the pulse did.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAnimated: Bool { pulses && !reduceMotion }

    var body: some View {
        Circle()
            .fill(status.color(in: palette))
            .frame(width: diameter, height: diameter)
            .opacity(status == .active && isAnimated && isPulsing ? 0.4 : 1)
            .animation(
                status == .active && isAnimated
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .task(id: status) {
                isPulsing = isAnimated && status == .active
            }
            .accessibilityHidden(label == nil)
            .accessibilityLabel(label ?? "")
    }
}
