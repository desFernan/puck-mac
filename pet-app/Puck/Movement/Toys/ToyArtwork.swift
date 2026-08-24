//
//  ToyArtwork.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Loads a toy's bundled PNG.
//
//  Shared because two places need the same file for different reasons: the
//  toy layer draws it, and the menu bar shows a thumbnail of it (2026-07-30).
//  Two copies of the lookup would be two places to change the day toys stop
//  being `Toys/<name>/<name>.png`.
//

import CoreGraphics
import Foundation
import ImageIO

enum ToyArtwork {
    /// A toy's bundled artwork, or nil if it isn't there. A missing file is a
    /// packaging problem rather than a user-facing error, so callers fall back
    /// (the layer draws a plain circle; the menu shows no icon) instead of
    /// failing.
    static func image(for toy: Toy) -> CGImage? {
        guard
            let url = Bundle.main.url(
                forResource: toy.name,
                withExtension: "png",
                subdirectory: "Toys/\(toy.name)"
            ),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return image
    }
}
