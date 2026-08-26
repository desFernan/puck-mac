//
//  DisplayChangeRelocation.swift
//  Puck
//
//  Where the pet belongs after the displays change.
//
//  A resolution change tears down and rebuilds every overlay window, and the
//  window that comes back is a different size. The areas the pet was walking
//  in were measured against the old one: the floor of the old area is below
//  the new screen's bottom edge, so the pet falls to a line nobody can see
//  and every state that follows keeps it there. From the outside that is a
//  pet that dropped off the bottom of the screen and will not come back.
//
//  Pure, so the rule can be tested without a display to unplug.
//

import CoreGraphics

enum DisplayChangeRelocation {
    /// Where the pet belongs in a freshly measured area.
    ///
    /// Only the desktop is passed in, and that is the whole rule: the
    /// island's rect is measured against the overlay window that has just
    /// been torn down, so after a rebuild it does not describe anywhere on
    /// the new screen. A pet held in it would stand somewhere the island is
    /// not drawn. It comes out instead, and the client's next report -- which
    /// a display change always produces, see PaneFrameReporter -- brings it
    /// home to a rect measured against the window that exists now.
    ///
    /// The pet keeps its place rather than being sent back to a spawn point:
    /// the display changed, the pet did not, and a teleport across the screen
    /// reads as a glitch. Containing it is enough to bring it back on screen,
    /// because the only reason it was off screen is that the floor moved.
    ///
    /// ScreenBounds.contain is horizontal only, and deliberately so: which
    /// surface a pet comes down on is the falling states' business, not a
    /// screen edge's. Here there is nothing to fall onto -- the floor it was
    /// standing on stopped existing between one frame and the next -- so the
    /// vertical limit is applied too. Feet no lower than the floor, head no
    /// higher than the ceiling, and the floor wins when the area is shorter
    /// than the pet.
    static func contained(_ position: CGPoint, visualBounds: CGRect, in area: CGRect) -> CGPoint {
        let horizontal = ScreenBounds.contain(position, visualBounds: visualBounds, in: area)
        // Y grows downward: the outline reaches up from the feet, so its minY
        // is negative and the highest the feet may be is that far below the
        // area's top edge.
        let ceiling = area.minY - visualBounds.minY
        let floor = area.maxY
        return CGPoint(x: horizontal.x, y: min(max(position.y, min(ceiling, floor)), floor))
    }

    /// Where a pet that was standing on something belongs after the change.
    ///
    /// `contained` alone is only half the answer, and which half depends on
    /// which way the screen went. A shorter screen puts its floor *above* the
    /// pet, so containing it brings it down onto the new floor and that is the
    /// whole move. A taller one puts the floor below: the pet is already
    /// inside the new area the moment the area grows, containment finds
    /// nothing to do, and the pet is left standing on a line that is now
    /// halfway up the screen with nothing under it.
    ///
    /// Which is why the surface is asked for rather than the area's floor:
    /// what the pet stands on is a window top as often as it is the bottom of
    /// the screen (see LandingSurfaceResolver), and both were re-measured
    /// along with everything else.
    ///
    /// Only for a pet that stands on the ground. One hanging from the ceiling
    /// or clinging to a window's side is holding something that is not below
    /// it, and putting its feet on the floor would drop it across the screen.
    static func standing(
        _ position: CGPoint,
        visualBounds: CGRect,
        in area: CGRect,
        onSurfaceUnder surfaceY: (CGPoint) -> CGFloat
    ) -> CGPoint {
        let contained = contained(position, visualBounds: visualBounds, in: area)
        return CGPoint(x: contained.x, y: surfaceY(contained))
    }
}
