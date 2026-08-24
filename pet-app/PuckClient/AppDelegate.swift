//
//  AppDelegate.swift
//  PuckClient
//
//  owner: 박해영 (Haeyoung Park)
//  The Claude-Desktop-style client window used to live in-process inside
//  Puck; it moved here (2026-07-30) so it can be a regular, Dock-
//  resident app rather than sharing Puck's LSUIElement lifecycle
//  so it has a permanent Dock presence of its own. Puck still hosts
//  bridge.sock -- this app is just another client of it, identifying
//  itself with client_hello role "gui" (protocol 3.7).
//

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let bridgeClient = BridgeSocketClient()
    private lazy var userInputSender = UserInputSender(transport: { [weak self] in self?.bridgeClient })
    private lazy var clientWindowStore = ClientWindowStore(sender: userInputSender)
    /// Second consumer of clientWindowStore's mutations, alongside the store
    /// itself -- see ClientChatBridge's own header comment for why this is
    /// pushed to imperatively rather than Combine-observed.
    /// F15 (2026-07-31): the agent runs in this process now -- see AgentHost.
    private lazy var agentHost = AgentHost(
        broadcast: { [weak self] message in
            self?.bridgeClient.broadcast(message) ?? false
        },
        resolveProjectPath: { [weak self] workspaceId in
            self?.clientWindowStore.workspaces.first { $0.id == workspaceId }?.projectPath
        },
        // Tells the agent which project it is looking at. Read fresh per run
        // rather than captured: the user switches workspaces between turns.
        describeWorkspace: { [weak self] workspaceId in
            guard let workspace = self?.clientWindowStore.workspaces.first(where: { $0.id == workspaceId })
            else { return nil }
            return AgentRunner.WorkspaceContext(name: workspace.name, projectPath: workspace.projectPath)
        }
    )
    /// Names chats after their first exchange. Its own client rather than the
    /// agent's: this is one small stateless call, and it must not join the
    /// run's conversation.
    private let chatTitler = ChatTitler(client: makeAgentLLMClient { .load() })
    private var window: ClientWindow?
    private var settingsWindow: NSWindow?
    private var clientThemeStyleObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var languageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The two processes go together -- launching either app brings up
        // the other, since this app is useless without Puck hosting
        // bridge.sock on the other end.
        CompanionAppLauncher.launchIfNeeded(bundleIdentifier: AppIdentity.puckBundleID)

        setUpLanguage()
        setUpClientThemeStyle()
        setUpAppearance()

        bridgeClient.onMessage = { [weak self] message in
            DispatchQueue.main.async { self?.handle(message) }
        }
        // pet-app hosts every tool the agent dispatches, so its going away
        // strands whatever is in flight. AgentHost has always known how to
        // fail those; nothing ever told it to.
        bridgeClient.onDisconnect = { [weak self] in
            DispatchQueue.main.async { self?.agentHost.socketDisconnected() }
        }
        // pet-app forgets the tank when the socket drops, and the window only
        // reports it when it changes -- so without this the pet had no way
        // home after pet-app restarted, and stayed on the desktop until
        // something in the window happened to move.
        bridgeClient.onConnect = { [weak self] in
            DispatchQueue.main.async { self?.clientWindowStore.reportPetHomeNow() }
        }
        bridgeClient.start()

        clientWindowStore.onUserCommand = { [weak self] text, workspaceId, sessionId in
            self?.agentHost.run(command: text, workspaceId: workspaceId, sessionId: sessionId)
        }
        clientWindowStore.onApprovalResolved = { [weak self] approvalId, approved in
            self?.agentHost.resolveApproval(id: approvalId, approved: approved)
        }
        clientWindowStore.onSessionDeleted = { [weak self] _, sessionId in
            self?.agentHost.forgetSession(sessionId)
        }
        clientWindowStore.onRunCancelled = { [weak self] in
            self?.agentHost.cancelPendingApprovals()
        }
        agentHost.onRunFinished = { [weak self] workspaceId, sessionId in
            self?.nameChatAfterItsTopic(workspaceId: workspaceId, sessionId: sessionId)
        }
        // Nothing else would ever show it: an event that could not go out is
        // an event pet-app will never relay back -- see AgentHost's own note.
        agentHost.onUndeliverableEvent = { [weak self] event, workspaceId, sessionId in
            DispatchQueue.main.async {
                self?.clientWindowStore.handleChatEvent(event, workspaceId: workspaceId, sessionId: sessionId)
            }
        }
        agentHost.onRevealInEditor = { [weak self] workspaceId, _ in
            self?.clientWindowStore.revealInEditor(workspaceId: workspaceId)
            self?.showWindow()
        }
        agentHost.onTaskSessionOpened = { [weak self] workspaceId, sourceSessionId, sessionId, title, userMessage in
            self?.clientWindowStore.moveTurnToTaskSession(
                workspaceId: workspaceId,
                from: sourceSessionId,
                to: sessionId,
                title: title,
                userMessage: userMessage
            )
        }

        // The pet only comes home for a frontmost window -- reported here
        // rather than inferred from the tank's own visibility, since the
        // window can be fully on screen and still not be the one in front.
        // `queue: .main` makes the MainActor.assumeIsolated below sound; the
        // block itself is not isolated in its signature, so the compiler
        // cannot see that and warns on the main-actor call without it.
        //
        // Matched against *this* window rather than accepting any window's
        // notification: Settings and a detached editor live in this same
        // process, so an unfiltered observer reports "frontmost" while the
        // chat window is behind one of them, and the pet comes home to a tank
        // nobody is looking at.
        // Closing the window takes the tank with it. Without this the pet
        // stayed in it whenever it was pinned -- pinning is for a window
        // behind something else, not for one that is gone.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, note.object as AnyObject === window else { return }
                self.clientWindowStore.setWindowIsOpen(false)
            }
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, note.object as AnyObject === window else { return }
                    self.clientWindowStore.setWindowIsFrontmost(name == NSWindow.didBecomeKeyNotification)
                }
            }
        }

        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    /// Closing this app's window quits it, the same as Cmd+Q, rather than
    /// lingering in the Dock with no window the way Mail and Notes do -- for
    /// this app the window *is* the app. This never touches Puck:
    /// CompanionAppLauncher only runs at each app's own launch, not on the
    /// other's quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Closing the window quits this app, which with a code_editor run in
    /// flight means an ACP child with nobody left to end it.
    func applicationWillTerminate(_ notification: Notification) {
        agentHost.endCodeEditorAgents()
    }

    // MARK: - Theme (ClientThemeStyle, synced from Puck's Settings)

    /// The theme follows the pet's, so it can be changed from the menu bar
    /// rather than from a window buried in this app. This process has no
    /// SettingsStore of its own (same reasoning as everywhere else this
    /// process reads Puck's UserDefaults domain directly instead), so it
    /// reads Puck's `clientThemeStyle` at launch and listens for the
    /// DistributedNotificationCenter broadcast Puck's AppDelegate posts
    /// whenever the setting changes -- the exact shape the old (2026-08-01,
    /// removed 2026-08-01, now reinstated here for a different value)
    /// AppAppearance cross-process wiring used.
    // MARK: - UI language, synced from Puck's Settings

    /// Same wiring as the theme below, for the same reason: this process has
    /// no SettingsStore, so it reads Puck's `language` at launch and follows
    /// the broadcast afterwards. Applied before the window is built, since
    /// every string in it is resolved as the views are constructed.
    private func setUpLanguage() {
        Localization.shared.apply(Self.currentLanguage())
        languageObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppLanguage.crossProcessChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            // The value travels with the notification; re-reading Puck's
            // defaults domain is only the fallback for one that arrived
            // without it. See the theme observer below.
            let language = AppLanguage.resolved(fromCrossProcessUserInfo: notification.userInfo)
                ?? Self.currentLanguage()
            Localization.shared.apply(language)
        }
    }

    /// nonisolated: the language observer runs outside the main actor's
    /// isolation even though it is delivered on the main queue, and this reads
    /// nothing but a defaults domain.
    private nonisolated static func currentLanguage() -> AppLanguage {
        let raw = UserDefaults(suiteName: AppIdentity.puckBundleID)?.string(forKey: AppLanguage.defaultsKey)
        return AppLanguage.resolved(fromDefaultsValue: raw)
    }

    private func setUpClientThemeStyle() {
        applyClientThemeStyle(currentClientThemeStyle())
        clientThemeStyleObserver = DistributedNotificationCenter.default().addObserver(
            forName: ClientThemeStyle.crossProcessChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // The value travels with the notification itself -- re-reading
            // Puck's UserDefaults domain here would race against whether
            // that write had actually propagated by the time this
            // notification arrived (the same race AppAppearance's old
            // broadcast hit first); re-reading is only the fallback for a
            // notification that somehow arrived without one.
            // `queue: .main` above is what makes this true; NotificationCenter's
            // block is not isolated in its signature, so the compiler cannot
            // see it and warns on both main-actor calls below.
            MainActor.assumeIsolated {
                let style = ClientThemeStyle.resolved(fromCrossProcessUserInfo: notification.userInfo)
                    ?? self?.currentClientThemeStyle()
                    ?? .dark
                self?.applyClientThemeStyle(style)
            }
        }
    }

    /// The light/dark override, which only Puck has a picker for. This
    /// process has its own NSApp, and nothing was setting its appearance:
    /// with the app set to Light, PuckClient's menus, popovers and every
    /// NSVisualEffectView stayed in whatever the system was, so the two
    /// windows of one app sat in two appearances.
    private func setUpAppearance() {
        applyNativeAppearance()
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppAppearance.crossProcessChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.applyNativeAppearance(
                    AppAppearance.resolved(fromCrossProcessUserInfo: notification.userInfo)
                )
            }
        }
    }

    private nonisolated static func currentAppearance() -> AppAppearance {
        AppAppearance.resolved(
            fromDefaultsValue: AppAppearance.sharedDefaults?.string(forKey: AppAppearance.defaultsKey)
        )
    }

    /// Both settings write `NSApp.appearance`, so one of them has to win.
    ///
    /// They used to write it in turn: the theme set dark/light, and the
    /// appearance setting then set nil for its "system" default, which is
    /// what ships -- so native chrome followed macOS while the app was in a
    /// dark theme, the exact mismatch applyClientThemeStyle exists to
    /// prevent. And the other way round, changing the theme overrode a Light
    /// choice the user had made explicitly.
    ///
    /// The rule: an explicit Light or Dark is the user saying what they want
    /// and wins. "System" hands the decision to the theme, because a theme is
    /// also a deliberate choice and the panels should match the window.
    @MainActor
    private func applyNativeAppearance(
        _ appearance: AppAppearance? = nil,
        themeStyle: ClientThemeStyle? = nil
    ) {
        // Either observer may already hold the new value; re-reading the
        // defaults is the fallback, not the first choice, because the write
        // came from the other process and its own cache may not have caught
        // up yet.
        if let explicit = (appearance ?? Self.currentAppearance()).nsApplicationAppearance {
            NSApp.appearance = explicit
            return
        }
        let style = themeStyle ?? currentClientThemeStyle()
        NSApp.appearance = NSAppearance(named: style.colorScheme == .dark ? .darkAqua : .aqua)
    }

    private func currentClientThemeStyle() -> ClientThemeStyle {
        let raw = UserDefaults(suiteName: AppIdentity.puckBundleID)?.string(forKey: ClientThemeStyle.defaultsKey)
        return ClientThemeStyle.resolved(fromDefaultsValue: raw)
    }

    private func applyClientThemeStyle(_ style: ClientThemeStyle) {
        clientWindowStore.themeStyle = style
        // Native chrome (NSOpenPanel, popovers) follows NSApp.appearance, not
        // SwiftUI's .preferredColorScheme, which never touches them -- same
        // reason Puck's own AppDelegate sets NSApp.appearance alongside
        // its SwiftUI modifier.
        applyNativeAppearance(themeStyle: style)
        // Clear, so WindowBackdrop's blur is what shows. Safe here in a way
        // the 2026-08-02 attempt was not: that one made the window
        // see-through with nothing behind the content, so the native
        // titlebar blended against the desktop. The backdrop now fills the
        // window, titlebar area included.
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }

    private func handle(_ message: BridgeMessage) {
        switch message {
        case .event(let event, let workspaceId, let sessionId):
            // Straight into the store since 2026-08-15: it used to go through
            // ClientChatBridge, which folded it here and then pushed the same
            // delta to chat-web. SwiftUI observes the store, so the second
            // half had nothing left to do.
            clientWindowStore.handleChatEvent(event, workspaceId: workspaceId, sessionId: sessionId)
            agentHost.handle(event, sessionId: sessionId)
        case .workspaceCreate, .sessionCreate, .workspaceDelete:
            clientWindowStore.handleClientUpdate(message)
        case .voiceListening(let listening):
            // pet-app owns the microphone; this is it saying whether the hold
            // this window asked for is actually recording.
            clientWindowStore.applyVoiceListening(listening)
        case .toolResult(let result):
            // The reply to a tool this app's agent dispatched. pet-app sends
            // it back on the same connection, so it arrives here rather than
            // through the relay.
            agentHost.handle(result)
        case .userInput(let input):
            // Mirrored from pet-app's quick-capture bubble: typing there has
            // to bring this window up with the text already in the chat
            // Only shows the window if the message
            // actually landed in a session -- an unknown workspace/session
            // would pop an empty window for nothing.
            if clientWindowStore.showUserMessage(input.text, workspaceId: input.workspaceId, sessionId: input.sessionId) {
                showWindow()
                // F15: and it is a command, not just text to display -- the
                // pet's bubble and its push-to-talk are inputs to the same
                // agent the chat's own input bar feeds.
                agentHost.run(
                    command: input.text,
                    workspaceId: input.workspaceId ?? ClientWindowStore.defaultWorkspaceId,
                    sessionId: input.sessionId ?? ClientWindowStore.defaultSessionId
                )
            }
        default:
            break // relayed to this connection only ever as one of the above (protocol 3.7)
        }
    }

    // MARK: - Settings (F15 agent config, moved here 2026-08-02)

    /// Wired from ClientMainMenu's Settings item (Cmd+,) via the responder
    /// chain: the agent's settings belong to this app, since the agent runs
    /// in this process. `@objc` and this exact selector name
    /// are load-bearing: ClientMainMenu references `Selector(("showSettings:"))`
    /// as a raw string rather than `#selector(AppDelegate.showSettings(_:))`
    /// so that file keeps compiling in PuckTests, which never links this
    /// class (see ClientMainMenu's own header comment).
    @objc private func showSettings(_ sender: Any?) {
        let window = settingsWindow ?? {
            let newWindow = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.applyGlassChrome()
            newWindow.contentViewController = NSHostingController(rootView: AgentSettingsView(clientWindowStore: clientWindowStore))
            newWindow.center()
            settingsWindow = newWindow
            return newWindow
        }()
        // Set on every show, not once at construction: the window is kept
        // around after closing, and its title is the one piece of it AppKit
        // owns rather than SwiftUI -- nothing would relabel it on a language
        // change otherwise.
        window.title = Strings.text(.chatSettings)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Replaces the name ChatSession gave itself from the opening line with
    /// one the model read off the whole first exchange.
    ///
    /// Everything that decides *whether* to ask lives on the session, so the
    /// cost is skipped without a call: a chat the agent or the protocol named,
    /// one already titled, and one whose run produced no answer to read.
    private func nameChatAfterItsTopic(workspaceId: String, sessionId: String) {
        guard let session = clientWindowStore.session(workspaceId: workspaceId, sessionId: sessionId),
              session.isAutoTitled,
              !session.hasTopicTitle,
              let exchange = session.firstExchange
        else { return }

        Task { [chatTitler] in
            guard let topic = await chatTitler.title(user: exchange.user, reply: exchange.reply) else { return }
            await MainActor.run { session.applyTopicTitle(topic) }
        }
    }

    private func showWindow() {
        clientWindowStore.setWindowIsOpen(true)
        let window = window ?? {
            // Sidebar + file tree + Monaco + chat all fighting for width once
            // the editor pane opens. At origin (0,0) it opens in the
            // bottom-left corner, so this keeps the explicit contentRect
            // instead of relying on center() alone.
            let newWindow = ClientWindow(contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900))
            let hosting = NSHostingController(rootView: ClientWindowView(store: clientWindowStore))
            // NSHostingController defaults to sizingOptions
            // .preferredContentSize, i.e. it keeps pushing the SwiftUI
            // fitting size onto the window -- which is why the window opened
            // at whatever the layout happened to fit in (~884x651, then
            // 700x471) no matter what contentRect or setContentSize said.
            hosting.sizingOptions = []
            newWindow.contentViewController = hosting
            newWindow.setContentSize(CGSize(width: 1440, height: 900))
            // The floor for a chat-only window. ClientWindowView raises it
            // while the editor pane is open (WindowMinimumSize) -- one number
            // cannot serve both, and this one is only the starting value.
            newWindow.minSize = CGSize(width: ClientTheme.Metrics.windowMinWidth, height: ClientTheme.Metrics.windowMinHeight)
            newWindow.center()
            self.window = newWindow
            return newWindow
        }()
        window.showAndActivate()
    }
}
