//
//  SettingsView.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  The menu bar panel: everything the app can be told to do, in one column.
//  Laid out as pokoPet's menu bar popover is -- one narrow scrolling column
//  on a single translucent panel, plain sections, a tinted item grid, action
//  rows at the foot -- dropping straight from the status item rather than
//  opening a separate window.
//
//  The F15 API-key section lives in PuckClient's own Settings window
//  (AgentSettingsView, Cmd+,) instead of here -- the agent that actually
//  reads the key runs there, not here (see AgentConfiguration's own doc
//  comment for why a shared .env rather than the Keychain in the first
//  place).
//

import SwiftUI

struct SettingsView: View {
    let store: SettingsStore
    var onAvatarScaleChanged: ((Double) -> Void)?

    /// Which toys are out when the panel opens. The panel is rebuilt on every
    /// open, so this is a seed rather than a source of truth -- the toy box
    /// itself is that.
    var initialToysOut: Set<String> = []
    /// Returns the toys that are out *after* the toggle -- from what the toy
    /// box actually did, not from what was asked.
    var onToggleToy: ((Toy) -> Set<String>)?

    /// The action rows the NSMenu used to hold.
    var initialIsCharacterHidden: Bool = false
    var onOpenClient: (() -> Void)?
    var onToggleVisibility: (() -> Void)?
    /// Opens the settings window. Only the panel offers this; the window is
    /// not going to offer to open itself.
    var onOpenSettings: (() -> Void)?
    /// Applied while the settings window is open, so the notch appears and
    /// disappears with the switch rather than at the next launch.
    var onNotchPanelChanged: ((Bool) -> Void)?

    /// Whether this is the menu bar's panel rather than the settings window.
    ///
    /// The panel is one click from the status item and sits over whatever the
    /// user was doing, so what belongs in it is what the pet is doing now --
    /// which toys are out, how big they are, which avatar. Volume curves,
    /// walk speed and the language are set once and then left, and they were
    /// making a drop-down panel into a scrolling form. They live in a window
    /// now, and the panel offers a row that opens it.
    var showsOnlyLiveControls = false
    var onQuit: (() -> Void)?

    /// Watched so flipping the language redraws this window's own text
    /// immediately -- every `text(_:)` call below reads through it.
    @ObservedObject private var localization = Localization.shared

    @State private var appearance: AppAppearance
    /// Held rather than read from the store on each render: the picker in
    /// PuckClient's own settings writes the same setting, and nothing here
    /// re-rendered when it did, so this panel kept showing the theme it was
    /// opened with while the chat window was already in the new one.
    @State private var clientTheme: ClientThemeStyle
    @State private var volume: Double
    @State private var isMuted: Bool
    @State private var autoMuteOnFocus: Bool
    @State private var isMuteComplaintEnabled: Bool
    @State private var avoidClimbingFocusedWindow: Bool
    @State private var notchPanelEnabled: Bool
    @State private var petAnnouncesRuns: Bool
    @State private var isAvatarMirrored: Bool
    @State private var isAvatarOutlined: Bool
    @State private var avatarScale: Double
    @State private var poseAdjustments: AvatarPoseAdjustments
    /// Which page is open. Stored rather than held: the window builds a
    /// fresh view on every show (see showSettingsWindow), and a page that
    /// reset to the first one each time would send somebody back through the
    /// list for the setting they were just looking at.
    @AppStorage("Puck.settingsCategory") private var category: SettingsCategory = .avatar
    @State private var toyScale: Double
    @State private var walkSpeedMultiplier: Double
    @State private var toysOut: Set<String>
    /// Tracked locally so the hide/show row relabels itself immediately --
    /// the panel stays open after the toggle, and rebuilding it just to
    /// change one word would dismiss whatever else the user was doing.
    @State private var isCharacterHidden: Bool

    init(
        store: SettingsStore,
        onAvatarScaleChanged: ((Double) -> Void)? = nil,
        initialToysOut: Set<String> = [],
        onToggleToy: ((Toy) -> Set<String>)? = nil,
        initialIsCharacterHidden: Bool = false,
        onOpenClient: (() -> Void)? = nil,
        onToggleVisibility: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onNotchPanelChanged: ((Bool) -> Void)? = nil,
        onQuit: (() -> Void)? = nil,
        showsOnlyLiveControls: Bool = false
    ) {
        self.store = store
        self.onAvatarScaleChanged = onAvatarScaleChanged
        self.initialToysOut = initialToysOut
        self.onToggleToy = onToggleToy
        self.initialIsCharacterHidden = initialIsCharacterHidden
        self.onOpenClient = onOpenClient
        self.onToggleVisibility = onToggleVisibility
        self.onOpenSettings = onOpenSettings
        self.onNotchPanelChanged = onNotchPanelChanged
        self.onQuit = onQuit
        self.showsOnlyLiveControls = showsOnlyLiveControls
        _appearance = State(initialValue: store.appearance)
        _clientTheme = State(initialValue: store.clientThemeStyle)
        _volume = State(initialValue: Double(store.volume))
        _isMuted = State(initialValue: store.isMuted)
        _autoMuteOnFocus = State(initialValue: store.autoMuteOnFocus)
        _isMuteComplaintEnabled = State(initialValue: store.isMuteComplaintEnabled)
        _avoidClimbingFocusedWindow = State(initialValue: store.avoidClimbingFocusedWindow)
        _notchPanelEnabled = State(initialValue: store.isNotchPanelEnabled)
        _petAnnouncesRuns = State(initialValue: store.petAnnouncesRuns)
        _isAvatarMirrored = State(initialValue: store.isAvatarMirrored)
        _isAvatarOutlined = State(initialValue: store.isAvatarOutlined)
        _poseAdjustments = State(initialValue: store.avatarPoseAdjustments)
        // Read from the avatar's manifest rather than a setting: that is
        // where the size lives, and a slider that opened at the wrong value
        // would move the pet the moment it was touched.
        _avatarScale = State(
            initialValue: (try? AvatarManifestEditor.loadManifest(
                directory: AvatarManifestEditor.currentAvatarDirectory(named: store.selectedAvatarName)
            ).scale) ?? 1
        )
        _walkSpeedMultiplier = State(initialValue: store.walkSpeedMultiplier)
        _toyScale = State(initialValue: store.toyScale)
        _toysOut = State(initialValue: initialToysOut)
        _isCharacterHidden = State(initialValue: initialIsCharacterHidden)
    }

    private func text(_ key: L10nKey) -> String {
        Strings.text(key, language: localization.language)
    }

    /// One block of settings, drawn wherever it is asked for.
    ///
    /// The split used to live in `body` alone, and the caller had to guess
    /// which callbacks that implied. It guessed wrong once -- the window drew
    /// the toy tiles, the visibility row and Quit with every callback nil, so
    /// they rendered as live controls and did nothing. One list, tested.
    enum SectionGroup: Equatable {
        /// Which avatar, how big, and which way round. The whole manager --
        /// picker, import, emotion mapping. Window only; it is a page.
        case avatar
        /// Just the size slider, for reaching at a glance.
        case avatarSize
        /// What the pet looks like walking, climbing and hanging, and how to
        /// turn one that came out the wrong way round.
        case poses
        /// Light, dark, or follow the system.
        case theme
        /// Which toys are out. Needs callbacks only the panel supplies.
        case toys
        /// Mute and volume: the two things worth reaching for mid-sentence.
        case quickSound
        /// The rest of sound, set once and left.
        case sound
        case movement
        case general
        /// Open chat, hide, quit -- and the row that opens the window.
        case actions
    }

    /// Which sections this instance draws.
    ///
    /// The window is where things are *configured*, so it holds everything
    /// that can be: the avatar manager included, which used to be reachable
    /// only from a popover you had to keep open while looking at it.
    ///
    /// The popover is a quick view, so it holds the handful of things worth
    /// changing without opening anything: the toys, mute and volume, how big
    /// the pet is, and which way the theme goes. Everything that is read
    /// before it is decided -- the avatar manager, the movement options, the
    /// language, the permissions -- is in the window.
    ///
    /// Size and theme are in both. They are settings you nudge and look at
    /// rather than settings you sit down to, and sending somebody to a window
    /// to nudge one is the reason the split exists.
    var sections: [SectionGroup] {
        showsOnlyLiveControls
            ? [.toys, .quickSound, .avatarSize, .theme, .actions]
            : SettingsCategory.allCases.flatMap(\.sections)
    }

    /// The window's left-hand list.
    ///
    /// The window used to be one column the width of the popover, so every
    /// section added to it made the same scroll longer -- the avatar manager
    /// alone is a picker, an importer and sixteen emotion rows, and after it
    /// came four more sections nobody could see without scrolling past all of
    /// that. A page you have to scroll to find out what is in it is a page
    /// that hides its own contents.
    ///
    /// Categories rather than a longer window: a taller window runs out of
    /// screen, and a wider one only helps if something is beside something
    /// else.
    enum SettingsCategory: String, CaseIterable, Identifiable {
        case avatar
        case poses
        case sound
        case movement
        case general

        var id: String { rawValue }

        var sections: [SectionGroup] {
            switch self {
            case .avatar: return [.avatar]
            case .poses: return [.poses]
            case .sound: return [.quickSound, .sound]
            case .movement: return [.movement]
            case .general: return [.general]
            }
        }

        var symbol: String {
            switch self {
            case .avatar: return "person.crop.square"
            case .poses: return "figure.walk"
            case .sound: return "speaker.wave.2"
            case .movement: return "arrow.left.arrow.right"
            case .general: return "gearshape"
            }
        }

        var label: L10nKey {
            switch self {
            case .avatar: return .tabAvatar
            case .poses: return .posePreviewHeader
            case .sound: return .tabSound
            case .movement: return .tabMovement
            case .general: return .tabGeneral
            }
        }
    }

    /// How tall the settings *window* asks to be.
    ///
    /// It has to ask. The window was left to size itself to its content, and
    /// what it holds is a ScrollView -- which has no height of its own to
    /// report, so there was nothing to size to. The window came up as a title
    /// bar with a sliver underneath and read as empty, when everything was
    /// in there all along.
    ///
    /// A minimum and an ideal rather than a fixed height, so the window opens
    /// showing most of the form and can still be dragged taller.
    static let windowMinHeight: CGFloat = 420
    static let windowIdealHeight: CGFloat = 620

    /// Wide enough for a form beside a list, rather than a column the width
    /// of a menu bar popover.
    static let sidebarWidth: CGFloat = 170
    static let windowMinWidth: CGFloat = 560
    static let windowIdealWidth: CGFloat = 820

    var body: some View {
        Group {
            if showsOnlyLiveControls { popover } else { window }
        }
        .preferredColorScheme(appearance.colorScheme)
        // `.id` forces SwiftUI to discard and rebuild this subtree instead of
        // diffing it in place: Light->System looked broken while Light->Dark
        // rendered fine.
        // Explicit->explicit (Light->Dark) is a genuine value change SwiftUI
        // diffs correctly; explicit->nil (System) is a documented SwiftUI
        // quirk where `.preferredColorScheme(nil)` sometimes fails to
        // invalidate a previously-applied explicit override in place, leaving
        // stale light-derived rendering under what should now be system
        // (dark) chrome. Keying identity on the enum itself sidesteps the
        // diff path entirely for every transition, not just this one.
        .id(appearance)
        // Wherever it was changed from -- this panel, or the picker in
        // PuckClient's settings window, which writes the same key.
        .onReceive(
            DistributedNotificationCenter.default().publisher(for: ClientThemeStyle.crossProcessChangeNotification)
        ) { notification in
            guard let style = ClientThemeStyle.resolved(fromCrossProcessUserInfo: notification.userInfo) else { return }
            clientTheme = style
        }
    }

    /// The menu bar's quick view: one column, fixed size, nothing to choose
    /// between.
    private var popover: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                column(of: sections)
            }
            if sections.contains(.actions) {
                Divider().opacity(0.5)
                actionSection
            }
        }
        .frame(width: MenuBarController.panelSize.width, height: MenuBarController.panelSize.height)
    }

    /// The window: a list of categories beside the one that is chosen.
    private var window: some View {
        HStack(spacing: 0) {
            List(SettingsCategory.allCases, selection: $category) { item in
                Label(text(item.label), systemImage: item.symbol)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: Self.sidebarWidth)
            Divider().opacity(0.5)
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                ScrollView {
                    // Keyed on the category so the scroll starts at the top
                    // of each page rather than wherever the last one was
                    // left.
                    column(of: category.sections).id(category)
                }
            }
        }
        .frame(
            minWidth: Self.windowMinWidth,
            idealWidth: Self.windowIdealWidth,
            maxWidth: .infinity,
            minHeight: Self.windowMinHeight,
            idealHeight: Self.windowIdealHeight,
            maxHeight: .infinity
        )
    }

    private func column(of groups: [SectionGroup]) -> some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingLarge) {
            // Each section is listed once and drawn where it is asked for.
            // The two halves used to be all-or-nothing, and a section that
            // belonged in both had nowhere to go.
            if groups.contains(.avatar) { avatarSection }
            if groups.contains(.toys) { toySection }
            if groups.contains(.quickSound) { quickSoundSection }
            if groups.contains(.avatarSize) { avatarSizeSection }
            if groups.contains(.poses) { poseSection }
            if groups.contains(.theme) { themeSection }
            if groups.contains(.sound) { soundSection }
            if groups.contains(.movement) { movementSection }
            if groups.contains(.general) { generalSection }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ClientTheme.Metrics.spacingMedium)
    }

    private var header: some View {
        HStack(spacing: ClientTheme.Metrics.spacingSmall) {
            Image("PumpkinLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            Text(AppIdentity.displayName)
                .font(ClientTheme.Typography.workspaceName)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .padding(.vertical, ClientTheme.Metrics.spacingMedium)
    }

    private var avatarSection: some View {
        AvatarManagementView(
            initialSelectedAvatarName: store.selectedAvatarName,
            onSelectAvatar: { store.selectedAvatarName = $0 }
        )
    }

    /// The reference's "아이템" grid. Ours is the toy box, which until now
    /// was reachable only from the menu bar's submenu.
    private var toySection: some View {
        SettingsSection(title: text(.menuToys)) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: ClientTheme.Metrics.spacingMedium),
                          GridItem(.flexible(), spacing: ClientTheme.Metrics.spacingMedium)],
                spacing: ClientTheme.Metrics.spacingMedium
            ) {
                ForEach(ToyCatalogue.all, id: \.name) { toy in
                    ToyTile(
                        name: text(ToyPresentation.label(for: toy)),
                        artwork: ToyThumbnail.image(for: toy, boundingSide: 64),
                        tint: ToyPresentation.tint(for: toy),
                        isOut: toysOut.contains(toy.name)
                    ) {
                        guard let onToggleToy else { return }
                        toysOut = onToggleToy(toy)
                    }
                }
            }
            SettingsStackedRow(label: text(.toySizeLabel), value: String(format: "%.2fx", toyScale)) {
                Slider(value: $toyScale, in: 0.5...3.0)
                    .onChange(of: toyScale) { _, newValue in store.toyScale = newValue }
            }
        }
    }

    /// The size slider on its own, without the manager around it.
    ///
    /// Writes through the same store property and the same live-apply
    /// callback the manager's slider uses, so the two cannot disagree about
    /// how big the pet is.
    private var avatarSizeSection: some View {
        SettingsSection(title: text(.sizeHeader)) {
            SettingsStackedRow(label: text(.sizeHeader), value: String(format: "%.2fx", avatarScale)) {
                Slider(value: $avatarScale, in: 0.25...3.0)
                    .onChange(of: avatarScale) { _, newValue in applyAvatarScale(newValue) }
            }
        }
    }

    /// Writes to the avatar's own manifest, which is where the size lives --
    /// the manager's slider does the same thing, and two sliders writing to
    /// two different places would be two sizes.
    private func applyAvatarScale(_ newScale: Double) {
        let directory = AvatarManifestEditor.currentAvatarDirectory(named: store.selectedAvatarName)
        guard (try? AvatarManifestEditor.updateScale(newScale, directory: directory)) != nil else { return }
        onAvatarScaleChanged?(newScale)
    }

    private var poseSection: some View {
        AvatarPosePreviewSection(
            avatarName: store.selectedAvatarName,
            isMirrored: isAvatarMirrored,
            adjustments: Binding(
                get: { poseAdjustments },
                set: { poseAdjustments = $0; store.avatarPoseAdjustments = $0 }
            )
        )
    }

    private var themeSection: some View {
        SettingsSection(title: text(.appearanceLabel)) {
            SettingsStackedRow(label: text(.appearanceLabel)) {
                Picker("", selection: $appearance) {
                    Text(text(.appearanceSystem)).tag(AppAppearance.system)
                    Text(text(.appearanceLight)).tag(AppAppearance.light)
                    Text(text(.appearanceDark)).tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Keyed on the language, for the reason the window's copy of
                // this row is: a segmented picker keeps the titles it was
                // built with while its rows' identities are unchanged.
                .id(localization.language)
                .onChange(of: appearance) { _, newValue in store.appearance = newValue }
            }
        }
    }

    /// Mute and the volume, in both surfaces.
    ///
    /// The rest of the sound settings are set once and left, which is what
    /// moved them to the window; these two get reached for while something is
    /// playing, and a toggle two clicks and a window away is a toggle nobody
    /// uses. So they sit with the other live controls as well.
    ///
    /// Being in both is only safe because the window rebuilds its contents on
    /// every show -- these switches are seeded from the store at init, and a
    /// window kept across opens showed the state it was first built with.
    private var quickSoundSection: some View {
        SettingsSection(title: text(.tabSound)) {
            SettingsRow(label: text(.muteLabel)) {
                Toggle("", isOn: $isMuted)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isMuted) { _, newValue in store.isMuted = newValue }
            }
            SettingsStackedRow(label: text(.volumeLabel)) {
                Slider(value: $volume, in: 0...1)
                    .onChange(of: volume) { _, newValue in store.volume = Float(newValue) }
            }
        }
    }

    private var soundSection: some View {
        SettingsSection(title: text(.tabSound)) {
            SettingsRow(label: text(.autoMuteLabel)) {
                Toggle("", isOn: $autoMuteOnFocus)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: autoMuteOnFocus) { _, newValue in store.autoMuteOnFocus = newValue }
            }
            SettingsRow(label: text(.muteComplaintLabel)) {
                Toggle("", isOn: $isMuteComplaintEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isMuteComplaintEnabled) { _, newValue in store.isMuteComplaintEnabled = newValue }
            }
        }
    }

    private var movementSection: some View {
        SettingsSection(title: text(.tabMovement)) {
            SettingsRow(label: text(.avoidClimbingLabel)) {
                Toggle("", isOn: $avoidClimbingFocusedWindow)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: avoidClimbingFocusedWindow) { _, newValue in store.avoidClimbingFocusedWindow = newValue }
            }
            SettingsStackedRow(label: text(.speedLabel), value: String(format: "%.2fx", walkSpeedMultiplier)) {
                Slider(value: $walkSpeedMultiplier, in: 0.25...3.0)
                    .onChange(of: walkSpeedMultiplier) { _, newValue in store.walkSpeedMultiplier = newValue }
            }
        }
    }

    private var generalSection: some View {
        SettingsSection(title: text(.tabGeneral)) {
            SettingsRow(label: text(.mirrorAvatarLabel)) {
                Toggle("", isOn: $isAvatarMirrored)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isAvatarMirrored) { _, newValue in store.isAvatarMirrored = newValue }
            }
            SettingsRow(label: text(.outlineAvatarLabel)) {
                Toggle("", isOn: $isAvatarOutlined)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isAvatarOutlined) { _, newValue in store.isAvatarOutlined = newValue }
            }
            SettingsRow(label: text(.petAnnouncesLabel)) {
                Toggle("", isOn: $petAnnouncesRuns)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: petAnnouncesRuns) { _, newValue in store.petAnnouncesRuns = newValue }
            }
            SettingsRow(label: text(.notchPanelLabel)) {
                Toggle("", isOn: $notchPanelEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: notchPanelEnabled) { _, newValue in
                        store.isNotchPanelEnabled = newValue
                        onNotchPanelChanged?(newValue)
                    }
            }
            // First in General: it changes every other label on screen, so
            // finding it should not require reading the rest in a language
            // you don't have. Options name themselves for the same reason.
            SettingsStackedRow(label: text(.languageLabel)) {
                // Bound to the live value rather than a copy taken at init:
                // PuckClient offers the same picker, and a copy would keep
                // showing the old choice after a change made over there.
                Picker("", selection: Binding(
                    get: { localization.language },
                    set: { store.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            // An explicit override,
            // not just passively following the system (.system does that).
            SettingsStackedRow(label: text(.appearanceLabel)) {
                Picker("", selection: $appearance) {
                    Text(text(.appearanceSystem)).tag(AppAppearance.system)
                    Text(text(.appearanceLight)).tag(AppAppearance.light)
                    Text(text(.appearanceDark)).tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Keyed on the language: a segmented picker keeps the titles
                // it was built with while its rows' identities are unchanged,
                // so these three stayed in the old language after a switch.
                .id(localization.language)
                .onChange(of: appearance) { _, newValue in store.appearance = newValue }
            }
            // The client theme should stay in sync with the menu bar
            // settings the way Shady-style apps do -- the client
            // (chat) window's own theme, moved here from a ClientWindow-
            // local popover so it's controlled from the same place as every
            // other appearance setting.
            SettingsStackedRow(label: text(.clientThemeLabel)) {
                // A menu, not segments: theme names are names now ("Tokyo
                // Night"), and three of them abbreviate to nothing across a
                // panel this narrow. A menu also takes a fourth without
                // being redesigned.
                Picker("", selection: Binding(
                    get: { clientTheme },
                    set: { style in
                        clientTheme = style
                        store.clientThemeStyle = style
                    }
                )) {
                    ForEach(ClientThemeStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            SettingsRow(label: text(.accessibilityLabel)) {
                Text(AccessibilityPermission.isTrusted(prompt: false) ? text(.accessibilityGranted) : text(.accessibilityNotGranted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // The launch prompt only appears once, so this is the way back
            // for anyone who dismissed it or revoked the grant later.
            SettingsActionRow(label: text(.openSystemSettingsButton), systemImage: "gearshape") {
                AccessibilityPermission.openSystemSettings()
            }
            Text(text(.accessibilityExplanation))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
        }
    }

    /// What the NSMenu used to be, now that the icon opens this panel
    /// instead. Pinned below the scroll view rather than scrolled to: quit
    /// has to be reachable without first scrolling past every setting.
    private var actionSection: some View {
        VStack(spacing: 0) {
            SettingsActionRow(label: text(.menuOpenClient), systemImage: "bubble.left.and.bubble.right") {
                onOpenClient?()
            }
            // Unconditional: `sections` already keeps this whole section out
            // of the window, and a window does not offer to open itself.
            SettingsActionRow(label: text(.menuSettings), systemImage: "gearshape") {
                onOpenSettings?()
            }
            SettingsActionRow(
                label: text(isCharacterHidden ? .menuShow : .menuHide),
                systemImage: isCharacterHidden ? "eye" : "eye.slash"
            ) {
                isCharacterHidden.toggle()
                onToggleVisibility?()
            }
            SettingsActionRow(label: text(.menuQuit), systemImage: "power") {
                onQuit?()
            }
        }
        .padding(ClientTheme.Metrics.spacingSmall)
    }

}
