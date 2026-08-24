//
//  AppDelegate+Bridge.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Socket server setup and F11/F3 event-reaction routing into
//  character/sfx/avatar and notice bubbles.
//

import Foundation

extension AppDelegate {
    // MARK: - Bridge (socket server, F11/F3 event routing)

    func setUpBridgeServer() {
        guard let toolExecutor else { return }

        let router = BridgeMessageRouter(toolExecutor: toolExecutor)
        router.onEventReaction = { [weak self] reaction in self?.applyEventReaction(reaction) }
        router.onPetHome = { [weak self] rect, visible in
            self?.applyPetHome(rect: rect, visible: visible)
        }
        router.onPetIslandHeight = { [weak self] height in
            self?.applyPetIslandHeight(height)
        }
        // The chat window has no microphone of its own -- the recogniser and
        // the permission for it are here. Same entry points the hotkey uses,
        // so a turn started from the window and one started from the keyboard
        // are the same turn.
        router.onVoiceListen = { [weak self] listening in
            guard let self, let controller = self.voiceInputController else { return }
            if listening {
                controller.pushToTalkDown()
            } else {
                controller.pushToTalkUp()
            }
            // The answer, which is not always the request: a press with no
            // speech-recognition permission is spent on the system prompt and
            // records nothing. Without this the chat window's mic button lit
            // up and stayed lit over a microphone that was never open.
            _ = self.bridgeServer?.send(.voiceListening(controller.isListening), to: .gui)
            if listening, !controller.isListening {
                self.showNoticeBubble(Strings.text(.voicePermissionNeeded), for: 4)
            }
        }
        // Workspace/session creation is answered in-process as of 2026-08-15
        // (was: relayed to workspace, which owned the registries). A registry
        // that can't open its store is not a reason to refuse to launch --
        // same independence principle as BridgeServer.start below.
        if let registry = try? WorkspaceRegistry() {
            router.workspaceCoordinator = WorkspaceCoordinator(workspaces: registry)
            router.onWorkspaceConfirmation = { [weak self] confirmation in
                _ = self?.bridgeServer?.send(confirmation, to: .gui)
            }
        } else {
            AppLogger.shared.log(.error, "WorkspaceRegistry unavailable: new workspaces cannot be created this run")
        }
        // The chat timeline is PuckClient's, fed by its own BridgeSocketClient
        // connection rather than this in-process router (2026-07-30). This
        // router's job is just the pet's own reactions + relaying
        // (BridgeServer.relay handles the actual forwarding to whichever
        // gui-role connections are attached).
        bridgeMessageRouter = router

        let server = BridgeServer()
        server.onFailure = { error in
            AppLogger.shared.log(.error, "BridgeServer failed: \(error)")
        }
        server.onMalformedLine = {
            AppLogger.shared.log(.warning, "BridgeServer: dropped a malformed line from a client")
        }
        server.onGUIPresenceChanged = { [weak self] hasGUI in
            guard hasGUI else {
                // The client's tank went with it -- a rect from a process
                // that's gone is not somewhere to live. Same main-thread hop
                // as the branch below: this touches CharacterController/
                // SpriteAvatar from BridgeServer's own queue otherwise.
                DispatchQueue.main.async { self?.petHomeConnectionLost() }
                return
            }
            // Fires on BridgeServer's own queue, and send() takes that queue
            // synchronously -- hop off it before sending, or it deadlocks.
            DispatchQueue.main.async {
                guard let self else { return }
                // Rebuild the client's sidebar from the registry before
                // anything else: a mirrored message addressed to a workspace
                // PuckClient does not know about yet would be dropped.
                for workspace in router.workspaceCoordinator?.replayForNewClient() ?? [] {
                    _ = self.bridgeServer?.send(workspace, to: .gui)
                }
                guard let pending = self.pendingClientMirror else { return }
                self.pendingClientMirror = nil
                self.bridgeServer?.send(pending, to: .gui)
            }
        }
        server.onMessage = { message, connection in
            // Delivered on BridgeServer's background queue. The router hops to
            // main before touching anything (RealityKit, NSWorkspace,
            // WindowListWatcher) — do not add main-thread work here.
            router.handle(message) { reply in connection.send(reply) }
        }

        do {
            try server.start()
            bridgeServer = server
        } catch {
            // Independence principle: pet-app still works as a pure desktop
            // pet even if the socket can't be set up.
            AppLogger.shared.log(.error, "BridgeServer failed to start: \(error)")
        }
    }

    func applyEventReaction(_ reaction: EventReaction) {
        // First, so the state transition below (if any) is the last word on
        // where the pet ends up rather than being undone by the release's own
        // hop back to idle.
        if reaction.runFinished {
            releasePointingForFinishedRun()
            // Whatever the client last said about its tank decides again now
            // that the tour is over.
            petHomeDecider.resumeReportedState()
            // The caption goes with the pointing it was describing.
            closeSpeechBubble()
        }
        if let kind = reaction.stateTransition {
            characterController?.transition(to: kind)
        }
        if let sfxKey = reaction.sfxKey {
            sfxPlayer?.trigger(sfxKey, loop: false)
        }
        if let emotion = reaction.emotion {
            avatar?.showEmotion(emotion)
        }
        if reaction.jump {
            characterBody?.triggerJump()
        }
        if let bubbleText = reaction.bubbleText {
            showAgentSummaryBubble(bubbleText, holdsForRun: reaction.bubbleHoldsForRun)
        }
    }

    /// Ends whatever the pet is currently saying. Called when a run ends, so
    /// a held caption and the pointing it describes let go together.
    ///
    /// The generation is bumped even when there is nothing to close: a notice
    /// whose timer is still pending must not fire against a bubble that by
    /// then belongs to someone else.
    func closeSpeechBubble() {
        noticeBubbleGeneration += 1
        // Speech only. The input panel is the user's, and this is not their
        // run to end.
        guard let bubbleWindow = textInputBubbleWindow, bubbleWindow.isShowingSpeech else { return }
        bubbleWindow.closeAndYieldFocus()
    }

    /// 02_pet-app.md F3: agent_done(ok=true) shows its summary in a "말풍선"
    /// -- reuses TextInputBubbleView's read-only notice mode (its own doc
    /// comment already anticipated this exact use, found via spec
    /// cross-check), same pattern as showClientOfflineBubble.
    private func showAgentSummaryBubble(_ summary: String, holdsForRun: Bool = false) {
        // Longer than the 2.5s "workspace offline" notice -- a summary is
        // meant to actually be read, not just glanced at.
        //
        // A caption held for the run gets the same backstop the pointing it
        // accompanies does, so the two expire together even if the run never
        // reports finishing at all.
        showNoticeBubble(summary, for: holdsForRun ? PointAtHandler.maximumHoldSeconds : 5.0)
    }

    /// The one timed-notice path (agent summary, workspace offline, mute
    /// sulk). Both handlers are reassigned on every show, not just set once:
    /// the bubble window is shared, so an input session's dismissal (which
    /// unpins the pet) would otherwise still be attached when a notice shows.
    func showNoticeBubble(_ message: String, for duration: TimeInterval, onExpire: (() -> Void)? = nil) {
        // A hidden pet doesn't speak. Every notice here is the pet talking
        // over its own head, and the overlay windows are ordered out while
        // hidden -- so the bubble arrived as a balloon pointing at nothing,
        // which is how an agent reply put the pet back on screen after the
        // user had explicitly hidden it. Guarded in the funnel rather than at
        // the four call sites so a fifth notice can't reintroduce it.
        //
        // `onExpire` still runs: callers use it to release state they took
        // before showing (isGuidingPermission, the mute sulk), and skipping it
        // would strand them.
        guard !isCharacterHidden else {
            if let onExpire {
                // Wrapped rather than handed over directly: `onExpire` is a
                // main-actor closure and `asyncAfter` takes a Sendable one,
                // which is only the same thing because this queue is main's.
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    MainActor.assumeIsolated(onExpire)
                }
            }
            return
        }
        guard let (bubbleWindow, bubbleView) = makeBubble() else { return }

        bubbleView.onCancel = { bubbleWindow.closeAndYieldFocus() }
        // Cleared, not reassigned: onDismiss fires from resignKey, and speech
        // never takes key in the first place. Left pointing at an input
        // session's dismissal it would also unpin the pet out from under a
        // notice.
        bubbleWindow.onDismiss = nil
        bubbleView.showMessage(message)
        // Sized and placed *after* showMessage, which is what decides the
        // typography the size is measured from.
        anchorBubbleToPet(bubbleWindow, size: TextInputBubbleView.speechSize(for: message))
        bubbleWindow.showSpeech()
        // Tagged, because the window is shared: a 5s agent summary followed
        // two seconds later by a 2s mute sulk used to have the summary's timer
        // close the sulk three seconds early -- and run the summary's onExpire
        // against a bubble that was no longer its own.
        noticeBubbleGeneration += 1
        let generation = noticeBubbleGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak bubbleWindow] in
            if self?.noticeBubbleGeneration == generation {
                bubbleWindow?.closeAndYieldFocus()
            }
            // Run either way: this notice is over whether it timed out or was
            // replaced, and the one caller that passes a handler uses it to
            // clear isGuidingPermission -- skipped, that wedges permission
            // guidance off for the rest of the session.
            onExpire?()
        }
    }

    /// How long the pet sulks about being muted.
    private static let mutedComplaintDuration: TimeInterval = 2

    /// Muting the pet mid-session gets a sulk -- the angry face plus
    /// "제 목소리가 시끄러우신거에요?" for two seconds.
    ///
    /// It has to be a bubble rather than a line: the complaint is *about*
    /// being muted, so playing it as audio is the one thing that can't work.
    ///
    /// Only on mute going ON, only from the Settings toggle (Focus's
    /// auto-mute, which sets SFXPlayer directly rather than through the
    /// store, isn't the user telling the pet to be quiet), and only when
    /// SettingsStore.isMuteComplaintEnabled is on -- it's a togglable
    /// preference, not a forced behavior. This used to also drag the pet to
    /// center screen (moveCharacter to controller.roamableArea's midpoint);
    /// that's gone -- the sulk now happens wherever the pet already is.
    /// pinCharacter is still what holds it there for the duration, since a
    /// wandering pet mid-sulk would read as broken either way.
    func showMutedComplaint() {
        guard characterController != nil else { return }

        // pinCharacter, not a raw .pinned transition -- it owns the
        // stateBeforePin bookkeeping, so a hotkey pin overlapping the sulk
        // can't corrupt that pairing. Transition first, then the emotion:
        // entering a state plays that state's own clip, which would otherwise
        // wipe the angry face immediately.
        pinCharacter()
        avatar?.showEmotion("angry")

        showNoticeBubble(Strings.text(.bubbleMutedComplaint), for: Self.mutedComplaintDuration) { [weak self] in
            // Falling is also what puts the face back: entering Fall plays the
            // fall clip, so the sulk ends without anyone having to remember
            // which expression the pet was wearing before it. The pin
            // bookkeeping is discarded rather than restored -- resuming a
            // pre-sulk walk in mid-air would be wrong.
            self?.stateBeforePin = nil
            self?.characterController?.transition(to: .fall)
        }
    }
}
