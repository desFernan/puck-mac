//
//  SpriteAvatar.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  2026-07-29 2D switch: primary AvatarPlayable implementation. Loads one PNG
//  per clip (same file-stem manifest convention usdz used) and shows it on a
//  CALayer parented into SpriteLayerView's contentLayer.
//
//  No mesh/animation to manage -- "playing a clip" is just swapping which
//  cached CGImage the layer shows. Whatever motion the pet has beyond a
//  static image comes from updateBounce (BouncePreset), not from this file.
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore

final class SpriteAvatar: AvatarPlayable {
    private let avatarDirectory: URL
    private let loadResult: AvatarLoadResult
    /// Unscaled manifest.hitbox -- updateScale recomputes bounds from this
    /// every time rather than the layer's current (already-scaled) bounds,
    /// so repeated Settings slider changes don't compound.
    private let hitbox: AvatarManifest.Hitbox
    private var isMirrored = false
    private var isOutlined = false
    /// What is on screen, so a change to how sprites are drawn can put the
    /// same pose back rather than waiting for the pet to move.
    private var currentClip: String?
    private var poseAdjustments = AvatarPoseAdjustments()
    let spriteLayer = CALayer()
    /// A flat colour washed over the character while a preset asks for a tint
    /// (the rainbow flips). Masked by the sprite itself, so it colours the
    /// artwork and not the transparent box around it. Hidden -- and costing
    /// nothing -- the rest of the time.
    private let tintLayer = CALayer()
    private let tintMaskLayer = CALayer()
    private var loadedImages: [String: CGImage] = [:]
    /// The showing image's silhouette, for hit testing. Built once per image
    /// alongside the outline measurement.
    private var hitMask: AlphaHitMask?
    /// The showing image's opaque pixel box and its size, measured once when
    /// the image is swapped in. Only the *scan* is cached: mapping it into
    /// layer coordinates is a handful of arithmetic and is redone on read, so
    /// resizing the layer (Settings' size slider) needs no invalidation.
    private var currentMeasurement: (opaquePixels: CGRect, imagePixelSize: CGSize)?
    private var facing: AvatarFacing = .right
    /// When the current left/right turn began, or nil if the pet has never
    /// turned. See FlipAnimation.
    private var flipStartedAt: TimeInterval?
    /// The angle the current turn started from. Where it is heading is
    /// always the angle of `facing`, and how long it takes always follows
    /// from the two, so neither is stored.
    private var flipFromAngle: CGFloat = 0
    /// Injectable so the turn can be tested without waiting in real time.
    private let now: () -> TimeInterval
    private var currentBounce = BounceTransform.identity
    private var isUpsideDown = false
    /// The last logical position passed to setScreenPosition, so
    /// setUpsideDown can immediately recompute the rendered offset for it --
    /// see setUpsideDown's doc comment.
    private var lastPosition: CGPoint = .zero
    /// When the current jump flourish began, or nil if none is playing --
    /// see triggerJump's doc comment.
    private var jumpStartedAt: TimeInterval?

    init(
        avatarDirectory: URL,
        loadResult: AvatarLoadResult,
        parent: CALayer,
        now: @escaping () -> TimeInterval = { CACurrentMediaTime() }
    ) {
        self.avatarDirectory = avatarDirectory
        self.loadResult = loadResult
        self.hitbox = loadResult.manifest.hitbox
        self.now = now

        let scale = loadResult.manifest.scale
        spriteLayer.bounds = CGRect(origin: .zero, size: Self.drawnSize(hitbox: hitbox, scale: scale))
        // SpriteVisualBounds re-derives this exact gravity to work out where
        // the artwork sits inside the layer -- changing it here without
        // changing it there silently makes every screen-edge limit wrong.
        spriteLayer.contentsGravity = .resizeAspect
        // A hand-made CALayer defaults to contentsScale 1.0 no matter which
        // display it ends up on -- only a view's own backing layer gets the
        // window's scale for free. At 1.0 on a 2x screen the sprite rasterizes
        // at half its physical resolution and is upscaled: soft, and its
        // bitmap snaps to the coarser 1x pixel grid, so a walk advancing
        // ~1.5pt per frame renders as stair-stepped jitter. SpriteLayerView
        // keeps the parent's value current across display changes.
        spriteLayer.contentsScale = parent.contentsScale
        // Mipmapped downscaling. Avatar artwork is drawn at a few thousand
        // pixels and shown at a hundred or so, and Core Animation's default
        // filter samples that without mipmaps: every fine line in it lands on
        // or between pixels depending on where the pet is standing, which is
        // the stair-stepping along its outline. Trilinear costs one extra
        // pyramid per image and takes it out.
        spriteLayer.minificationFilter = .trilinear
        // The pet is flipped, squashed and stretched every frame. Without
        // this the edges of those transformed layers are cut on the pixel
        // grid rather than blended into it.
        spriteLayer.allowsEdgeAntialiasing = true
        // The FSM drives this layer every frame; Core Animation must not
        // interpolate between those frames on top of it.
        spriteLayer.disableImplicitAnimations()

        // A sublayer, so it inherits every transform applied to the sprite --
        // the tint flips and squashes with the character rather than sitting
        // still behind it.
        tintLayer.frame = spriteLayer.bounds
        tintLayer.isHidden = true
        tintLayer.disableImplicitAnimations()
        tintMaskLayer.frame = spriteLayer.bounds
        tintMaskLayer.contentsGravity = spriteLayer.contentsGravity
        tintMaskLayer.contentsScale = spriteLayer.contentsScale
        tintMaskLayer.minificationFilter = .trilinear
        tintMaskLayer.disableImplicitAnimations()
        tintLayer.mask = tintMaskLayer
        spriteLayer.addSublayer(tintLayer)

        parent.addSublayer(spriteLayer)
    }

    func play(clip: String, loop: Bool) {
        currentClip = clip
        guard let fileName = AvatarLoader.resolvedClipName(for: clip, in: loadResult) else { return }
        // A load failure (missing/corrupt file) leaves whatever was already
        // showing rather than blanking the pet -- same "don't strand the
        // caller with nothing" reasoning USDZAvatar's animation-less-file path uses.
        guard let image = loadedImage(named: fileName) else { return }
        show(image)
    }

    func stop() {
        // Nothing to stop -- a static image has no playback state of its own.
    }

    func setScreenPosition(_ position: CGPoint) {
        // SpriteLayerView is isFlipped (top-left origin, Y down), the same
        // convention GlobalScreenSpace/StateContext already use -- unlike
        // USDZAvatar/ScreenSpaceMapper, no world<->screen conversion needed.
        //
        // `position` is the character's ground/feet point -- the one
        // convention every other piece of the FSM already assumes (WalkState's
        // targets sit at roamableArea.maxY, LandingSurfaceResolver returns a
        // surface's top edge, USDZAvatar's rig has its root bone at the feet).
        // CALayer's own `position` is its *center*, so without this offset the
        // sprite floats half its height above wherever the FSM thinks it's
        // standing -- visible as the pet hanging in empty space instead of
        // standing on the Dock/window edge it just "landed" on.
        //
        // CeilingState instead passes roamableArea.minY (the ceiling line) as
        // an attachment point the character hangs FROM, with its body
        // extending downward into the room, not upward off the top of the
        // screen -- and since setUpsideDown's flip renders the art's feet at
        // the layer's top edge, that attachment point is the layer's top
        // edge too. Getting this offset's sign wrong doesn't just look
        // wrong, it pushes the whole sprite off the top of the screen.
        lastPosition = position
        let verticalOffset = isUpsideDown ? spriteLayer.bounds.height / 2 : -spriteLayer.bounds.height / 2
        spriteLayer.position = CGPoint(x: position.x, y: position.y + verticalOffset + currentJumpOffset)
    }

    /// A short visual hop -- F3 (agent_done, code_editor
    /// detail.path changes). Purely a render-time offset on top of whatever
    /// the FSM's real `position` is, recomputed every frame via updateBounce
    /// (already called unconditionally each frame) rather than baked into
    /// the affine transform -- translatedBy inside applyTransform would
    /// rotate along with climb's quarter-turn or any future rotation preset,
    /// which a vertical screen-space hop must not do.
    func triggerJump() {
        jumpStartedAt = now()
    }

    private var currentJumpOffset: CGFloat {
        guard let jumpStartedAt else { return 0 }
        return JumpFlourish.offset(elapsed: now() - jumpStartedAt)
    }

    /// Mirrors the artwork, on top of whichever way the pet is facing.
    ///
    /// Multiplied into the same scaleX the turn animation uses rather than
    /// swapping what `left` and `right` mean: the pet still turns to face
    /// where it is going, and this only decides which way round the drawing
    /// is while it does.
    /// Draws a white edge around the character, sticker-fashion.
    ///
    /// Clears the cache, because the outline is baked into the images rather
    /// than drawn over them -- see SpriteOutline for why. Turning it on and
    /// off re-decodes a package's sprites, which is a cost paid once by
    /// somebody looking at a switch.
    func setOutlined(_ isOutlined: Bool) {
        guard isOutlined != self.isOutlined else { return }
        self.isOutlined = isOutlined
        loadedImages.removeAll()
        if let currentClip { play(clip: currentClip, loop: true) }
    }

    /// Per-pose corrections for artwork drawn the other way round.
    func setPoseAdjustments(_ adjustments: AvatarPoseAdjustments) {
        guard adjustments != poseAdjustments else { return }
        poseAdjustments = adjustments
        applyTransform()
    }

    /// Which of the poses the pet is in right now, so the right correction is
    /// applied. Worked out from what is already known rather than pushed in
    /// by the movement states: a pose is a clip and a direction, and both are
    /// already here.
    private var currentPose: AvatarPose? {
        // Which way along the ceiling, for the reason the walls are two
        // poses: upside down, a character drawn to face one way is wrong the
        // other way in a way one correction cannot fix.
        if isUpsideDown {
            return facing == .left ? .onTheCeilingFacingLeft : .onTheCeilingFacingRight
        }
        // Which wall, not just "climbing": the pet keeps its facing all the
        // way up, so that is which side it is on.
        if currentClip == "climb" {
            return facing == .left ? .climbingLeftWall : .climbingRightWall
        }
        guard currentClip == "walk" else { return nil }
        return facing == .left ? .walkingLeft : .walkingRight
    }

    func setMirrored(_ isMirrored: Bool) {
        guard isMirrored != self.isMirrored else { return }
        self.isMirrored = isMirrored
        applyTransform()
    }

    func setFacing(_ facing: AvatarFacing) {
        guard facing != self.facing else { return }
        // Turning again mid-turn continues from the angle currently on
        // screen rather than snapping back to full width and starting over.
        flipFromAngle = currentFlipAngle
        flipStartedAt = now()
        self.facing = facing
        applyTransform()
    }

    /// F3 wall-climbing: rotates the sprite 90deg while the "climb" clip is
    /// playing -- ClimbState (a window's side) and ClimbToCeilingState (open
    /// air, toward the ceiling) both use it, so both get the rotation for
    /// free with no per-state wiring. The rotation fact itself lives on
    /// BounceTransform (BouncePreset.preset(for:)'s own dispatch), not
    /// re-derived here from the raw clip string.
    func updateBounce(clip: String, elapsed: TimeInterval, intensity: Double) {
        // Recorded here as well as in `play`. This arrives every frame and
        // `play` only on a change, and which pose the pet is in decides how
        // the sprite is turned -- so taking it from `play` alone made the
        // turn depend on two callers agreeing about the clip rather than on
        // the one that is always current.
        currentClip = clip
        currentBounce = BouncePreset.preset(for: clip).transform(elapsed: elapsed, intensity: intensity)
        applyTransform()
        // Called every frame regardless of state, same as applyTransform
        // above -- the natural per-frame hook to keep an in-progress jump
        // animating even while `position` itself doesn't change (Type,
        // Point, ...).
        setScreenPosition(lastPosition)
    }

    /// F3 ceiling-crawling. A Y-only flip (not a 180deg rotation) so the
    /// walking-direction/facing semantics stay correct while upside-down --
    /// a full rotation would also reverse the apparent direction of motion.
    ///
    /// Also immediately re-applies setScreenPosition's offset for the cached
    /// last position, not just the transform -- otherwise there's a one-frame
    /// window (right when CeilingState hands off to FallState, which resets
    /// isUpsideDown before its own first position update runs) where the
    /// flip is already correct but the position is still offset for the OLD
    /// orientation, a visible pop that reads as a stutter/teleport.
    func setUpsideDown(_ isUpsideDown: Bool) {
        guard isUpsideDown != self.isUpsideDown else { return }
        self.isUpsideDown = isUpsideDown
        applyTransform()
        setScreenPosition(lastPosition)
    }

    /// Settings' size slider. Recomputes from the original manifest hitbox
    /// (not the layer's current bounds) so this stays idempotent under
    /// repeated calls. Self-heals the ground-point offset via
    /// setScreenPosition(lastPosition) -- same pattern setUpsideDown uses --
    /// rather than leaving that an implicit caller contract (found via
    /// review: a call site that forgot to re-push the position would leave
    /// the sprite floating at the stale offset).
    func updateScale(_ scale: Double) {
        spriteLayer.bounds = CGRect(origin: .zero, size: Self.drawnSize(hitbox: hitbox, scale: scale))
        tintLayer.frame = spriteLayer.bounds
        tintMaskLayer.frame = spriteLayer.bounds
        setScreenPosition(lastPosition)
    }

    /// The hitbox is a shape, not a size: every avatar is drawn at the same
    /// standard height and the manifest's numbers only decide the aspect
    /// ratio. See AvatarStandardSize.
    private static func drawnSize(hitbox: AvatarManifest.Hitbox, scale: Double) -> CGSize {
        AvatarStandardSize.size(
            hitbox: CGSize(width: hitbox.width, height: hitbox.height),
            scale: CGFloat(scale)
        )
    }

    /// Settings' emotion mapping / EventRouter-driven mood swap. Silent
    /// no-op for an unmapped key or a missing file -- same policy as clips'
    /// idle fallback and the sounds table's "unmapped = silence."
    func showEmotion(_ emotion: String) {
        guard
            case .name(let fileName)? = loadResult.manifest.emotions?[emotion],
            let image = loadedImage(named: fileName)
        else {
            return
        }
        show(image)
    }

    /// OverlayWindowController tears down and recreates every window+SpriteLayerView
    /// on a real display change (monitor plug/unplug, resolution change) --
    /// callers must re-parent to the rebuilt view's contentLayer or the
    /// sprite is left attached to an orphaned layer (mirrors USDZAvatar.reparent).
    func reparent(to newParent: CALayer) {
        spriteLayer.removeFromSuperlayer()
        // Reparenting is exactly when the pet can cross between a 1x and a 2x
        // display (the rebuild happens *because* the display setup changed),
        // so the rasterization scale has to follow it to the new screen. The
        // tint mask rasterizes the same artwork and needs the same scale, or
        // the colour sits slightly off the character's outline.
        spriteLayer.contentsScale = newParent.contentsScale
        tintMaskLayer.contentsScale = newParent.contentsScale
        newParent.addSublayer(spriteLayer)
    }

    /// The turn angle to draw at right now: the settled angle for the current
    /// facing, or a partway one while a turn is playing.
    private var currentFlipAngle: CGFloat {
        let target = FlipAnimation.angle(facing: facing)
        guard let flipStartedAt else { return target }
        return FlipAnimation.angle(
            elapsed: now() - flipStartedAt,
            from: flipFromAngle,
            to: target,
            duration: FlipAnimation.duration(from: flipFromAngle, to: target)
        )
    }

    private func applyTransform() {
        // The orientation the pose is in before anything moves, worked out in
        // the one place the settings window's preview reads it from too --
        // see AvatarPoseOrientation for what went wrong when there were two.
        let pose = currentPose
        let orientation = AvatarPoseOrientation.of(
            pose,
            adjustment: pose.map { poseAdjustments[$0] } ?? .none,
            isMirrored: isMirrored
        )
        // How far through the turn the pet is, which the pose cannot know:
        // facing is a fact, and this is the animation between two of them.
        let turning = FlipAnimation.horizontalScale(atAngle: currentFlipAngle)
            * (pose?.facing == .left ? -1 : 1)
        var transform = CGAffineTransform(
            scaleX: CGFloat(currentBounce.scaleX) * orientation.scaleX * turning,
            y: CGFloat(currentBounce.scaleY) * orientation.scaleY
        )
        transform = transform.rotated(by: orientation.rotation)
        // After the climb turn, so the preset's rocking is relative to
        // however the sprite is already oriented rather than to the screen --
        // a climbing pet leans off its own upright, not off vertical.
        transform = transform.rotated(by: CGFloat(currentBounce.rotation))
        applyTint(currentBounce.tintHue)
        spriteLayer.setAffineTransform(transform)
    }

    /// Measured from whichever clip is currently showing, so a wider pose
    /// gives a wider outline. Falls back to the layer box (the pre-existing
    /// behaviour) when nothing has been drawn yet or the image is blank.
    var visualBounds: CGRect {
        guard let currentMeasurement else { return layerBox }
        return SpriteVisualBounds.relativeToGroundPoint(
            opaquePixels: currentMeasurement.opaquePixels,
            imagePixelSize: currentMeasurement.imagePixelSize,
            layerSize: spriteLayer.bounds.size
        )
    }

    /// The whole layer, ground-point relative -- what the outline was before
    /// it was measured from the artwork.
    private var layerBox: CGRect {
        let size = spriteLayer.bounds.size
        return CGRect(x: -size.width / 2, y: -size.height, width: size.width, height: size.height)
    }

    /// The single place the layer's image changes, so the outline is measured
    /// exactly once per swap instead of being recomputed by the frame loop.
    private func show(_ image: CGImage) {
        spriteLayer.contents = image
        // The mask has to follow the artwork, or a tint applied while one
        // clip is showing would keep the previous clip's silhouette.
        tintMaskLayer.contents = image
        measureVisualBounds(of: image)
    }

    /// `hue` in 0...1, or nil for the artwork's own colours.
    private func applyTint(_ hue: Double?) {
        guard let hue else {
            tintLayer.isHidden = true
            return
        }
        tintLayer.isHidden = false
        tintLayer.backgroundColor = NSColor(
            hue: CGFloat(hue),
            saturation: Self.tintSaturation,
            brightness: 1,
            alpha: Self.tintAlpha
        ).cgColor
    }

    /// Strong enough to read as "the pet turned red", weak enough that the
    /// face still shows through -- a fully opaque wash turns it into a
    /// silhouette and loses the expression the flips are celebrating.
    private static let tintSaturation: CGFloat = 0.9
    private static let tintAlpha: CGFloat = 0.55

    /// The alpha scan -- the expensive half. Kept off the frame loop by
    /// running only here, on the image swap.
    private func measureVisualBounds(of image: CGImage) {
        hitMask = AlphaHitMask(image: image)
        guard let opaque = OpaquePixelBounds.of(image) else {
            currentMeasurement = nil
            return
        }
        currentMeasurement = (opaque, CGSize(width: image.width, height: image.height))
    }

    func setAlpha(_ alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setCompletionBlock(completion)
        spriteLayer.opacity = Float(alpha)
        CATransaction.commit()
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        guard let hitMask, let currentMeasurement else {
            // No artwork measured yet: the layer box is the best answer there is.
            return visualBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }

        let size = spriteLayer.bounds.size
        // `point` is relative to the ground point; the layer's own origin sits
        // half a width to the left of it and a full height above -- or below,
        // hanging from a ceiling, where setScreenPosition flips the offset.
        let layerPoint = isUpsideDown
            ? CGPoint(x: point.x + size.width / 2, y: point.y)
            : CGPoint(x: point.x + size.width / 2, y: point.y + size.height)

        guard let unit = SpriteHitTest.unitPoint(
            forLayerPoint: layerPoint,
            transform: spriteLayer.affineTransform(),
            layerSize: size,
            imagePixelSize: currentMeasurement.imagePixelSize
        ) else { return false }

        // Tolerance is in points; the mask works in fractions of the artwork.
        let fit = min(size.width / currentMeasurement.imagePixelSize.width,
                      size.height / currentMeasurement.imagePixelSize.height)
        let drawnHeight = currentMeasurement.imagePixelSize.height * fit
        return hitMask.isDrawn(atUnit: unit, tolerance: drawnHeight > 0 ? tolerance / drawnHeight : 0)
    }

    /// Only caches on a successful load -- caching a failure would make a
    /// transient error (e.g. file briefly locked during an avatar import)
    /// permanent for the rest of the process, mirroring USDZAvatar's
    /// loadedEntity(named:) precedent.
    private func loadedImage(named fileName: String) -> CGImage? {
        if let cached = loadedImages[fileName] {
            return cached
        }
        guard let url = AvatarPackagePath.fileURL(in: avatarDirectory, relativePath: "\(fileName).png") else {
            AppLogger.shared.log(.error, "Avatar sprite name points outside the package: \(fileName)")
            return nil
        }
        guard
            let dataProvider = CGDataProvider(url: url as CFURL),
            let image = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            AppLogger.shared.log(.error, "Failed to load avatar sprite at \(url.path)")
            return nil
        }
        let drawn = isOutlined ? SpriteOutline.outlined(image) : image
        loadedImages[fileName] = drawn
        return drawn
    }
}
