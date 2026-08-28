//
//  AppDelegate+HotkeysVoice.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Global hotkeys, voice input, and the quick-capture text bubble.
//

import AppKit
import CoreGraphics

extension AppDelegate {
    // MARK: - Global hotkeys + voice (F6/F7)

    func setUpGlobalHotkeys() {
        let manager = GlobalHotkeyManager(bindings: settingsStore.hotkeyBindings)
        let speechService = SpeechRecognitionService(locale: Locale(identifier: settingsStore.speechRecognitionLocaleIdentifier))
        let voiceController = VoiceInputController(speechService: speechService)

        voiceController.onListenStart = { [weak self] in
            guard let self, let characterController = self.characterController else { return }
            self.stateBeforeListen = characterController.currentState
            characterController.transition(to: self.states.listen)
            // F7: listen_start is an event-name sound key (plan/01_protocol.md
            // section 6), separate from the state's own "listen" clip key that
            // the shared enter() path triggers.
            self.sfxPlayer?.trigger("listen_start", loop: false)
        }
        voiceController.onListenEnd = { [weak self] in
            guard let self, let characterController = self.characterController else { return }
            characterController.transition(to: self.stateBeforeListen ?? self.states.idle)
            self.stateBeforeListen = nil
            self.closeCaptionBubble()
        }
        // What is being heard, over the pet's head, while the key is held.
        // The service has always asked for partial results and this was the
        // one end of it nobody connected, so they were computed and dropped.
        voiceController.onPartialText = { [weak self] text in
            self?.showCaptionBubble(text)
        }
        voiceController.onFinalText = { [weak self] text in
            self?.sendUserInput(text: text, source: .voice)
        }
        voiceController.onError = { error in
            AppLogger.shared.log(.error, "Speech recognition error: \(error)")
        }
        voiceInputController = voiceController

        manager.onPushToTalkDown = { [weak voiceController] in voiceController?.pushToTalkDown() }
        manager.onPushToTalkUp = { [weak voiceController] in voiceController?.pushToTalkUp() }
        manager.onTextInputRequested = { [weak self] in self?.showTextInputBubble() }
        manager.onCharacterSummonRequested = { [weak self] in self?.summonCharacter() }
        manager.onToySummon1Requested = { [weak self] in self?.summonToy(at: 0) }
        manager.onToySummon2Requested = { [weak self] in self?.summonToy(at: 1) }

        hotkeyManager = manager
        if !manager.start() {
            AppLogger.shared.log(.warning, "GlobalHotkeyManager failed to start (Accessibility permission likely not granted)")
            waitForAccessibilityThenStartHotkeys()
        }
    }

    /// Tries again once Accessibility is granted.
    ///
    /// The tap can only be created with that permission, and granting it is
    /// something the user does *after* launching -- in System Settings, in
    /// another window, minutes later. Without this the shortcuts stayed dead
    /// until the app was relaunched, with nothing on screen to say so.
    ///
    /// Polled rather than observed: there is no notification for this, and a
    /// check that costs nothing every few seconds is cheaper than a user
    /// wondering why their push-to-talk key does nothing.
    private func waitForAccessibilityThenStartHotkeys() {
        // Scheduled on the main run loop, which is where it fires; the
        // closure's own signature is not isolated, so it has to be said.
        // The timer is reached through the property rather than through the
        // block's own parameter: that parameter is a value handed in from
        // outside the main actor, and passing it into the hop below is the
        // one thing here that actually crosses.
        let timer = Timer.scheduledTimer(withTimeInterval: Self.accessibilityRetrySeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let manager = self.hotkeyManager else {
                    self?.accessibilityRetryTimer?.invalidate()
                    return
                }
                guard AccessibilityPermission.isTrusted() else { return }
                if manager.start() {
                    AppLogger.shared.log(.info, "GlobalHotkeyManager started after Accessibility was granted")
                    self.accessibilityRetryTimer?.invalidate()
                }
            }
        }
        // The pet's own frame loop runs in a common mode, and a timer left in
        // the default mode stops firing while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = timer
    }

    static let accessibilityRetrySeconds: TimeInterval = 3

    /// Hands a command to PuckClient, which hosts the agent that acts on it.
    ///
    /// One send, to the gui role: it is the only role there is, so the second
    /// send this used to make (through UserInputSender, nominally addressed to
    /// a workspace) resolved to the same connections and delivered every
    /// quick-capture submission and voice command twice.
    private func sendUserInput(text: String, source: UserInput.Source, attachments: [Attachment] = []) {
        let message = BridgeMessage.userInput(
            UserInput(text: text, source: source, attachments: attachments.isEmpty ? nil : attachments)
        )
        guard bridgeServer?.send(message, to: .gui) != true else { return }

        // Held rather than dropped -- PuckClient is launched alongside the
        // pet (CompanionAppLauncher) and is most likely still connecting.
        pendingClientMirror = message
        // F6: tell the user why nothing happened. Re-opening the input
        // bubble here (what this used to do) just looped — typing again
        // reopened it again, and the input was never delivered.
        showClientOfflineBubble()
    }

    /// Submitting from the quick-capture bubble should also bring up the
    /// client window showing what was typed. The bubble stays the lightweight
    /// capture it is; what it submits goes to PuckClient, which brings its
    /// window up showing the text. Closing or quitting that window changes
    /// nothing here -- it's a separate process, and the pet doesn't observe
    /// its presence.
    /// Not private: the notch panel sends its line through here too, so a
    /// turn started there and one started from the bubble are the same turn.
    func submitFromInputBubble(_ text: String, attachments: [Attachment] = []) {
        // Brought up first so the window is on its way while the text is
        // delivered; sendUserInput queues it if the connection isn't up yet.
        openClientApp()
        sendUserInput(text: text, source: .text, attachments: attachments)
    }

    /// Revised 2026-07-30: once the client window became an app of its own
    /// (PuckClient), this hotkey went back to being only the light
    /// quick-capture bubble -- there is no longer a reason for it to open the
    /// whole window.
    private func showTextInputBubble() {
        guard let (bubbleWindow, bubbleView) = makeBubble() else { return }

        // The bubble window is shared with the pet's notices, and each notice
        // leaves a timer behind that closes whatever is in it when it fires.
        // Taking the generation claims the window: a notice shown a second
        // before this panel opened would otherwise close the panel the user
        // is typing into, and leave the pet pinned with nothing on screen.
        noticeBubbleGeneration += 1
        pinCharacter()
        // Fresh session, fresh state -- bubbleView itself is a brand-new
        // instance per makeBubble() call, but this property lives on the
        // delegate and would otherwise carry a stale attachment into a
        // session whose (also fresh) view shows no thumbnail at all.
        pendingBubbleAttachment = nil

        bubbleView.onSubmit = { [weak self] text in
            // Focus goes to PuckClient below, not back to the app the
            // user invoked the bubble from -- restoring it first would flash
            // that app forward for a frame.
            bubbleWindow.closeAndYieldFocus()
            self?.unpinCharacter()
            let attachment = self?.pendingBubbleAttachment
            self?.pendingBubbleAttachment = nil
            self?.submitFromInputBubble(text, attachments: attachment.map { [$0] } ?? [])
        }
        let dismiss = { [weak self] in
            bubbleWindow.closeAndRestoreFocus()
            self?.unpinCharacter()
            self?.pendingBubbleAttachment = nil
        }
        bubbleView.onCancel = dismiss
        // Clicking away is the other way out of a Spotlight panel.
        bubbleWindow.onDismiss = dismiss
        bubbleView.onAttachRequested = { [weak self, weak bubbleView] in
            self?.startAttachmentCapture(bubbleView: bubbleView)
        }
        bubbleView.onRemoveAttachment = { [weak self, weak bubbleView] in
            self?.pendingBubbleAttachment = nil
            bubbleView?.setAttachmentThumbnail(nil)
        }
        bubbleWindow.showAndActivate()
        // After showAndActivate, not before: makeFirstResponder on a window
        // that isn't key yet doesn't put the caret in the field, so the panel
        // came up needing a click before it would take a keystroke.
        bubbleView.showInput()
    }

    /// F14: interactive drag-to-select screen capture, attached as one of the
    /// bubble's attachments. Shells out to screencapture -i
    /// rather than the bubble hiding itself first: the system's own capture
    /// overlay draws on top of everything regardless, and hiding/reshowing
    /// the panel around an async, human-paced drag risked exactly the
    /// resignKey/refocus races closeAndRestoreFocus exists to avoid
    /// elsewhere in this file.
    private func startAttachmentCapture(bubbleView: TextInputBubbleView?) {
        ScreenRegionCapture.capture { [weak self, weak bubbleView] url in
            // Delivered on the main queue by `capture` itself, which its
            // signature cannot say -- the callback is armed on whichever
            // thread the child process ended on.
            MainActor.assumeIsolated {
                // The interactive capture takes focus system-wide; hand it
                // back regardless of whether anything was actually captured.
                NSApp.activate(ignoringOtherApps: true)
                self?.textInputBubbleWindow?.makeKeyAndOrderFront(nil)

                guard let url else { return } // Escape, or capture failed
                self?.pendingBubbleAttachment = Attachment(path: url.path)
                bubbleView?.setAttachmentThumbnail(NSImage(contentsOf: url))
            }
        }
    }

    /// F13 (2026-07-30): the client window is now PuckClient.app, a
    /// separate Dock-resident process -- opening/focusing it is just
    /// activating that app, the same as clicking its Dock icon.
    func openClientApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppIdentity.puckClientBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// No-op if already pinned (repeated Option+Shift+Space while the bubble
    /// is open) -- otherwise a second call would capture .pinned itself as
    /// the state to restore to.
    func pinCharacter() {
        guard let characterController, stateBeforePin == nil else { return }
        stateBeforePin = characterController.currentState
        characterController.transition(to: states.pinned)
    }

    private func unpinCharacter() {
        guard let characterController else { return }
        characterController.transition(to: stateBeforePin ?? states.idle)
        stateBeforePin = nil
    }

    /// The bubble shown when the socket has nobody on it. What is missing is
    /// PuckClient now, not workspace -- it hosts the agent as of 2026-08-15 --
    /// so the wording names the chat window the user would actually open.
    private func showClientOfflineBubble() {
        showNoticeBubble(Strings.text(.bubbleClientOffline), for: 2.5)
    }

    /// Puts the bubble over the pet's head, so what it says comes from it
    /// rather than from the middle of the screen.
    ///
    /// Only speech does this. The Option+Shift+Space input panel stays put at
    /// its own fixed spot (bottom-center, see makeBubble) -- it's a capture
    /// field the user aims at, not something that should chase the pet
    /// around the screen.
    ///
    /// `wasMovedByUser` is deliberately ignored: a bubble the user once
    /// dragged is still the pet's speech, and leaving it parked where the pet
    /// no longer is defeats the whole point.
    /// Live captions while push-to-talk is held.
    ///
    /// No timer, unlike a notice: this bubble lasts exactly as long as the
    /// hold, and `closeCaptionBubble` ends it. It still takes the notice
    /// generation, because the window is shared -- a notice shown a moment
    /// earlier would otherwise close the captions mid-sentence.
    private func showCaptionBubble(_ text: String) {
        guard !isCharacterHidden, !text.isEmpty else { return }
        guard let (bubbleWindow, bubbleView) = makeBubble() else { return }

        noticeBubbleGeneration += 1
        captionBubbleGeneration = noticeBubbleGeneration
        bubbleView.onCancel = { bubbleWindow.closeAndYieldFocus() }
        bubbleWindow.onDismiss = nil
        bubbleView.showMessage(text)
        anchorBubbleToPet(bubbleWindow, size: TextInputBubbleView.speechSize(for: text))
        bubbleWindow.showSpeech()
    }

    /// Ends the caption bubble, if the hold put one up.
    ///
    /// Generation-guarded so releasing the key cannot close something else:
    /// by the time a hold ends, the window may already be showing a notice
    /// that replaced the captions.
    private func closeCaptionBubble() {
        guard captionBubbleGeneration == noticeBubbleGeneration else { return }
        captionBubbleGeneration = nil
        textInputBubbleWindow?.closeAndYieldFocus()
    }

    func anchorBubbleToPet(_ bubbleWindow: TextInputBubbleWindow, size: CGSize) {
        bubbleWindow.setContentSize(size)

        guard
            let window = overlayWindow,
            let body = characterBody,
            let screen = petScreen
        else {
            return
        }

        let origin = SpeechBubblePlacement.origin(
            // body.position is the pet's ground point.
            petGroundPoint: globalAppKitPoint(fromWindowLocal: body.position, window: window),
            petHeight: avatarHitboxSize.height,
            bubbleSize: size,
            visibleFrame: screen.visibleFrame
        )
        bubbleWindow.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
    }

    /// Keeps an open speech bubble over the pet's head as it moves. Called
    /// every frame, next to the click-through hitbox update, which has to
    /// follow the pet for the same reason.
    ///
    /// Placement only, never sizing: the text has not changed, and re-running
    /// `speechSize(for:)` per frame would measure the same string 60 times a
    /// second.
    func keepSpeechBubbleOnPet() {
        guard
            let bubbleWindow = textInputBubbleWindow,
            bubbleWindow.isVisible,
            // Speech only. The input panel sits at its own fixed spot, is
            // being typed into, and honours a drag the user made.
            bubbleWindow.isShowingSpeech,
            let window = overlayWindow,
            let body = characterBody,
            let screen = petScreen
        else {
            return
        }

        let origin = SpeechBubblePlacement.origin(
            petGroundPoint: globalAppKitPoint(fromWindowLocal: body.position, window: window),
            petHeight: avatarHitboxSize.height,
            bubbleSize: bubbleWindow.frame.size,
            visibleFrame: screen.visibleFrame
        )
        guard bubbleWindow.frame.origin != NSPoint(x: origin.x, y: origin.y) else { return }
        bubbleWindow.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
    }

    /// Gap between the quick-capture panel and the bottom of the visible
    /// (Dock-excluded) screen area.
    private static let bottomModalMargin: CGFloat = 60

    func makeBubble() -> (TextInputBubbleWindow, TextInputBubbleView)? {
        guard let screen = petScreen else { return nil }

        let size = TextInputBubbleView.panelSize
        let bubbleWindow = textInputBubbleWindow ?? {
            let newWindow = TextInputBubbleWindow(contentRect: CGRect(origin: .zero, size: size))
            textInputBubbleWindow = newWindow
            return newWindow
        }()

        let bubbleView = TextInputBubbleView(frame: CGRect(origin: .zero, size: size))
        bubbleWindow.setContentSize(size)
        bubbleWindow.contentView = bubbleView

        // Bottom-center -- centred across, hovering just above the Dock.
        // visibleFrame already excludes the Dock/menu bar, so this margin is
        // just breathing room, not Dock clearance.
        let frame = screen.visibleFrame
        if !bubbleWindow.wasMovedByUser {
            bubbleWindow.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + Self.bottomModalMargin
            ))
        }
        return (bubbleWindow, bubbleView)
    }

    private func summonCharacter() {
        // TODO(F3): a real "summon" (walk to the cursor/frontmost window,
        // now that MoveToState exists and is used by point_at/launch_app)
        // isn't wired up here yet. For now this just re-centers the pet on
        // the primary display, standing on the ground.
        guard let area = screenWorkAreas.first else { return }
        moveCharacter(to: GroundedSpawnPosition.position(in: area))
    }

    /// Teleports the pet -- through characterBody (see handleWindowsRebuilt's
    /// comment) so the frame loop's hitbox tracking and any in-flight
    /// movement state stay consistent with where the pet actually renders.
    private func moveCharacter(to windowLocalPoint: CGPoint) {
        guard let window = overlayWindow else { return }
        characterBody?.position = windowLocalPoint
        clickThroughController?.updateCharacter(
            screenPosition: globalAppKitPoint(fromWindowLocal: windowLocalPoint, window: window),
            hitboxSize: avatarHitboxSize
        )
    }

}
