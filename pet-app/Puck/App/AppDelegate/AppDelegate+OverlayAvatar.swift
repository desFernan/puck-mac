//
//  AppDelegate+OverlayAvatar.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Overlay window + avatar lifecycle: initial activation, hot-swapping
//  presets, click-through wiring, and Space/display-change recovery.
//

import AppKit
import CoreGraphics
import Foundation

extension AppDelegate {
    // MARK: - Overlay + avatar (F1/F2/F3/F5)

    func setUpOverlayAndAvatar() {
        guard let screenManager = ScreenManager() else { return }
        self.screenManager = screenManager

        let overlayController = OverlayWindowController(screenManager: screenManager)
        overlayController.onWindowsRebuilt = { [weak self] in self?.handleWindowsRebuilt() }
        overlayController.start()
        self.overlayController = overlayController

        guard
            let window = overlayController.windows.first,
            let spriteView = window.contentView as? SpriteLayerView
        else {
            return
        }

        // First run has nothing in Application Support yet; seed the bundled
        // package so a fresh clone shows a pet instead of an empty screen.
        if let bundled = Bundle.main.url(forResource: "Avatars/dummy", withExtension: nil) {
            let outcome = AvatarInstaller.installIfNeeded(
                bundledPackage: bundled,
                intoAvatarsDirectory: AvatarCatalogue.avatarsDirectory
            )
            AppLogger.shared.log(.info, "Bundled avatar install: \(outcome)")
        } else {
            AppLogger.shared.log(.warning, "No bundled avatar package in the app bundle")
        }

        guard activateAvatar(named: settingsStore.selectedAvatarName, window: window, spriteView: spriteView) else { return }

        settingsStore.onToyScaleChanged = { [weak self] scale in
            self?.toyBox?.updateScale(scale)
        }
        settingsStore.onWalkSpeedMultiplierChanged = { [weak self] multiplier in
            self?.characterController?.walkSpeed = MovementSolver.walkSpeed * multiplier
        }
        // The avatar should be switchable live, like flipping a preset --
        // Settings' avatar picker writes this; activateAvatar
        // tears down whatever's running and swaps the new package in live.
        settingsStore.onSelectedAvatarChanged = { [weak self] name in self?.switchAvatar(to: name) }
        // autoMuteOnFocus existed as a setting with nothing acting on it --
        // FocusModeObserver was implemented but never instantiated anywhere.
        // Reads self.sfxPlayer fresh each time (not captured), so it keeps
        // working against whichever sfxPlayer is current after a later
        // avatar switch replaces it -- capturing it directly here would go
        // stale the same way onVolumeChanged/onMuteChanged would without
        // being reassigned in activateAvatar.
        let focusObserver = FocusModeObserver()
        focusObserver.onChange = { [weak self] isFocusActive in
            guard let self, self.settingsStore.autoMuteOnFocus else { return }
            // Focus can add muting, never take it away: assigning the flag
            // outright meant Focus switching off unmuted a pet the user had
            // muted in Settings, and nothing put that back.
            self.sfxPlayer?.isMuted = isFocusActive || self.settingsStore.isMuted
        }
        focusObserver.startObserving()
        focusModeObserver = focusObserver

        // F12 (optional, lowest priority): ball-toy interaction. Lives on the
        // same sprite layer as the avatar so it reparents on display changes
        // the same way. Avatar-agnostic -- set up once here, not touched by
        // activateAvatar/switchAvatar.
        makeToyBox(on: spriteView.contentLayer)
    }

    /// (Re)builds the avatar/body/controller/sound stack for the avatar
    /// installed under `name`, tearing down whatever was running before it.
    /// Loads and validates the new package FIRST, before touching anything
    /// live -- an invalid/missing preset must leave the current pet running,
    /// not blank the screen. Returns false (leaving the previous avatar
    /// untouched) if the load fails.
    ///
    /// Deliberately does NOT touch toyBox or focusObserver: both are
    /// avatar-agnostic and set up exactly once, in setUpOverlayAndAvatar.
    /// The FSM's StateHandler instances (idleState, walkState, ...) are
    /// likewise reused as-is across a switch -- they take body/controller
    /// through StateContext at call time rather than storing either at
    /// construction (see e.g. IdleState.update(dt:context:)), so
    /// re-registering them onto a fresh CharacterController is safe.
    @discardableResult
    private func activateAvatar(named name: String, window: NSWindow, spriteView: SpriteLayerView) -> Bool {
        let avatarDirectory = AvatarCatalogue.avatarsDirectory.appendingPathComponent(name, isDirectory: true)

        let loadResult: AvatarLoadResult
        do {
            loadResult = try AvatarLoader.load(avatarDirectory: avatarDirectory)
        } catch {
            // Keep the specific reason (missing required clips, unsupported
            // schema version, undecodable manifest) — `try?` threw away the
            // distinction AvatarLoaderError exists to make.
            AppLogger.shared.log(.error, "Failed to load avatar '\(name)' at \(avatarDirectory.path): \(error)")
            return false
        }

        // Torn down only now that the replacement is known-good.
        clickThroughController?.stopMonitoring()
        avatar?.spriteLayer.removeFromSuperlayer()

        // manifest.hitbox scaled by manifest.scale -- must be computed before
        // controller.avatarHeight below, which the FSM's climb/land/wander
        // logic depends on being non-zero from the very first frame (found
        // via review: this used to read the .zero default here because the
        // computation used to happen after controller setup instead of
        // before it).
        let scale = loadResult.manifest.scale
        baseHitboxSize = CGSize(width: loadResult.manifest.hitbox.width, height: loadResult.manifest.hitbox.height)
        avatarHitboxSize = CGSize(width: baseHitboxSize.width * scale, height: baseHitboxSize.height * scale)

        let newAvatar = SpriteAvatar(
            avatarDirectory: avatarDirectory,
            loadResult: loadResult,
            parent: spriteView.contentLayer
        )
        // Keeps the pet where it already stood across a switch rather than
        // re-spawning it -- only the very first activation (no prior
        // characterBody) has no "where it already stood" to keep.
        let initialPosition = characterBody?.position ?? GroundedSpawnPosition.position(in: groundAwareSize(of: window))
        newAvatar.setScreenPosition(initialPosition)
        avatar = newAvatar

        let soundTable = SoundTable(avatarDirectory: avatarDirectory, sounds: loadResult.manifest.sounds)
        let sfxPlayer = SFXPlayer(soundTable: soundTable)
        sfxPlayer.volume = settingsStore.volume
        sfxPlayer.isMuted = settingsStore.isMuted
        self.sfxPlayer = sfxPlayer

        // Reassigned every activation, not just once -- these close over
        // sfxPlayer directly (weakly), which would otherwise go stale
        // pointing at whichever avatar's sound player this replaced.
        settingsStore.onVolumeChanged = { [weak sfxPlayer] volume in sfxPlayer?.volume = volume }
        settingsStore.onMuteChanged = { [weak self, weak sfxPlayer] isMuted in
            sfxPlayer?.isMuted = isMuted
            guard isMuted, self?.settingsStore.isMuteComplaintEnabled == true else { return }
            self?.showMutedComplaint()
        }

        let body = CharacterBody(
            avatar: newAvatar,
            position: initialPosition,
            bounceIntensity: loadResult.manifest.bounceIntensity ?? CharacterBody.defaultBounceIntensity
        )
        characterBody = body
        let controller = CharacterController(initialState: idleState, body: body, sfxPlayer: sfxPlayer)
        for (kind, state) in [
            (StateKind.idle, idleState as StateHandler),
            (.walk, walkState), (.climb, climbState), (.walkOnTop, walkOnTopState),
            (.fall, fallState), (.land, landState), (.moveTo, moveToState),
            (.point, pointState), (.type, typeState), (.listen, listenState),
            (.reactClick, reactClickState), (.reactDrag, reactDragState),
            (.petting, pettingState), (.spin, spinState),
            (.chaseBall, chaseBallState), (.juggleBall, juggleBallState), (.kickBall, kickBallState),
            (.climbToCeiling, climbToCeilingState), (.ceiling, ceilingState),
            (.pinned, pinnedState),
            (.travel, travelState),
        ] {
            controller.register(state, as: kind)
        }
        controller.idleChatter.keys = soundTable.keys(withPrefix: "chatter_")
        controller.roamableArea = CGRect(origin: .zero, size: groundAwareSize(of: window))
        controller.avatarHeight = avatarHitboxSize.height
        controller.walkSpeed = MovementSolver.walkSpeed * settingsStore.walkSpeedMultiplier
        // F4 reports global Quartz frames; the pet lives in overlay-local
        // pixels. Rebase once here so no state has to know both spaces.
        // Looks up the current overlay window each call rather than
        // capturing `window` -- a captured reference goes stale (weak-nils,
        // or worse, refers to a since-discarded window) the moment
        // OverlayWindowController rebuilds its windows on a real display
        // change, found via review since handleWindowsRebuilt() never
        // re-assigns this closure.
        controller.windows = { [weak self] in
            guard let self, let window = self.primaryWindow else { return [] }
            return self.overlayLocalWindows(excluding: window)
        }
        // The other half of Settings' "포커스된 창 위로는 올라가지 않기": the
        // wander destination is picked in AppDelegate+Wander, but a plain walk
        // that happens to cross the focused window's edge climbs it too, and
        // that decision is WalkState's. Resolved per frame against the same
        // list the pet is walking through, so the id always matches.
        // Straight off the watcher rather than through overlayLocalWindows:
        // this runs every frame alongside `windows` above, and rebasing the
        // whole list a second time buys nothing -- a CGWindowID is the same id
        // in either coordinate space.
        controller.unclimbableWindows = { [weak self] in
            guard let self, let watcher = self.windowListWatcher else { return [] }
            return self.unclimbableWindowIDs(in: watcher.windows)
        }
        controller.landingY = { [weak self, weak controller] point in
            let floor = controller?.roamableArea.maxY ?? 0
            guard let self, let controller else { return floor }
            return LandingSurfaceResolver.landingY(
                atX: point.x,
                fallingFromY: point.y,
                windows: self.overlayLocalWindows(excluding: nil),
                screenBottomY: controller.roamableArea.maxY,
                roamableTop: controller.roamableArea.minY,
                avatarHeight: controller.avatarHeight
            )
        }
        idleState.wanderDelegate = self
        pointState.onEnter = { [weak self] in self?.beginPointingTimer() }
        characterController = controller

        // manifest.hitbox was decoded but had no consumer -- ClickThroughController
        // is the piece that uses it (click-through everywhere except over the
        // character), just never instantiated here. (avatarHitboxSize itself
        // is now computed earlier, above, before controller.avatarHeight needs it.)
        clickThroughController = makeClickThroughController(window: window, screenPosition: initialPosition)
        return true
    }

    private func switchAvatar(to name: String) {
        guard let window = primaryWindow, let spriteView = window.contentView as? SpriteLayerView else { return }
        activateAvatar(named: name, window: window, spriteView: spriteView)
    }

    /// Shared by initial setup and `handleWindowsRebuilt` -- previously
    /// duplicated verbatim at both call sites (found via review), which is
    /// exactly the kind of duplication that already caused one regression
    /// ("clicking the pet silently stops working after a display change",
    /// see the comment this used to carry at the rebuild site) since the two
    /// copies could drift.
    private func makeClickThroughController(window: NSWindow, screenPosition: CGPoint) -> ClickThroughController {
        let clickThrough = ClickThroughController(window: window)
        clickThrough.updateCharacter(
            screenPosition: globalAppKitPoint(fromWindowLocal: screenPosition, window: window),
            hitboxSize: avatarHitboxSize
        )
        clickThrough.onGesture = { [weak self] gesture in self?.handlePetGesture(gesture) }
        clickThrough.onCursorMoved = { [weak self] cursor, overHead in
            self?.handleCursorMoved(cursor, overHead: overHead)
        }
        clickThrough.onToyGesture = { [weak self] gesture in self?.handleToyGesture(gesture) }
        clickThrough.isOnPet = { [weak self] cursor in self?.isCursorOnPet(cursor) ?? false }
        clickThrough.isOnToy = { [weak self] cursor in self?.isCursorOnToy(cursor) ?? false }
        clickThrough.startMonitoring()
        return clickThrough
    }

    /// ScreenSpaceMapper's screen points are window-local (top-left origin,
    /// Y-down); NSEvent.mouseLocation (which ClickThroughController hit-tests
    /// against) is AppKit's global screen space (bottom-left origin, Y-up).
    func globalAppKitPoint(fromWindowLocal point: CGPoint, window: NSWindow) -> CGPoint {
        CGPoint(x: window.frame.origin.x + point.x, y: window.frame.origin.y + (window.frame.height - point.y))
    }

    /// `window`'s size with the Dock's strip trimmed off the bottom (see
    /// DockInset's doc comment) -- what roamableArea/GroundedSpawnPosition
    /// should treat as "the ground," so the pet stands in front of the Dock
    /// instead of being drawn underneath it.
    func groundAwareSize(of window: NSWindow) -> CGSize {
        let dockInset = NSScreen.screens.first
            .map { DockInset.bottomInset(screenFrame: $0.frame, visibleFrame: $0.visibleFrame) } ?? 0
        return CGSize(width: window.frame.width, height: window.frame.height - dockInset)
    }

    /// In a fullscreen Space the pet should roam over the whole screen, not
    /// stay confined above where the Dock would be -- OverlayWindow already
    /// joins fullscreen Spaces
    /// (.fullScreenAuxiliary), but nothing previously re-checked
    /// groundAwareSize after initial setup, so roamableArea stayed reserved
    /// for the Dock's height even in a fullscreen Space where the Dock isn't
    /// actually shown at all (NSScreen.visibleFrame reports no Dock inset
    /// there). Space switches don't fire didChangeScreenParametersNotification
    /// (that's for real display reconfiguration), so this needs its own
    /// observer. IdleState's existing "supporting surface disappeared" check
    /// then naturally settles the pet onto the new, taller floor if the pet
    /// happens to be resting when the Space changes.
    func setUpSpaceChangeObserving() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` above is what makes this true; a notification
            // block's signature cannot say it.
            MainActor.assumeIsolated { self?.refreshRoamableAreaForCurrentSpace() }
        }
    }

    private func refreshRoamableAreaForCurrentSpace() {
        guard let window = primaryWindow, let controller = characterController else { return }
        controller.roamableArea = CGRect(origin: .zero, size: groundAwareSize(of: window))
    }

    /// OverlayWindowController tears down and recreates every window+SpriteLayerView
    /// on a real display change (monitor plug/unplug, resolution change).
    /// Without this, the avatar/click-through stayed parented to the now-gone
    /// window and silently disappeared. `avatar`/`clickThroughController` are
    /// nil on the very first call (fired from inside overlayController.start(),
    /// before setUpOverlayAndAvatar has built them yet) -- nothing to do then.
    private func handleWindowsRebuilt() {
        guard
            let window = primaryWindow,
            let spriteView = window.contentView as? SpriteLayerView,
            let avatar
        else {
            return
        }

        // The window that came back is a different size, and every area the
        // pet walks in was measured against the old one. Re-measure before
        // anything reads them: left stale, the floor of the old area sits
        // below the new screen's bottom edge and the pet drops out of sight
        // with no state able to bring it back.
        let desktop = CGRect(origin: .zero, size: groundAwareSize(of: window))
        // Out of the tank first, if it was in one: that rect was measured
        // against the window just torn down. The client re-reports its island
        // on a display change and the pet walks back into it a moment later.
        leaveTankAfterDisplayChange()
        characterController?.roamableArea = desktop
        let position = DisplayChangeRelocation.contained(
            characterBody?.position ?? .zero,
            visualBounds: characterBody?.visualBounds ?? .zero,
            in: desktop
        )
        // OverlayWindowController always orderFrontRegardless()s a freshly
        // rebuilt window -- a display change (monitor plug/unplug) shouldn't
        // silently un-hide a pet the user explicitly hid.
        if isCharacterHidden {
            window.orderOut(nil)
        }
        avatar.reparent(to: spriteView.contentLayer)
        toyBox?.reparent(to: spriteView.contentLayer)
        // Through characterBody, not avatar directly -- its didSet is the
        // only path that's supposed to push position to the avatar. Setting
        // avatar.setScreenPosition() here left characterBody.position stale,
        // desyncing the frame-loop's hitbox tracking (which reads
        // body.position) from where the pet is actually rendered, and
        // causing a visible teleport next time a movement state computed
        // from the stale position.
        characterBody?.position = position

        // Rebuilding the window drops the old monitor with its handler;
        // without re-attaching (via makeClickThroughController below),
        // clicking the pet silently stops working after a display change.
        clickThroughController?.stopMonitoring()
        clickThroughController = makeClickThroughController(window: window, screenPosition: position)
    }

    /// F4's window list rebased from global Quartz coordinates into the
    /// overlay window's local space, with our own overlay filtered out — the
    /// pet must not try to stand on the window it is drawn in.
    func overlayLocalWindows(excluding overlay: NSWindow?) -> [WindowInfo] {
        // Reuses ScreenManager's cached GlobalScreenSpace instead of calling
        // GlobalScreenSpace.current() fresh here -- this runs every frame
        // (60Hz while active) via CharacterController.windows(), and
        // .current() re-queries NSScreen.screens and rebuilds the whole
        // space from scratch every time, for a value that only actually
        // changes on a real display reconfiguration (which ScreenManager
        // already observes and refreshes on).
        guard
            let watcher = windowListWatcher,
            let overlayFrame = primaryWindow?.frame,
            let screenSpace = screenManager?.current
        else {
            return []
        }
        // overlayFrame is AppKit space (bottom-left origin, Y-up); info.frame
        // (from CGWindowListCopyWindowInfo) is already Quartz space (primary
        // display top-left origin, Y-down) -- the same convention
        // GlobalScreenSpace normalizes into. A straight subtraction of
        // AppKit's origin with no Y-flip only happened to work for the
        // primary display's overlay window (whose AppKit origin is (0,0));
        // route through the same conversion GlobalScreenSpace itself uses for
        // every other screen frame so a non-primary overlay window works too.
        let origin = screenSpace.normalized(fromAppKit: CGPoint(x: overlayFrame.minX, y: overlayFrame.maxY))
        let overlayNumber = overlay.map { CGWindowID($0.windowNumber) }
        return watcher.windows.compactMap { info in
            guard info.windowID != overlayNumber else { return nil }
            return WindowInfo(
                windowID: info.windowID,
                ownerPID: info.ownerPID,
                ownerName: info.ownerName,
                title: info.title,
                layer: info.layer,
                frame: info.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            )
        }
    }
}
