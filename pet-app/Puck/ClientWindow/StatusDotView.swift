//
//  StatusDotView.swift
//  Puck
//
//  Design system v2 (2026-08-14) -- the status-color vocabulary
//  (docs/decisions.md) needs one shared visual it's rendered as: a small
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

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(status.color(in: palette))
            .frame(width: diameter, height: diameter)
            .opacity(status == .active && pulses && isPulsing ? 0.4 : 1)
            .animation(
                status == .active
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .task(id: status) {
                isPulsing = pulses && status == .active
            }
    }
}
