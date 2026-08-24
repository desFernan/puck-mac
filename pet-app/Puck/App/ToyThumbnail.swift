//
//  ToyThumbnail.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Menu-bar icons for the toy list, shown alongside each toy's name.
//
//  The one thing that actually needs care here is proportions. The wand's art
//  is 310x804; fitted into a square box it renders as a squashed smear, which
//  is the same trap ToyCatalogue's header documents for the toy LAYER. So the
//  bounding side is a maximum for both axes, never an assignment to both.
//

import AppKit
import CoreGraphics

enum ToyThumbnail {
    /// Menu-item icon size. Matches what macOS draws menu images at, so
    /// AppKit doesn't resample it a second time.
    static let defaultSide: CGFloat = 18

    /// The largest size fitting `boundingSide` on both axes while keeping the
    /// artwork's own aspect ratio.
    static func fittedSize(imagePixelSize: CGSize, boundingSide: CGFloat) -> CGSize {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return .zero }
        let fit = min(boundingSide / imagePixelSize.width, boundingSide / imagePixelSize.height)
        return CGSize(width: imagePixelSize.width * fit, height: imagePixelSize.height * fit)
    }

    /// A toy's artwork as a menu-item image, or nil when the toy has no
    /// artwork bundled -- the item then shows as plain text rather than with a
    /// blank gap where an icon should be.
    static func image(for toy: Toy, boundingSide: CGFloat = ToyThumbnail.defaultSide) -> NSImage? {
        guard let artwork = ToyArtwork.image(for: toy) else { return nil }

        let pixelSize = CGSize(width: artwork.width, height: artwork.height)
        let size = fittedSize(imagePixelSize: pixelSize, boundingSide: boundingSide)
        guard size.width > 0, size.height > 0 else { return nil }

        let image = NSImage(cgImage: artwork, size: size)
        // Left as-is rather than templated: these toys are recognised by their
        // colour (an orange pumpkin, a wand), and a template image would render
        // every one of them as the same flat silhouette.
        return image
    }
}
