//
//  TankTone.swift
//  Puck
//
//  The colours a folded island is drawn in, taken from the picture the open
//  one is filled with.
//
//  The band is drawn rather than photographed -- a picture is a scene and a
//  band is too short to hold one -- but the two are the same island a second
//  apart, so a band in colours of its own would be a different place. And the
//  picture is replaceable: anyone can drop their own seabed.png into the
//  customisation folder, and a band hard-coded to the shipped one would go
//  wrong the moment they did. So the colours are read out of whatever picture
//  is actually there.
//
//  The reading is split in two: a thin AppKit part that shrinks the picture to
//  a handful of pixels, and the pure part that turns those into a tone. Only
//  the second is worth testing, and it is the one with the decisions in it.
//

import AppKit
import SwiftUI

/// One averaged sample of the picture.
struct TankSample: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// The same colour with more light on it -- toward white by `amount`.
    func lightened(by amount: Double) -> TankSample {
        TankSample(
            red: red + (1 - red) * amount,
            green: green + (1 - green) * amount,
            blue: blue + (1 - blue) * amount
        )
    }

    /// And with less -- toward black.
    func darkened(by amount: Double) -> TankSample {
        TankSample(red: red * (1 - amount), green: green * (1 - amount), blue: blue * (1 - amount))
    }
}

/// What the band needs to know about the picture.
struct TankTone: Equatable {
    /// Down the water: lit surface first, unlit depth last.
    var depth: [TankSample]
    /// Across it, one per column of the picture's water. What keeps the band
    /// from being one flat colour the width of a window.
    var currents: [TankSample]

    /// For when there is no picture at all -- the shipped one's own tone,
    /// measured once and written down, so an island with nothing in it is
    /// still the same island.
    static let fallback = TankTone(
        depth: [
            TankSample(red: 0.42, green: 0.82, blue: 0.95),
            TankSample(red: 0.22, green: 0.61, blue: 0.88),
            TankSample(red: 0.10, green: 0.38, blue: 0.70),
        ],
        currents: [
            TankSample(red: 0.30, green: 0.70, blue: 0.92),
            TankSample(red: 0.24, green: 0.64, blue: 0.90),
            TankSample(red: 0.34, green: 0.74, blue: 0.93),
            TankSample(red: 0.26, green: 0.66, blue: 0.91),
        ]
    )
}

enum TankToneReader {
    /// How many samples across and down the picture is reduced to.
    ///
    /// Small on purpose: this is a tone, not a thumbnail. Enough columns that
    /// the band varies along its length, enough rows to tell the lit water
    /// from the dark water.
    static let columns = 12
    static let rows = 10

    /// How far down the picture is still water.
    ///
    /// The band shows water, so the seabed at the bottom -- the sand and the
    /// stones, which in this picture are a different colour family
    /// altogether -- must not be averaged into it. Half is the safe answer
    /// for a scene laid out like the shipped one and a harmless one for a
    /// picture that is water all the way down.
    static let waterRows = 5

    /// The tone of a grid of samples, `rows` rows of `columns` each.
    ///
    /// Returns the fallback for anything it cannot read a tone out of, rather
    /// than a black band: a picture that samples to nothing is a picture
    /// somebody will replace, and until they do the island should look like
    /// itself.
    static func tone(fromGrid grid: [[TankSample]]) -> TankTone {
        let water = grid.prefix(waterRows).filter { !$0.isEmpty }
        guard !water.isEmpty, let columns = water.first?.count, columns > 0 else { return .fallback }
        // One colour, lit at the top and dark at the bottom, rather than
        // three rows of the picture. A drawn scene's water is very nearly the
        // same blue all the way down -- three samples of it come back within
        // a hundredth of each other -- so a gradient between them is a flat
        // bar. The depth is put there rather than found, and the colour it is
        // put on comes from the picture, which is what makes the two match.
        let base = average(water.flatMap { $0 })
        let depth = [base.lightened(by: surfaceLight), base, base.darkened(by: depthShade)]
        let currents = (0..<columns).map { column in
            average(water.map { $0[column] })
        }
        return TankTone(depth: depth, currents: currents)
    }

    /// How much light is on the band's surface, and how little reaches its
    /// floor. Enough that the band has a top and a bottom; not so much that
    /// it stops being the colour the picture is.
    static let surfaceLight: Double = 0.30
    static let depthShade: Double = 0.34

    static func average(_ samples: [TankSample]) -> TankSample {
        guard !samples.isEmpty else { return TankSample(red: 0, green: 0, blue: 0) }
        let count = Double(samples.count)
        return TankSample(
            red: samples.reduce(0) { $0 + $1.red } / count,
            green: samples.reduce(0) { $0 + $1.green } / count,
            blue: samples.reduce(0) { $0 + $1.blue } / count
        )
    }

    /// The picture redrawn into a `columns` x `rows` bitmap, which is what
    /// averaging a region actually is -- the interpolation does the summing,
    /// in the graphics library rather than in a loop over four million
    /// pixels.
    static func grid(of image: NSImage) -> [[TankSample]]? {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: columns * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let pixels = context.data
        else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: columns, height: rows))

        let bytes = pixels.bindMemory(to: UInt8.self, capacity: columns * rows * 4)
        // Row 0 is the picture's top -- which is what "the lit surface"
        // means -- because drawing a CGImage into a context flips it on the
        // way in, and the two flips cancel. Reversing here as well put the
        // seabed where the water goes and turned the band beige.
        return (0..<rows).map { row in
            (0..<columns).map { column in
                let offset = (row * columns + column) * 4
                return TankSample(
                    red: Double(bytes[offset]) / 255,
                    green: Double(bytes[offset + 1]) / 255,
                    blue: Double(bytes[offset + 2]) / 255
                )
            }
        }
    }

    /// The tone of the picture the island is actually filled with.
    ///
    /// Held rather than recomputed: the band is redrawn on every frame a pet
    /// walks along it, and this reads a bitmap. A picture dropped into the
    /// customisation folder is picked up at the next launch, the same as the
    /// picture itself.
    static func current() -> TankTone {
        held() ?? .fallback
    }

    private static let held = HeldOnce<TankTone> {
        TankArtwork.image().flatMap(grid(of:)).map(tone(fromGrid:)) ?? .fallback
    }
}
