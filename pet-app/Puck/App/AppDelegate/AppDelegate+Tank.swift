//
//  AppDelegate+Tank.swift
//  Puck
//
//  The pet's tank inside the client window (2026-08-22): applying what the
//  client reports, and moving the pet in and out.
//
//  Everything the pet can do follows roamableArea, so going home is one
//  assignment plus a scale. The rendering stays here rather than moving
//  into PuckClient because there is one pet and pet-app owns it: the
//  client reports where the island is, and nothing else.
//

import AppKit
import CoreGraphics

extension AppDelegate {
    /// How much smaller the pet is while it is in the tank. A 90pt strip
    /// cannot hold a 120pt pet, and the tank reads as a small glass box.
    /// How tall the pet stands on the island, in points.
    ///
    /// A fixed height, not a fraction of whatever the size slider is set to:
    /// the island is a fixed 90pt whoever is looking at it, so a relative
    /// scale made the pet fill it at one setting and rattle around in it at
    /// another. On the desktop the slider still decides.
    static let defaultTankPetHeight: CGFloat = 72

    /// Where the lever on the island puts it. Written by the client over the
    /// bridge and kept here rather than in SettingsStore: it is the size of
    /// the pet in one particular place, which is a property of that place.
    /// `@MainActor`: written when the bridge's message reaches the main
    /// thread and read by the frame loop, which runs there too.
    @MainActor static var tankPetHeight: CGFloat = defaultTankPetHeight

    /// The client reported its tank. Stores the geometry and hands the
    /// in-or-out question to the decider; nothing moves until `tickPetHome`
    /// says the state has held.
    func applyPetHome(rect: BridgeRect?, visible: Bool) {
        // Remembered before the area is worked out, because the size the pet
        // travels at is worked out from it -- see `tankScale`.
        lastTankSize = rect.map { CGSize(width: $0.width, height: $0.height) }
        petTankArea = rect.flatMap { wire in
            guard let window = overlayWindow, let space = screenManager?.current else { return nil }
            let origin = space.normalized(fromAppKit: CGPoint(x: window.frame.minX, y: window.frame.maxY))
            return PetTankArea.roamableArea(
                fromWire: wire,
                overlayOriginInQuartz: origin,
                // The whole window, Dock and menu bar included: this is only
                // asking what part of the island the overlay can draw on, and
                // the island is a window's, not the desktop's.
                overlaySize: window.frame.size,
                petSize: CGSize(
                    width: baseHitboxSize.width * self.tankScale,
                    height: baseHitboxSize.height * self.tankScale
                )
            )
        }
        petHomeDecider.isPetHidden = isCharacterHidden
        petHomeDecider.report(hasTank: petTankArea != nil, visible: visible)

        // PetHomeDecider only fires on a home<->desktop transition, so a
        // dragged or resized client window while the pet is already home
        // would otherwise never reach roamableArea again. The pet isn't
        // going anywhere -- the room around it moved -- so no fade.
        if let tank = petTankArea, desktopRoamableAreas != nil,
           let controller = characterController, let body = characterBody {
            // The size as well as the room. `tankScale` fits the pet to the
            // tank it is standing in, so a tank that changed shape changes the
            // answer -- and the report of the new shape arrives after whoever
            // changed it has already asked for a height. Folding the island
            // down to its band and back is exactly that: the height for the
            // open island was asked for while the band was still the last
            // thing reported, fitted to the band, and never revisited, so the
            // pet stayed band-sized on a full island. Not while a trip is
            // running -- that lerps the scale itself, and this would fight it
            // every frame.
            if controller.currentState !== travelState {
                applyLiveAvatarScale(tankScale)
            }
            controller.roamableAreas = [tank]
            body.position = ScreenBounds.contain(
                CGPoint(x: body.position.x, y: tank.maxY),
                visualBounds: body.visualBounds,
                in: tank
            )
        }
    }

    /// Called every frame. Does nothing until a reported state has held.
    func tickPetHome(dt: TimeInterval) {
        petHomeDecider.isPetHidden = isCharacterHidden
        // Read from the state machine rather than set when a drag begins and
        // ends. Nothing moves the pet while it is in somebody's hand -- but a
        // flag raised on mouse-down is only lowered by a mouse-up that can go
        // missing (a display change replaces the click monitor mid-drag), and
        // one stuck raised means the pet can never come home again. Asking
        // where the pet *is* cannot get stuck.
        petHomeDecider.isBeingHeld = characterController?.currentState === reactDragState
        switch petHomeDecider.tick(dt: dt) {
        case .home: movePetHome()
        case .desktop: sendPetToDesktop()
        case nil: break
        }
    }

    /// The lever on the island moved. Applied to a pet that is already home,
    /// so the size follows the drag rather than waiting for the next trip:
    /// the whole point of putting the lever there is watching what it does.
    func applyPetIslandHeight(_ height: Double) {
        Self.tankPetHeight = CGFloat(height)
        guard desktopRoamableAreas != nil, let controller = characterController else { return }
        // The size a trip in progress is heading for, so a drag during the
        // flight home lands at the size that was chosen rather than the one
        // chosen before it: the trip lerps toward this every frame, and
        // writing the scale directly would just be overwritten by the next.
        travelTargetScale = tankScale
        guard controller.currentState !== travelState else { return }
        applyLiveAvatarScale(tankScale)
        // The area was measured against the old size; a pet that just grew
        // would be standing through the floor of it.
        if let tank = petTankArea, let body = characterBody {
            controller.roamableAreas = [tank]
            body.position = ScreenBounds.contain(
                CGPoint(x: body.position.x, y: tank.maxY),
                visualBounds: body.visualBounds,
                in: tank
            )
        }
    }

    /// The client went away. The tank went with it, so the pet comes out --
    /// a rect from a process that is gone is not somewhere to live.
    func petHomeConnectionLost() {
        petTankArea = nil
        petHomeDecider.report(hasTank: false, visible: false)
        sendPetToDesktop()
    }

    private func movePetHome() {
        guard let controller = characterController, let tank = petTankArea else { return }
        cancelWander()
        // A shelf a few pets wide, in the window being looked at: the pet
        // potters about on it rather than keeping the desktop's slower beat.
        idleState.pace = .island
        if desktopRoamableAreas == nil {
            desktopRoamableAreas = controller.roamableAreas
            desktopAvatarScale = currentAvatarScale
        }
        carryPet(
            of: controller,
            to: CGPoint(x: tank.midX, y: tank.maxY),
            arrivingIn: [tank],
            scale: tankScale
        )
    }

    /// Comes out of the tank without the trip, for a display change.
    ///
    /// `sendPetToDesktop` carries the pet across the screen, which is right
    /// when the window went away under it and wrong here: the overlay is
    /// being rebuilt and the pet is about to be put down in a freshly
    /// measured area anyway. What still has to happen is everything else that
    /// leaving does -- the desktop size back, the desktop's slower wander,
    /// and the memory of having been home cleared, without which the pet
    /// stays island-sized on the desktop forever and can never leave again.
    func leaveTankAfterDisplayChange() {
        guard desktopRoamableAreas != nil else { return }
        cancelWander()
        desktopRoamableAreas = nil
        idleState.pace = .desktop
        applyLiveAvatarScale(desktopAvatarScale)
    }

    func sendPetToDesktop() {
        guard let controller = characterController, let desktop = desktopRoamableAreas else { return }
        cancelWander()
        idleState.pace = .desktop
        desktopRoamableAreas = nil
        // Onto the display the pet came from, not the middle of the box
        // around every display -- that point can be on no screen at all.
        let home = ScreenGround.area(at: characterBody?.position ?? .zero, in: desktop)
            ?? ScreenGround.union(desktop)
        carryPet(
            of: controller,
            to: CGPoint(x: home.midX, y: home.maxY),
            arrivingIn: desktop,
            scale: desktopAvatarScale
        )
    }

    /// The scale that puts the pet at `tankPetHeight` -- or at whatever the
    /// tank can actually hold, when that is less. 1 when there is no avatar
    /// yet, which only happens before one is installed and never while a move
    /// is running.
    ///
    /// The tank's width is what usually binds: it has to be two pets across
    /// before it is worth standing in, and a narrow window's island is not.
    /// Sizing down is the difference between a small pet and no pet -- the
    /// area is refused outright otherwise, and a refusal looks like the pet
    /// ignoring the window.
    var tankScale: Double {
        guard baseHitboxSize.height > 0 else { return 1 }
        guard let lastTankSize, baseHitboxSize.width > 0 else {
            return Double(Self.tankPetHeight / baseHitboxSize.height)
        }
        let fitted = PetTankArea.fittedPetHeight(
            desired: Self.tankPetHeight,
            tank: lastTankSize,
            aspect: baseHitboxSize.width / baseHitboxSize.height
        )
        return Double(fitted / baseHitboxSize.height)
    }

    /// What `applyLiveAvatarScale` was last given, derived rather than stored:
    /// that method sets `avatarHitboxSize = baseHitboxSize * scale`, so the
    /// ratio is the scale. Nothing else keeps it -- the size slider hands a
    /// value straight in and forgets it.
    private var currentAvatarScale: Double {
        guard baseHitboxSize.height > 0 else { return 1 }
        return Double(avatarHitboxSize.height / baseHitboxSize.height)
    }

    /// Carries the pet across, in view the whole way.
    ///
    /// This used to be a cut -- fade out, set the position, fade in -- which
    /// read as the pet vanishing and a copy appearing elsewhere. Both worlds
    /// are rectangles in the same space, so the trip between them is an
    /// ordinary move and there is no reason to hide it.
    ///
    /// The roamable area is widened to cover both ends for the duration.
    /// `update(dt:)` clamps horizontally into it every frame whatever the
    /// state is doing, so leaving it at the world being left would drag the
    /// pet back at the first step out of it. TravelState hands it back on
    /// arrival, before anything else runs.
    ///
    /// The size travels with it, on the same eased curve. It used to change
    /// on arrival, which read as the pet landing and then being resized --
    /// two events where there is one.
    private func carryPet(
        of controller: CharacterController,
        to destination: CGPoint,
        arrivingIn areas: [CGRect],
        scale: Double
    ) {
        guard let body = characterBody else { return }
        let departingScale = currentAvatarScale
        travelState.origin = body.position
        travelState.destination = destination
        // Sized along the way rather than on landing. Snapping at the end
        // reads as the pet arriving and *then* being resized, which is two
        // events where the eye expects one -- and going the other way it
        // popped to full size the instant it touched the desktop.
        travelTargetScale = scale
        travelState.onProgress = { [weak self] progress in
            guard let self else { return }
            // Read live rather than captured: the size lever can move while
            // the pet is in the air, and the trip should end at the size the
            // person is looking at.
            let target = self.travelTargetScale
            self.applyLiveAvatarScale(departingScale + (target - departingScale) * progress)
        }
        travelState.onArrival = { controller.roamableAreas = areas }
        controller.roamableAreas = controller.roamableAreas + areas
        controller.transition(to: .travel)
    }
}
