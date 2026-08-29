// Draws the dummy avatar pack, the toys and the app icons from scratch — one
// original mascot, no third party art. The web repo carries a trimmed twin of
// this file (web/scripts/gen-pet.swift) for the site's own sprite sizes; the
// two share a look, not a build.
//
//   swift pet-app/scripts/gen-avatar.swift <outDir>
//
// Writes <outDir>/{avatar,toys,logo}. Distribution into the repos is the
// caller's job. The app icon and the menu bar glyph are hand drawn and are
// deliberately not generated here.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: palette

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}
let ink    = rgb(0x4B, 0x44, 0x66)
let body   = rgb(0xCB, 0xC2, 0xEE)
let bodyLo = rgb(0xAB, 0x9F, 0xDA)
let shine  = rgb(0xFF, 0xFF, 0xFF)
let tear   = rgb(0x8F, 0xC7, 0xEA)

// MARK: expression vocabulary

enum Eyes { case arc, dot, wide, closed, swirl, sparkle, wink, worried, angry, heart, teary, narrow }
enum Mouth { case smile, open, wavy, tiny, wide, flat, grin }
enum Limbs { case stand, walk, up, grip, kick, none }

struct Pose {
    var rx: CGFloat = 88
    /// Taller than wide, so the character's own proportions match the canvas
    /// it is drawn on and it fills both dimensions. A squatter body fills the
    /// width and leaves a band of empty rows top and bottom -- and since the
    /// app derives the pet's outline from the artwork, those empty rows are a
    /// shorter pet: every clearance measured off `visualBounds` (petting,
    /// ceilings, ball collisions, the bounce off a wall) shrinks with it.
    var ry: CGFloat = 77
    var lift: CGFloat = 0
    var lean: CGFloat = 0
    var eyes: Eyes = .arc
    var mouth: Mouth = .smile
    var limbs: Limbs = .stand
    var eyeGap: CGFloat = 40
    var blush: CGFloat = 0.55
    var tuft = true
    var drops = 0        // sweat
    var tears = false    // from the eyes, not the temple
    var wind = false
    var dust = false
    var bubbles = false  // sleep / thought
    var notes = false    // humming
    var spark = false    // idea
}

// MARK: drawing helpers

func stroke(_ c: CGContext, _ p: CGPath, _ w: CGFloat, _ col: CGColor = ink) {
    c.addPath(p); c.setStrokeColor(col); c.setLineWidth(w)
    c.setLineCap(.round); c.setLineJoin(.round); c.strokePath()
}
func fill(_ c: CGContext, _ p: CGPath, _ col: CGColor) {
    c.addPath(p); c.setFillColor(col); c.fillPath()
}
func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2), transform: nil)
}
func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ from: CGFloat, _ to: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
             startAngle: from * .pi / 180, endAngle: to * .pi / 180, clockwise: false)
    return p
}
func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGPath {
    let p = CGMutablePath(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2))
    return p
}
func spiral(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0...48 {
        let t = CGFloat(i) / 48, a = t * .pi * 3.4, rr = r * (1 - t * 0.78)
        let pt = CGPoint(x: cx + cos(a) * rr, y: cy + sin(a) * rr)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    return p
}
func teardrop(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x, y: y + s))
    p.addCurve(to: CGPoint(x: x, y: y - s * 0.6),
               control1: CGPoint(x: x + s * 0.85, y: y - s * 0.1),
               control2: CGPoint(x: x + s * 0.6, y: y - s * 0.6))
    p.addCurve(to: CGPoint(x: x, y: y + s),
               control1: CGPoint(x: x - s * 0.6, y: y - s * 0.6),
               control2: CGPoint(x: x - s * 0.85, y: y - s * 0.1))
    return p
}
func star(_ cx: CGFloat, _ cy: CGFloat, _ outer: CGFloat, _ inner: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<10 {
        let a = (-.pi / 2) + CGFloat(i) * .pi / 5
        let r = i % 2 == 0 ? outer : inner
        let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath(); return p
}
func heart(_ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: cy - s))
    p.addCurve(to: CGPoint(x: cx - s * 1.1, y: cy + s * 0.45),
               control1: CGPoint(x: cx - s * 0.8, y: cy - s * 0.3),
               control2: CGPoint(x: cx - s * 1.1, y: cy - s * 0.05))
    p.addArc(center: CGPoint(x: cx - s * 0.55, y: cy + s * 0.45), radius: s * 0.55,
             startAngle: .pi, endAngle: 0, clockwise: true)
    p.addArc(center: CGPoint(x: cx + s * 0.55, y: cy + s * 0.45), radius: s * 0.55,
             startAngle: .pi, endAngle: 0, clockwise: true)
    p.addCurve(to: CGPoint(x: cx, y: cy - s),
               control1: CGPoint(x: cx + s * 1.1, y: cy - s * 0.05),
               control2: CGPoint(x: cx + s * 0.8, y: cy - s * 0.3))
    p.closeSubpath(); return p
}

/// An egg, wider at the base. One drawing reads as a whole character, so every
/// expression is this shape squashed or stretched with a different face.
func blob(_ cx: CGFloat, _ base: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    let cy = base + ry, top = base + ry * 2
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: base))
    p.addCurve(to: CGPoint(x: cx + rx, y: cy),
               control1: CGPoint(x: cx + rx * 0.62, y: base),
               control2: CGPoint(x: cx + rx, y: cy - ry * 0.62))
    p.addCurve(to: CGPoint(x: cx, y: top),
               control1: CGPoint(x: cx + rx, y: cy + ry * 0.68),
               control2: CGPoint(x: cx + rx * 0.58, y: top))
    p.addCurve(to: CGPoint(x: cx - rx, y: cy),
               control1: CGPoint(x: cx - rx * 0.58, y: top),
               control2: CGPoint(x: cx - rx, y: cy + ry * 0.68))
    p.addCurve(to: CGPoint(x: cx, y: base),
               control1: CGPoint(x: cx - rx, y: cy - ry * 0.62),
               control2: CGPoint(x: cx - rx * 0.62, y: base))
    p.closeSubpath(); return p
}

// MARK: face

func eye(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ kind: Eyes, mirrored: Bool) {
    switch kind {
    case .arc:     stroke(c, arc(x, y - 4, 15, 20, 160), 8)
    case .dot:
        fill(c, ellipse(x, y, 11, 12), ink); fill(c, ellipse(x + 4, y + 5, 4, 4), shine)
    case .narrow:
        fill(c, ellipse(x, y, 12, 7), ink)
    case .wide:
        fill(c, ellipse(x, y, 17, 19), ink); fill(c, ellipse(x + 6, y + 7, 6.5, 6.5), shine)
    case .closed:  stroke(c, arc(x, y + 12, 14, 205, 335), 7)
    case .worried: stroke(c, arc(x, y - 14, 14, 25, 155), 7)
    case .swirl:   stroke(c, spiral(x, y, 15), 6)
    case .sparkle:
        fill(c, ellipse(x, y, 16, 18), ink); fill(c, star(x + 3, y + 5, 9, 3.6), shine)
    case .heart:
        fill(c, heart(x, y, 15), rgb(0xF0, 0x7A, 0x9B)); fill(c, ellipse(x - 5, y + 6, 4, 4), shine)
    case .teary:
        fill(c, ellipse(x, y, 16, 18), ink); fill(c, ellipse(x + 6, y + 7, 6, 6), shine)
        fill(c, ellipse(x, y - 14, 12, 7), tear)
    case .wink:
        // The closed eye is the trailing one, so a mirrored sprite still winks.
        if mirrored { stroke(c, arc(x, y + 12, 14, 205, 335), 7) }
        else { fill(c, ellipse(x, y, 13, 14), ink); fill(c, ellipse(x + 5, y + 6, 5, 5), shine) }
    case .angry:
        fill(c, ellipse(x, y, 12, 13), ink); fill(c, ellipse(x + 4, y + 5, 4, 4), shine)
        stroke(c, line(x - 16 * (mirrored ? -1 : 1), y + 16,
                       x + 14 * (mirrored ? -1 : 1), y + 28), 7)
    }
}

func drawFace(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ p: Pose) {
    let dx = p.eyeGap
    eye(c, cx - dx, cy, p.eyes, mirrored: true)
    eye(c, cx + dx, cy, p.eyes, mirrored: false)

    if p.blush > 0 {
        for s in [-1.0, 1.0] as [CGFloat] {
            fill(c, ellipse(cx + (dx + 26) * s, cy - 20, 13, 8), rgb(0xF2, 0xA4, 0xB6, p.blush))
        }
    }
    if p.tears {
        for s in [-1.0, 1.0] as [CGFloat] {
            fill(c, teardrop(cx + dx * s, cy - 30, 11), tear)
            fill(c, teardrop(cx + dx * s, cy - 56, 8), tear)
        }
    }

    let my = cy - 30
    switch p.mouth {
    case .smile: stroke(c, arc(cx, my + 8, 12, 200, 340), 6)
    case .grin:  stroke(c, arc(cx, my + 12, 20, 205, 335), 6)
    case .tiny:  stroke(c, arc(cx, my + 5, 7, 200, 340), 5.5)
    case .flat:  stroke(c, line(cx - 11, my, cx + 11, my), 6)
    case .open:  fill(c, ellipse(cx, my - 1, 10, 12), ink)
    case .wide:  fill(c, ellipse(cx, my - 2, 15, 16), ink)
    case .wavy:
        let p2 = CGMutablePath()
        p2.move(to: CGPoint(x: cx - 15, y: my))
        p2.addCurve(to: CGPoint(x: cx + 15, y: my),
                    control1: CGPoint(x: cx - 5, y: my + 13),
                    control2: CGPoint(x: cx + 5, y: my - 13))
        stroke(c, p2, 6)
    }
}

// MARK: the character

func drawPet(_ c: CGContext, _ w: CGFloat, _ h: CGFloat, _ p: Pose) {
    let cx = w / 2
    let ground: CGFloat = 12
    let base = ground + p.lift

    c.saveGState()
    c.translateBy(x: cx, y: ground + fitShift)
    c.scaleBy(x: fitScale, y: fitScale)
    c.translateBy(x: -cx, y: -ground)
    c.saveGState()
    if p.lean != 0 {
        c.translateBy(x: cx, y: base); c.rotate(by: p.lean * .pi / 180)
        c.translateBy(x: -cx, y: -base)
    }

    let footY = base + 3
    switch p.limbs {
    case .stand:
        for s in [-1.0, 1.0] as [CGFloat] { fill(c, ellipse(cx + 30 * s, footY, 20, 13), bodyLo) }
    case .walk:
        fill(c, ellipse(cx - 46, footY + 4, 20, 12), bodyLo)
        fill(c, ellipse(cx + 40, footY + 2, 20, 12), bodyLo)
    case .kick:
        fill(c, ellipse(cx - 34, footY, 20, 13), bodyLo)
        let leg = CGPath(roundedRect: CGRect(x: cx + 20, y: base + p.ry * 0.42, width: 112, height: 30),
                         cornerWidth: 15, cornerHeight: 15, transform: nil)
        fill(c, leg, bodyLo); stroke(c, leg, 6)
    case .up:
        for s in [-1.0, 1.0] as [CGFloat] {
            fill(c, ellipse(cx + (p.rx * 0.72) * s, base + p.ry * 1.55, 15, 19), bodyLo)
        }
        for s in [-1.0, 1.0] as [CGFloat] { fill(c, ellipse(cx + 28 * s, footY, 19, 12), bodyLo) }
    case .grip:
        for s in [-1.0, 1.0] as [CGFloat] {
            fill(c, ellipse(cx + (p.rx * 0.74) * s, base + p.ry * 1.4, 14, 18), bodyLo)
        }
        for s in [-1.0, 1.0] as [CGFloat] { fill(c, ellipse(cx + 26 * s, footY + 2, 18, 12), bodyLo) }
    case .none:
        break
    }

    let shape = blob(cx, base, p.rx, p.ry)
    fill(c, shape, body); stroke(c, shape, 7)

    if p.tuft {
        let t = CGMutablePath(), ty = base + p.ry * 2 - 10
        t.move(to: CGPoint(x: cx - 13, y: ty - 6))
        t.addCurve(to: CGPoint(x: cx + 6, y: ty + 30),
                   control1: CGPoint(x: cx - 10, y: ty + 16), control2: CGPoint(x: cx - 4, y: ty + 26))
        t.addCurve(to: CGPoint(x: cx + 12, y: ty - 4),
                   control1: CGPoint(x: cx + 14, y: ty + 18), control2: CGPoint(x: cx + 15, y: ty + 6))
        fill(c, t, body); stroke(c, t, 6)
    }

    drawFace(c, cx, base + p.ry * 1.12, p)
    c.restoreGState()  // lean

    // Over the head rather than beside it: idle fills the frame, so anything
    // drawn outside the body is drawn outside the canvas.
    for i in 0..<(measuringFit ? 0 : p.drops) {
        fill(c, teardrop(cx + p.rx * 0.62 + CGFloat(i) * 14,
                         base + p.ry * 1.62 - CGFloat(i) * 20, 12), tear)
    }
    if p.wind, !measuringFit {
        for (i, y) in [0.4, 0.85, 1.3].enumerated() {
            let len: CGFloat = 34 - CGFloat(i) * 6
            for s in [-1.0, 1.0] as [CGFloat] {
                let x = cx + p.rx * 0.82 * s
                stroke(c, line(x, base + p.ry * CGFloat(y), x, base + p.ry * CGFloat(y) + len),
                       6, rgb(0x9A, 0x92, 0xC0, 0.75))
            }
        }
    }
    if p.dust, !measuringFit {
        for s in [-1.0, 1.0] as [CGFloat] {
            fill(c, ellipse(cx + p.rx * 0.72 * s, base + 10, 14, 10), rgb(0x9A, 0x92, 0xC0, 0.6))
            fill(c, ellipse(cx + p.rx * 0.96 * s, base + 24, 9, 7), rgb(0x9A, 0x92, 0xC0, 0.42))
        }
    }
    if p.bubbles, !measuringFit {
        for (i, r) in [7.0, 10.0, 14.0].enumerated() {
            let b = ellipse(cx + p.rx * 0.5 + CGFloat(i) * 16,
                            base + p.ry * 1.5 + CGFloat(i) * 17, CGFloat(r), CGFloat(r))
            fill(c, b, rgb(0xFF, 0xFF, 0xFF, 0.85)); stroke(c, b, 4)
        }
    }
    if p.notes, !measuringFit {
        for (i, dy) in [0.0, 26.0].enumerated() {
            let x = cx + p.rx * 0.42 + CGFloat(i) * 22, y = base + p.ry * 1.24 + dy
            fill(c, ellipse(x, y, 10, 7), ink)
            stroke(c, line(x + 9, y + 2, x + 9, y + 30), 5)
        }
    }
    if p.spark, !measuringFit {
        fill(c, star(cx, base + p.ry * 1.95, 24, 9), rgb(0xFF, 0xD9, 0x6B))
        stroke(c, star(cx, base + p.ry * 1.95, 24, 9), 6)
    }
    c.restoreGState()  // fit
}

/// Set once by the fit pass below.
var fitScale: CGFloat = 1
var fitShift: CGFloat = 0

/// True only during the dry run that picks the scale.
///
/// The scale has to be one number for the whole pack, or the pet changes size
/// when its face does. Measured over everything drawn, that number is set by
/// whichever pose flings a sweat drop furthest -- and the character itself
/// then fills a little over half the frame. The app fits the image into a
/// fixed layer, so half a frame of art is a pet at half size with a hit area
/// to match, which is what made the new pack hard to grab.
///
/// So the decorations sit out the measurement. They are drawn at full size
/// like everything else; they just do not get a vote on how big the pet is,
/// and may reach into the padding.
var measuringFit = false

// MARK: output

func render(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setAllowsAntialiasing(true); draw(c)
    return c.makeImage()!
}

func write(_ img: CGImage, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    precondition(CGImageDestinationFinalize(d), "failed writing \(url.lastPathComponent)")
}

func alphaBounds(_ img: CGImage) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let c = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = w, minY = h, maxX = -1, maxY = -1
    for row in 0..<h {
        for col in 0..<w where px[(row * w + col) * 4 + 3] > 8 {
            let y = h - 1 - row
            if col < minX { minX = col }; if col > maxX { maxX = col }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
    return maxX < 0 ? nil : (minX, minY, maxX, maxY)
}

// MARK: the pack

/// Every name the dummy manifest can ask for. The clip names map onto these
/// through the manifest, so this list is exactly the pack's PNG file names.
let pack: [(String, Pose)] = [
    ("starry-eyed",  Pose(eyes: .sparkle, mouth: .smile, blush: 0.6)),
    ("beaming",      Pose(eyes: .arc, mouth: .grin, blush: 0.7)),
    ("sunny",        Pose(eyes: .arc, mouth: .grin, blush: 0.8, spark: true)),
    ("giddy",        Pose(eyes: .sparkle, mouth: .open, limbs: .up, blush: 0.7)),
    ("giggly",       Pose(eyes: .closed, mouth: .open, blush: 0.75)),
    ("thrilled",     Pose(eyes: .sparkle, mouth: .wide, limbs: .up, blush: 0.7)),
    ("cheeky",       Pose(eyes: .wink, mouth: .grin, blush: 0.8)),
    ("smitten",      Pose(eyes: .heart, mouth: .smile, blush: 0.95)),
    ("bashful",      Pose(rx: 84, ry: 72, eyes: .closed, mouth: .tiny, blush: 1.0)),
    ("serene",       Pose(rx: 88, ry: 70, eyes: .closed, mouth: .smile, blush: 0.45)),
    ("phew",         Pose(rx: 88, ry: 70, eyes: .closed, mouth: .smile, blush: 0.4, drops: 1)),
    ("humming",      Pose(lean: -2, eyes: .closed, mouth: .tiny, limbs: .walk, notes: true)),
    ("melting",      Pose(rx: 88, ry: 44, eyes: .closed, mouth: .smile, limbs: .none, blush: 0.85)),
    ("all-ears",     Pose(eyes: .dot, mouth: .tiny, limbs: .up, blush: 0.5)),
    ("pondering",    Pose(eyes: .narrow, mouth: .flat, blush: 0.35, bubbles: true)),
    ("in-the-zone",  Pose(eyes: .narrow, mouth: .flat, blush: 0.3)),
    ("determined",   Pose(rx: 84, ry: 76, eyes: .angry, mouth: .flat, limbs: .grip, blush: 0.4)),
    ("eureka",       Pose(eyes: .sparkle, mouth: .open, limbs: .up, blush: 0.5, spark: true)),
    ("startled",     Pose(rx: 80, ry: 76, eyes: .wide, mouth: .wide, limbs: .up,
                          blush: 0.3, drops: 1)),
    ("agape",        Pose(eyes: .wide, mouth: .wide, blush: 0.35)),
    ("yikes",        Pose(lean: -2, eyes: .wide, mouth: .open, limbs: .up, blush: 0.3, drops: 2)),
    ("spooked",      Pose(rx: 82, ry: 76, eyes: .wide, mouth: .wide, limbs: .up, blush: 0.15,
                          wind: true)),
    ("flustered",    Pose(eyes: .swirl, mouth: .wavy, limbs: .up, blush: 0.9, drops: 2)),
    ("dazed",        Pose(rx: 88, ry: 66, eyes: .swirl, mouth: .tiny, blush: 0.5, dust: true)),
    ("fretting",     Pose(eyes: .worried, mouth: .wavy, blush: 0.5, drops: 1)),
    ("welling-up",   Pose(eyes: .teary, mouth: .wavy, blush: 0.65)),
    ("sobbing",      Pose(rx: 86, ry: 72, eyes: .closed, mouth: .wide, blush: 0.7, tears: true)),
    ("grumpy",       Pose(rx: 88, ry: 70, eyes: .angry, mouth: .wavy, blush: 0.4)),
]

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let AW = 1200, AH = 1224

// One scale for the whole pack, taken from the pose the pet spends its life
// in rather than from the union of all of them.
//
// Measured over the union, the widest pose sets the scale and the ordinary
// one is left filling 79% of its frame -- and since the app fits the whole
// PNG into a layer sized from the manifest hitbox, a character at 79% is a
// pet at 79%, smaller than the hand-drawn pack this replaced and smaller to
// aim at. The pack it replaced filled 96%, and the manifest hitbox is
// calibrated against that.
//
// So idle fills the frame, and the poses that are deliberately wider or
// flatter than it -- a puddle, a landing squash -- are checked afterwards
// and must still fit. That is a design constraint on the pose table, which
// is where it belongs, rather than a tax on every other drawing.
let PAD: CGFloat = 16
/// How far the feet sit above the bottom of the canvas -- see `fitShift`.
let groundMargin: CGFloat = 6
do {
    measuringFit = true
    defer { measuringFit = false }
    let pw = 900, ph = 900
    let reference = pack.first { $0.0 == "starry-eyed" }!.1
    let img = render(pw, ph) { drawPet($0, CGFloat(pw), CGFloat(ph), reference) }
    guard let b = alphaBounds(img) else { fatalError("the reference pose drew nothing") }
    let cx = CGFloat(pw) / 2, ground: CGFloat = 12
    let half = max(cx - CGFloat(b.minX), CGFloat(b.maxX) - cx)
    let above = CGFloat(b.maxY) - ground, below = ground - CGFloat(b.minY)
    fitScale = min((CGFloat(AW) / 2 - PAD) / half, (CGFloat(AH) - PAD * 2) / (above + below))
    // Sat on the bottom of the frame, not floated in the middle of it.
    //
    // The app puts the layer so the pet's ground point is the layer's bottom
    // edge, and fits the whole PNG into that layer -- so empty rows under the
    // feet are a gap between where the pet is drawn and where the app thinks
    // it is standing. The hand-drawn pack it replaces leaves six pixels; this
    // leaves the same, and the padding the poses need goes above instead.
    fitShift = groundMargin - (ground - below * fitScale)
    print(String(format: "fit: scale %.3f shift %.1f (from starry-eyed)", fitScale, fitShift))
}

var clipped: [String] = []
for (name, pose) in pack {
    let img = render(AW, AH) { drawPet($0, CGFloat(AW), CGFloat(AH), pose) }
    precondition(img.width == AW && img.height == AH, "\(name): wrong size")
    guard let bounds = alphaBounds(img) else { fatalError("\(name): blank") }
    // Clipped art is worse than small art: a puddle with its edge sheared off
    // reads as a bug. If this fires, the pose is too wide or too tall for the
    // frame idle sets -- narrow it in the table above.
    // A margin rather than the edge itself: art that reaches the last column
    // has almost certainly been cut off at it.
    let margin = 2
    if bounds.minX < margin || bounds.maxX > AW - 1 - margin
        || bounds.minY < margin || bounds.maxY > AH - 1 - margin {
        clipped.append("\(name): x \(bounds.minX)...\(bounds.maxX) y \(bounds.minY)...\(bounds.maxY)")
    }
    write(img, out.appendingPathComponent("avatar/\(name).png"))
}

if !clipped.isEmpty {
    print("clipped by the frame idle sets — narrow these in the pose table:")
    clipped.forEach { print("  \($0)") }
}

// MARK: toys

func pumpkin(_ w: Int, _ h: Int) -> CGImage {
    render(w, h) { c in
        let cx = CGFloat(w) / 2, cy = CGFloat(h) * 0.46
        let rx = CGFloat(w) * 0.42, ry = CGFloat(h) * 0.36
        let orange = rgb(0xF0, 0x9A, 0x4E), orangeLo = rgb(0xD8, 0x7C, 0x38)
        let outer = ellipse(cx, cy, rx, ry)
        fill(c, outer, orange)
        for s in [-1.0, 1.0] as [CGFloat] { fill(c, ellipse(cx + rx * 0.56 * s, cy, rx * 0.37, ry * 0.94), orangeLo) }
        fill(c, ellipse(cx, cy, rx * 0.56, ry * 0.99), orange)
        stroke(c, outer, CGFloat(w) * 0.028)
        for s in [-1.0, 1.0] as [CGFloat] {
            let rib = CGMutablePath()
            rib.move(to: CGPoint(x: cx + rx * 0.2 * s, y: cy + ry * 0.94))
            rib.addQuadCurve(to: CGPoint(x: cx + rx * 0.2 * s, y: cy - ry * 0.92),
                             control: CGPoint(x: cx + rx * 0.7 * s, y: cy))
            stroke(c, rib, CGFloat(w) * 0.02)
        }
        let stem = CGPath(roundedRect: CGRect(x: cx - rx * 0.13, y: cy + ry * 0.84,
                                              width: rx * 0.26, height: ry * 0.46),
                          cornerWidth: rx * 0.11, cornerHeight: rx * 0.11, transform: nil)
        fill(c, stem, rgb(0x7B, 0xA5, 0x66)); stroke(c, stem, CGFloat(w) * 0.024)
    }
}

func wand(_ w: Int, _ h: Int) -> CGImage {
    render(w, h) { c in
        let cx = CGFloat(w) / 2, W = CGFloat(w), H = CGFloat(h)
        let shaft = CGPath(roundedRect: CGRect(x: cx - W * 0.09, y: H * 0.05,
                                               width: W * 0.18, height: H * 0.72),
                           cornerWidth: W * 0.09, cornerHeight: W * 0.09, transform: nil)
        fill(c, shaft, rgb(0xB9, 0x8E, 0x6A)); stroke(c, shaft, W * 0.027)
        let grip = CGPath(roundedRect: CGRect(x: cx - W * 0.12, y: H * 0.09,
                                              width: W * 0.24, height: H * 0.13),
                          cornerWidth: W * 0.11, cornerHeight: W * 0.11, transform: nil)
        fill(c, grip, rgb(0x8F, 0x6A, 0x4C)); stroke(c, grip, W * 0.023)
        let head = star(cx, H * 0.82, W * 0.44, W * 0.19)
        fill(c, head, rgb(0xFF, 0xD9, 0x6B)); stroke(c, head, W * 0.032)
        fill(c, ellipse(cx, H * 0.82, W * 0.12, W * 0.12), rgb(0xFF, 0xF2, 0xC2))
    }
}

write(pumpkin(494, 505), out.appendingPathComponent("toys/pumpkin.png"))
write(wand(221, 827), out.appendingPathComponent("toys/wand.png"))

// The pumpkin logo, on its own tile.
for (name, px) in [("logo", 256), ("logo@2x", 512)] {
    let img = render(px, px) { c in
        let s = CGFloat(px)
        fill(c, CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil),
             rgb(0xFD, 0xEE, 0xDC))
        let art = pumpkin(px, px)
        c.draw(art, in: CGRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84))
    }
    write(img, out.appendingPathComponent("logo/\(name).png"))
}

print("wrote \(pack.count) avatar PNGs, 2 toys, 2 logo")
