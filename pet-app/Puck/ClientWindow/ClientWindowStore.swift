//
//  ClientWindowStore.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Source of truth for the client window's sidebar: workspaces, each
//  workspace's chat sessions, and which one is active. Fed by PuckClient's
//  BridgeSocketClient for incoming state and UserInputSender for outgoing
//  requests (F13).
//

import Foundation

final class ClientWindowStore: ObservableObject {
    static let defaultWorkspaceId = "default"
    static let defaultSessionId = "default"
    /// Defined on ChatSession, which is also what matches on it. A stored,
    /// language-independent value; `ChatSession.displayTitle` translates it.
    private static let casualSessionTitle = ChatSession.casualTitle

    private let sender: UserInputSender
    /// Every chat this window knows about -- see SessionList, which owns the
    /// keying and the ordering.
    private var sessionList = SessionList()

    static let tankPinnedKey = "Puck.tankPinned"

    /// What this window tells pet-app about the island -- see PetHomeReport,
    /// which owns the three facts and what they mean together.
    private var petHome = PetHomeReport()

    /// Read by the island's own tests and by nothing else in the app: the
    /// window reports these in and never reads them back.
    var tankFrame: CGRect? { petHome.tankFrame }
    var windowIsFrontmost: Bool { petHome.windowIsFrontmost }
    var windowIsOpen: Bool { petHome.windowIsOpen }

    func setTankFrame(_ frame: CGRect?) {
        reportPetHomeIfChanged(petHome.setTankFrame(frame))
    }

    /// How tall the pet stands on the island, in points, from the lever on
    /// the island. Kept here rather than read straight from UserDefaults by
    /// the lever, because unlike the backdrop this one leaves the process --
    /// pet-app is what actually resizes the pet.
    func setPetIslandHeight(_ height: CGFloat) {
        sender.setPetIslandHeight(Double(height))
    }

    func setWindowIsFrontmost(_ isFrontmost: Bool) {
        reportPetHomeIfChanged(petHome.setWindowIsFrontmost(isFrontmost))
    }

    func setWindowIsOpen(_ isOpen: Bool) {
        reportPetHomeIfChanged(petHome.setWindowIsOpen(isOpen))
    }

    /// Sends the tank as it stands, whether or not anything changed.
    ///
    /// For a reconnection: pet-app forgets the tank when the socket drops, and
    /// everything else here reports only on change, so after a reconnect
    /// nothing would ever tell it where the tank is again.
    func reportPetHomeNow() {
        reportPetHome()
    }

    private func reportPetHomeIfChanged(_ changed: Bool) {
        guard changed else { return }
        reportPetHome()
    }

    private func reportPetHome() {
        guard let space = GlobalScreenSpace.current() else { return }
        sender.reportPetHome(
            rect: petHome.wireRect(in: space),
            visible: petHome.isPetVisible(in: space)
        )
    }

    /// F15 (2026-07-31): set when an agent runs in this process, which it now
    /// does -- see AgentHost. A command then goes straight to it instead of
    /// out as user_input, since user_input exists to hand the command to
    /// *workspace's* agent and there is no workspace. Left nil in tests and
    /// wherever no agent is attached, in which case the old socket path
    /// stands.
    var onUserCommand: ((_ text: String, _ workspaceId: String, _ sessionId: String) -> Void)?
    /// A chat was deleted. The agent keeps that chat's conversation, and the
    /// user throwing the chat away is them throwing that away too.
    var onSessionDeleted: ((_ workspaceId: String, _ sessionId: String) -> Void)?
    /// Same reason: approval is resolved inside this process, not by a
    /// workspace on the far side of the socket.
    var onApprovalResolved: ((_ approvalId: String, _ approved: Bool) -> Void)?
    var onRunCancelled: (() -> Void)?

    @Published private(set) var workspaces: [ClientWorkspace] {
        didSet { refreshWorkspaceIndex() }
    }

    /// What `workspaces` says, readable from any thread.
    ///
    /// The array itself is not: SwiftUI mutates it on the main thread, and
    /// the agent asks which project a workspace points at from inside a run,
    /// on whatever executor that run is using. Those overlapped -- a
    /// workspace created or deleted over the socket mid-run is a mutation
    /// racing a read of the same array, not merely a stale answer. This is
    /// the copy the other threads read.
    private let workspaceIndexLock = NSLock()
    private var workspaceIndex: [String: ClientWorkspace] = [:]

    /// One workspace, for a caller that is not on the main thread. Nil when
    /// there is no such workspace -- including when it has just been deleted,
    /// which is the honest answer to a run still asking about it.
    nonisolated func workspaceSnapshot(_ id: String) -> ClientWorkspace? {
        workspaceIndexLock.lock()
        defer { workspaceIndexLock.unlock() }
        return workspaceIndex[id]
    }

    private func refreshWorkspaceIndex() {
        let index = Dictionary(workspaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        workspaceIndexLock.lock()
        workspaceIndex = index
        workspaceIndexLock.unlock()
    }
    @Published var activeWorkspaceId: String
    @Published var activeSessionId: String

    /// The theme should stay in sync with the menu bar settings, the same
    /// way Shady-style apps let you flip theme from the menu bar -- so it's
    /// a Puck Settings item now
    /// (SettingsStore.clientThemeStyle), not a ClientWindow-local one. This
    /// store doesn't persist or own the value at all; PuckClient's
    /// AppDelegate seeds it at launch (reading Puck's UserDefaults domain)
    /// and keeps it live via a DistributedNotificationCenter broadcast --
    /// same shape the old `appearance` property (removed 2026-08-01, since
    /// undone here) used for Puck's own system-wide AppAppearance.
    @Published var themeStyle: ClientThemeStyle = .dark

    /// Bumped when the agent wants a file on screen -- ClientWindowView opens
    /// the editor pane in response. A counter rather than a Bool: two files in
    /// a row have to register as two requests, and the second one must still
    /// re-open a pane the user closed in between.
    @Published private(set) var editorRevealRequests = 0

    /// Called when the agent opens a file for the user to look at, or edits
    /// one during a code_editor run. Switches to the file's workspace first --
    /// the pane can only show the active one.
    func revealInEditor(workspaceId: String) {
        if activeWorkspaceId != workspaceId, workspaces.contains(where: { $0.id == workspaceId }) {
            activeWorkspaceId = workspaceId
            activeSessionId = Self.defaultSessionId
        }
        editorRevealRequests += 1
    }

    /// - Parameter archive: where the chats are kept between launches. Nil
    ///   means "do not keep them", which is what every test wants -- a default
    ///   pointing at the real file would have each of them reading and
    ///   overwriting the user's own conversations.
    init(sender: UserInputSender, archive: ChatArchive? = nil) {
        self.sender = sender
        self.archive = archive
        workspaces = [ClientWorkspace(id: Self.defaultWorkspaceId, name: Self.casualSessionTitle, projectPath: nil)]
        activeWorkspaceId = Self.defaultWorkspaceId
        activeSessionId = Self.defaultSessionId
        // `didSet` does not run for an initialisation, so the first index is
        // built by hand -- after the last stored property, which is when
        // `self` may be used at all.
        refreshWorkspaceIndex()
        // Before the casual session is seeded, not after: the seed is
        // idempotent per (workspace, id), so a restored casual chat keeps
        // everything said in it and the seed then does nothing. The other way
        // round, an empty one would be in the list first and the restored one
        // refused.
        for session in archive?.load() ?? [] {
            insertSession(session)
        }
        seedDefaultSession(forWorkspace: Self.defaultWorkspaceId)
    }

    /// Everything said in every chat, kept between launches -- see ChatArchive.
    private let archive: ChatArchive?
    /// The pending write. Coalesced rather than written per change: a reply
    /// streams in a chunk at a time, and a file write per chunk is a file
    /// write per token.
    private var pendingSave: DispatchWorkItem?

    /// Long enough to fold a whole streamed reply into one write, short enough
    /// that a crash loses a sentence rather than a conversation.
    static let saveDelay: TimeInterval = 2

    /// Something in a chat changed, so the file is now behind.
    ///
    /// Called from the places a transcript is actually mutated. It has to be
    /// every one of them -- a chat that changed and never asked to be saved is
    /// a chat that comes back missing its last exchange.
    private func scheduleSave() {
        guard archive != nil else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// Writes now rather than in a moment. For quitting, which is the one
    /// case where "in a moment" never arrives.
    func saveNow() {
        guard let archive else { return }
        pendingSave?.cancel()
        pendingSave = nil
        archive.save(sessionList.all(), knownWorkspaceIds: Set(workspaces.map(\.id)))
    }

    private func seedDefaultSession(forWorkspace workspaceId: String) {
        insertSession(ChatSession(id: Self.defaultSessionId, workspaceId: workspaceId, title: Self.casualSessionTitle, origin: .user))
    }

    /// The one way a session joins the list. `sessionList` is not
    /// `@Published` (the sidebar reads it through `sessions(in:)`), so an
    /// insert has to announce itself -- a sidebar drawn from a stale snapshot
    /// drops rows that exist and leaves the selection under the wrong header.
    /// See SessionList for why an insert that changes nothing is legitimate
    /// and must not announce.
    private func insertSession(_ session: ChatSession) {
        announceIfChanged(sessionList.insert(session))
    }

    /// The one way a session leaves the list -- the mirror of insertSession,
    /// and it announces for the same reason.
    private func removeSession(workspaceId: String, sessionId: String) {
        announceIfChanged(sessionList.remove(workspaceId: workspaceId, sessionId: sessionId))
    }

    /// SessionList reports whether it changed; a mutation that changed
    /// nothing must not announce, or every replayed registry entry redraws
    /// the sidebar.
    private func announceIfChanged(_ changed: Bool) {
        guard changed else { return }
        objectWillChange.send()
        scheduleSave()
    }

    /// Whether the sidebar's Delete should be offered for this chat.
    ///
    /// Two chats it is never offered for. The workspace's casual session:
    /// protocol 3.4 keeps `session_id: "default"` present under every
    /// workspace, and deleteSession falls back to it, so it has to survive. And
    /// one the agent is still working in: the stop button lives inside that
    /// chat, so deleting it would leave a run going with nothing left on screen
    /// to stop it.
    func canDeleteSession(workspaceId: String, sessionId: String) -> Bool {
        guard sessionId != Self.defaultSessionId else { return false }
        return session(workspaceId: workspaceId, sessionId: sessionId)?.isRunning == false
    }

    /// Deletes a chat and everything said in it.
    ///
    /// Local-only, like the close in moveTurnToTaskSession: protocol 3.4 has no
    /// "session deleted" message to send, and replayForNewClient replays
    /// workspaces but never sessions, so nothing brings this one back. pet-app's
    /// SessionRegistry keeps its record, which is harmless -- handleChatEvent
    /// already drops events for a session this store does not know.
    ///
    /// - Returns: whether it was deleted.
    @discardableResult
    func deleteSession(workspaceId: String, sessionId: String) -> Bool {
        guard canDeleteSession(workspaceId: workspaceId, sessionId: sessionId) else { return false }
        removeSession(workspaceId: workspaceId, sessionId: sessionId)
        // Deleting the chat on screen has to leave the user somewhere, and the
        // casual session is the one that is guaranteed to still be there.
        if activeWorkspaceId == workspaceId, activeSessionId == sessionId {
            activeSessionId = Self.defaultSessionId
        }
        onSessionDeleted?(workspaceId, sessionId)
        return true
    }

    /// Sessions under `workspaceId`, oldest first.
    func sessions(in workspaceId: String) -> [ChatSession] {
        sessionList.sessions(in: workspaceId)
    }

    func session(workspaceId: String, sessionId: String) -> ChatSession? {
        sessionList.session(workspaceId: workspaceId, sessionId: sessionId)
    }

    /// Feed for the workspace_create/session_create confirmations off the
    /// socket (protocol 3.4/3.5). Anything else is a caller error --
    /// PuckClient's AppDelegate never routes other kinds here.
    func handleClientUpdate(_ message: BridgeMessage) {
        switch message {
        case .workspaceDelete(let workspaceId):
            applyWorkspaceDeletion(workspaceId: workspaceId)

        case .workspaceCreate(let workspaceId, let name, let projectPath):
            // Idempotent, for the same reason session_create below is: this
            // arrives both when a workspace is created and when pet-app
            // replays its registry on connect (2026-08-15), and the replay
            // includes the "default" workspace this store already seeded for
            // itself. Appending blindly duplicated every sidebar row on
            // reconnect. A repeat updates in place instead -- name and project
            // path can legitimately have changed since.
            if let index = workspaces.firstIndex(where: { $0.id == workspaceId }) {
                workspaces[index].name = name
                workspaces[index].projectPath = projectPath
                workspaces[index].refreshEditorAvailability()
            } else {
                workspaces.append(ClientWorkspace(id: workspaceId, name: name, projectPath: projectPath))
                seedDefaultSession(forWorkspace: workspaceId)
            }

        case .sessionCreate(let workspaceId, let sessionId, let title, let origin):
            insertSession(ChatSession(id: sessionId, workspaceId: workspaceId, title: title, origin: origin))
            if origin == .agent {
                // The agent branching a casual chat into a task
                // session should bring the user along automatically, not
                // leave them to notice a new sidebar entry on their own.
                activeWorkspaceId = workspaceId
                activeSessionId = sessionId
            } else if let waiting = pendingSessionRequests[workspaceId], waiting > 0 {
                // This is a chat our own ChatSession.placeholderTitle button asked for. Spend one
                // press as we go, so one session follows one press.
                pendingSessionRequests[workspaceId] = waiting - 1
                activeWorkspaceId = workspaceId
                activeSessionId = sessionId
            }

        default:
            break
        }
    }

    /// The agent decided this turn is real work and opened a task session for
    /// it (F15 open_task_session, 2026-08-12). This is a **move**, not a
    /// branch: the session the prompt was typed into should close once the
    /// task session takes over, not linger alongside it.
    ///
    /// - the user's own message goes with it, because ChatView echoed it into
    ///   the source session locally and it would otherwise vanish with that
    ///   session, leaving the task session open with nothing in it
    /// - the source chat is closed, *unless* it is the workspace's casual
    ///   session: F13 has `session_id: "default"` always
    ///   present, and closing it would also throw away conversation that has
    ///   nothing to do with this task
    ///
    /// Called locally rather than driven off the socket because there is no
    /// "session closed" message in protocol 3.4 -- only create. Nothing else
    /// owns a session list, so nothing else needs telling.
    func moveTurnToTaskSession(
        workspaceId: String,
        from sourceSessionId: String,
        to sessionId: String,
        title: String,
        userMessage: String
    ) {
        insertSession(ChatSession(id: sessionId, workspaceId: workspaceId, title: title, origin: .agent))
        if !userMessage.isEmpty {
            session(workspaceId: workspaceId, sessionId: sessionId)?.appendUserMessage(userMessage)
        }

        activeWorkspaceId = workspaceId
        activeSessionId = sessionId

        guard sourceSessionId != Self.defaultSessionId, sourceSessionId != sessionId else { return }
        removeSession(workspaceId: workspaceId, sessionId: sourceSessionId)
        // The chat is gone, so the agent's memory of it should be too. The
        // task session was handed a copy on the way out, so nothing is lost.
        onSessionDeleted?(workspaceId, sourceSessionId)
    }

    private func updateWorkspace(_ workspaceId: String, _ mutate: (inout ClientWorkspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        mutate(&workspaces[index])
    }

    /// Re-resolves a workspace's EditorAvailability against the filesystem
    /// right now -- ClientWorkspace.init already does this once at
    /// creation, so this is only needed for the two cases where the
    /// on-disk state can change out from under an already-created
    /// workspace: right before the editor toggle opens (a stale answer from
    /// creation time would otherwise persist for the workspace's whole
    /// lifetime) and when EditorPaneView's live watcher reports the open
    /// project's root itself was moved/deleted.
    func refreshEditorAvailability(forWorkspace workspaceId: String) {
        updateWorkspace(workspaceId) { $0.refreshEditorAvailability() }
    }

    /// Feed for protocol 3.2 events off the socket. A session that doesn't exist
    /// yet (e.g. an event racing ahead of its session_create) is dropped
    /// rather than fabricated with guessed metadata.
    func handleChatEvent(_ event: BridgeEvent, workspaceId: String, sessionId: String) {
        guard let session = session(workspaceId: workspaceId, sessionId: sessionId) else { return }
        session.apply(event)
        scheduleSave()
    }

    @discardableResult
    func requestNewWorkspace(name: String, projectPath: String?) -> UserInputDelivery {
        sender.createWorkspace(name: name, projectPath: projectPath)
    }

    /// How many ChatSession.placeholderTitle presses each workspace is still waiting on. The
    /// session id is minted on the other side, so the button cannot switch to
    /// its chat at press time -- a press arms this, and the matching
    /// session_create spends one. Scoped to our own requests on purpose: a
    /// user-origin session created from anywhere else arrives identically, and
    /// following that one would move the chat out from under whoever is typing
    /// here.
    ///
    /// A count rather than a flag: pressing twice quickly makes two chats, and
    /// with a flag only the first arrival switched, leaving the user in the
    /// older of the two chats they just asked for.
    private var pendingSessionRequests: [String: Int] = [:]

    @discardableResult
    func requestNewSession(title: String, in workspaceId: String) -> UserInputDelivery {
        let delivery = sender.createSession(workspaceId: workspaceId, title: title)
        // Only on `.sent`: a request that never left has no session coming,
        // and leaving this armed would hand the next unrelated session_create
        // a switch it never asked for.
        if delivery == .sent { pendingSessionRequests[workspaceId, default: 0] += 1 }
        return delivery
    }

    /// Routes through whichever workspace/session is currently active.
    ///
    /// The session is put into its running state here rather than in the view
    /// that owns the input bar: this is the one funnel every send goes
    /// through, so a second send button added later cannot forget to do it.
    /// Only on `.sent` -- a message that never left has no answer coming, and
    /// a spinner for it would never stop.
    /// Injectable so tests can run a command without touching the real
    /// `.env`; the app uses the default, which writes the file Settings does.
    /// Built lazily so it can be told which project is open: `/skills` lists
    /// the project's own skills first, and the store is the only thing that
    /// knows which workspace that is. Still assignable, which is how tests
    /// run a command without touching the real `.env`.
    lazy var slashCommands: SlashCommandRunner = {
        var runner = SlashCommandRunner()
        runner.projectPath = { [weak self] in
            // The snapshot, for the same reason the agent's closures use it:
            // a slash command runs from wherever it was submitted.
            guard let self else { return nil }
            return self.workspaceSnapshot(self.activeWorkspaceId)?.projectPath
        }
        return runner
    }()

    /// Whether pet-app is actually listening, as pet-app reports it. The
    /// button asks; this is the answer, and the two differ whenever the
    /// permission is missing.
    @Published private(set) var isVoiceListening = false

    /// Asks pet-app to listen. Held rather than pressed: recognition
    /// finalises when it is released, and what it heard arrives as an
    /// ordinary voice message in whichever session is active.
    func setVoiceListening(_ listening: Bool) {
        sender.setVoiceListening(listening)
    }

    /// pet-app's answer, off the socket.
    func applyVoiceListening(_ listening: Bool) {
        isVoiceListening = listening
    }

    @discardableResult
    func sendMessage(_ text: String, source: UserInput.Source, attachments: [Attachment]? = nil) -> UserInputDelivery {
        let target = session(workspaceId: activeWorkspaceId, sessionId: activeSessionId)
        // A command changes a setting and is answered here; it never reaches
        // the agent. Echoed first so the transcript reads as a conversation
        // rather than an answer to nothing.
        if let command = SlashCommand.parse(text) {
            target?.appendUserMessage(text)
            target?.appendNotice(slashCommands.run(command))
            scheduleSave()
            return .sent
        }
        // Nothing else puts the user's own text in the transcript -- the
        // agent runs in this process and is handed a string, and ChatInputBar
        // clears its field the instant it sends, so without this echo the
        // message is gone for good. Unconditional, unlike markWaitingForAgent
        // below: a message that did not leave still has to be visible to the
        // person who typed it, and the echo has no answer to wait for.
        //
        // The socket branch further down is a different matter. pet-app
        // relays a gui-addressed message back to the connection it came from
        // (BridgeServer.relay, deliberately -- that is how this process hears
        // its own agent's events), so a user_input sent from here would
        // arrive back and be echoed and run a second time. It is unreachable
        // in PuckClient, where `onUserCommand` is always wired, and anything
        // reviving it has to carry a sender id and drop its own.
        // The in-process agent has no attachment channel -- ACP takes a
        // prompt, and `onUserCommand` is a string. Rather than drop the
        // pictures the user just attached, their paths go into the message,
        // where the agent's own file tools can reach them. The socket path
        // below carries them as attachments, which is what it is for.
        let carried = Self.message(text, carrying: onUserCommand == nil ? [] : (attachments ?? []))
        target?.appendUserMessage(carried)
        scheduleSave()
        if let onUserCommand {
            onUserCommand(carried, activeWorkspaceId, activeSessionId)
            target?.markWaitingForAgent()
            // Not `.notDelivered`: the agent is right here, so the
            // offline banner would be a lie even though no
            // workspace is connected.
            return .sent
        }
        let delivery = sender.send(
            text: text,
            source: source,
            workspaceId: activeWorkspaceId,
            sessionId: activeSessionId,
            attachments: attachments
        )
        if delivery == .sent { target?.markWaitingForAgent() }
        return delivery
    }

    /// `text` with the attached files named after it, or unchanged when
    /// there are none. One blank line between, so a long message and its
    /// attachments do not run together.
    static func message(_ text: String, carrying attachments: [Attachment]) -> String {
        guard !attachments.isEmpty else { return text }
        let lines = attachments.map { "Attached file: \($0.path)" }.joined(separator: "\n")
        return text.isEmpty ? lines : text + "\n\n" + lines
    }

    /// Asks pet-app to throw a workspace away. Nothing changes here until it
    /// confirms: the registry is over there, and a sidebar that removed the
    /// row on the ask would be showing a deletion that may not have happened.
    ///
    /// - Returns: whether it was worth asking. The default workspace is not
    ///   removable -- it is where a deleted one's occupants land.
    @discardableResult
    func requestWorkspaceDeletion(workspaceId: String) -> Bool {
        guard canDeleteWorkspace(workspaceId) else { return false }
        sender.deleteWorkspace(workspaceId: workspaceId)
        return true
    }

    /// Whether this one can go at all.
    func canDeleteWorkspace(_ workspaceId: String) -> Bool {
        workspaceId != Self.defaultWorkspaceId && workspaces.contains { $0.id == workspaceId }
    }

    /// pet-app confirmed the deletion: take the workspace, its chats, and any
    /// selection standing in them out of this window.
    func applyWorkspaceDeletion(workspaceId: String) {
        guard workspaces.contains(where: { $0.id == workspaceId }) else { return }
        workspaces.removeAll { $0.id == workspaceId }
        announceIfChanged(sessionList.removeAll(inWorkspace: workspaceId))
        pendingSessionRequests.removeValue(forKey: workspaceId)
        guard activeWorkspaceId == workspaceId else { return }
        // Somewhere to stand: the workspace that cannot be deleted.
        activeWorkspaceId = Self.defaultWorkspaceId
        activeSessionId = Self.defaultSessionId
    }

    /// The sidebar's own selection. Goes through the store rather than
    /// setting the two ids directly so that picking a chat by hand also puts
    /// down any ChatSession.placeholderTitle still armed -- a request whose
    /// confirmation never arrived would otherwise stay armed indefinitely and
    /// jump the user away from the chat they chose the next time any
    /// user-origin session turned up.
    func selectSession(workspaceId: String, sessionId: String) {
        pendingSessionRequests.removeValue(forKey: workspaceId)
        activeWorkspaceId = workspaceId
        activeSessionId = sessionId
    }

    /// Shows text the user typed *somewhere else* (pet-app's quick-capture
    /// bubble, mirrored over the socket as user_input) in this window's chat,
    /// and switches to the session it was sent to -- submitting from the
    /// quick-capture bubble should bring this window up showing what was
    /// typed. Messages sent from this window's own input bar are echoed by
    /// `sendMessage` instead, and go to the in-process agent rather than over
    /// the socket -- see the note there about what would happen if they did.
    ///
    /// - Returns: where the text actually landed, so the caller can run the
    ///   agent against the same chat the user is now looking at, or nil when
    ///   there is nowhere at all to put it.
    ///
    /// A named session that does not exist falls back to the chat on screen
    /// rather than being dropped. Dropping was defensible when this only
    /// decided whether to raise the window; it is not now that the same text
    /// is a command. pet-app has already told the user it was sent -- a gui
    /// connection existed -- so a disagreement between its registry and this
    /// sidebar (a session_create that raced a reconnect) meant someone typed
    /// into the pet's bubble, watched it accept, and nothing ever happened.
    @discardableResult
    func showUserMessage(
        _ text: String,
        workspaceId: String?,
        sessionId: String?
    ) -> (workspaceId: String, sessionId: String)? {
        let requestedWorkspaceId = workspaceId ?? Self.defaultWorkspaceId
        let requestedSessionId = sessionId ?? Self.defaultSessionId
        if let session = session(workspaceId: requestedWorkspaceId, sessionId: requestedSessionId) {
            session.appendUserMessage(text)
            scheduleSave()
            activeWorkspaceId = requestedWorkspaceId
            activeSessionId = requestedSessionId
            return (requestedWorkspaceId, requestedSessionId)
        }
        guard let fallback = session(workspaceId: activeWorkspaceId, sessionId: activeSessionId) else {
            return nil
        }
        fallback.appendUserMessage(text)
        scheduleSave()
        return (activeWorkspaceId, activeSessionId)
    }

    /// Answers the oldest queued approval. The answer never leaves this
    /// process -- the agent waiting on it is `onRunCancelled`'s AgentHost,
    /// right here -- so the request is always dequeued.
    func respondToPendingApproval(in session: ChatSession, approved: Bool) {
        guard let approvalId = session.pendingApproval?.approvalId else { return }
        onApprovalResolved?(approvalId, approved)
        session.resolveApproval(approvalId: approvalId)
    }

    func cancelActiveRun() {
        onRunCancelled?()
    }
}
