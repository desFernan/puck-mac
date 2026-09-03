//
//  SpriteOutline.swift
//  Puck
//
//  A sticker's white edge, drawn around whatever the character is.
//
//  The outline follows the artwork's own silhouette rather than its box, so a
//  character with a tail or an ear sticking out gets an edge around those
//  too. That means growing the alpha channel outward and filling what the
//  growth adds, which is a dilation -- CoreImage has one, and it runs on the
//  GPU.
//
//  A dilation on its own is not enough to look like anything. It reproduces
//  every step in the artwork's own edge at full contrast, so a line that was
//  smooth at the drawing's scale comes back as a staircase, and every sharp
//  corner stays sharp -- the shape reads as cut out with scissors rather than
//  drawn around. So the grown silhouette is softened and then firmed up
//  again: the blur rounds the corners and swallows the stepping, and pushing
//  the alpha back up keeps the edge solid instead of leaving a haze around
//  the character. What is left of the blur is a pixel or two of falloff at
//  the very rim, which is what the eye reads as a drawn line.
//
//  Done once when a sprite is first loaded, never per frame. There are a
//  couple of dozen images in a package and each is drawn thousands of times.
//
//  The image comes back larger than it went in, by the thickness on every
//  side. That is deliberate: the outline is part of the drawing now, and
//  everything downstream measures the pet from its pixels -- so an edge that
//  lived outside the image would be an edge the pet could push off screen.
//

import CoreGraphics
import CoreImage

enum SpriteOutline {
    /// How thick the edge is, in the sprite's own pixels.
    ///
    /// Scaled with the image rather than fixed in points, so a sprite drawn
    /// at 300px and one drawn at 1200px get an edge of the same visual
    /// weight once both are shown at the standard size.
    static let relativeThickness: CGFloat = 0.018

    /// How much of the thickness is spent softening the edge.
    ///
    /// Enough to round the corners and lose the stepping, not so much that
    /// the line turns into a glow.
    static let softness: CGFloat = 0.55

    /// How hard the softened edge is pushed back to solid. Below about two
    /// the rim stays visibly translucent; far above it the rounding the blur
    /// bought is squared off again.
    static let firmness: CGFloat = 2.6

    static func thickness(for image: CGImage) -> CGFloat {
        max(1, (CGFloat(max(image.width, image.height)) * relativeThickness).rounded())
    }

    /// How much room the edge needs around the artwork.
    ///
    /// More than the thickness. The dilation reaches exactly that far, but
    /// the blur after it reaches further -- a Gaussian is effectively three
    /// times its radius -- and the canvas was only ever widened by the
    /// dilation's share. So the soft outer part of the edge was cropped away
    /// wherever the drawing came near its own bounds, which for a sprite
    /// trimmed to its artwork is every side: the ears came out with the
    /// outline sliced flat across the top.
    static func padding(for image: CGImage) -> CGFloat {
        let radius = thickness(for: image)
        return (radius * (1 + softness * 3)).rounded(.up)
    }

    /// `image` with a white edge around its silhouette, or `image` unchanged
    /// if the work cannot be done -- an outline is decoration, and losing it
    /// must never lose the pet.
    static func outlined(
        _ image: CGImage,
        context: CIContext = CIContext(options: [.useSoftwareRenderer: false])
    ) -> CGImage {
        let radius = thickness(for: image)
        let room = padding(for: image)
        let source = CIImage(cgImage: image)
        // Grown on every side, so the room for the edge has to be made first
        // -- a dilation clipped to the original extent has nowhere to put the
        // pixels it adds, and neither has the blur after it.
        let padded = source.transformed(by: CGAffineTransform(translationX: room, y: room))
        let canvas = CGRect(
            x: 0, y: 0,
            width: CGFloat(image.width) + room * 2,
            height: CGFloat(image.height) + room * 2
        )

        // Not clamped to the extent. Clamping repeats an image's edge pixels
        // outward forever, and a sprite trimmed to its artwork is opaque
        // right up to its own bounds -- so the character's edge colour was
        // smeared across the padding and came back as a flat band instead of
        // an outline. What is outside the artwork is nothing, and nothing is
        // what the edge has to grow into.
        guard let grown = CIFilter(name: "CIMorphologyMaximum", parameters: [
            kCIInputImageKey: padded,
            "inputRadius": radius,
        ])?.outputImage else { return image }

        // Rounds the corners the dilation left sharp and swallows the
        // stepping along the edge. Unclamped for the same reason as above:
        // the blur is meant to fade the rim out into nothing, which it can
        // only do if there is nothing there.
        guard let softened = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: grown,
            kCIInputRadiusKey: radius * softness,
        ])?.outputImage else { return image }

        // The dilation spreads colour as well as alpha, so the result is a
        // smeared copy of the character. Only its shape is wanted: everything
        // opaque becomes white, and the rest stays out of it. The alpha is
        // pushed back up at the same time, because the blur just made the
        // whole rim translucent -- a soft edge is wanted at the very outside,
        // not a haze across the whole line.
        guard let boosted = CIFilter(name: "CIColorMatrix", parameters: [
            kCIInputImageKey: softened.cropped(to: canvas),
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: firmness),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])?.outputImage else { return image }

        // Multiplying alpha takes it over 1 in the middle of the rim, which
        // is not a colour; clamped, that becomes solid white with the falloff
        // left only at the outer edge.
        guard let silhouette = CIFilter(name: "CIColorClamp", parameters: [
            kCIInputImageKey: boosted,
        ])?.outputImage else { return image }

        guard let composited = CIFilter(name: "CISourceOverCompositing", parameters: [
            kCIInputImageKey: padded,
            kCIInputBackgroundImageKey: silhouette,
        ])?.outputImage else { return image }

        return context.createCGImage(composited, from: canvas) ?? image
    }
}
