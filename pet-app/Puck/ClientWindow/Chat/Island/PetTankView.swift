//
//  PetTankView.swift
//  Puck
//
//  The pet's island: a panel floating across the top of the chat (and the
//  editor, when it is open). Draws the ground, never the pet -- the pet is
//  rendered by Puck.app's overlay window on top of this, which is what keeps
//  there being exactly one pet. See the 2026-08-22 spec.
//
//  A floating panel rather than the full-bleed strip it started as: a strip
//  reads as part of the window's chrome, and the pet standing on it reads as
//  standing on a toolbar. Inset, lightly rounded and lit from above, it reads
//  as a thing the pet is on -- the sidebar laid on its side.
//
//  The island is filled with one picture; see TankArtwork.swift.
//

import SwiftUI

struct PetTankView: View {
    /// The strip's frame in AppKit global coordinates, or nil when it is off
    /// screen. Reported to the store, which forwards it over the socket.
    let onFrameChange: (CGRect?) -> Void

    /// Sends the pet's height on the island to pet-app, which is the process
    /// that actually resizes it. Nil in the editor's segment: one pet, one
    /// control, and two would disagree the moment either moved.
    var onPetHeightChange: ((CGFloat) -> Void)?

    /// Where the toolbar's buttons end, in SwiftUI's global space, or nil
    /// when nothing has measured them. The island rises into the empty band
    /// past this point and stays clear of it before -- see IslandShape.
    var toolbarTrailingX: CGFloat?

    @Environment(\.clientPalette) private var palette



    /// Dragged from the island's bottom edge, and remembered. Stored as a
    /// Double because that is what @AppStorage keeps; clamped on read, so a
    /// value written by a future version with different limits cannot leave
    /// the pet in an island it does not fit in.
    @AppStorage(PetTankView.heightStorageKey) private var storedHeight = Double(PetTankView.islandHeight)

    /// Whether the island is folded down to its band. Written by
    /// IslandFoldButton, up in the toolbar; read here for the shape. Stored
    /// rather than passed in so that the two cannot disagree, and remembered
    /// because it is a choice about how much of the window the pet is allowed
    /// rather than a thing you do to look at something once.
    @AppStorage(PetTankView.collapsedStorageKey) private var isCollapsed = false

    /// What each drag is working from, captured once when the gesture starts
    /// so it measures against where it began rather than against the value it
    /// is itself changing.
    ///
    /// `@GestureState` rather than `@State`: the gesture system owns it for
    /// the life of the drag and clears it afterwards. Held in view state it
    /// was lost mid-drag -- this view is rebuilt when the island's frame is
    /// reported, which is exactly what dragging it causes -- and every event
    /// then measured from the value the previous event had just written,
    /// which ran away to whichever limit the drag was heading for.
    @GestureState private var heightAtDragStart: CGFloat?

    /// 2 on a Retina display. Read from the environment rather than the
    /// screen, so an island dragged onto a 1x display gets its full range
    /// back on the next redraw instead of keeping the other screen's limit.
    @Environment(\.displayScale) private var displayScale

    /// How tall the pet stands here. Remembered on this side because the
    /// lever has to draw the value it is about to send; pet-app is told on
    /// every change and on every window that opens.

    private var islandHeight: CGFloat {
        Self.clamped(storedHeight, from: Self.minimumIslandHeight, to: maximumHeight)
    }

    /// How tall the island is drawn right now: the height it was dragged to,
    /// or the band it folds down to.
    private var shownHeight: CGFloat {
        isCollapsed ? Self.collapsedHeight : islandHeight
    }

    /// A folded island does not climb into the toolbar's band. The shoulder
    /// exists to fill a strip of nothing across the top of the window; folded
    /// down, the island is that strip, and a shoulder on it would be a raised
    /// edge on something one line tall.
    private var shownRise: CGFloat { isCollapsed ? 0 : Self.shoulderRise }

    private var shownLift: CGFloat { isCollapsed ? 0 : Self.baseLift }

    /// Half the height when folded, which is what makes it a capsule: the
    /// shape clamps its own radius to half the rect, so asking for more than
    /// that rounds the ends off completely.
    private var shownCornerRadius: CGFloat {
        isCollapsed ? Self.collapsedHeight / 2 : Self.cornerRadius
    }

    /// This island's own limit -- see the static behind it. Recomputed rather
    /// than stored: the picture can be swapped in the customisation folder
    /// and the window can be moved to a display with a different scale, and
    /// both change the answer.
    private var maximumHeight: CGFloat {
        Self.maximumHeight(
            artworkPixelHeight: TankArtwork.image().map(TankArtwork.pixelHeight) ?? 0,
            displayScale: displayScale
        )
    }

    /// Clamps a stored number into its limits, and treats one that is not a
    /// number at all as the smallest allowed. A `Double` read back from
    /// UserDefaults can be anything -- a hand-edited plist, a value written by
    /// a version with different limits -- and NaN passes straight through
    /// `min`/`max` into a SwiftUI frame, which is a window that will not draw.
    static func clamped(_ value: Double, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        guard value.isFinite else { return lower }
        return min(max(CGFloat(value), lower), upper)
    }

    /// How tall the island opens at, and the pet's whole world while it is
    /// home.
    ///
    /// Insetting *this* is what once broke the move: the reported area is
    /// refused when it is shorter than the pet, so trimming 8pt off each end
    /// left 74 against an 80pt pet and the pet simply stayed on the desktop.
    /// The padding goes outside instead.
    ///
    /// Tall enough that the pet living on it reads as the character it is
    /// rather than a token. The pet is fitted to whatever room this leaves,
    /// so this number *is* how big the pet comes out -- 90 gave a shelf you
    /// had to lean in to see anything on, and the drag handle was the only
    /// way to find that out.
    static let islandHeight: CGFloat = 180

    /// The floor of the drag. Below this the pet no longer fits and the whole
    /// area is refused -- which looks like the pet refusing to come home, so
    /// the handle stops here rather than letting anyone find that out.
    static let minimumIslandHeight: CGFloat = 84

    /// Somewhere to stop. Past this the island is a pane rather than a shelf,
    /// and the conversation under it is what the window is for.
    ///
    /// The design's limit, not always the reachable one -- see
    /// `maximumHeight(forArtworkPixelHeight:displayScale:)`, which stops the
    /// drag earlier when the picture in the island cannot fill that much.
    static let maximumIslandHeight: CGFloat = 260

    /// How tall the island may actually be dragged, given the picture in it.
    ///
    /// The picture is scaled by *height* and it is a wide one -- the shipped
    /// seabed is 3596x447, eight points across for every point down. So each
    /// point the island grows costs eight points of picture width, and past
    /// the height where one copy is as wide as the picture has pixels, the
    /// island is asking to have it blown up: 260pt tall is a 1.16x
    /// magnification of art that is drawn at 0.40x at the island's default
    /// 90pt, i.e. every soft edge in it is suddenly three times the size it
    /// was designed to be seen at. That is what "the picture goes strange
    /// when the island gets big" was.
    ///
    /// There is no way to fill a taller island from a shorter picture without
    /// that magnification -- the aspect is fixed and the whole scene has to
    /// stay in frame (see `tiles`) -- so the drag stops where the picture
    /// stops being able to serve it.
    ///
    /// - Parameters:
    ///   - artworkPixelHeight: the real pixels (TankArtwork.pixelHeight), or
    ///     0 when there is no picture at all -- then nothing can look soft
    ///     and the design's own ceiling is the only limit.
    ///   - displayScale: 2 on a Retina display, where a point of island costs
    ///     two pixels of picture.
    static func maximumHeight(artworkPixelHeight: CGFloat, displayScale: CGFloat) -> CGFloat {
        guard artworkPixelHeight > 0, displayScale > 0 else { return maximumIslandHeight }
        let sharpest = artworkPixelHeight / displayScale
        // Never below the floor: a small picture must not make the island
        // undraggable, and a pet refused an area it cannot stand in looks
        // like the pet refusing to come home. A picture that small is
        // magnified, and that is the better of the two failures.
        return min(maximumIslandHeight, max(minimumIslandHeight, sharpest))
    }

    /// What the island folds down to: a band the width of the window with a
    /// pet walking along it.
    ///
    /// A toolbar button's height and a little over, grown evenly above and
    /// below their line: the row is what the band belongs to, but a pet that
    /// fits inside a button is not a pet you can see. Still clear of both the
    /// window's top edge and the pane below -- the whole band is inside the
    /// toolbar's own strip.
    static let collapsedHeight: CGFloat = 38

    /// What the band is measured against: the height of the buttons it sits
    /// beside. Not a layout value -- `collapsedHeight` is -- but the line the
    /// band stays centred on however far it grows past them.
    static let toolbarRowHeight: CGFloat = 28

    /// How tall the pet stands on the band: all of it, less the two edges the
    /// band is drawn with.
    ///
    /// It was 26 against a 38pt band, which left a third of the band empty
    /// above the pet's head -- and a band is short enough already that the
    /// empty part reads as the pet having shrunk rather than as headroom.
    /// Filling it is what makes the folded island still show a pet.
    ///
    /// Exactly the reported height is allowed -- pet-app refuses a tank
    /// *shorter* than the pet, not one the same size -- but the two edges are
    /// drawn inside that rect, so the pet stops short of them.
    static let collapsedPetHeight: Double = Double(collapsedHeight) - 2

    /// Its own key, not the background's: how tall someone wants the shelf is
    /// not which mood they picked, and one changing should not reset the
    /// other.
    static let heightStorageKey = "Puck.islandHeight"

    /// Folded or not. Separate from the height so that folding and unfolding
    /// gives back the island someone had, not the default one.
    static let collapsedStorageKey = "Puck.islandCollapsed"

    /// How far the island floats from the window's own edges. Was 20 on each
    /// side, which read as a gap rather than as the island floating: the strip
    /// is only ~90pt tall, and 40pt of the width went to nothing.
    static let horizontalInset: CGFloat = 10
    static let verticalInset: CGFloat = 8

    /// The strip the island floats in.
    static func stripHeight(island: CGFloat) -> CGFloat { island + verticalInset * 2 }

    /// The same corners every floating panel in this window has.
    static let cornerRadius: CGFloat = ClientTheme.Metrics.panelCornerRadius

    /// How far the island reaches up into the toolbar's empty band. Short of
    /// filling it: the buttons beside it need air, and an island level with
    /// the traffic lights reads as the titlebar rather than as a panel.
    static let shoulderRise: CGFloat = 40

    /// Between the toolbar's last button and where the island starts to
    /// climb.
    static let shoulderGap: CGFloat = 14

    /// The pet's height on the island, and what the slider may set it to.
    /// Kept in points rather than as a fraction of the island: the island is
    /// resizable now, and a pet that changed size when the shelf did would
    /// undo the lever every time.
    static let defaultPetHeight: Double = 72
    static let minimumPetHeight: Double = 32
    static let maximumPetHeight: Double = 200

    /// Left above the pet's head on the island. Not style: pet-app refuses an
    /// area it cannot stand the pet in, and refusing looks like the pet
    /// ignoring the window entirely.
    static let petHeadroom: Double = 10
    static let petHeightStorageKey = "Puck.petIslandHeight"

    /// How far the part *under* the buttons rises too. The step down to it
    /// was the full shoulder, which left the buttons sitting in a trench;
    /// lifting the low end a little puts them on the island rather than
    /// beside it, without reaching the traffic lights' row.
    static let baseLift: CGFloat = 9

    /// The island itself: always the app's own ground, whatever mood is
    /// behind it. A pet standing on a picture reads as standing *in* it, so
    /// the backdrop stays behind the island rather than under the pet.
    private var island: some View {
        // Flat, on purpose. It carried a sheen and a specular edge for a
        // while, which read as glass -- and glass beside a plain sidebar and a
        // plain file list looked like one panel borrowed from another app.
        // What makes it a panel is its outline and the ground showing around
        // it, not a highlight.
        GeometryReader { proxy in
            let shape = IslandShape(
                cornerRadius: shownCornerRadius,
                rise: shownRise,
                shoulderStart: shoulderStart(in: proxy)
            )
            ZStack(alignment: .bottom) {
                islandFill(shape)
                // The floor the pet stands on. Clipped by the island as a
                // whole rather than by itself: a 1pt-tall box has no corners
                // to round, so clipping it in place left the line running
                // straight out past both bottom corners.
                Rectangle()
                    .fill(palette.textSecondary.opacity(0.25))
                    .frame(height: 1)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(palette.surfaceBorder.opacity(0.8), lineWidth: 1) }
            .compositingGroup()
            // Floating, so it sits above its surroundings rather than beside
            // them. Softer than a card's: the island is a shelf, not a dialog.
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        }
        .frame(height: shownHeight + shownRise + shownLift)
        // The grab area for resizing, on the edge it moves. Nothing to drag
        // while the island is folded: the band is one size, and dragging it
        // taller is what unfolding is for.
        .overlay(alignment: .bottom) {
            if !isCollapsed { resizeHandle }
        }
        // Up the left edge, the height of the island it sizes the pet for,
        // and clear of the toolbar's band -- which takes every click in it.
        .overlay(alignment: .bottomLeading) {
            if let onPetHeightChange, !isCollapsed {
                PetSizeSlider(
                    length: max(24, islandHeight - PetSizeSlider.inset * 2),
                    onChange: onPetHeightChange
                )
                .padding(.leading, 6)
                .padding(.bottom, PetSizeSlider.inset)
            }
        }
        // Reported from the island's floor rather than its outline: the pet's
        // world is the part it can stand in, and the raised shoulder is a
        // shape, not a room. A frame taken from the padded box would also let
        // it stand in the gap on either side.
        .overlay(alignment: .bottom) {
            Color.clear
                .frame(height: shownHeight)
                // Measured *inside* the inset, not outside it. A background
                // is sized to the view it is attached to, so reporting after
                // the padding reported the full width and the strip was never
                // actually kept clear -- the pet went on standing on the bar
                // and taking the drags meant for it.
                .background(PaneFrameReporter(onChange: onFrameChange))
                .padding(.leading, onPetHeightChange == nil || isCollapsed ? 0 : PetSizeSlider.footprint)
                .allowsHitTesting(false)
        }
    }

    /// What the island is made of: the app's own ground, or -- for the one
    /// picture background -- the picture, with glass over it.
    ///
    /// The glass is the point of putting a picture here at all. What the pet
    /// stands on has to read as a surface; an illustration under its feet
    /// reads as a poster it is standing in front of. Frosted, and lit along
    /// the top edge, it reads as looking down through water.
    @ViewBuilder
    private func islandFill(_ shape: IslandShape) -> some View {
        if isCollapsed {
            waterBand
                .clipShape(shape)
                // The same two edges the picture gets: the bright one is the
                // light caught on the rim, the darker one under it is the
                // glass having thickness.
                .overlay { shape.strokeBorder(.white.opacity(0.40), lineWidth: 1) }
                .overlay { shape.inset(by: 1).strokeBorder(.black.opacity(0.14), lineWidth: 1) }
        } else if let artwork = TankArtwork.image() {
            // One Canvas, not a stack of Images. Every copy of a 4000px-wide
            // PNG laid out as its own view is rescaled by the render server
            // on each pass, and the island redraws whenever anything in the
            // window moves -- which, with a pet walking about on it, is every
            // frame. Drawn here the picture is resolved once and the tiles
            // are placed by arithmetic instead of by layout.
            Canvas { context, size in
                let image = context.resolve(Image(nsImage: artwork))
                let aspect = TankArtwork.aspect(artwork)
                for tile in Self.tiles(across: size, aspect: aspect) {
                    context.draw(image, in: tile)
                }
            }
            // Frosting, not Liquid Glass. The real material was tried here
            // and it works -- it refracts what is behind it, which is the
            // scene -- but at this size that turns a drawn picture into a
            // smear: the ship and the lighthouse stop being anything. The
            // glass on this island is the light, not the blur.
            .overlay(Rectangle().fill(.ultraThinMaterial).opacity(0.26))
            // What makes it glass rather than a frosted photo: light collects
            // along the top edge, thins out over the first inch, and the
            // bottom sits in the shade of its own thickness.
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.42), location: 0),
                        .init(color: .white.opacity(0.10), location: 0.08),
                        .init(color: .clear, location: 0.42),
                        .init(color: .black.opacity(0.10), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // The glint, up in the corner the light comes from. Soft-edged
            // and wide, so it reads as a sheen across the surface rather than
            // as a lamp drawn on it.
            .overlay(alignment: .topLeading) {
                RadialGradient(
                    colors: [.white.opacity(0.28), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 220
                )
                .allowsHitTesting(false)
            }
            .clipShape(shape)
            // Two edges, not one: the bright one is the light caught on the
            // rim, and the darker one under it is the glass having thickness.
            .overlay { shape.strokeBorder(.white.opacity(0.45), lineWidth: 1) }
            .overlay { shape.inset(by: 1).strokeBorder(.black.opacity(0.12), lineWidth: 1) }
        } else {
            shape.fill(palette.background)
        }
    }

    /// The folded band's water: drawn, not photographed.
    ///
    /// The picture is a scene, and a band is too short to hold one -- every
    /// slice of it is either the busiest strip in the scene (the floor, where
    /// all the drawn things are) or the tops of objects with no bottoms.
    /// Colour has no such problem: what a band wants is depth and movement,
    /// which is light through water, and that is three gradients and some
    /// bubbles rather than a photograph of anything.
    ///
    /// One Canvas rather than stacked views, for the same reason the picture
    /// is one: the island redraws on every frame a pet walks across it.
    private var waterBand: some View {
        let tone = TankToneReader.current()
        return Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            // Down: the surface is lit and the bottom is not. This is the
            // whole of the depth, and everything after it is what moves.
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: tone.depth.map(\.color)),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            // Along: without this the band is one flat blue the width of a
            // window, which reads as a painted bar rather than as water.
            // Kept faint -- it is a current running through the colour, not a
            // second set of stripes.
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: Self.currentWash(tone.currents)),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)
            ))
            for ray in Self.rays(across: size) {
                // Across the shaft, not down it. Down it leaves two hard
                // edges the length of the band, which is a stripe; across it
                // the shaft has no edge at all, which is light.
                context.fill(ray.path, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.16), location: 0.5),
                        .init(color: .white.opacity(0), location: 1),
                    ]),
                    startPoint: ray.across.start,
                    endPoint: ray.across.end
                ))
            }
            for bubble in Self.bubbles(across: size) {
                context.stroke(
                    Path(ellipseIn: bubble),
                    with: .color(.white.opacity(0.35)),
                    lineWidth: 0.75
                )
            }
        }
    }

    /// The picture's own columns, laid across the band's length over the
    /// depth gradient.
    ///
    /// Every other one is dropped to clear rather than running one straight
    /// into the next. Column averages of a scene are close together by
    /// nature, so a gradient through all of them is a wash of one colour;
    /// letting the depth show between them is what makes the band vary
    /// along its length instead.
    static func currentWash(_ currents: [TankSample]) -> [Color] {
        guard !currents.isEmpty else { return [.clear] }
        return currents.enumerated().flatMap { index, sample -> [Color] in
            index.isMultiple(of: 2) ? [sample.color.opacity(Self.currentStrength)] : [.clear]
        }
    }

    /// How much of the picture's own colour is laid over the depth. Enough to
    /// be seen moving along the band, not enough to flatten the depth under
    /// it.
    static let currentStrength: Double = 0.45

    /// One shaft of light, and the line to fade it along.
    struct LightRay: Equatable {
        var path: Path
        /// The two edges of the shaft at half its height. Fading between
        /// these is what stops it being a stripe.
        var across: (start: CGPoint, end: CGPoint)

        static func == (lhs: LightRay, rhs: LightRay) -> Bool {
            lhs.path.description == rhs.path.description
                && lhs.across.start == rhs.across.start
                && lhs.across.end == rhs.across.end
        }
    }

    /// Shafts of light coming down through the water, leaning the way light
    /// does when it enters at an angle.
    ///
    /// Placed by arithmetic rather than by chance: this is redrawn on every
    /// frame, and rays that moved between frames would be a shimmer nobody
    /// asked for. Spaced by `rayPitch` so a wider window gets more of them
    /// rather than wider ones -- wide and far apart, because a shaft of light
    /// is a broad soft thing and a run of narrow ones is hatching.
    static func rays(across size: CGSize) -> [LightRay] {
        guard size.width > 0, size.height > 0 else { return [] }
        let lean = size.height * 0.9
        let count = max(Int(size.width / rayPitch), 1)
        return (0..<count).map { index in
            // Offset so the first shaft is not pinned to the band's left end,
            // and widths alternate: evenly spaced identical shafts are a
            // pattern, and light is not.
            let x = rayPitch * (CGFloat(index) + 0.35)
            let width = index.isMultiple(of: 2) ? rayWidth : rayWidth * 0.6
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + width, y: 0))
            path.addLine(to: CGPoint(x: x + width - lean, y: size.height))
            path.addLine(to: CGPoint(x: x - lean, y: size.height))
            path.closeSubpath()
            let middle = size.height / 2
            return LightRay(
                path: path,
                across: (
                    start: CGPoint(x: x - lean / 2, y: middle),
                    end: CGPoint(x: x + width - lean / 2, y: middle)
                )
            )
        }
    }

    static let rayPitch: CGFloat = 170
    static let rayWidth: CGFloat = 70

    /// A few bubbles, drawn as outlines rather than filled: a filled dot at
    /// this size is a speck of dust, and a ring is a bubble.
    ///
    /// Deterministic for the same reason the rays are, and off the pet's own
    /// line -- they rise through the upper half, where the pet's head is not.
    static func bubbles(across size: CGSize) -> [CGRect] {
        guard size.width > 0, size.height > 0 else { return [] }
        let count = max(Int(size.width / bubblePitch), 1)
        return (0..<count).map { index in
            // Three sizes and three heights, cycling at different rates, so
            // the run does not repeat until it has to.
            let diameter = bubbleSizes[index % bubbleSizes.count]
            let heights: [CGFloat] = [0.18, 0.44, 0.30, 0.58]
            let y = size.height * heights[index % heights.count]
            return CGRect(
                x: bubblePitch * (CGFloat(index) + 0.5) - diameter / 2,
                y: y - diameter / 2,
                width: diameter,
                height: diameter
            )
        }
    }

    static let bubblePitch: CGFloat = 74
    static let bubbleSizes: [CGFloat] = [3, 5, 2, 4, 6]

    /// The picture laid end to end across the island, as many copies as it
    /// takes to fill it.
    ///
    /// Scaled by height, never by width: the whole scene from the water down
    /// to the sand is the picture, and a strip that filled by width showed a
    /// horizontal slice of it -- sand, or open water, depending on how tall
    /// the island was that day. The sides are allowed to run off the end
    /// instead, and the run is centred, because what is worth looking at in a
    /// scene is in the middle of it.
    ///
    /// Copies are drawn as they are, never mirrored: mirroring hides the
    /// seam by turning the scene round, and two lighthouses facing each other
    /// reads as a mistake in a way a repeat does not.
    static func tiles(across size: CGSize, aspect: CGFloat) -> [CGRect] {
        guard size.width > 0, size.height > 0 else { return [] }
        let unit = max(size.height * aspect, 1)
        let copies = max(Int(ceil(size.width / unit)), 1)
        let start = (size.width - unit * CGFloat(copies)) / 2
        return (0..<copies).map { index in
            CGRect(
                x: start + unit * CGFloat(index),
                y: 0,
                // A hair wider than the tile it fills. Two rectangles that
                // merely touch are antialiased against the ground separately,
                // and the join shows as a pale line down the picture at any
                // width where the edge lands between two pixels.
                width: unit + Self.tileOverlap,
                height: size.height
            )
        }
    }

    /// How far each copy reaches under the next one -- see `tiles`.
    static let tileOverlap: CGFloat = 0.5

    /// Where the shoulder begins in the island's own space: just past the
    /// toolbar's last button, with a gap so the two do not touch.
    ///
    /// Off the left edge when this segment starts to the right of the buttons
    /// already -- the editor's segment always does -- which raises the whole
    /// top edge. Off the right edge when nothing has measured the toolbar
    /// yet, which draws the plain rectangle it drew before.
    private func shoulderStart(in proxy: GeometryProxy) -> CGFloat {
        guard let toolbarTrailingX else { return .greatestFiniteMagnitude }
        return toolbarTrailingX + Self.shoulderGap - proxy.frame(in: .global).minX
    }

    /// Drag the bottom edge to make the shelf taller or shorter.
    ///
    /// On the island rather than in Settings: it is a size you judge by
    /// looking at it, and the pet is standing right there while you do.
    private var resizeHandle: some View {
        Capsule()
            .fill(palette.textSecondary.opacity(0.35))
            .frame(width: 34, height: 3)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .center)
            // A grab area taller than the grip itself: a 3pt target is a
            // pixel hunt, and the edge is where the pointer already is.
            .frame(height: 12)
            .contentShape(.rect)
            .onHover { inside in
                // The cursor says which way it moves before the drag starts.
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($heightAtDragStart) { _, start, _ in
                        if start == nil { start = islandHeight }
                    }
                    .onChanged { value in
                        let start = heightAtDragStart ?? islandHeight
                        // Down grows it: the handle is on the bottom edge, so
                        // the edge follows the pointer.
                        storedHeight = Double(
                            min(max(start + value.translation.height, Self.minimumIslandHeight), maximumHeight)
                        )
                    }
            )
            .accessibilityLabel(Strings.text(.islandResize))
            .help(Strings.text(.islandResize))
    }

    /// The island at its full height: a strip across the top of the pane,
    /// with the shoulder drawn outside it.
    private var openIsland: some View {
        island
            .padding(.horizontal, Self.horizontalInset)
            .padding(.vertical, Self.verticalInset)
            // Bottom-aligned and then pulled up by exactly what it grew: the
            // strip keeps the height it always had, and the shoulder is drawn
            // outside it, in the toolbar's band. Laying the shoulder out
            // *inside* the strip would push the conversation down by the
            // height of a decoration.
            .frame(
                height: Self.stripHeight(island: shownHeight) + Self.shoulderRise + Self.baseLift,
                alignment: .bottom
            )
            .padding(.top, -(Self.shoulderRise + Self.baseLift))
    }

    /// The folded island, up in the toolbar's own row beside its buttons.
    ///
    /// Not in a row of its own below them, which is where it landed first --
    /// and where it landed again, briefly, when the overlap below was "fixed"
    /// by giving it a real row. The band is a line the pet walks along, the
    /// toolbar is already a band with nothing in the half past its buttons,
    /// and a second thin row under them is a thicker top than the island it
    /// replaced. It sits on the line the open island's raised shoulder
    /// reaches, so folding and unfolding do not move the top edge of the
    /// pet's world, and it costs the layout nothing.
    ///
    /// Drawn *above* what comes after it, which is the part that was missing.
    /// A view drawn outside its own bounds is still drawn in its sibling
    /// order, and the next sibling here is the whole rest of the window: the
    /// transcript scrolled straight over the band, and with the editor open
    /// the split view's columns -- AppKit views with layers of their own --
    /// cut it off at each column edge. The open island shows neither fault
    /// because it has height: it is what the panes are laid out *under*
    /// rather than something they are laid out over.
    private var foldedBand: some View {
        GeometryReader { proxy in
            island
                .padding(.leading, bandStart(in: proxy))
                .padding(.trailing, Self.horizontalInset)
                .padding(.vertical, Self.verticalInset)
        }
        .frame(height: Self.bandRaise, alignment: .top)
        .padding(.top, -Self.bandRaise)
        // Above the panes rather than behind them -- see the note above. The
        // band's shadow rides up with it, so it fades out over the pane
        // instead of being cut off at the pane's top edge.
        .zIndex(1)
    }

    /// How far above the pane the folded band is drawn.
    ///
    /// The open island's raised shoulder reaches `shoulderRise + baseLift`,
    /// and at a button's height the band sits exactly on that line. Half of
    /// whatever it grows past a button is added, so the extra height is taken
    /// evenly above and below rather than all of it downward -- the band stays
    /// centred on the buttons' own line however tall it gets.
    static var bandRaise: CGFloat {
        shoulderRise + baseLift + (collapsedHeight - toolbarRowHeight) / 2
    }

    /// Where the band begins: past the toolbar's last button, with the same
    /// gap the shoulder leaves. The whole width when nothing has measured the
    /// toolbar yet, which is one layout pass at most.
    private func bandStart(in proxy: GeometryProxy) -> CGFloat {
        guard let toolbarTrailingX else { return Self.horizontalInset }
        return max(
            Self.horizontalInset,
            toolbarTrailingX + Self.shoulderGap - proxy.frame(in: .global).minX
        )
    }

    var body: some View {
        Group {
            if isCollapsed { foldedBand } else { openIsland }
        }
        // Nothing behind the island: it floats in the window's own ground.
        // A backdrop the colour of the picture filled the strip edge to edge
        // and the island lost its outline in it.
        //
        // `.contain`, not a leaf: the decoration inside is not worth
        // announcing piece by piece, but the size slider is a control, and a
        // leaf element would take it out of the tree altogether.
        .accessibilityElement(children: .contain)
    }
}
