//
//  AlphaHitMask.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Which parts of an image are actually drawn, as a bitmask you can hit-test
//  against.
//
//  Every asset here is background-removed art, so the picture is a silhouette
//  floating in a transparent canvas and its bounding box is a poor stand-in
//  for it. A rectangle
//  can only ever be too big -- around the pet's hair and skirt, or around a
//  wand that is mostly empty space either side of a thin stick -- so clicks
//  land on it in places where nothing is drawn.
//
//  F1 always listed per-pixel hit testing as the refinement after the AABB
//  version; this is it.
//
//  Sampled coarsely on purpose. The mask exists to answer "did the user mean
//  to click this?", where being a pixel out is meaningless and the memory and
//  build cost of a full-resolution copy are not.
//

import CoreGraphics
import Foundation

struct AlphaHitMask: Equatable {
    /// Longest side of the sampled mask. At 64 a 1200px sprite rendered ~130pt
    /// tall gives each mask cell about 2pt on screen -- finer than anyone can
    /// aim, and 4KB instead of 1.4MB.
    static let resolution = 64

    /// Alpha at or below this counts as not drawn. Matches OpaquePixelBounds:
    /// anti-aliased edges fade over several pixels, and treating the faintest
    /// of them as solid puts the edge outside anything a person can see.
    static let alphaThreshold: UInt8 = 10

    let width: Int
    let height: Int
    /// Row-major, top row first -- the same layout CGBitmapContext gives back,
    /// and the same top-left origin the rest of the app uses.
    private let drawn: [Bool]

    /// Nil for an image with nothing drawn in it at all: callers fall back to
    /// their bounding box rather than to a thing that can never be clicked.
    init?(image: CGImage) {
        guard image.width > 0, image.height > 0 else { return nil }

        let downscale = min(1, CGFloat(Self.resolution) / CGFloat(max(image.width, image.height)))
        let width = max(Int((CGFloat(image.width) * downscale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * downscale).rounded()), 1)

        var alpha = [UInt8](repeating: 0, count: width * height)
        let drew = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        let drawn = alpha.map { $0 > Self.alphaThreshold }
        guard drawn.contains(true) else { return nil }

        self.width = width
        self.height = height
        self.drawn = drawn
    }

    /// - Parameters:
    ///   - point: position within the image, 0...1 on each axis, top-left origin.
    ///   - tolerance: how far away, in the same 0...1 units, still counts as a
    ///     hit. Grabbing a 130pt character by its exact silhouette is
    ///     needlessly fiddly, so callers dilate the mask a little
    ///     rather than demanding pixel precision.
    func isDrawn(atUnit point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        guard tolerance > 0 else { return isDrawn(atCell: cell(for: point)) }

        let radiusX = max(Int((tolerance * CGFloat(width)).rounded()), 0)
        let radiusY = max(Int((tolerance * CGFloat(height)).rounded()), 0)
        let centre = cell(for: point)

        // A box rather than a circle: the difference is well under one cell at
        // these radii, and this stays branch-free and obvious.
        for dy in -radiusY...radiusY {
            for dx in -radiusX...radiusX where isDrawn(atCell: (centre.x + dx, centre.y + dy)) {
                return true
            }
        }
        return false
    }

    private func cell(for point: CGPoint) -> (x: Int, y: Int) {
        (Int((point.x * CGFloat(width)).rounded(.down)), Int((point.y * CGFloat(height)).rounded(.down)))
    }

    private func isDrawn(atCell cell: (x: Int, y: Int)) -> Bool {
        guard cell.x >= 0, cell.x < width, cell.y >= 0, cell.y < height else { return false }
        return drawn[cell.y * width + cell.x]
    }
}
