//
//  SettingsComponents.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The settings window's building blocks, in pokoPet's vocabulary -- modeled
//  after that app's menu bar popover.
//
//  What that reference actually is, structurally: one narrow scrolling
//  column on a single translucent panel. Small grey section labels, compact
//  rows, a grid of tinted item tiles, then flat action rows at the bottom.
//  Notably it has NO per-section card -- the panel is the only surface, and
//  everything sits directly on it. That is the opposite of the GlassCard
//  stack this window had, and it is most of why the reference reads as
//  light while ours read as a stack of slabs.
//

import SwiftUI

/// A titled run of controls. The title is the only chrome -- no card, no
/// background (see the file header).
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingSmall) {
            Text(title)
                .font(ClientTheme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)

            VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingMedium) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A label on the left, its control on the right -- the reference's row
/// shape. Controls that are wide by nature (sliders, segmented pickers) use
/// `SettingsStackedRow` instead, since squeezing one into half a 340pt
/// column leaves it unusable.
struct SettingsRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: ClientTheme.Metrics.spacingMedium) {
            Text(label)
                .font(ClientTheme.Typography.sessionTitle)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
    }
}

/// Label above, full-width control below.
struct SettingsStackedRow<Control: View>: View {
    let label: String
    /// Shown right-aligned next to the label -- the live value for a slider
    /// ("1.25x"), the granted/denied state for a permission.
    var value: String?
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingSmall) {
            HStack {
                Text(label)
                    .font(ClientTheme.Typography.sessionTitle)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(ClientTheme.Typography.mono)
                        .foregroundStyle(.secondary)
                }
            }
            control
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
    }
}

/// One item in the toy grid: artwork on a tinted rounded tile, name beneath,
/// a ring when the toy is out. The reference's most distinctive element, and
/// the one place colour survives in this window -- it comes from the item's
/// own artwork (an orange pumpkin, a purple wand), not from an app accent.
struct ToyTile: View {
    let name: String
    let artwork: NSImage?
    let tint: Color
    let isOut: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Group {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFit()
                    } else {
                        // A toy whose PNG didn't ship still gets a tile, so
                        // the grid doesn't silently lose an entry.
                        Image(systemName: "questionmark")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 34)

                Text(name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ClientTheme.Metrics.spacingMedium)
            .background(tint.opacity(isOut ? 0.28 : 0.14), in: ClientTheme.Shapes.card)
            .overlay {
                ClientTheme.Shapes.card
                    .strokeBorder(isOut ? tint.opacity(0.9) : .clear, lineWidth: 1.5)
            }
            .contentShape(ClientTheme.Shapes.card)
        }
        .buttonStyle(.plain)
    }
}

/// The flat, full-width rows the reference ends on (사용 방법 / 설정 /
/// 개발자 후원하기 …): text on the left, chevron on the right, no button
/// chrome at all until hovered.
struct SettingsActionRow: View {
    let label: String
    var systemImage: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: ClientTheme.Metrics.spacingMedium) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                }
                Text(label)
                    .font(ClientTheme.Typography.sessionTitle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall)
            .contentShape(ClientTheme.Shapes.row)
            .background {
                if isHovering {
                    ClientTheme.Shapes.row.fill(.quaternary)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
