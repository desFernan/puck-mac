//
//  SpriteLayerView.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  CALayer-backed NSView replacing PetARView (2026-07-29 2D switch).
//
//  RealityKit's ARView, a full 3D render pipeline, is overkill for a static
//  PNG illustration -- it's also what the alpha-halo mitigation dance in
//  PetARView's history existed for in the first place. Drawing a sprite as a
//  CALayer's `contents` has no such artifact to fight, and there's no GPU 3D
//  pass running every frame just to show a flat image (F1's idle-CPU note).
//
//  isFlipped = true puts this view's coordinate space at top-left origin,
//  Y down -- the same convention GlobalScreenSpace/StateContext already use
//  for every movement calculation, so SpriteAvatar can set screen positions
//  directly with zero conversion (unlike ScreenSpaceMapper's world<->screen
//  mapping, which the removed USDZAvatar needed for RealityKit's Y-up world
//  space).
//

import AppKit
import QuartzCore

final class SpriteLayerView: NSView {
    /// Where the avatar's sprite layer attaches -- analogous to PetARView's
    /// `contentAnchor`, just a CALayer instead of a RealityKit AnchorEntity.
    let contentLayer = CALayer()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(contentLayer)
        applyBackingScale()
    }

    /// AppKit hands the view's *own* backing layer the window's scale; a
    /// hand-added sublayer like contentLayer keeps CALayer's 1.0 default. Left
    /// alone on a 2x display the pet rasterizes at half its physical
    /// resolution and gets upscaled -- soft edges, and motion that stair-steps
    /// along the coarser 1x pixel grid rather than advancing smoothly at the
    /// ~1.5pt per frame the FSM actually moves it.
    ///
    /// Fires on window attach and on every display change (Retina <-> non-Retina,
    /// resolution/scale change), which is also when the value can change.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyBackingScale()
    }

    private func applyBackingScale() {
        // No window yet (constructed before insertion): 2x is the safer guess
        // than 1x -- overshooting only costs memory, undershooting is the
        // visible blur this exists to prevent, and viewDidChangeBackingProperties
        // corrects it the moment the view lands in a real window.
        // The sharpest display, not the window's own factor: one overlay
        // window covers every display (see OverlayWindowController), and
        // AppKit answers `backingScaleFactor` for whichever one holds most of
        // it -- so a pet walking onto a Retina display from a 1x one would
        // rasterize at half resolution and stay that way. Overshooting only
        // costs memory, which is the same trade the 2x guess below makes.
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? window?.backingScaleFactor ?? 2
        contentLayer.contentsScale = scale
        // The avatar's sprite layer is already parented in by the time a
        // display change arrives, so the container alone is not enough.
        contentLayer.sublayers?.forEach { $0.contentsScale = scale }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for SpriteLayerView")
    }
}
