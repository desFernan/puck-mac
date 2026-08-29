//
//  AppDelegate+PetInteraction.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Click/drag gestures on the pet and toys, head petting, and the shared
//  global-to-window-local coordinate conversion.
//

import AppKit
import CoreGraphics
import QuartzCore

extension AppDelegate {
    // MARK: - Pet interaction (F1/F3)

    /// Clicking the pet makes it react; dragging carries it and dropping it
    /// lets it fall. Gesture coordinates are
    /// AppKit global (bottom-left origin); the FSM works in overlay-local
    /// pixels (top-left origin), so they are converted on the way in.
    func handlePetGesture(_ gesture: PetGesture) {
        guard let controller = characterController else { return }
        switch gesture {
        case .tapped:
            controller.transition(to: .reactClick)
        case .doubleTapped:
            // A happier, distinct reaction from a plain click -- also shows
            // the "happy" emotion if the user has mapped one in Settings,
            // same as EventRouter-driven reactions do.
            controller.transition(to: .petting)
            avatar?.showEmotion("happy")
        case .dragBegan(let point):
            // Order matters: transition(to:) calls ReactDragState.enter(),
            // which resets cursorPosition and the grab offset to nil (so a
            // stale drag can't resume mid-grab on re-entry) -- setting the
            // position before the transition let enter() immediately wipe it
            // out, and the grab offset would then be captured from wherever
            // the cursor had already moved on by, shifting the pet.
            controller.transition(to: .reactDrag)
            states.reactDrag.cursorPosition = windowLocalPoint(fromGlobalAppKit: point)
        case .dragMoved(let point):
            states.reactDrag.cursorPosition = windowLocalPoint(fromGlobalAppKit: point)
        case .dragEnded:
            states.reactDrag.release()
        }
    }

    /// Whether the cursor is on the pet's drawn artwork rather than on the
    /// transparent canvas around it -- only the pet's actual visible
    /// silhouette should be clickable, not the whole bounding box. Converted
    /// into the pet's own space and then answered by the avatar, which is
    /// the only thing that knows how it is currently drawn.
    func isCursorOnPet(_ cursor: CGPoint) -> Bool {
        guard let body = characterBody else { return false }
        let local = windowLocalPoint(fromGlobalAppKit: cursor)
        return body.hitTest(
            CGPoint(x: local.x - body.position.x, y: local.y - body.position.y),
            tolerance: Self.hitTestTolerance
        )
    }

    func isCursorOnToy(_ cursor: CGPoint) -> Bool {
        toyUnderCursor(cursor) != nil
    }

    /// The topmost toy drawn under the cursor, or nil. Topmost rather than
    /// nearest: toys can overlap once several are out, and the one on top is
    /// the one the user sees themselves reaching for.
    private func toyUnderCursor(_ cursor: CGPoint) -> BallController? {
        toyBox?.hitTest(windowLocalPoint(fromGlobalAppKit: cursor), tolerance: Self.hitTestTolerance)
    }

    /// How far outside the artwork still counts as clicking it. Grabbing a
    /// ~130pt character by its exact silhouette is needlessly fiddly -- but
    /// this is a fraction of the 28pt the old rectangle padded by, because it
    /// now hugs the drawing rather than a box around it.
    private static let hitTestTolerance: CGFloat = 8

    /// Picking the toy up with the cursor, the same way the pet itself can be
    /// picked up. The same rigid model the pet's drag uses:
    /// the grab offset is captured once so whatever point was grabbed stays
    /// under the cursor, and the toy is assigned outright rather than eased.
    func handleToyGesture(_ gesture: PetGesture) {
        if case .dragBegan(let point) = gesture {
            // Which toy this gesture is about is decided here and held for the
            // rest of it; every other case reads `grabbedToy`.
            grabbedToy = toyUnderCursor(point)
        }
        guard let ball = grabbedToy, ball.isActive else { return }
        switch gesture {
        case .dragBegan(let point):
            // Taking the toy the pet is playing with ends the game --
            // otherwise the pet stands there playing with something it no
            // longer has, and (for a spun toy) tries to keep hold of it.
            // Picking up a DIFFERENT toy leaves the game alone.
            if ball === toyBox?.focused, isPlayingWithToy {
                ball.stopCarrying()
                toyBox?.clearFocus()
                characterController?.transition(to: .idle)
            }
            toyDrag.begin(
                at: windowLocalPoint(fromGlobalAppKit: point),
                toyPosition: ball.state?.position,
                now: CACurrentMediaTime()
            )
            ball.grab()
        case .dragMoved(let point):
            ball.move(to: toyDrag.move(
                to: windowLocalPoint(fromGlobalAppKit: point),
                now: CACurrentMediaTime()
            ))
        case .dragEnded:
            // Let go of a still cursor and this is zero, i.e. the plain drop
            // it was before -- exactly like the pet's throw.
            ball.release(velocity: toyDrag.releaseVelocity)
        case .tapped, .doubleTapped:
            // A tap with no drag still counts as having picked it up and put
            // it straight back down; releasing restarts its fall.
            ball.release()
        }
    }

    /// Stroking the pet's head makes it happy, and letting go sets it
    /// twirling for a while.
    func handleCursorMoved(_ cursor: CGPoint, overHead: Bool) {
        apply(headPetDetector.cursorMoved(to: cursor, overHead: overHead, now: CACurrentMediaTime()))
    }

    func apply(_ update: HeadPetDetector.Update) {
        guard let controller = characterController else { return }
        switch update {
        case .began:
            // Never interrupt the pet being carried: a drag is the user's
            // hand already, and the cursor necessarily moves over the head
            // while dragging it around.
            guard controller.currentState !== states.reactDrag else { return }
            controller.transition(to: .petting)
            // After the transition -- enter() clears the flag.
            states.petting.beginStroking()
            avatar?.showEmotion("happy")
        case .ended:
            states.petting.endStroking()
        case .unchanged:
            break
        }
    }

    /// Inverse of globalAppKitPoint(fromWindowLocal:window:).
    func windowLocalPoint(fromGlobalAppKit point: CGPoint) -> CGPoint {
        guard let window = overlayWindow else { return point }
        return OverlayCoordinates.windowLocal(fromGlobalAppKit: point, windowFrame: window.frame)
    }
}
