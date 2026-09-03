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
//  Closed, it is not flat black. Real black on an OLED-ish dark desktop is a
//  hole; what sells a closed notch is that its top edge picks up a little
//  light from the bezel and the body falls away below it, so the thing has a
//  surface. The same reading the island's glass gets in PetTankView, at a
//  tenth the strength.
//
//  Open, that light comes off. It is there to make a small dark shape read as
//  part of the machine, and on a panel five times the depth the same gradient
//  is just a bright streak across the top of a window -- the very thing that
//  makes a panel look like a box drawn on the screen rather than something
//  the screen opened up.
//

import SwiftUI

struct NotchShell<Content: View>: View {
    let isOpen: Bool
    /// The closed size: the real notch's, or the given one's on a display
    /// that has none. Wider than the hardware while the wings are out -- see
    /// NotchPanelGeometry.shutRect.
    let notchSize: CGSize
    /// What is drawn while it is shut, if anything.
    let shut: AnyView?
    @ViewBuilder let content: () -> Content

    init(
        isOpen: Bool,
        notchSize: CGSize,
        shut: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isOpen = isOpen
        self.notchSize = notchSize
        self.shut = shut
        self.content = content
    }

    /// A closed notch's bottom corners, as a fraction of its depth.
    static var closedCornerFraction: CGFloat { 0.34 }

    /// How far the content is scaled down once the panel is shut.
    ///
    /// The same ratio the shell's own height collapses by, so the two read
    /// as one thing shrinking into the bezel. Left to itself the content
    /// kept its size and slid upward out of the closing shape, which looked
    /// like two animations disagreeing about what was happening.
    static func contentScale(notchHeight: CGFloat) -> CGFloat {
        max(0, min(1, notchHeight / NotchPanelGeometry.openHeight(notchDepth: notchHeight)))
    }
    /// An open panel's, in points.
    static var openCornerRadius: CGFloat { 22 }

    /// How strongly the top edge catches the bezel's light.
    ///
    /// Only while closed. Scaled off as it opens rather than switched, so the
    /// light leaves with the shape it belonged to instead of blinking out
    /// part way through.
    static func topLightOpacity(isOpen: Bool) -> CGFloat { isOpen ? 0 : 1 }

    private var size: CGSize {
        isOpen
            ? CGSize(width: NotchPanelGeometry.openWidth, height: NotchPanelGeometry.openHeight(notchDepth: notchSize.height))
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
                    .opacity(Self.topLightOpacity(isOpen: isOpen))
                }
                .overlay {
                    // The rim, which stays: it is what gives the open panel
                    // an edge rather than letting it bleed into the desktop.
                    // Only worth drawing once open -- on a 30pt closed notch
                    // the two lines are the whole shape.
                    shape
                        .strokeBorder(isOpen ? NotchStyle.border : .clear, lineWidth: 1)
                }
                .frame(width: size.width, height: size.height)
                // Hung from the top edge, which is the one that does not
                // move: the shape closes upward into the bezel, so anything
                // centred in it drifts up as it shrinks.
                .overlay(alignment: .top) {
                    // Built in both states so the field keeps what was typed
                    // across an open and shut, and faded rather than removed
                    // so the shape has nothing to resize around.
                    content()
                        .frame(
                            width: NotchPanelGeometry.openWidth,
                            height: NotchPanelGeometry.openHeight(notchDepth: notchSize.height)
                        )
                        .scaleEffect(
                            isOpen ? 1 : Self.contentScale(notchHeight: notchSize.height),
                            anchor: .top
                        )
                        .opacity(isOpen ? 1 : 0)
                        .allowsHitTesting(isOpen)
                }
                // The shut state's own contents, faded the other way. Not
                // hit-tested: the whole shut shape is one target, and a
                // thumbnail that swallowed the click would be a button that
                // does nothing.
                .overlay {
                    if let shut {
                        shut
                            .frame(width: size.width, height: size.height)
                            .opacity(isOpen ? 0 : 1)
                            .allowsHitTesting(false)
                    }
                }
                // Outside the overlay, so the clip follows the shape at the
                // size it is now rather than the size it will be: clipped
                // inside, the content spilled past the shell all the way
                // through the close.
                .clipShape(shape)
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
