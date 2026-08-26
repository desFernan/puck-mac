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

    /// Whether the island is folded down to its band. Remembered, because it
    /// is a choice about how much of the window the pet is allowed rather
    /// than a thing you do to look at something once.
    @AppStorage(PetTankView.collapsedStorageKey) private var isCollapsed = false

    /// Read here as well as in the slider, so folding the island back open
    /// can hand the pet its size back without waiting for the slider to be
    /// rebuilt and say so itself.
    @AppStorage(PetTankView.petHeightStorageKey) private var storedPetHeight = PetTankView.defaultPetHeight

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
    static let islandHeight: CGFloat = 90

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
    /// pet walking along it. Chosen against the pet rather than by eye -- it
    /// has to hold `collapsedPetHeight` with air above the pet's head, and
    /// pet-app refuses a tank shorter than the pet standing in it.
    static let collapsedHeight: CGFloat = 26

    /// How tall the pet stands on the band. Small enough that the band reads
    /// as a line the pet walks along rather than as a short island.
    static let collapsedPetHeight: Double = 16

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
        // At the far end, where it is out of the pet's way and does not move
        // when the island is folded -- the one control that has to be
        // reachable in both shapes.
        .overlay(alignment: .bottomTrailing) { foldToggle }
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
                // The same reasoning as the slider's: the pet is drawn by the
                // window above this one, so a pet standing on the fold button
                // takes the clicks meant for it.
                .padding(.trailing, Self.foldFootprint)
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
        if let artwork = TankArtwork.image() {
            // One Canvas, not a stack of Images. Every copy of a 4000px-wide
            // PNG laid out as its own view is rescaled by the render server
            // on each pass, and the island redraws whenever anything in the
            // window moves -- which, with a pet walking about on it, is every
            // frame. Drawn here the picture is resolved once and the tiles
            // are placed by arithmetic instead of by layout.
            Canvas { context, size in
                let image = context.resolve(Image(nsImage: artwork))
                let aspect = TankArtwork.aspect(artwork)
                if isCollapsed {
                    context.draw(image, in: Self.band(across: size, aspect: aspect))
                } else {
                    for tile in Self.tiles(across: size, aspect: aspect) {
                        context.draw(image, in: tile)
                    }
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

    /// The picture in a folded island: one copy, as wide as the band, with
    /// the seabed at the bottom of it showing through.
    ///
    /// The opposite rule to `tiles`, for the opposite reason. Scaling by
    /// height is what keeps the whole scene in frame, and at a band's height
    /// that costs a copy of the scene every couple of hundred points -- nine
    /// lighthouses across a window, which reads as a patterned rule rather
    /// than as the pet's water. Folded, a slice is the honest thing to show,
    /// and the slice worth showing is the one the pet is standing on.
    static func band(across size: CGSize, aspect: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        // As tall as one copy would be at this width -- taller than the band,
        // which is the point: what hangs off the top is the water above the
        // sand.
        let drawn = size.width / aspect
        return CGRect(x: 0, y: size.height - drawn, width: size.width, height: drawn)
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

    /// How wide the button and its air are, across the island. The pet is
    /// kept out of this strip the same way it is kept out of the slider's.
    static let foldFootprint: CGFloat = foldButtonSize + 12

    static let foldButtonSize: CGFloat = 18

    /// Folds the island down to a band, and back.
    ///
    /// The pet's size goes with it, because it has to: pet-app refuses a tank
    /// shorter than the pet standing in it, and a refusal is silent from the
    /// outside -- the pet just stays on the desktop and the button looks
    /// broken. Folding therefore hands over `collapsedPetHeight`, and
    /// unfolding hands back the size the slider had, clamped to the island it
    /// is coming back to.
    private var foldToggle: some View {
        Button {
            isCollapsed.toggle()
            onPetHeightChange?(CGFloat(petHeightForCurrentShape))
        } label: {
            Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: Self.foldButtonSize, height: Self.foldButtonSize)
                .background(Circle().fill(palette.background.opacity(0.55)))
                .overlay(Circle().strokeBorder(palette.surfaceBorder.opacity(0.75), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
        // Centred in the band when folded, and level with the resize grip
        // when not -- both times, on the island rather than over its edge.
        .padding(.bottom, isCollapsed ? (Self.collapsedHeight - Self.foldButtonSize) / 2 : PetSizeSlider.inset)
        .accessibilityLabel(Strings.text(isCollapsed ? .islandUnfold : .islandFold))
        .help(Strings.text(isCollapsed ? .islandUnfold : .islandFold))
    }

    /// The pet's height for the shape the island is in now.
    private var petHeightForCurrentShape: Double {
        guard !isCollapsed else { return Self.collapsedPetHeight }
        // The same ceiling the slider draws itself against, so unfolding
        // cannot ask for a pet the island it is opening to cannot hold.
        return min(storedPetHeight, Double(islandHeight) - Self.petHeadroom)
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

    var body: some View {
        island
            .padding(.horizontal, Self.horizontalInset)
            .padding(.vertical, Self.verticalInset)
            // Bottom-aligned and then pulled up by exactly what it grew: the
            // strip keeps the height it always had, and the shoulder is drawn
            // outside it, in the toolbar's band. Laying the shoulder out
            // *inside* the strip would push the conversation down by the
            // height of a decoration.
            .frame(
                height: Self.stripHeight(island: shownHeight) + shownRise + shownLift,
                alignment: .bottom
            )
            .padding(.top, -(shownRise + shownLift))
        // Nothing behind the island: it floats in the window's own ground.
        // A backdrop the colour of the picture filled the strip edge to edge
        // and the island lost its outline in it.
        //
        // `.contain`, not a leaf: the decoration inside is not worth
        // announcing piece by piece, but the fold button and the size slider
        // are controls, and a leaf element would take them out of the tree
        // altogether. No label of its own -- a container named after one of
        // the two things inside it is worse than an unnamed group.
        .accessibilityElement(children: .contain)
    }
}
