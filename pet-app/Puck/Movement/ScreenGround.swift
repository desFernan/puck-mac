//
//  ScreenGround.swift
//  Puck
//
//  Which display the pet is standing on, and what to do when it is standing
//  on none of them.
//
//  With one display the pet's world is a rectangle and every point inside it
//  is on screen. With two it is a *list* of rectangles, and the box drawn
//  around that list is not the world: displays of different heights, or one
//  sitting above the other, leave space inside that box that belongs to no
//  display at all. A pet left there is not off to one side -- it is nowhere,
//  invisible, and no state will bring it back on its own.
//
//  So the rules that need the actual displays live here, and they are all
//  written against the pet's outline rather than the single point at its
//  feet: half a pet hanging over the edge is as much "off the display" as
//  all of it.
//
//  Pure, so a two-monitor arrangement can be tested without a second monitor.
//

import CoreGraphics

enum ScreenGround {
    /// The box around every area. What horizontal containment and wander
    /// draws use, and deliberately NOT what "is the pet on a display" uses.
    static func union(_ areas: [CGRect]) -> CGRect {
        let union = areas.reduce(CGRect.null) { $0.union($1) }
        return union.isNull ? .zero : union
    }

    /// Is there a display below this point to come down on? Above is not
    /// looked at: a pet thrown over the top of its own screen is still on
    /// that screen, and it comes back down onto it.
    static func hasGround(under point: CGPoint, in areas: [CGRect]) -> Bool {
        areas.contains { $0.minX <= point.x && point.x <= $0.maxX && $0.maxY >= point.y }
    }

    /// The same question asked of the pet's whole width. Standing with one
    /// foot's worth of artwork over the gap between two displays is the
    /// visible half of the same bug.
    static func artworkHasGround(at position: CGPoint, visualBounds: CGRect, in areas: [CGRect]) -> Bool {
        hasGround(under: CGPoint(x: position.x + visualBounds.minX, y: position.y), in: areas)
            && hasGround(under: CGPoint(x: position.x + visualBounds.maxX, y: position.y), in: areas)
    }

    /// The area this point is in, or -- since a point between two displays is
    /// in none of them -- the nearest one. Nil only when there are no areas
    /// at all, which is a pet with nowhere to be.
    static func area(at point: CGPoint, in areas: [CGRect]) -> CGRect? {
        // CGRect.contains excludes the maxY edge, which is exactly where a
        // standing pet's feet are, so the nearest-area fallback is the
        // ordinary path rather than the exception. It answers the same area
        // at distance zero.
        areas.first { $0.contains(point) } ?? nearestArea(to: point, in: areas)
    }

    /// Where a pet found standing in the void belongs: on the nearest
    /// display, with its whole outline on it.
    static func standable(_ position: CGPoint, visualBounds: CGRect, in areas: [CGRect]) -> CGPoint {
        guard let area = nearestArea(to: position, in: areas) else { return position }
        // The same "put the pet back inside this rectangle" rule a display
        // change already uses -- there is one definition of it, not two.
        return DisplayChangeRelocation.contained(position, visualBounds: visualBounds, in: area)
    }

    /// Where the pet would stand after climbing the ledge in `directionX`,
    /// or nil if there is no display that way with a higher floor.
    ///
    /// Displays with different floor heights are a one-way trip otherwise:
    /// walking onto the lower one is a fall, and there is nothing in a walk
    /// that goes back up. The pet ends up living on the short monitor.
    static func ledge(
        beyond position: CGPoint,
        directionX: CGFloat,
        visualBounds: CGRect,
        in areas: [CGRect]
    ) -> CGPoint? {
        let ahead = areas.filter { area in
            // Y grows downward: a floor "higher up" is a smaller maxY.
            area.maxY < position.y && (directionX > 0 ? area.minX >= position.x : area.maxX <= position.x)
        }
        guard let area = ahead.min(by: { gap(from: position.x, to: $0, directionX: directionX) < gap(from: position.x, to: $1, directionX: directionX) }) else {
            return nil
        }
        // Standing on the ledge means the whole drawing is on the display
        // above, not just the foot that reached it.
        let standing = ScreenBounds.contain(
            CGPoint(x: position.x, y: area.maxY),
            visualBounds: visualBounds,
            in: area
        )
        return CGPoint(x: standing.x, y: area.maxY)
    }

    private static func gap(from x: CGFloat, to area: CGRect, directionX: CGFloat) -> CGFloat {
        directionX > 0 ? area.minX - x : x - area.maxX
    }

    private static func nearestArea(to point: CGPoint, in areas: [CGRect]) -> CGRect? {
        areas.min { squaredDistance(from: point, to: $0) < squaredDistance(from: point, to: $1) }
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
