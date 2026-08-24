//
//  CALayer+ImplicitAnimations.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Turns off Core Animation's implicit animations for layers the FSM drives
//  by hand, every frame.
//
//  A CALayer that is NOT a view's backing layer animates `position`,
//  `transform` and `contents` implicitly: each assignment starts a 0.25s
//  ease-in-ease-out animation. Assigning 60 times a second means what you see
//  is never the position the FSM computed -- it is a presentation value
//  perpetually easing toward a target that moved again a frame ago, so the
//  sprite lags behind, overshoots on direction changes, and slides after the
//  pet has stopped -- the overall movement read as unnatural and janky
//  rather than smooth.
//
//  This masqueraded as physics bugs for a long time, because the symptoms
//  land on whatever motion is being looked at: a drag that trails the cursor
//  no matter how the follow is tuned, a fall that seems to slur into the
//  floor. Tuning those numbers could never fix it -- the numbers were right
//  and the renderer was smoothing them.
//
//  Hand-driven layers want no interpolation of their own: the per-frame
//  update IS the animation.
//

import QuartzCore

extension CALayer {
    /// The properties Puck assigns every frame. NSNull as an action is
    /// Core Animation's documented "do nothing" -- it doesn't merely shorten
    /// the implicit animation, it stops one from being created at all.
    private static let handDrivenProperties = [
        "position", "transform", "contents", "bounds", "hidden", "opacity", "backgroundColor",
    ]

    /// Call once at construction for any layer the frame loop mutates.
    func disableImplicitAnimations() {
        var actions: [String: CAAction] = [:]
        for property in Self.handDrivenProperties {
            actions[property] = NSNull()
        }
        self.actions = actions
    }
}
