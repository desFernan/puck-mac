//
//  OpaquePixelBounds.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Finds the tight bounding box of an image's non-transparent pixels.
//
//  Avatar PNGs are authored with the character floating in a transparent
//  canvas, and how much padding surrounds it is entirely up to whoever drew
//  it. Treating the whole canvas as the character makes the pet stop short of
//  a screen edge by however much empty space its artist happened to leave.
//
//  Measured once per image, when SpriteAvatar swaps it onto the layer, and
//  cached by the caller -- never per frame. Measured at a reduced resolution
//  (see measurementResolution) because that cost lands inside a frame.
//

import CoreGraphics
import Foundation

enum OpaquePixelBounds {
    /// Pixels at or below this alpha count as transparent. Not zero: PNG
    /// anti-aliasing leaves a fringe of nearly-invisible pixels around the
    /// artwork, and including them puts the "edge" a few pixels outside
    /// anything a person can actually see.
    static let alphaThreshold: UInt8 = 10

    /// Longest side of the buffer the alpha is measured in. The rectangle is
    /// only ever used to clamp and bounce the pet against screen edges at a
    /// rendered size of roughly 130pt, so measuring a 1200px source at full
    /// resolution buys precision nobody can see and costs ~20x the work --
    /// both the redraw (which forces a second full decode of the PNG) and the
    /// scan scale with the pixel count. At 256 the error is well under a
    /// rendered point.
    static let measurementResolution = 256

    /// The bounding box of `image`'s visible pixels, in image pixel
    /// coordinates with a top-left origin. Nil if the image is fully
    /// transparent -- callers fall back to the full canvas rather than to an
    /// empty rect, since a pet with a zero-width outline can never be inside
    /// the screen at all.
    static func of(_ image: CGImage) -> CGRect? {
        guard image.width > 0, image.height > 0 else { return nil }

        // Measured small, then scaled back up to the source's coordinates so
        // callers still get a rect in image pixels.
        let downscale = min(
            1,
            CGFloat(measurementResolution) / CGFloat(max(image.width, image.height))
        )
        let width = max(Int((CGFloat(image.width) * downscale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * downscale).rounded()), 1)

        // Redrawn into a known 8-bit alpha-last layout: CGImage can be any of
        // a dozen pixel formats, and reading its raw data would mean handling
        // all of them.
        var alpha = [UInt8](repeating: 0, count: width * height)
        let ok = alpha.withUnsafeMutableBytes { buffer -> Bool in
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
        guard ok else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            // Rows are visited in order, so the first row with any opaque
            // pixel is minY and the last one is maxY -- no need to re-test
            // either on every pixel.
            var rowMinX = width, rowMaxX = -1
            for x in 0..<width where alpha[row + x] > alphaThreshold {
                if x < rowMinX { rowMinX = x }
                rowMaxX = x
            }
            guard rowMaxX >= 0 else { continue }

            if y < minY { minY = y }
            maxY = y
            if rowMinX < minX { minX = rowMinX }
            if rowMaxX > maxX { maxX = rowMaxX }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // No Y flip: a CGBitmapContext's *coordinate* origin is bottom-left,
        // but its backing buffer is laid out top row first, so scanning the
        // buffer already yields the top-left origin the rest of the app uses.
        // Flipping here (as this did originally) mirrors the outline
        // vertically -- invisible on artwork with even padding above and
        // below, wrong the moment it isn't.
        //
        // Scaled back to source pixels, rounded outward on every side so the
        // measured box never cuts into artwork that the downscale merged into
        // a partially-covered edge pixel, and per axis because the two scales
        // differ slightly once the downscaled size is rounded to whole pixels.
        let scaleX = CGFloat(image.width) / CGFloat(width)
        let scaleY = CGFloat(image.height) / CGFloat(height)
        return CGRect(
            x: (CGFloat(minX) * scaleX).rounded(.down),
            y: (CGFloat(minY) * scaleY).rounded(.down),
            width: (CGFloat(maxX - minX + 1) * scaleX).rounded(.up),
            height: (CGFloat(maxY - minY + 1) * scaleY).rounded(.up)
        )
    }
}
