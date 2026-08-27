//
//  AppDelegate+FrameLoop.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  The per-frame clock that drives character/pointing/toy updates, and the
//  permission-guidance and window-pointing gestures that ride on it.
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore

extension AppDelegate {
    // MARK: - Frame loop (F3)

    /// Nothing drove CharacterController.update(dt:) before this, so every
    /// time-based behavior was inert: IdleState's WanderScheduler never fired
    /// (the pet stood still forever) and PointingController's release timeout
    /// never elapsed. One clock ticks both.
    func setUpFrameLoop() {
        frameClock.onTick = { [weak self] dt in
            guard let self else { return }
            self.characterController?.update(dt: dt)
            self.pointingController.tick(dt: dt)
            if let controller = self.characterController, let toyBox = self.toyBox {
                // Resolved per toy: where a toy comes to rest depends on where
                // it is and how big it is, and with several out they are in
                // different places over different windows.
                toyBox.tickAll(
                    dt: dt,
                    landingY: { ball in
                        let ballPosition = ball.state?.position ?? .zero
                        let floorLandingY = controller.landingY(ballPosition)
                        // A ball falling through the character's head bonks off
                        // it instead of passing straight through to the
                        // floor/window below -- see ToyBox.onLanded for what
                        // happens once it actually lands there.
                        let headLandingY = self.characterBody.flatMap {
                            BallHeadCollision.landingY(
                                ballX: ballPosition.x,
                                ballHalfWidth: ball.visualBounds.width / 2,
                                characterPosition: $0.position,
                                avatarSize: self.avatarHitboxSize
                            )
                        }
                        return min(floorLandingY, headLandingY ?? floorLandingY)
                    },
                    // Per toy, like the landing surface above and for the
                    // same reason: a ball that rolls off the side of a short
                    // monitor into the space beside a taller one is a ball
                    // nobody can see or reach again.
                    roamableArea: { ball in controller.area(at: ball.state?.position ?? .zero) }
                )
            }
            // Stroking ends when the cursor stops moving, which by definition
            // sends no events -- so it has to be noticed on a tick.
            self.apply(self.headPetDetector.tick(now: CACurrentMediaTime()))

            // A resting 2D pet can use the lower heartbeat immediately after
            // the policy's idle threshold without losing timer-driven work.
            let isResting = self.characterController?.currentState === self.states.idle
            self.frameClock.setFramesPerSecond(self.idleFrameRate.framesPerSecond(idle: isResting, dt: dt))
            // The window list is only worth asking for while something is
            // happening -- see WindowPollPolicy. The watcher decides what to
            // do about it; this only says what the pet is doing.
            self.windowListWatcher?.isPetActive = !isResting

            // A spin-style toy is carried above the pet's head for as long as
            // the pet is playing with it -- position and rotation both come
            // from here, since it is the frame loop that knows dt.
            if let toyBox = self.toyBox, let body = self.characterBody {
                let isPlaying = self.characterController?.currentState === self.states.juggleBall
                let spins = toyBox.focusedToy?.play == .spinOverhead
                for ball in toyBox.all where ball.isActive {
                    // Only a toy the pet actually has. Held means the cursor
                    // took it; kicked means it is mid-throw, by the user or by
                    // the pet itself. Without this the pet re-attaches it to
                    // its head on the very next frame, and a spun toy can never
                    // be thrown at all -- every toy, including spin-style ones
                    // like the wand, has to remain throwable like the rest.
                    // Nor a rolling one: it is still in motion, and taking it
                    // out of the air mid-roll reads as the pet snatching it.
                    let petMayHold = ball.state.map {
                        $0.phase != .held && $0.phase != .kicked && $0.phase != .rolling
                    } ?? false
                    if isPlaying, spins, petMayHold, ball === toyBox.focused {
                        ball.carry(
                            to: CGPoint(
                                x: body.position.x,
                                y: body.position.y - self.avatarHitboxSize.height - Self.spinHoverGap
                            ),
                            dt: dt
                        )
                    } else if ball.state?.phase == .carried {
                        // Play ended (or something interrupted it): give the
                        // toy back to physics rather than leaving it stuck in
                        // the air.
                        ball.stopCarrying()
                    }
                }
            }

            // The toy being played with can be taken away mid-game -- from the
            // menu, or by the cursor. The play states have nothing to act on
            // once it's gone, so the pet is put back to idle rather than left
            // miming a game with nothing.
            if self.isPlayingWithToy, self.toyBox?.focused == nil {
                self.characterController?.transition(to: .idle)
            }

            // The hitbox has to follow the pet, or clicks only work where it
            // first appeared.
            if let body = self.characterBody, let window = self.overlayWindow {
                self.clickThroughController?.updateCharacter(
                    screenPosition: self.globalAppKitPoint(fromWindowLocal: body.position, window: window),
                    hitboxSize: self.avatarHitboxSize,
                    isUpsideDown: body.isUpsideDown
                )
            }

            // And so does anything the pet is currently saying -- the bubble
            // was placed once at show time, so it stayed behind the moment the
            // pet walked off (agent summary, mute sulk, permission notice, and
            // every stop of a code tour).
            self.keepSpeechBubbleOnPet()
            // Only does anything in the frame after a fall that ended inside
            // the window that caused it.
            self.perchAfterLandingIfNeeded()
            self.tickPetHome(dt: dt)
            // A wander is walked in legs, and this is what starts the next one.
            self.continueWanderIfNeeded(dt: dt)
        }
        frameClock.start()
    }

    /// Walks the pet over to a freshly launched app's window (M-1's visible
    /// half). The window doesn't exist the instant the app launches, so F4's
    /// list is polled briefly rather than read once.
    /// A tool was blocked by a missing permission: put the system's own
    /// request dialog on screen, and have the pet walk over and ask the user
    /// to click it.
    ///
    /// Pointing rather than clicking is not a shortcut -- macOS will not let
    /// any app click a security dialog on the user's behalf, which
    /// plan/02_pet-app.md F10 records as the hard limit of this whole
    /// feature. Guiding *is* the interaction.
    func guideThroughPermission(deniedFor tool: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard PermissionGuidance.shouldGuide(tool: tool, isGranted: { permission in
                switch permission {
                case .accessibility: return AccessibilityPermission.isTrusted(prompt: false)
                }
            }) != nil else {
                return
            }
            // Debounced: a run that calls find_ui_element three times would
            // otherwise stack three prompts and three bubbles.
            guard !self.isGuidingPermission else { return }
            self.isGuidingPermission = true

            let before = Set(self.overlayLocalWindows(excluding: nil).map(\.windowID))
            // macOS's own dialog, not one of ours -- it is the only thing that
            // can actually open the Accessibility pane with us pre-selected.
            _ = AccessibilityPermission.isTrusted(prompt: true)
            self.showNoticeBubble(
                Strings.text(.permissionNeededBubble),
                for: Self.permissionGuidanceDuration
            ) { [weak self] in
                self?.isGuidingPermission = false
            }
            self.pointAtNewWindow(excluding: before, attemptsRemaining: 12)
        }
    }

    /// Long enough to read the request and find the dialog.
    private static let permissionGuidanceDuration: TimeInterval = 6

    /// Points the pet at whichever window appeared after `known` -- the
    /// permission dialog, without having to know what macOS names it.
    ///
    /// Uses the F4 window list, which reads CGWindowList and needs no
    /// permission at all. That matters here more than anywhere else in the
    /// app: this runs precisely when the Accessibility-based lookup
    /// (find_ui_element) is the thing that just failed.
    private func pointAtNewWindow(excluding known: Set<CGWindowID>, attemptsRemaining: Int) {
        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            // Straight off the watcher, not through overlayLocalWindows:
            // pointAt takes the global frame (it is what the click detector
            // hit-tests the cursor against) and rebases it itself.
            guard let appeared = self.windowListWatcher?.windows.first(where: { !known.contains($0.windowID) }) else {
                self.pointAtNewWindow(excluding: known, attemptsRemaining: attemptsRemaining - 1)
                return
            }
            self.pointAt(frame: appeared.frame) {}
        }
    }

    /// The pet's "there you go" -- fired before the app opens, so the window
    /// coming up half a second later looks like the pet did it.
    ///
    /// Point, not a bespoke state: it is the gesture the pet already uses for
    /// "look at this", and the arm is up for the whole lead-in rather than for
    /// one frame the way a jump alone would be. The jump rides on top of it
    /// for the flourish, and `app_launch` is the sound protocol section 6
    /// reserved for exactly this moment and nothing had ever played.
    func performSummonGesture() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyEventReaction(EventReaction(
                stateTransition: .point,
                sfxKey: "app_launch",
                jump: true,
                emotion: "excited"
            ))
        }
    }

    func sendPetToWindow(ownedBy pid: pid_t, attemptsRemaining: Int = 20) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, let controller = self.characterController else { return }
            guard let window = self.overlayLocalWindows(excluding: nil).first(where: { $0.ownerPID == pid }) else {
                guard attemptsRemaining > 0 else { return } // the app never showed a window
                self.sendPetToWindow(ownedBy: pid, attemptsRemaining: attemptsRemaining - 1)
                return
            }
            self.states.moveTo.target = CGPoint(x: window.frame.midX, y: window.frame.minY)
            self.states.moveTo.nextState = .idle
            controller.transition(to: .moveTo)
        }
    }
}
