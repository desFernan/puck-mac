//
//  AppDelegate+BallToy.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Ball toy state, spawn, and play/summon logic (menu bar + Option+Shift+1/2).
//

import AppKit
import CoreGraphics
import QuartzCore

extension AppDelegate {
    // MARK: - Ball toy (F12, optional)

    /// Whether the pet is currently in a toy-play state.
    var isPlayingWithToy: Bool {
        let state = characterController?.currentState
        return state === chaseBallState || state === juggleBallState || state === kickBallState
    }

    /// Builds the toy box and wires every callback that involves a toy.
    ///
    /// Called once, at launch: individual toys come and go through the menu
    /// (ToyBox.toggle), and a display change reparents the box rather than
    /// rebuilding it.
    func makeToyBox(on parent: CALayer) {
        let box = ToyBox(parent: parent, scale: settingsStore.toyScale)
        box.onLanded = { [weak self] toy, position in
            guard let self, let ball = self.toyBox?.controller(for: toy) else { return }
            // A toy that fell onto the character's head bonks off it
            // immediately instead of resting there to be chased. It stays
            // in play after the bounce -- nothing removes the toy any more.
            // Compared at the toy's bottom edge, not its centre: the toy
            // rests with its artwork on the surface, so its centre sits a
            // good 20pt above whatever it landed on. Comparing centres here
            // meant a toy that had genuinely landed on the head read as
            // having missed it, and it sat on the pet instead of bouncing.
            let toyBottom = position.y + ball.visualBounds.maxY
            if let body = self.characterBody,
               let headY = BallHeadCollision.landingY(
                   ballX: position.x,
                   ballHalfWidth: ball.visualBounds.width / 2,
                   characterPosition: body.position,
                   avatarSize: self.avatarHitboxSize
               ),
               abs(toyBottom - headY) < 0.5 {
                if self.characterController?.currentState === self.juggleBallState,
                   ball === self.toyBox?.focused {
                    // Mid-game: caught, not headed. The toy is left resting on
                    // the pet's head and JuggleBall throws it again after a
                    // beat. Popping it here instead would make contact and
                    // re-launch the same instant, which reads as a bounce.
                    self.juggleBallState.caught()
                } else {
                    // Dropped on the pet's head by the user, out of the blue:
                    // it bounces off and makes its way down rather than
                    // perching there. The drift is what gets it off the head;
                    // straight up would just land on the same spot again.
                    ball.bounce(drift: .random(in: 70...110) * (Bool.random() ? 1 : -1))
                }
                return
            }

            // Idle/Walk-only gate (F3's priority rule): the pet must not
            // abandon an agent-driven task to go chase a ball. And not the
            // toy it just threw away, until it has had a break from toys --
            // otherwise the throw's own landing starts the next game.
            guard !self.isRestingFromToys,
                  let controller = self.characterController,
                  controller.currentState === self.idleState || controller.currentState === self.walkState
            else { return }
            self.startPlaying(with: toy)
        }
        juggleBallState.onThrow = { [weak self] in
            guard let self, let body = self.characterBody else { return }
            // Straight up over the pet's own x, so it comes back down on the
            // head rather than beside it.
            self.toyBox?.focused?.lift(
                overX: body.position.x,
                headTop: body.position.y - self.avatarHitboxSize.height
            )
        }
        kickBallState.onEnter = { [weak self] in
            guard let self else { return }
            // The throw-away IS the end of the game, for every toy and both
            // play styles, so this is the one place the break starts from.
            self.toyPlayEndedAt = CACurrentMediaTime()
            self.toyBox?.focused?.kick(direction: self.characterBody?.facing ?? .right)
        }
        toyBox = box
    }

    /// Sends the pet off to play with one particular toy. The single entry
    /// point into the play states, so "which toy is the pet playing with" is
    /// only ever answered in one place.
    func startPlaying(with toy: Toy) {
        guard let controller = characterController,
              let box = toyBox,
              let ball = box.controller(for: toy),
              let position = ball.state?.position
        else { return }

        box.focus(ball)
        // Beside the toy and on the surface it's resting on -- not at the
        // toy's own centre, which is a toy-radius up in the air and puts
        // the pet on top of it.
        chaseBallState.target = ToyApproach.standingPosition(
            toyPosition: position,
            toyBounds: ball.visualBounds,
            petPosition: characterBody?.position ?? position,
            petBounds: characterBody?.visualBounds ?? .zero
        )
        juggleBallState.style = toy.play
        juggleBallState.toyName = toy.name
        controller.transition(to: .chaseBall)
    }

    /// Menu bar toy list — puts the chosen toy out at the cursor, onto
    /// whatever's below it (F4's landing-surface logic, same as Fall), or
    /// takes it away if it was already out.
    /// Returns the toys that are out afterwards -- the settings window's toy
    /// grid seeds itself from the same answer the menu bar gets, so the two
    /// switches for one toy box can't drift apart.
    @discardableResult
    func toggleToy(_ toy: Toy) -> Set<String> {
        guard let box = toyBox else { return [] }
        box.toggle(toy, at: windowLocalPoint(fromGlobalAppKit: NSEvent.mouseLocation))
        // Handing the pet a toy on purpose beats its break -- being ignored
        // right after clicking the menu just reads as broken.
        toyPlayEndedAt = nil
        // From what's actually out, not from what the toggle was asked to do.
        return box.outToyNames
    }

    /// Option+Shift+1/2 (F6) summon ToyCatalogue.all[0]/[1] directly, reusing
    /// toggleToy's on/off semantics.
    func summonToy(at index: Int) {
        guard ToyCatalogue.all.indices.contains(index) else { return }
        toggleToy(ToyCatalogue.all[index])
    }
}
