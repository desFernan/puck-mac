//
//  SidebarRowBackground.swift
//  Puck
//
//  The fill under a sidebar row, and the tracking area that decides when the pointer is over one.
//
//  Split out of ChatSidebarView, which had grown to seven types and seven
//  hundred lines: the list, the rows it holds, the fill under them, and a
//  sheet listing every workspace are four separate things.
//

import AppKit
import SwiftUI

/// Reports the pointer entering and leaving, from AppKit rather than from
/// SwiftUI's `.onHover`.
///
/// `.onHover` never fired for the rows at the top of this list. They sit
/// inside a `List`, which is an NSTableView underneath, and the row views it
/// manages do not hand plain SwiftUI content the mouse-moved events -- the
/// chats appeared to work only because a selectable row gets AppKit's own
/// hover highlight for free, and the rows with no selection tag got nothing
/// at all. A tracking area is what AppKit answers this question with, so
/// that is what this asks with.
struct HoverReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tracking: NSTrackingArea?

        /// Never the answer to a click. This view sits behind the row's own
        /// content, and an NSView that accepts hits there would swallow every
        /// press meant for the button in front of it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            // .activeAlways rather than .activeInKeyWindow: the pointer moves
            // over this list on the way to clicking it, which is exactly the
            // moment the window is not yet key.
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            tracking = area
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
    }
}

/// The fill under a sidebar row: the selection's, the pointer's, or none.
///
/// Every row here is something you click, and until now only the selected one
/// showed it. A list that does not react to the pointer reads as a picture of
/// a list -- and with rows this close together, the highlight is also how you
/// tell which one you are about to hit.
struct SidebarRowBackground: ViewModifier {
    @Environment(\.clientPalette) private var palette

    let isSelected: Bool
    @State private var isHovering = false

    /// Rounder than a list row's usual corner: these fills run the whole
    /// width of the column, and at that length a 4pt corner is a rectangle.
    private static let cornerRadius: CGFloat = 9

    /// How far the fill runs past the row's own box on each side. `List`
    /// keeps a margin of its own around every row that nothing can set to
    /// zero, and inside it the fill read as a small tablet under the name
    /// rather than as the row being lit. A background is allowed to overflow.
    private static let overhang: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(fill)
                    .padding(.horizontal, -Self.overhang)
            )
            // An overlay, not a background: a row that is never selected has
            // a `.clear` fill from the first frame, and a tracking view
            // nested inside that never came up -- which is why the three rows
            // at the top of this list, the only ones with no selected state,
            // never lit at all. It refuses hit tests, so the button under it
            // still takes the click.
            .overlay(HoverReporter { isHovering = $0 }.padding(.horizontal, -Self.overhang))
            .contentShape(.rect)
            // Animated, because the pointer crosses several rows on the way
            // to one and a hard flicker down the list is noise.
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    /// Darker than the panel it sits on rather than lighter. A pale fill on
    /// a near-black sidebar draws more attention than the name it is behind,
    /// which is backwards -- the highlight is there to say "this one", not to
    /// be the brightest thing in the column.
    private var fill: Color {
        if isSelected { return palette.surface.opacity(0.85) }
        return isHovering ? palette.surface.opacity(0.55) : .clear
    }
}

extension View {
    func sidebarRowBackground(isSelected: Bool = false) -> some View {
        modifier(SidebarRowBackground(isSelected: isSelected))
    }
}

