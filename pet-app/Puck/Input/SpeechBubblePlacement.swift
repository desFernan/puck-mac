//
//  SpeechBubblePlacement.swift
//  Puck
//
//  Where the pet's speech bubble goes, given where the pet is standing.
//
//  Split out of AppDelegate.anchorBubbleToPet (2026-08-21) because the frame
//  loop now re-runs this every frame -- the bubble used to be placed once at
//  show time and left behind the moment the pet walked off, which a code tour
//  makes constant. A free function over plain geometry so the rule can be
//  tested without a window, a screen or a live pet.
//

import CoreGraphics

enum SpeechBubblePlacement {
    /// Close enough to read as attached, far enough not to cover the pet.
    static let gap: CGFloat = 8
    /// How near the bubble may come to the edge of the usable screen area.
    static let margin: CGFloat = 8

    /// - Parameters:
    ///   - petGroundPoint: the pet's position in AppKit global coordinates
    ///     (bottom-left origin), which is its *feet*.
    ///   - petHeight: hitbox height, so the bubble clears the pet's head.
    ///   - bubbleSize: the bubble's content size, already measured.
    ///   - visibleFrame: the screen area excluding the menu bar and Dock.
    /// - Returns: the bubble window's bottom-left origin.
    static func origin(
        petGroundPoint: CGPoint,
        petHeight: CGFloat,
        bubbleSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        // In AppKit's bottom-left space, up is +y.
        let headY = petGroundPoint.y + petHeight
        var origin = CGPoint(x: petGroundPoint.x - bubbleSize.width / 2, y: headY + gap)

        // Clamped, because a pet in a corner would otherwise put half its
        // speech off the screen. Vertically it flips below the pet instead of
        // being shoved down over its head.
        origin.x = min(max(origin.x, visibleFrame.minX + margin), visibleFrame.maxX - bubbleSize.width - margin)
        if origin.y + bubbleSize.height > visibleFrame.maxY - margin {
            origin.y = petGroundPoint.y - bubbleSize.height - gap
        }
        origin.y = max(origin.y, visibleFrame.minY + margin)
        return origin
    }
}
