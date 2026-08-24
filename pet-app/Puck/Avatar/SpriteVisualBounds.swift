//
//  SpriteVisualBounds.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Where the pet's *visible* pixels actually are, as a rectangle.
//
//  Two things stand between the layer's bounds and what the eye sees, and
//  both have to be undone to keep the pet's actual visible edges -- not its
//  layer bounds -- bouncing correctly off the screen boundary:
//
//  1. `contentsGravity = .resizeAspect` fits the image inside the layer
//     without distorting it, so unless the image's aspect ratio matches the
//     manifest hitbox exactly, the drawn image is letterboxed -- narrower or
//     shorter than the layer, centered, with dead space along two sides.
//  2. The PNG itself has transparent padding around the character. The dummy
//     avatar draws nothing in the leftmost 27 of its 1200 pixel columns.
//
//  Clamping to the layer box instead would leave a visible gap at the screen
//  edge (the pet "bounces" off nothing); clamping to the raw image box would
//  do the same, just less. This walks both transforms so the rectangle is the
//  character's own outline.
//
//  Pure geometry, no CALayer/AppKit -- the values it needs are measured once
//  at load time and the arithmetic is testable on its own.
//

import CoreGraphics
import Foundation

enum SpriteVisualBounds {
    /// The opaque pixels' rectangle in layer coordinates (origin top-left of
    /// the layer's own box).
    ///
    /// - Parameters:
    ///   - opaquePixels: the image's alpha bounding box, in image pixels.
    ///   - imagePixelSize: the full image's size, in pixels.
    ///   - layerSize: the layer's bounds — manifest hitbox times scale.
    static func inLayer(opaquePixels: CGRect, imagePixelSize: CGSize, layerSize: CGSize) -> CGRect {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return CGRect(origin: .zero, size: layerSize) }

        // .resizeAspect: the largest uniform scale that still fits, centered.
        let fit = min(layerSize.width / imagePixelSize.width, layerSize.height / imagePixelSize.height)
        let drawnSize = CGSize(width: imagePixelSize.width * fit, height: imagePixelSize.height * fit)
        let letterbox = CGPoint(x: (layerSize.width - drawnSize.width) / 2, y: (layerSize.height - drawnSize.height) / 2)

        return CGRect(
            x: letterbox.x + opaquePixels.minX * fit,
            y: letterbox.y + opaquePixels.minY * fit,
            width: opaquePixels.width * fit,
            height: opaquePixels.height * fit
        )
    }

    /// The same rectangle expressed relative to the *centre* of the layer --
    /// the anchor a layer positioned by `layer.position` actually uses. The
    /// ball toy is placed that way (its physics position is its middle),
    /// where the character is placed by its feet.
    static func relativeToCenter(opaquePixels: CGRect, imagePixelSize: CGSize, layerSize: CGSize) -> CGRect {
        inLayer(opaquePixels: opaquePixels, imagePixelSize: imagePixelSize, layerSize: layerSize)
            .offsetBy(dx: -layerSize.width / 2, dy: -layerSize.height / 2)
    }

    /// The same rectangle expressed relative to the character's ground point
    /// — the position the FSM moves around, at the bottom-center of the layer.
    /// Movement only ever needs this form: add the pet's position to get the
    /// on-screen rectangle.
    ///
    /// Y grows downward, so a rect above the feet has a negative `minY`.
    static func relativeToGroundPoint(opaquePixels: CGRect, imagePixelSize: CGSize, layerSize: CGSize) -> CGRect {
        let inLayer = inLayer(opaquePixels: opaquePixels, imagePixelSize: imagePixelSize, layerSize: layerSize)
        return inLayer.offsetBy(dx: -layerSize.width / 2, dy: -layerSize.height)
    }
}
