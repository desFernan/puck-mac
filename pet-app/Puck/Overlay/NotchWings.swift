//
//  NotchWings.swift
//  Puck
//
//  What the notch shows while it is shut.
//
//  A thumbnail on one side and a few moving bars on the other, either side of
//  the hardware. Nothing to read and nothing to aim at -- it answers "is
//  something playing, and what" at a glance, and the panel behind it answers
//  everything else.
//
//  It is drawn beside the notch rather than under it because the notch is
//  where the camera is: anything put there on a real MacBook is behind the
//  housing and invisible. The two sides are the only space that is both next
//  to the notch and actually on screen.
//

import SwiftUI

struct NotchWings: View {
    let artwork: NSImage?
    let isPlaying: Bool
    /// The notch itself, which nothing may be drawn over.
    let notchSize: CGSize

    /// The thumbnail's side. Close to the full depth of the notch, leaving
    /// only enough above and below to keep it off the edges: a cover you have
    /// to lean in to recognise is not doing the job the wing exists for.
    var coverSide: CGFloat { max(12, min(24, notchSize.height - 6)) }

    /// The bars are shorter than the cover is tall. They read as a level
    /// meter, and a meter that fills its whole space has nowhere left to go.
    private var barsHeight: CGFloat { coverSide * 0.62 }

    var body: some View {
        HStack(spacing: 0) {
            cover
            // The hardware. Left empty on purpose.
            Spacer(minLength: notchSize.width)
            NotchEqualizer(isPlaying: isPlaying)
                .frame(width: NotchEqualizer.width, height: barsHeight)
        }
        .padding(.leading, (NotchPanelGeometry.wingWidth - coverSide) / 2)
        .padding(.trailing, (NotchPanelGeometry.wingWidth - NotchEqualizer.width) / 2)
    }

    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return shape
            .fill(NotchStyle.surface)
            .frame(width: coverSide, height: coverSide)
            .overlay {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        // Sized before clipped: filling a square with a
                        // picture that is not square makes the image bigger
                        // than the square, and a clip on the image follows
                        // the image.
                        .frame(width: coverSide, height: coverSide)
                        .clipShape(shape)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: coverSide * 0.5, weight: .medium))
                        .foregroundStyle(NotchStyle.subtleForeground)
                }
            }
    }
}

/// Three bars that rise and fall while something is playing.
///
/// Not a spectrum: reading the actual audio would mean tapping the output
/// device, which is a permission prompt and a real cost for decoration. These
/// just move, which is all the thing has to say -- that sound is coming out.
///
/// Driven from the clock rather than from a repeating animation on a toggled
/// state. The repeating kind stopped the moment the panel was opened: opening
/// replaces the whole hosted view, and a repetition attached to a value that
/// did not change does not survive being rebuilt -- so the bars froze
/// mid-stride and stayed that way. A height that is a function of the time
/// has nothing to lose when the view is made again.
///
/// The timeline is paused while nothing is playing, so a silent machine is
/// not redrawing its menu bar fifteen times a second.
struct NotchEqualizer: View {
    let isPlaying: Bool

    /// Thin lines rather than blocks. At this size a bar wide enough to have
    /// a shape of its own stops reading as a level and starts reading as a
    /// row of buttons.
    static let barWidth: CGFloat = 2
    static let barGap: CGFloat = 2.5
    static var width: CGFloat { barWidth * 3 + barGap * 2 }

    /// Different lengths, speeds and starting points, or three bars moving as
    /// one read as a single block flexing.
    static let bars: [Bar] = [
        Bar(low: 0.30, high: 1.00, period: 1.30, phase: 0.0),
        Bar(low: 0.55, high: 0.80, period: 0.90, phase: 0.6),
        Bar(low: 0.22, high: 0.90, period: 1.60, phase: 1.9),
    ]

    struct Bar {
        let low: CGFloat
        let high: CGFloat
        let period: Double
        let phase: Double

        /// Where this bar stands at `time`, as a fraction of the full height.
        ///
        /// A sine rather than a straight up and down: a level meter that
        /// changes direction abruptly reads as a counter ticking.
        func height(at time: TimeInterval) -> CGFloat {
            let turn = sin(time / period * 2 * .pi + phase)
            return low + (high - low) * CGFloat(0.5 + 0.5 * turn)
        }
    }

    /// Fifteen a second. Smooth enough for something two points wide, and a
    /// fifth of the redraws a full frame rate would cost for decoration.
    static let framesPerSecond: Double = 15

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / Self.framesPerSecond, paused: !isPlaying)) { context in
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: Self.barGap) {
                    ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, bar in
                        Capsule()
                            .fill(NotchStyle.foreground.opacity(0.85))
                            .frame(
                                width: Self.barWidth,
                                height: geometry.size.height * height(bar, at: context.date)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func height(_ bar: Bar, at date: Date) -> CGFloat {
        // Paused, they settle at their low mark rather than vanishing: three
        // stubs still read as a stopped meter, where nothing reads as a gap
        // in the shape.
        guard isPlaying else { return bar.low }
        return bar.height(at: date.timeIntervalSinceReferenceDate)
    }
}
