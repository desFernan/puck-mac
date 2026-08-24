//
//  SpriteHitTest.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Turns a point on screen into a point inside a sprite's artwork, so it can
//  be tested against that artwork's AlphaHitMask.
//
//  Everything drawn here is a CALayer showing an image with
//  `contentsGravity = .resizeAspect` and an affine transform on top -- facing
//  flips, the ceiling flip, the climb rotation, the procedural bounce, a
//  wand's spin. Hit testing has to undo all of that, which is exactly why it
//  lives next to the things that own those transforms rather than in the
//  click-handling code: only the renderer knows what it currently looks like.
//
//  Pure geometry, no CALayer, so the whole chain is testable without a screen.
//

import CoreGraphics
import Foundation

enum SpriteHitTest {
    /// Where `point` falls inside the artwork, as 0...1 on each axis with a
    /// top-left origin, or nil if it misses the drawn image entirely.
    ///
    /// - Parameters:
    ///   - point: in the layer's own coordinates, top-left origin, before any
    ///     transform -- i.e. what the caller gets after subtracting the
    ///     layer's position and undoing its anchor.
    ///   - transform: the layer's current affine transform, applied about the
    ///     layer's centre (CALayer's default anchor point).
    ///   - layerSize: the layer's bounds.
    ///   - imagePixelSize: the artwork's size, for the aspect fit.
    static func unitPoint(
        forLayerPoint point: CGPoint,
        transform: CGAffineTransform,
        layerSize: CGSize,
        imagePixelSize: CGSize
    ) -> CGPoint? {
        guard layerSize.width > 0, layerSize.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else { return nil }

        // Undo the transform. It acts about the centre, so the point has to be
        // centre-relative while it's inverted, and a non-invertible transform
        // (a bounce squashed flat to zero, mid-flip) has nothing to hit.
        let centre = CGPoint(x: layerSize.width / 2, y: layerSize.height / 2)
        // A transform squashed flat -- the bounce at its extreme, a flip
        // caught exactly edge-on -- has no inverse, and nothing visible to
        // hit either. CGAffineTransform.inverted() returns the input
        // unchanged in that case rather than telling you, so check the
        // determinant directly.
        let determinant = transform.a * transform.d - transform.b * transform.c
        guard abs(determinant) > 1e-9 else { return nil }
        let untransformed = CGPoint(x: point.x - centre.x, y: point.y - centre.y)
            .applying(transform.inverted())

        // Then undo .resizeAspect's letterboxing: the image is drawn as large
        // as it fits without distorting, centred, so there is dead space on
        // two sides whenever the aspect ratios differ.
        let fit = min(layerSize.width / imagePixelSize.width, layerSize.height / imagePixelSize.height)
        let drawn = CGSize(width: imagePixelSize.width * fit, height: imagePixelSize.height * fit)

        let unit = CGPoint(
            x: (untransformed.x + drawn.width / 2) / drawn.width,
            y: (untransformed.y + drawn.height / 2) / drawn.height
        )
        guard (0...1).contains(unit.x), (0...1).contains(unit.y) else { return nil }
        return unit
    }
}
