//
//  VerticalSlider.swift
//  Puck
//
//  An upright slider, which SwiftUI does not have on macOS.
//
//  Three attempts. A SwiftUI `Slider` turned on its side with
//  `rotationEffect` drew correctly and took no drags at all: the control
//  underneath is an AppKit one, and it goes on receiving mouse events in its
//  own unrotated space whatever the layer is doing. AppKit's own vertical
//  NSSlider took the drags -- and drew AppKit's groove and knob, which on the
//  island is a solid bar laid across a picture.
//
//  So it is drawn here. The gesture is SwiftUI's own, which has none of the
//  rotation problem: nothing is rotated, the geometry is just read upside
//  down, because up is more and screen coordinates run the other way.
//

import SwiftUI

struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// The colour of the knob and the filled part of the track. The track
    /// itself is always a hint of the same colour -- see `body`.
    var tint: Color = .white

    /// How wide the track is drawn, inside whatever width the caller gives.
    /// The rest of that width is grab area: a 4pt target is a pixel hunt.
    private static let trackWidth: CGFloat = 4
    private static let knobDiameter: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.height - Self.knobDiameter, 1)
            let position = Self.fraction(of: value, in: range)
            ZStack(alignment: .top) {
                // Transparent, so the island's own background is what shows
                // through it: this is a control drawn on glass, not a bar
                // sitting on top of the picture.
                Capsule()
                    .fill(tint.opacity(0.22))
                    .frame(width: Self.trackWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Capsule()
                    .fill(tint.opacity(0.45))
                    .frame(width: Self.trackWidth, height: travel * position + Self.knobDiameter / 2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: travel * (1 - position) + Self.knobDiameter / 2)
                Circle()
                    .fill(tint)
                    .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(y: travel * (1 - position))
                    .frame(maxWidth: .infinity)
            }
            .contentShape(.rect)
            // minimumDistance 0, so a click anywhere on the bar jumps there
            // rather than needing a drag to start.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value = Self.value(
                            atY: drag.location.y,
                            height: proxy.size.height,
                            knob: Self.knobDiameter,
                            in: range
                        )
                    }
            )
        }
        .frame(width: Self.knobDiameter + 8)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(value))"))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    /// Where `value` sits in `range`, 0 at the bottom and 1 at the top.
    /// Guarded against an empty range, which would divide by zero.
    static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// The value a point on the track means. `y` runs down the screen and the
    /// scale runs up it, and the knob's own height is not travel -- its
    /// centre only reaches from half a knob below the top to half a knob
    /// above the bottom.
    static func value(atY y: CGFloat, height: CGFloat, knob: CGFloat, in range: ClosedRange<Double>) -> Double {
        let travel = max(height - knob, 1)
        let fromTop = min(max(y - knob / 2, 0), travel) / travel
        return range.lowerBound + (1 - Double(fromTop)) * (range.upperBound - range.lowerBound)
    }
}
