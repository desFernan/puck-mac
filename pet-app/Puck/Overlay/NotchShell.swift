//
//  NotchShell.swift
//  Puck
//
//  The shape the notch panel lives in, closed and open.
//
//  One view for both states rather than two, so what happens between them is
//  the same shape changing size: swapping one view for another reads as the
//  notch vanishing and a panel arriving where it was, which is not what a
//  notch opening looks like.
//
//  ## What makes it read as hardware rather than as a black box
//
//  Square across the top where it meets the bezel and rounded below, at both
//  sizes -- that outline is the whole recognisability of a notch, and a panel
//  that rounds all four corners is a popover that happens to be near the top
//  of the screen.
//
//  The corners flare as it opens. A closed notch's radius is about a third of
//  its depth; keeping that ratio on something five times deeper gives it a
//  bowl for a bottom, and keeping the radius fixed makes an open panel look
//  like a slab. It is interpolated between the two.
//
//  It is not flat black. Real black on an OLED-ish dark desktop is a hole;
//  what sells it is that the top edge picks up a little light from the bezel
//  and the body falls away below it, so the thing has a surface. The same
//  reading the island's glass gets in PetTankView, at a tenth the strength.
//

import SwiftUI

struct NotchShell<Content: View>: View {
    let isOpen: Bool
    /// The closed size: the real notch's, or the given one's on a display
    /// that has none.
    let notchSize: CGSize
    @ViewBuilder let content: () -> Content

    /// A closed notch's bottom corners, as a fraction of its depth.
    static var closedCornerFraction: CGFloat { 0.34 }
    /// An open panel's, in points.
    static var openCornerRadius: CGFloat { 22 }

    private var size: CGSize {
        isOpen
            ? CGSize(width: NotchPanelGeometry.openWidth, height: NotchPanelGeometry.openHeight)
            : notchSize
    }

    private var cornerRadius: CGFloat {
        isOpen ? Self.openCornerRadius : notchSize.height * Self.closedCornerFraction
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: 0
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            shape
                .fill(.black)
                // Light along the top edge, falling away over the first
                // few points: a surface catching the bezel rather than a
                // hole cut in the screen.
                .overlay {
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.14), location: 0),
                                .init(color: .white.opacity(0.04), location: 0.06),
                                .init(color: .clear, location: 0.35),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                // The lit rim itself, and the thickness under it. Only worth
                // drawing once it is open -- on a 30pt closed notch the two
                // lines are the whole shape.
                .overlay {
                    shape
                        .strokeBorder(.white.opacity(isOpen ? 0.10 : 0), lineWidth: 1)
                }
                .frame(width: size.width, height: size.height)
                .overlay {
                    // Built in both states so the field keeps what was typed
                    // across an open and shut, and faded rather than removed
                    // so the shape has nothing to resize around.
                    content()
                        .opacity(isOpen ? 1 : 0)
                        .allowsHitTesting(isOpen)
                        .frame(width: NotchPanelGeometry.openWidth, height: NotchPanelGeometry.openHeight)
                        // Clipped to the shape, so nothing inside crosses the
                        // rounded corners on the way out while it closes.
                        .clipShape(shape)
                }
                // Cast onto the desktop below, not around all four sides: the
                // top edge is against the bezel and has nothing to cast onto.
                .shadow(color: .black.opacity(isOpen ? 0.45 : 0), radius: 18, y: 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Settles rather than snaps, and slightly slower opening than a
        // popover would: the shape is growing out of the bezel, and a fast
        // one reads as a flicker at the top of the screen.
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: isOpen)
    }
}
