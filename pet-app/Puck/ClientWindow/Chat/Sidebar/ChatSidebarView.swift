//
//  ChatSidebarView.swift
//  Puck
//
//  The workspace/session sidebar, native again (2026-08-15). Replaces
//  chat-web's Sidebar.tsx.
//
//  Stock AppKit idioms rather than a bespoke tree: `List` with a `Section`
//  per workspace is what Mail, Notes and Xcode use for exactly this shape,
//  and it brings selection, keyboard navigation, and the sidebar material
//  with it instead of asking for them to be rebuilt.
//

import AppKit
import SwiftUI

struct ChatSidebarView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    @ObservedObject var store: ClientWindowStore
    /// The branch of the workspace being looked at, from the reader that
    /// refreshes after every write. Overrides this view's own scan for that
    /// one row: a checkout run in the window's terminal is picked up by that
    /// reader, and a sidebar still naming the old branch is worse than no
    /// branch at all.
    var activeBranch: String?
    /// Which branch each project is on, shown beside its name. Held here
    /// rather than in the store: nothing outside this list uses it, and it is
    /// read from disk rather than sent over the socket.
    @StateObject private var branches = WorkspaceBranches()
    /// Presented by the new-workspace button; the folder picker itself is
    /// AppKit's, since SwiftUI has no directory-choosing equivalent.
    @State private var isAddingWorkspace = false
    /// The chat whose Delete was picked, held until the confirmation is
    /// answered. Deleting a chat throws away everything said in it and there
    /// is no undo, so the menu item asks rather than acts.
    @State private var pendingDeletion: SessionSelection?
    /// The workspace whose Delete was picked, held until the confirmation is
    /// answered. A workspace takes every chat in it, so this asks first.
    @State private var pendingWorkspaceDeletion: ClientWorkspace?
    /// What is typed into the filter field. Not remembered across launches:
    /// a filter left on from yesterday is a sidebar that looks empty for no
    /// visible reason.
    @State private var filter = ""
    /// Which workspaces are showing their chats. Opened by clicking the
    /// workspace, and the active one opens itself -- see `body`'s task.
    @State private var expanded: Set<String> = []
    /// The full list of workspaces, as a sheet. The sidebar shows them all
    /// already when there are a few; this is for when there are not a few.
    @State private var isBrowsingWorkspaces = false

    var body: some View {
        // No `selection:`. `List` draws its own highlight for a selected row
        // -- a different shape, a different colour, and drawn edge to edge --
        // so the chats looked nothing like the projects above them, which are
        // buttons that draw their own. One list, one highlight: these draw
        // theirs too.
        List {
            // Three groups, top to bottom: what you can start, the
            // workspaces, and the chats that belong to no workspace in
            // particular. The default workspace is not a row here -- it is
            // the app's own home, and listing it beside the projects made the
            // list say "기본 워크스페이스" twice, once as a place and once as
            // the place you already were.
            Section { actionRows }
            Section {
                ForEach(visibleWorkspaces) { workspace in
                    WorkspaceGroup(
                        workspace: workspace,
                        branch: branch(for: workspace),
                        isActive: workspace.id == store.activeWorkspaceId,
                        sessions: sessions(in: workspace),
                        activeSessionId: store.activeSessionId,
                        isExpanded: Binding(
                            get: { expanded.contains(workspace.id) },
                            set: { isOpen in
                                if isOpen {
                                    expanded.insert(workspace.id)
                                } else {
                                    expanded.remove(workspace.id)
                                }
                            }
                        ),
                        onSelectSession: { session in
                            store.selectSession(workspaceId: workspace.id, sessionId: session.id)
                        },
                        onSelectWorkspace: { store.activeWorkspaceId = workspace.id },
                        onDelete: store.canDeleteWorkspace(workspace.id)
                            ? { pendingWorkspaceDeletion = workspace }
                            : nil,
                        onDeleteSession: { session in
                            pendingDeletion = SessionSelection(
                                workspaceId: workspace.id,
                                sessionId: session.id
                            )
                        },
                        canDeleteSession: { session in
                            store.canDeleteSession(workspaceId: workspace.id, sessionId: session.id)
                        }
                    )
                }
                .listRowInsets(Self.rowInsets)
            } header: {
                sectionHeader(Strings.text(.chatWorkspaces)) {
                    Button { isAddingWorkspace = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.text(.chatNewWorkspace))
                    .help(Strings.text(.chatNewWorkspace))
                }
            }
            Section {
                ForEach(homeSessions) { session in
                    ChatSessionRow(
                        session: session,
                        isActive: store.activeWorkspaceId == ClientWindowStore.defaultWorkspaceId
                            && session.id == store.activeSessionId,
                        onSelect: {
                            store.selectSession(
                                workspaceId: ClientWindowStore.defaultWorkspaceId,
                                sessionId: session.id
                            )
                        }
                    )
                    .contextMenu {
                        // Right-click on the row rather than a visible
                        // button: destructive, rarely wanted, and a trash
                        // icon on every row is a mis-click waiting to happen
                        // in a list you navigate by clicking.
                        Button(Strings.text(.commonDelete), role: .destructive) {
                            pendingDeletion = SessionSelection(
                                workspaceId: ClientWindowStore.defaultWorkspaceId,
                                sessionId: session.id
                            )
                        }
                        .disabled(!store.canDeleteSession(
                            workspaceId: ClientWindowStore.defaultWorkspaceId,
                            sessionId: session.id
                        ))
                    }
                    .listRowInsets(Self.rowInsets)
                }
            } header: {
                sectionHeader(Strings.text(.chatChatsAndTasks)) { EmptyView() }
            }
        }
        // The workspace being worked in shows its chats without being asked;
        // a collapsed group holding the chat you are in is a list that hides
        // where you are.
        .onChange(of: store.activeWorkspaceId, initial: true) {
            guard store.activeWorkspaceId != ClientWindowStore.defaultWorkspaceId else { return }
            expanded.insert(store.activeWorkspaceId)
        }
        .sheet(isPresented: $isBrowsingWorkspaces) {
            WorkspaceBrowserSheet(
                store: store,
                onCreate: {
                    isBrowsingWorkspaces = false
                    isAddingWorkspace = true
                }
            )
        }
        .task(id: store.workspaces.map(\.id).joined()) {
            await branches.reload(projects: projectsByWorkspace)
        }
        // Above the list rather than inside it: it filters every group at
        // once. This went missing when the list was rebuilt around
        // workspaces -- the field stopped being drawn while `filter` and
        // everything reading it stayed, so the box was gone and the code that
        // answers it was still there, filtering by an empty string forever.
        .safeAreaInset(edge: .top) { filterField }
        .listStyle(.sidebar)
        // `List` keeps horizontal margins of its own around the scroll
        // content, on top of every row's insets -- which is where the wide
        // gap down the left of this column came from. `listRowInsets` cannot
        // reach them; this can.
        .contentMargins(.horizontal, 0, for: .scrollContent)
        // AppKit's own sidebar material sat two shades lighter than the
        // island beside it -- (40,39,39) against (16,16,16) -- which read as
        // two unrelated panels rather than one window. Hidden, and painted
        // with the same ground the island uses, so the two agree.
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .sheet(isPresented: $isAddingWorkspace) {
            NewWorkspaceSheet(store: store)
        }
        .confirmationDialog(
            String(format: Strings.text(.chatDeleteWorkspaceTitleFormat), pendingWorkspaceDeletion?.displayName ?? ""),
            isPresented: .init(
                get: { pendingWorkspaceDeletion != nil },
                set: { if !$0 { pendingWorkspaceDeletion = nil } }
            ),
            presenting: pendingWorkspaceDeletion
        ) { target in
            Button(Strings.text(.commonDelete), role: .destructive) {
                store.requestWorkspaceDeletion(workspaceId: target.id)
            }
            Button(Strings.text(.commonCancel), role: .cancel) {}
        } message: { _ in
            Text(Strings.text(.chatDeleteWorkspaceMessage))
        }
        .confirmationDialog(
            Strings.text(.chatDeleteSessionTitle),
            isPresented: .init(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { target in
            Button(Strings.text(.commonDelete), role: .destructive) {
                store.deleteSession(workspaceId: target.workspaceId, sessionId: target.sessionId)
            }
            Button(Strings.text(.commonCancel), role: .cancel) {}
        } message: { _ in
            Text(Strings.text(.chatDeleteSessionMessage))
        }
    }

    /// What can be started from here, above everything that already exists.
    /// The toolbar has ⌘N too, but a sidebar whose first row is "새 대화" is
    /// how every app of this shape opens -- and the toolbar's version is a
    /// glyph you have to already know.
    ///
    /// No settings row: the toolbar's gear is right above it, and two ways in
    /// sitting a centimetre apart is one too many.
    @ViewBuilder
    private var actionRows: some View {
        SidebarActionRow(
            title: Strings.text(.chatNewSession),
            systemImage: "square.and.pencil"
        ) {
            store.requestNewSession(title: ChatSession.placeholderTitle, in: store.activeWorkspaceId)
        }
        // On the row itself, not on the Section around them: a Section's
        // `listRowInsets` never reached these three, so they kept `List`'s
        // own generous gutter and sat visibly shorter than every row below.
        .listRowInsets(Self.rowInsets)
        SidebarActionRow(
            title: Strings.text(.chatWorkspaces),
            systemImage: "square.grid.2x2"
        ) {
            isBrowsingWorkspaces = true
        }
        .listRowInsets(Self.rowInsets)
    }

    /// One rule for every row here. `List` leaves a generous gutter around
    /// each row by default, which is why the chats sat further from each
    /// other than they did from the heading above them -- exactly backwards,
    /// since the heading is what separates one group from the next.
    private static let rowInsets = EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0)

    /// A group's name, with whatever acts on the group at its trailing edge.
    private func sectionHeader<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(ClientTheme.Typography.sessionTitle)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            trailing()
                .foregroundStyle(palette.textSecondary)
        }
        .textCase(nil)
        // Air above the heading, not below it: a heading belongs to the rows
        // under it, and the gap that says "new group" goes over the top.
        .padding(.top, 12)
        .padding(.bottom, 2)
        .padding(.horizontal, 4)
    }

    /// The chats that belong to no project: the default workspace's, shown
    /// directly under "채팅 및 작업" rather than behind a row named after a
    /// place nobody chose to be in.
    private var homeSessions: [ChatSession] {
        guard let home = store.workspaces.first(where: { $0.id == ClientWindowStore.defaultWorkspaceId }) else {
            return []
        }
        return sessions(in: home)
    }

    /// A row of its own above the list, the way Mail and Notes put it. Not
    /// `.searchable`, which on macOS moves the field into the toolbar --
    /// where it would be filtering a list it no longer sits above, and would
    /// share the bar with the chat's own controls.
    private var filterField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                // The field beside it announces itself; this is decoration.
                .accessibilityHidden(true)
            TextField(Strings.text(.chatFilterPlaceholder), text: $filter)
                .textFieldStyle(.plain)
                .font(ClientTheme.Typography.workspaceName)
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.text(.a11yClearSearch))
                .help(Strings.text(.a11yClearSearch))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        // A capsule: it is a field you type a word into, not a panel, and at
        // this height the 4pt corner read as a rectangle with the corners
        // sanded off.
        .background(palette.surface, in: .capsule)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
        .background(palette.background)
    }

    /// Workspaces with something left to show. A workspace whose own name
    /// answers the filter keeps all of its chats; otherwise it is here only
    /// if one of its chats answers it.
    private var visibleWorkspaces: [ClientWorkspace] {
        let workspaces = store.workspaces.filter { $0.id != ClientWindowStore.defaultWorkspaceId }
        guard SidebarFilter.isActive(filter) else { return workspaces }
        return workspaces.filter {
            SidebarFilter.matchesWorkspace(filter, name: $0.displayName, projectPath: $0.projectPath)
                || !sessions(in: $0).isEmpty
        }
    }

    private func sessions(in workspace: ClientWorkspace) -> [ChatSession] {
        let all = store.sessions(in: workspace.id)
        guard SidebarFilter.isActive(filter) else { return all }
        if SidebarFilter.matchesWorkspace(filter, name: workspace.displayName, projectPath: workspace.projectPath) {
            return all
        }
        return all.filter { SidebarFilter.matchesSession(filter, title: $0.displayTitle) }
    }

    private func branch(for workspace: ClientWorkspace) -> String? {
        if workspace.id == store.activeWorkspaceId, let activeBranch { return activeBranch }
        return branches.branches[workspace.id]
    }

    private var projectsByWorkspace: [String: String] {
        store.workspaces.reduce(into: [:]) { result, workspace in
            result[workspace.id] = workspace.projectPath
        }
    }
}

struct SessionSelection: Hashable {
    let workspaceId: String
    let sessionId: String
}
