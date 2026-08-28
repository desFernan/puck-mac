//
//  NotchShell.swift
//  Puck
//
//  The black shape the panel lives in, closed and open.
//
//  One view for both states rather than two, so the change between them is
//  an animation of the same shape rather than one thing being swapped for
//  another: it is the notch that grows, and a swap reads as the notch
//  disappearing and a panel arriving in its place.
//
//  Square across the top where it meets the bezel, rounded at the two bottom
//  corners where it juts into the screen -- the hardware's own outline, kept
//  at both sizes so an opened notch is still recognisably the notch.
//

import SwiftUI

struct NotchShell<Content: View>: View {
    let isOpen: Bool
    /// The closed size, which is the real notch's -- or the given one's on a
    /// display that has no real notch.
    let notchSize: CGSize
    @ViewBuilder let content: () -> Content

    /// How round the bottom corners are when closed and when open. A real
    /// housing's are about a third of its depth; an open panel is much
    /// deeper, and keeping the fraction would give it a bowl for a bottom.
    static var closedCornerFraction: CGFloat { 0.34 }
    static var openCornerRadius: CGFloat { 20 }

    var body: some View {
        VStack {
            shape
                .frame(
                    width: isOpen ? NotchPanelGeometry.openWidth : notchSize.width,
                    height: isOpen ? NotchPanelGeometry.openHeight : notchSize.height
                )
                .overlay {
                    // Built either way so the fields inside keep their state
                    // across an open and shut, and hidden rather than removed
                    // so the shape has nothing to resize around.
                    content()
                        .opacity(isOpen ? 1 : 0)
                        .allowsHitTesting(isOpen)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isOpen)
    }

    private var shape: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: isOpen ? Self.openCornerRadius : notchSize.height * Self.closedCornerFraction,
            bottomTrailingRadius: isOpen ? Self.openCornerRadius : notchSize.height * Self.closedCornerFraction,
            topTrailingRadius: 0
        )
        .fill(.black)
    }
}
