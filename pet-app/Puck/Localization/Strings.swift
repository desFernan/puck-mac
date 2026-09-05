//
//  Strings.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  All user-facing text in the Settings window, the merged Avatar tab, and
//  the menu bar. A flat key/table lookup rather than Apple's .lproj/
//  Localizable.strings + Bundle mechanism, because the language here is an
//  in-app setting the user can flip live, not a fixed-at-launch system
//  locale -- there is no real bundle to swap.
//
//  One table per AppLanguage. A key missing from the selected table falls
//  back to Korean rather than showing its raw name; `StringsTests` holds the
//  line that no key is ever actually missing.
//
//  Format-string keys (ending in "Format") take %1$@, %2$@, ... via
//  String(format:) at the call site -- positional specifiers because
//  Korean word order for these doesn't always match English's.
//

import Foundation

enum L10nKey: String, CaseIterable, Hashable {
    /// Section headers in the menu bar panel. `tabAvatar` went with the tabs
    /// themselves -- AvatarManagementView titles its own sections now.
    case tabGeneral, tabSound, tabMovement
    /// The settings window's own sidebar row for the avatar manager.
    case tabAvatar
    /// The avatar's base drawing, which every clip falls back to.
    case baseImageHeader, baseImageExplanation, baseImageUpdated

    /// The UI language picker. Its options name themselves
    /// (`AppLanguage.displayName`) rather than going through this table.
    case languageLabel

    case appearanceLabel, appearanceSystem, appearanceLight, appearanceDark
    /// The client (chat) window's own theme, kept in sync with the menu bar
    /// settings the way Shady-style apps do. A separate setting from `appearanceLabel` above (that
    /// one is system-wide light/dark/system; this one is the client
    /// window's own light/dark ClientThemeStyle).
    case clientThemeLabel
    case accessibilityLabel, accessibilityGranted, accessibilityNotGranted
    case openSystemSettingsButton, accessibilityExplanation

    case volumeLabel, muteLabel, autoMuteLabel, muteComplaintLabel

    case avoidClimbingLabel, speedLabel, toySizeLabel, toyPumpkin, toyWand

    case openCustomisationFolder
    case avatarsHeader, importAvatarButton, importPanelPrompt
    /// Picking a different installed avatar as a preset.
    case avatarSelectButton
    case avatarReloadButton, avatarReloadedFormat
    /// The avatar package format needs to be explained to end users too --
    /// condensed for them, not the full creator-facing spec.
    case avatarPackageFormatExplanation
    case sizeHeader
    case emotionsHeader, emotionsExplanation, mappedLabel, notMappedLabel
    case chooseImageButton, choosePanelPrompt
    case customEmotionPlaceholder, addButton

    /// "%1$@ of %2$@ mapped" -- the collapsed emotion list's summary.
    case mappedCountFormat

    /// What the pet says when it needs a permission it doesn't have.
    case permissionNeededBubble
    /// The rest of the pet's own speech-bubble copy.
    case bubbleClientOffline, bubbleMutedComplaint, bubbleCapturePrompt, bubblePlaceholder

    /// Stands in for the track in the notch panel when no music app is
    /// playing anything.
    case notchNothingPlaying

    // F15: the agent's API key, entered here rather than in a .env.
    case agentHeader, apiKeySave, apiKeyClear
    /// Shown for the CLI provider with no key of ours: not a problem there.
    case apiKeyOptionalForCLI
    case apiKeySavedFormat, apiKeySourceFormat, apiKeyMissing, apiKeySaveFailed
    /// F15 (task 4): which LLM host the agent talks to. `apiKeyLabelFormat`
    /// and `apiKeyExplanationFormat` take the selected `AgentProvider`'s
    /// name/env-var so the key field always names the provider it is
    /// actually editing, instead of always saying "OpenAI".
    case providerLabel, apiKeyLabelFormat, apiKeyExplanationFormat
    case cliCredentialLabelFormat
    /// Joins the credential variable names in a list. Korean and English do
    /// not use the same word, and the sentence around it is translated, so
    /// the joiner has to be too -- it read "CLAUDE_CODE_OAUTH_TOKEN 또는
    /// ANTHROPIC_API_KEY" in the middle of an English sentence.
    case listOrJoiner
    /// The model name, for the providers where one is ours to choose, and the
    /// coding-agent CLI, for the provider that runs one. Both were previously
    /// reachable only through an environment variable.
    case modelLabel, modelExplanationFormat, modelReset
    case codingAgentLabel, cliProviderExplanation
    /// How much the CLI may do without being asked each time.
    case permissionsLabel, permissionsExplanation
    case permissionsToolsOnly, permissionsEdits, permissionsEverything, permissionsAuto
    /// The skills the coding CLI loads, and where each came from.
    case skillsHeader, skillSourcePersonal, skillSourceProject
    /// The right sidebar's tabs, and the session list inside one of them.
    case explorerTabFiles, explorerTabSessions, explorerTabGit
    case gitHeader, gitClean, gitNotARepository, gitDetached
    case sessionsHeader, sessionsEmpty, sessionsLoading, sessionsRefresh
    case skillsEmpty, skillsExplanation, skillReveal, skillCountFormat

    /// `/effort` and friends.
    case effortLow, effortMedium, effortHigh
    /// What a slash command answers with.
    case slashModelCurrentFormat, slashModelSetFormat, slashModelUnsupportedFormat
    case slashEffortCurrentFormat, slashEffortSetFormat
    case slashUnknownFormat, slashWriteFailed, slashHelp
    case slashPermissionsCurrentFormat, slashPermissionsSetFormat
    case slashSkillsHeader, slashSkillsEmpty
    case slashSummaryModel, slashSummaryEffort, slashSummaryFast
    case slashSummaryPermissions, slashSummarySkills, slashSummaryHelp
    case installedFormat
    case installedMissingRecommendedFormat
    case failedToInstallFormat
    case rejectedMissingRequiredFormat
    case failedToValidateFormat
    case updatedEmotionFormat
    case failedToSetEmotionFormat


    // MARK: - Client window (PuckClient)

    /// Shared by more than one surface, so they cannot drift apart.
    case commonCancel, commonDelete, commonCreate, commonChoose, commonClose, commonDone

    /// Labels only a screen reader ever reads. Two kinds: a control that is
    /// an icon and nothing else (a mouse gets a tooltip, VoiceOver got the
    /// SF Symbol's name or silence), and state a sighted user takes from a
    /// colour -- an unsaved dot, a project that failed to open. The two
    /// `Format` ones are spoken out loud when something happens off-screen:
    /// the pet saying something, and a run stopping to ask.
    case a11yRemoveAttachment, a11yAgentSettings, a11yClearSearch, a11yCloseTab
    case a11yUnsavedChanges, a11yFileModified, a11ySelectTab
    case a11yProjectReady, a11yProjectNone, a11yProjectUnavailable
    case a11yOpenFile, a11ySelected
    case a11yPetSaysFormat, a11yApprovalNeededFormat
    case codeBlockCopy, codeBlockCopied

    case chatSelectAConversation, chatNewSession, chatCasualSession, chatThisWorkspace
    case chatSettings, chatComposerPlaceholder, chatStop, chatSend
    case voicePermissionNeeded
    case chatAttach, chatModel, chatEffort, chatFilterPlaceholder, chatRunning, chatVoice
    case chatChatsAndTasks, chatWorkspaces, chatNoSessionsHere
    case chatEditor, chatAttachEditor, chatDetachEditor
    case chatAttachEditorHelp, chatDetachEditorHelp
    case islandResize
    case islandPetSize
    case islandFold
    case islandUnfold
    case terminalTitle
    case terminalToggle
    case terminalHide
    case terminalCouldNotStart
    case chatNoProjectLinked, chatEditorInSeparateWindow
    case chatEmptyTitle, chatEmptySubtitle, chatThinking, chatFailed
    case chatDone, chatDoneFailed
    case chatApprovalAnswered, chatApprovalRespondToPreviousFirst
    case chatApprovalAllow, chatApprovalDeny
    case chatDeleteWorkspaceTitleFormat, chatDeleteWorkspaceMessage
    case chatDeleteSessionTitle, chatDeleteSessionMessage
    case chatNewWorkspace, chatWorkspaceName, chatProjectFolder
    case chatNoFolderSelected, chatProjectFolderExplanation

    /// The sidebar's relative times. `Format` keys take the number as %1$@ --
    /// the unit trails it in Korean and in English alike, but the two
    /// disagree on spacing, so the whole string is translated rather than
    /// concatenated from a number and a unit.
    case timeJustNow, timeYesterday
    case timeMinutesFormat, timeHoursFormat, timeDaysFormat, timeMonthDayFormat


    // MARK: - Editor pane

    case editorUnsavedTitle, editorSaveAndClose, editorDiscard
    case editorUnsavedMessageFormat
    case editorProjectFolderMissing, editorProjectPathNotAFolder, editorProjectFolderUnreadable
    case editorConflictTitle, editorConflictMessage, editorUseDiskVersion, editorKeepMyVersion
    case editorChangedOnly
    case editorGoToLine, editorGoToLinePlaceholder, editorNextTab, editorPreviousTab, editorFind
    case editorOpenQuickly, editorOpenQuicklyPlaceholder

    /// WorkspaceFileService's refusals. The user reads these in the editor
    /// pane, so they are copy, not diagnostics.
    case fileNotAFilePath, fileInvalidPath, fileOutsideProject, fileSymlinkEscapesProject
    case fileNotADirectoryPath, fileNameTaken, fileInvalidName, fileCannotDeleteRoot, fileCouldNotCreate
    case explorerNewFile, explorerNewFolder, explorerRename, explorerDelete, explorerRevealInFinder
    case explorerCopyPath, explorerDeleteTitleFormat, explorerDeleteMessage, explorerRenameTitle
    case explorerNewFileTitle, explorerNewFolderTitle, explorerNamePlaceholder, explorerCreate
    case fileNotFound, fileBinaryNotEditable, fileBinaryNotSavable, fileOnlyUTF8
    case fileImageTooLargeToPreview, fileImageFormatMismatch
    case fileTooLargeReadOnly, fileChangedOnDisk, fileSaveExceedsLimit, fileInUseByAnotherProcess


    // MARK: - Agent run outcomes and approval prompts

    /// What the user reads when a run ends badly. Not the tool-protocol
    /// `detail` strings, which are addressed to the model.
    case agentCancelled, agentSettingsHint, agentModelNotFound, agentRateLimited
    case agentToolCeilingFormat, agentNoAPIKeyFormat, agentBadAPIKeyFormat
    case agentServerErrorFormat, agentAPIErrorFormat, agentAPIErrorWithMessageFormat

    case approvalRunShellFormat, approvalRunAppleScriptFormat
    case approvalClickElementFormat, approvalRunToolFormat


    // MARK: - Agent tool results and setup failures

    /// Tool `detail` the user reads in the transcript. The strings that only
    /// the model ever sees -- protocol errors, path hints -- stay put.
    case toolNoProjectLinked, toolShownButPetCouldNotGo
    case toolAmbiguousPathFormat, toolAmbiguousPathMoreFormat, toolPickOneFullPath
    case toolCouldNotOpenFormat, toolNoSuchLineFormat
    case toolEditorOffscreenShownAnyway
    case toolDuplicateRequest, toolCodeEditTimedOutFormat, toolCodeEditPurpose
    case toolTaskSessionUnavailable, toolTaskIsEmpty, toolPathIsEmpty, toolShowCodeNeedsEverything
    /// Appended to a path failure. Aimed at the model -- a person reading the
    /// editor pane already knows what they clicked -- but the transcript
    /// shows a tool's detail, so it is read by both.
    case toolPathIsRelativeHint, toolListFilesHint

    case acpAborted, acpTaskFailed, acpWroteOutsideProject, acpTaskDoneFormat
    case acpNeedsNodeFormat, acpCLINotFoundFormat, acpAgentNotBundledFormat, acpCouldNotStart

    case cliErrorFormat, cliTimedOutFormat, cliNoAnswerFormat
    /// The CLI's own login has expired or been revoked. Takes the agent's
    /// display name and the command that logs it back in.
    case cliNotLoggedInFormat
    /// The agent's own long-running shells -- see AgentTerminals.
    case terminalUnknownFormat, terminalEndedFormat, terminalTooManyFormat, terminalCouldNotStartFormat
    case terminalNeedsAProject, terminalNeedsAnId, terminalNeedsText, terminalNeedsACommand
    /// Whether the pet speaks up about a run while the window is behind
    /// something else -- see SettingsStore.petAnnouncesRuns.
    case petAnnouncesLabel
    /// The change review -- what the agent edited, before you keep it.
    case reviewTitle, reviewCountFormat, reviewRefresh, reviewNothingChanged
    case reviewNothingChangedDetail, reviewBinaryFile, reviewNoContentChange
    case reviewRenamedFromFormat, reviewRevert, reviewRevertHelp, reviewOpenFormat
    /// Scheduled agent runs -- see AgentSchedule.
    case scheduleEveryMinutesFormat, scheduleDailyFormat, scheduleWeeklyFormat
    case schedulesHeader, schedulesExplanation, schedulesNew, schedulesPromptPlaceholder
    case schedulesWhen, schedulesAdd, scheduleEveryLabel, scheduleDailyLabel
    case scheduleWeeklyLabel, scheduleAtLabel, scheduleDaysLabel
    /// A sent message folded down because it was too long to draw -- see
    /// LongMessage. Takes the number of lines and a human size.
    case chatLongMessageFormat, chatExpandMessage, chatCollapseMessage, chatOpenMessageAsFile
    case cliNoToolsFallbackFormat, cliConversationPurpose

    case providerNoAPIKey, providerAPIErrorFormat, providerUndecodableFormat
    case mcpCouldNotOpenFormat, mcpNoPort
    case keySourceEnvironmentFormat


    case themeLight, themeDark
    case workspaceDefaultName, sessionDefaultTitle
    case editorSelectAFile, editorSearchFiles, editorSaveHint
    case editorCollapse, editorExpand
    case providerRefusedResponse, providerTruncatedFormat, acpProcessExited

    /// The panel's action rows. Settings and Switch Avatar are gone with the
    /// NSMenu: the panel *is* settings, and it opens on the avatar section.
    case menuToys, menuHide, menuShow, menuQuit
    /// F13 (2026-07-30): PuckClient is a separate Dock-resident app now
    /// -- this menu item activates/launches it, replacing the old
    /// Option+Shift+Space-opens-the-client-window behavior.
    case menuOpenClient
    case menuSettings
    case notchPanelLabel
    /// Draws the avatar the other way round.
    case mirrorAvatarLabel
    /// A white edge around the character, sticker-fashion.
    case outlineAvatarLabel
    /// The pose preview: what the pet looks like walking, climbing, hanging.
    case posePreviewHeader, posePreviewExplanation
    case poseWalkingRight, poseWalkingLeft
    case poseOnTheCeilingFacingRight, poseOnTheCeilingFacingLeft
    case poseClimbingRightWall, poseClimbingLeftWall
}

enum Strings {
    /// The language defaults to whatever the running process has selected;
    /// tests pass one explicitly rather than mutating shared state.
    static func text(_ key: L10nKey, language: AppLanguage = Localization.shared.language) -> String {
        table(for: language)[key] ?? korean[key] ?? key.rawValue
    }

    /// Every key the given language has its own text for -- not the Korean
    /// fallback. `StringsTests` uses this to hold the line that a new key
    /// lands in both tables at once; nothing in the app reads it, because the
    /// fallback is what the app should do when one is missing anyway.
    static func translatedKeys(in language: AppLanguage) -> Set<L10nKey> {
        Set(table(for: language).keys)
    }

    private static func table(for language: AppLanguage) -> [L10nKey: String] {
        switch language {
        case .korean: return korean
        case .english: return english
        }
    }

    private static let korean: [L10nKey: String] = [
        .languageLabel: "언어",
        .tabGeneral: "일반",
        .tabAvatar: "아바타",
        .baseImageHeader: "기본 이미지",
        .baseImageExplanation: "아바타가 기본으로 쓰는 그림입니다. 따로 지정하지 않은 동작은 전부 이 그림을 씁니다.",
        .baseImageUpdated: "기본 이미지를 바꿨습니다.",
        .tabSound: "사운드",
        .tabMovement: "이동",

        .appearanceLabel: "테마",
        .appearanceSystem: "시스템",
        .appearanceLight: "라이트",
        .appearanceDark: "다크",
        .clientThemeLabel: "채팅 테마",
        .accessibilityLabel: "손쉬운 사용",
        .accessibilityGranted: "허용됨",
        .accessibilityNotGranted: "허용 안 됨",
        .openSystemSettingsButton: "시스템 설정 열기…",
        .accessibilityExplanation: "전역 단축키, 다른 앱의 UI 읽기, 가상 클릭 기능에 필요합니다.",

        .volumeLabel: "음량",
        .muteLabel: "음소거",
        .autoMuteLabel: "포커스 모드에서 자동 음소거 (최선 노력 기반, 정확하지 않을 수 있음)",
        .muteComplaintLabel: "음소거하면 투덜대기",

        .avoidClimbingLabel: "포커스된 창 위로는 올라가지 않기",
        .speedLabel: "이동 속도",
        .toySizeLabel: "장난감 크기",
        .toyPumpkin: "호박",
        .toyWand: "지팡이",

        .openCustomisationFolder: "커스터마이징 폴더 열기",
        .avatarsHeader: "아바타",
        .importAvatarButton: "아바타 패키지 가져오기…",
        .avatarSelectButton: "선택",
        .avatarReloadButton: "아바타 다시 불러오기",
        .avatarReloadedFormat: "'%1$@'을(를) 다시 불러왔습니다.",
        .avatarPackageFormatExplanation:
            "아바타 패키지는 폴더 하나입니다: manifest.json과 동작별 투명 배경 PNG(idle은 필수, walk·climb·fall 등은 권장), 그리고 선택적으로 .wav 파일이 담긴 sounds/ 폴더로 구성됩니다. 이미지는 긴 변 기준 1024px 내외, 파일당 약 500KB 이하를 권장합니다.",
        .importPanelPrompt: "가져오기",
        .sizeHeader: "크기",
        .emotionsHeader: "감정 표현",
        .emotionsExplanation: "소켓 이벤트(생각 중, 작업 실패, 작업 완료)를 이미지에 매핑합니다. 매핑되지 않으면 대기 이미지로 대체됩니다.",
        .mappedLabel: "매핑됨",
        .notMappedLabel: "매핑 안 됨",
        .chooseImageButton: "이미지 선택…",
        .choosePanelPrompt: "선택",
        .customEmotionPlaceholder: "사용자 지정 감정 이름",
        .addButton: "추가",

        .mappedCountFormat: "%2$@개 중 %1$@개 매핑됨",

        .permissionNeededBubble: "그거 하려면 권한이 필요해요. 제가 가리키는 창에서 허용해 주세요!",
        .bubbleClientOffline: "채팅 창이 꺼져 있어요",
        .bubbleMutedComplaint: "제 목소리가 시끄러우신거에요?",
        .bubbleCapturePrompt: "화면 영역 캡처",
        .bubblePlaceholder: "무엇을 도와드릴까요?",
        .notchNothingPlaying: "재생 중인 음악이 없어요",

        .agentHeader: "에이전트",
        .providerLabel: "AI 공급자",
        .apiKeyLabelFormat: "%1$@ API 키",
        .cliCredentialLabelFormat: "%1$@ 설정 토큰 / API 키",
        .listOrJoiner: " 또는 ",
        .apiKeySave: "저장",
        .apiKeyClear: "삭제",
        .apiKeySavedFormat: "%1$@에 저장했어요",
        .apiKeySourceFormat: "사용 중 — 출처: %1$@",
        .apiKeyMissing: "키가 없어요 — 아직 명령을 수행할 수 없습니다.",
        .apiKeyOptionalForCLI: "비워 두면 CLI에 이미 로그인된 계정을 그대로 씁니다.",
        .apiKeySaveFailed: "키 파일을 저장하지 못했어요.",
        .apiKeyExplanationFormat:
            "본인만 읽을 수 있는 .env 파일에 저장됩니다. 환경변수 %1$@나 프로젝트 폴더의 .env가 있으면 그쪽이 우선합니다.",
        .modelLabel: "모델",
        .modelReset: "기본값",
        .modelExplanationFormat: "비워 두고 저장하면 기본값 %1$@을(를) 씁니다. 환경변수 %2$@가 있으면 그쪽이 우선합니다.",
        .codingAgentLabel: "코딩 CLI",
        .permissionsLabel: "자동 허용",
        .permissionsExplanation: "CLI가 스스로 하는 일을 매번 묻지 않고 허용할 범위입니다. 파일 쓰기는 어느 설정에서든 선택한 프로젝트 폴더 밖으로 나가지 못합니다. '묻지 않고 전부'는 펫의 명령 실행·AppleScript·클릭까지 승인 없이 바로 실행합니다.",
        .slashModelCurrentFormat: "지금 모델: %1$@. 바꾸려면 /model 이름 을 쓰세요.",
        .slashModelSetFormat: "모델을 %1$@(으)로 바꿨어요.",
        .slashModelUnsupportedFormat: "%1$@ 공급자는 모델을 고를 수 없어요 — CLI가 자기 설정을 씁니다.",
        .slashEffortCurrentFormat: "지금 사고량: '%1$@'. /effort low·medium·high 로 바꿀 수 있어요.",
        .slashEffortSetFormat: "사고량을 '%1$@'(으)로 바꿨어요. 다음 turn부터 적용됩니다.",
        .slashUnknownFormat: "%1$@ 은(는) 없는 명령이에요. /help 로 목록을 보세요.",
        .slashWriteFailed: "설정 파일을 저장하지 못했어요.",
        .slashPermissionsCurrentFormat: "지금은 '%1$@'예요. `/permissions tools|edits|all|auto` 로 바꿀 수 있어요.",
        .slashPermissionsSetFormat: "'%1$@'(으)로 바꿨어요. 다음 turn부터 적용됩니다.",
        .slashSummaryModel: "모델 보기 · 바꾸기",
        .slashSummaryEffort: "사고량 보기 · 바꾸기",
        .slashSummaryFast: "사고량을 가장 낮게",
        .slashSummaryPermissions: "CLI가 스스로 할 수 있는 범위",
        .slashSummarySkills: "설치된 스킬 목록",
        .slashSummaryHelp: "명령 목록",
        .slashSkillsHeader: "설치된 스킬이에요.",
        .slashSkillsEmpty: "설치된 스킬이 없어요. `~/.claude/skills` 나 프로젝트의 `.claude/skills` 에 폴더를 두면 여기 보여요.",
        .slashHelp: """
        쓸 수 있는 명령이에요.

        - `/model` — 지금 모델 보기, `/model 이름` 으로 바꾸기
        - `/effort` — 사고량 보기, `/effort low|medium|high` 로 바꾸기
        - `/fast` — 사고량을 가장 낮게 (`/effort low` 와 같아요)
        - `/permissions` — CLI가 스스로 할 수 있는 범위 보기, `/permissions tools|edits|all` 로 바꾸기
        - `/skills` — 설치된 스킬 목록
        - `/help` — 이 목록
        """,
        .explorerTabFiles: "파일",
        .explorerTabSessions: "세션",
        .explorerTabGit: "변경사항",
        .gitHeader: "변경사항",
        .gitClean: "변경된 파일이 없어요.",
        .gitNotARepository: "git 저장소가 아니에요.",
        .gitDetached: "분리된 HEAD",
        .sessionsHeader: "에이전트 세션 기록",
        .sessionsEmpty: "기록이 없어요.",
        .sessionsLoading: "읽는 중…",
        .sessionsRefresh: "새로고침",
        .skillsHeader: "스킬",
        .skillSourcePersonal: "내 계정",
        .skillSourceProject: "프로젝트",
        .skillsEmpty: "설치된 스킬이 없어요.",
        .skillsExplanation: "코딩 CLI가 불러오는 스킬입니다. 같은 이름이 양쪽에 있으면 프로젝트 쪽이 쓰입니다.",
        .skillReveal: "Finder에서 보기",
        .skillCountFormat: "%1$@개",
        .effortLow: "간결",
        .effortMedium: "보통",
        .effortHigh: "꼼꼼",
        .permissionsToolsOnly: "펫 도구만",
        .permissionsEdits: "파일 수정까지",
        .permissionsEverything: "명령 실행까지",
        .permissionsAuto: "묻지 않고 전부",
        .cliProviderExplanation:
            "선택한 CLI와 안정적인 설정 토큰 또는 API 키를 씁니다. 펫 도구는 MCP로 연결되고, 선택한 프로젝트 안의 파일 작업은 샌드박스 안에서 실행됩니다.",
        .installedFormat: "'%1$@' 설치 완료.",
        .installedMissingRecommendedFormat: "'%1$@' 설치 완료 — 권장 클립 누락(대기 이미지로 대체): %2$@",
        .failedToInstallFormat: "'%1$@' 설치 실패: %2$@",
        .rejectedMissingRequiredFormat: "거부됨 — 필수 클립 파일 누락: %1$@",
        .failedToValidateFormat: "유효성 검사 실패: %1$@",
        .updatedEmotionFormat: "'%1$@' 업데이트 완료.",
        .failedToSetEmotionFormat: "'%1$@' 설정 실패: %2$@",
        .islandResize: "섬 높이 조절",
        .islandPetSize: "펫 크기 조절",
        .islandFold: "섬 접기",
        .islandUnfold: "섬 펴기",
        .terminalTitle: "터미널",
        .terminalToggle: "터미널 (⌃`)",
        .terminalHide: "터미널 닫기",
        .terminalCouldNotStart: "셸이 시작하자마자 끝났습니다. 터미널을 닫았다가 다시 열어보세요.",
        .codeBlockCopy: "복사",
        .codeBlockCopied: "복사했어요",
        .commonClose: "닫기",
        .a11yRemoveAttachment: "첨부 제거",
        .a11yAgentSettings: "에이전트 설정",
        .a11yClearSearch: "검색어 지우기",
        .a11yCloseTab: "탭 닫기",
        .a11yUnsavedChanges: "저장하지 않음",
        .a11yFileModified: "수정됨",
        .a11ySelectTab: "이 탭 열기",
        .a11yProjectReady: "프로젝트 열림",
        .a11yProjectNone: "프로젝트 없음",
        .a11yProjectUnavailable: "프로젝트를 열 수 없음",
        .a11yOpenFile: "파일 열기",
        .a11ySelected: "사용 중",
        .a11yPetSaysFormat: "펫: %1$@",
        .a11yApprovalNeededFormat: "승인이 필요해요: %1$@",
        .commonCancel: "취소",
        .commonDone: "완료",
        .commonDelete: "삭제",
        .commonCreate: "만들기",
        .commonChoose: "선택…",

        .chatSelectAConversation: "대화를 선택하세요",
        .chatNewSession: "새로운 대화",
        .chatCasualSession: "새로운 대화",
        .chatThisWorkspace: "이 워크스페이스",
        .chatSettings: "설정",
        .chatComposerPlaceholder: "Agent에게 메시지를 보내세요…",
        .chatStop: "중지",
        .voicePermissionNeeded: "음성 인식 권한이 필요해요. 시스템 설정 > 개인정보 보호 및 보안 > 음성 인식에서 Puck을 켜주세요.",
        .chatAttach: "이미지 첨부",
        .chatFilterPlaceholder: "대화 찾기",
        .chatRunning: "처리 중",
        .chatVoice: "음성으로 말하기",
        .chatWorkspaces: "워크스페이스",
        .chatNoSessionsHere: "아직 대화가 없어요",
        .chatChatsAndTasks: "채팅 및 작업",
        .chatModel: "모델",
        .chatEffort: "사고량",
        .chatSend: "보내기",
        .chatEditor: "에디터",
        .chatAttachEditor: "에디터 붙이기",
        .chatDetachEditor: "에디터 떼기",
        .chatAttachEditorHelp: "에디터를 이 창으로 다시 붙여요",
        .chatDetachEditorHelp: "에디터를 별도 창으로 떼어내요",
        .chatNoProjectLinked: "이 워크스페이스에는 연결된 프로젝트가 없어요",
        .chatEditorInSeparateWindow: "에디터가 별도 창에 열려 있어요",
        .chatEmptyTitle: "무엇을 도와드릴까요?",
        .chatEmptySubtitle: "코드든 잡담이든, 편하게 말 걸어보세요.",
        .chatThinking: "생각 중…",
        .chatFailed: "실패했어요.",
        .chatDone: "완료",
        .chatDoneFailed: "실패",
        .chatApprovalAnswered: "응답함",
        .chatApprovalRespondToPreviousFirst: "앞의 요청에 먼저 응답해 주세요.",
        .chatApprovalAllow: "허용",
        .chatApprovalDeny: "거부",
        .chatDeleteWorkspaceTitleFormat: "%1$@를 삭제할까요?",
        .chatDeleteWorkspaceMessage: "이 워크스페이스의 대화가 모두 사라집니다. 프로젝트 폴더는 그대로 남습니다.",
        .chatDeleteSessionTitle: "이 대화를 삭제할까요?",
        .chatDeleteSessionMessage: "주고받은 내용이 모두 사라지고, 되돌릴 수 없어요.",
        .chatNewWorkspace: "새 워크스페이스",
        .chatWorkspaceName: "이름",
        .chatProjectFolder: "프로젝트 폴더",
        .chatNoFolderSelected: "선택 안 함",
        .chatProjectFolderExplanation: "폴더를 연결하면 에디터와 코드 편집을 쓸 수 있어요. 대화만 할 거면 비워 두세요.",

        .timeJustNow: "방금",
        .timeYesterday: "어제",
        .timeMinutesFormat: "%1$@분",
        .timeHoursFormat: "%1$@시간",
        .timeDaysFormat: "%1$@일",
        .timeMonthDayFormat: "%1$@월 %2$@일",

        .editorUnsavedTitle: "저장하지 않은 변경사항이 있어요",
        .editorSaveAndClose: "저장 후 닫기",
        .editorDiscard: "저장 안 함",
        .editorUnsavedMessageFormat: "%1$@의 변경사항을 저장할까요?",
        .editorProjectFolderMissing: "프로젝트 폴더를 찾을 수 없어요 -- 이동되었거나 삭제된 것 같아요",
        .editorProjectPathNotAFolder: "연결된 경로가 폴더가 아니에요",
        .editorProjectFolderUnreadable: "프로젝트 폴더를 읽을 권한이 없어요",
        .editorConflictTitle: "디스크에서 파일이 변경됐습니다",
        .editorConflictMessage: "저장하기 전에 사용할 버전을 선택하세요.",
        .editorChangedOnly: "변경된 파일만",
        .editorGoToLine: "줄로 이동",
        .editorFind: "파일에서 찾기",
        .editorOpenQuickly: "빠른 열기",
        .editorOpenQuicklyPlaceholder: "파일 이름으로 열기",
        .editorGoToLinePlaceholder: "줄 번호",
        .editorNextTab: "다음 탭",
        .editorPreviousTab: "이전 탭",
        .editorUseDiskVersion: "디스크 내용 사용",
        .editorKeepMyVersion: "내 내용 유지",

        .fileNotAFilePath: "파일 경로가 아닙니다",
        .fileNotADirectoryPath: "폴더 경로가 아닙니다",
        .fileNameTaken: "같은 이름이 이미 있습니다",
        .fileInvalidName: "쓸 수 없는 이름입니다",
        .fileCannotDeleteRoot: "프로젝트 폴더 자체는 지울 수 없습니다",
        .fileCouldNotCreate: "만들지 못했습니다",
        .explorerNewFile: "새 파일",
        .explorerNewFolder: "새 폴더",
        .explorerRename: "이름 변경",
        .explorerDelete: "휴지통으로 이동",
        .explorerRevealInFinder: "Finder에서 보기",
        .explorerCopyPath: "경로 복사",
        .explorerDeleteTitleFormat: "%@을(를) 휴지통으로 옮길까요?",
        .explorerDeleteMessage: "휴지통에서 되돌릴 수 있습니다.",
        .explorerRenameTitle: "이름 변경",
        .explorerNewFileTitle: "새 파일",
        .explorerNewFolderTitle: "새 폴더",
        .explorerNamePlaceholder: "이름",
        .explorerCreate: "만들기",
        .fileInvalidPath: "잘못된 파일 경로입니다",
        .fileOutsideProject: "프로젝트 밖 경로입니다",
        .fileSymlinkEscapesProject: "심볼릭 링크가 프로젝트 밖을 가리킵니다",
        .fileNotFound: "파일을 찾을 수 없습니다",
        .fileBinaryNotEditable: "바이너리 파일은 편집할 수 없습니다",
        .fileBinaryNotSavable: "바이너리 파일은 저장할 수 없습니다",
        .fileOnlyUTF8: "UTF-8 텍스트 파일만 지원합니다",
        .fileImageTooLargeToPreview: "10MB를 초과하는 이미지는 미리 볼 수 없습니다",
        .fileImageFormatMismatch: "지원하는 이미지 형식과 실제 파일 내용이 일치하지 않습니다",
        .fileTooLargeReadOnly: "2MB를 초과하는 파일은 읽기 전용입니다",
        .fileChangedOnDisk: "디스크 파일이 마지막 읽기 이후 변경되었습니다",
        .fileSaveExceedsLimit: "저장할 내용이 2MB 제한을 초과합니다",
        .fileInUseByAnotherProcess: "디스크 파일이 다른 프로세스에 의해 사용 중입니다",

        .agentCancelled: "중지했어요.",
        .agentSettingsHint: "설정(⌘,)에서 키를 확인해 주세요.",
        .agentModelNotFound: "모델을 찾을 수 없어요. 설정(⌘,)에서 모델 이름을 확인해 주세요.",
        .agentRateLimited: "요청이 너무 잦거나 사용 한도를 넘었어요. 잠시 후 다시 시도해 주세요.",
        .agentToolCeilingFormat: "도구를 %1$@번 넘게 호출해서 중단했어요.",
        .agentNoAPIKeyFormat: "API 키가 없어요. %1$@",
        .agentBadAPIKeyFormat: "API 키가 올바르지 않아요. %1$@",
        .agentServerErrorFormat: "AI 서버가 응답하지 못했어요 (오류 %1$@). 잠시 후 다시 시도해 주세요.",
        .agentAPIErrorFormat: "API 오류 %1$@가 났어요.",
        .agentAPIErrorWithMessageFormat: "API 오류 %1$@: %2$@",

        .approvalRunShellFormat: "셸 명령 실행: %1$@",
        .approvalRunAppleScriptFormat: "AppleScript 실행: %1$@",
        .approvalClickElementFormat: "화면 클릭: %1$@",
        .approvalRunToolFormat: "%1$@ 실행: %2$@",

        .toolNoProjectLinked: "이 워크스페이스에는 연결된 프로젝트가 없어요.",
        .toolShownButPetCouldNotGo: "펫이 가지 못했지만 코드는 표시했어요. (%1$@)",
        .toolAmbiguousPathFormat: "%1$@와 이름이 같은 파일이 여러 개예요: %2$@.",
        .toolAmbiguousPathMoreFormat: " 외 %1$@개",
        .toolPickOneFullPath: " 이 중 하나를 전체 경로로 다시 불러주세요.",
        .toolCouldNotOpenFormat: "%1$@를 열지 못했어요.",
        .toolNoSuchLineFormat: "%1$@에는 %2$@번째 줄이 없어요. (%3$@줄짜리 파일이에요)",
        .toolEditorOffscreenShownAnyway: "에디터가 화면에 없어서 펫은 가지 못했어요. 코드는 표시했습니다.",
        .toolDuplicateRequest: "중복된 요청입니다.",
        .toolTaskSessionUnavailable: "open_task_session은 이 연결에서 쓸 수 없어요.",
        .toolTaskIsEmpty: "task가 비어 있어요.",
        .toolPathIsEmpty: "path가 비어 있어요.",
        .toolShowCodeNeedsEverything: "show_code는 path, start_line, end_line, caption이 모두 필요해요.",
        .toolPathIsRelativeHint: " 경로는 프로젝트 루트 기준 상대 경로여야 해요 (예: src/App/main.swift).",
        .toolListFilesHint: " 정확한 경로를 모르면 list_files로 확인한 뒤 다시 부르세요.",
        .toolCodeEditTimedOutFormat: "코드 편집 에이전트가 %1$@초 동안 아무 말이 없어서 중단했어요.",
        .toolCodeEditPurpose: "코드 편집",

        .acpAborted: "중단됨",
        .acpTaskFailed: "ACP 작업에 실패했습니다.",
        .acpWroteOutsideProject: "이 작업이 프로젝트 밖의 파일을 수정했다고 보고했어요. 확인이 필요합니다.",
        .acpTaskDoneFormat: "ACP 작업 완료 (%1$@)",
        .acpNeedsNodeFormat: "%1$@에는 Node.js가 필요합니다. 설치 후 다시 시도해 주세요.",
        .acpCLINotFoundFormat: "%1$@ CLI를 찾을 수 없습니다. 설치한 뒤 다시 시도해 주세요.",
        .acpAgentNotBundledFormat: "코딩 에이전트(%1$@)가 앱에 포함되어 있지 않습니다.",
        .acpCouldNotStart: "코딩 에이전트를 시작하지 못했습니다.",

        .cliErrorFormat: "코딩 CLI 오류: %1$@",
        .cliNotLoggedInFormat: "%1$@ 로그인이 만료됐어요. 터미널에서 `%2$@` 를 실행해 다시 로그인한 뒤 보내주세요.",
        .terminalUnknownFormat: "그런 터미널이 없어요 (%1$@).",
        .terminalEndedFormat: "이미 끝난 터미널이에요 (%1$@).",
        .terminalTooManyFormat: "터미널을 %1$@개까지만 띄울 수 있어요. 쓰던 것을 먼저 정리해 주세요.",
        .terminalCouldNotStartFormat: "터미널을 시작하지 못했어요: %1$@",
        .terminalNeedsAProject: "이 워크스페이스에는 프로젝트 폴더가 없어서 터미널을 열 곳이 없어요.",
        .terminalNeedsAnId: "어느 터미널인지 id가 필요해요.",
        .terminalNeedsText: "보낼 내용이 필요해요.",
        .terminalNeedsACommand: "실행할 명령이 필요해요.",
        .petAnnouncesLabel: "창이 가려져 있을 때 펫이 알려주기",
        .reviewTitle: "변경 사항 검토",
        .reviewCountFormat: "%1$@개 파일 · +%2$@ −%3$@",
        .reviewRefresh: "다시 읽기",
        .reviewNothingChanged: "바뀐 것이 없어요",
        .reviewNothingChangedDetail: "이 프로젝트에 커밋되지 않은 변경이 없습니다.",
        .reviewBinaryFile: "바이너리 파일이라 내용은 보여줄 수 없어요.",
        .reviewNoContentChange: "내용은 그대로예요 (이름이나 권한만 바뀜).",
        .reviewRenamedFromFormat: "← %1$@",
        .reviewRevert: "되돌리기",
        .reviewRevertHelp: "이 파일을 마지막 커밋 상태로 되돌립니다. 새로 만들어진 파일은 지워집니다.",
        .reviewOpenFormat: "%1$@개 파일 변경 — 검토하기",
        .scheduleEveryMinutesFormat: "%1$@분마다",
        .scheduleDailyFormat: "매일 %1$@",
        .scheduleWeeklyFormat: "%1$@ %2$@",
        .schedulesHeader: "예약 실행",
        .schedulesExplanation: "정해진 때에 지금 워크스페이스로 보낼 말입니다. Puck이 켜져 있을 때만 실행되고, 꺼져 있는 동안 지난 것은 다시 켤 때 한 번 실행됩니다.",
        .schedulesNew: "보낼 말",
        .schedulesPromptPlaceholder: "예: CI 확인해서 깨졌으면 알려줘",
        .schedulesWhen: "언제",
        .schedulesAdd: "예약 추가",
        .scheduleEveryLabel: "간격(분)",
        .scheduleDailyLabel: "매일",
        .scheduleWeeklyLabel: "요일마다",
        .scheduleAtLabel: "시각",
        .scheduleDaysLabel: "요일",
        .chatLongMessageFormat: "%1$@줄 · %2$@",
        .chatExpandMessage: "전체 보기",
        .chatCollapseMessage: "접기",
        .chatOpenMessageAsFile: ".txt로 열기",
        .cliTimedOutFormat: "코딩 CLI가 %1$@초 동안 아무 말이 없어서 중단했어요.",
        .cliNoAnswerFormat: "코딩 CLI가 답을 주지 않았어요. (%1$@)",
        .cliNoToolsFallbackFormat: "MCP 서버를 열지 못해 도구 없이 대화합니다: %1$@",
        .cliConversationPurpose: "대화",

        .providerNoAPIKey: "API 키가 설정되지 않았습니다.",
        .providerAPIErrorFormat: "API 오류 %1$@: %2$@",
        .providerUndecodableFormat: "응답을 해석할 수 없습니다: %1$@",
        .mcpCouldNotOpenFormat: "로컬 서버를 열지 못했습니다: %1$@",
        .mcpNoPort: "로컬 서버가 포트를 얻지 못했습니다.",
        .keySourceEnvironmentFormat: "환경변수 %1$@",

        .workspaceDefaultName: "기본 워크스페이스",
        .sessionDefaultTitle: "새로운 대화",
        .themeLight: "화이트",
        .themeDark: "다크",
        .editorCollapse: "파일 접기",
        .editorExpand: "파일 다시 열기",
        .editorSelectAFile: "오른쪽 탐색기에서 파일을 선택하세요",
        .editorSearchFiles: "파일 검색",
        .editorSaveHint: "저장 (⌘S)",
        .providerRefusedResponse: "모델이 응답을 거부했습니다 (stop_reason: refusal)",
        .providerTruncatedFormat: "응답이 max_tokens(%1$@)에서 잘렸습니다 -- 도구 호출이 중간에 끊겼을 수 있습니다",
        .acpProcessExited: "ACP 프로세스가 종료되었습니다.",

        .menuToys: "장난감",
        .menuHide: "숨기기",
        .menuShow: "보이기",
        .menuQuit: "Puck 종료",
        .menuOpenClient: "Puck 채팅 열기",
        .menuSettings: "설정…",
        .mirrorAvatarLabel: "아바타 좌우 반전",
        .outlineAvatarLabel: "아바타 흰 테두리",
        .posePreviewHeader: "자세 미리보기",
        .posePreviewExplanation: "걷고 기어오를 때 아바타가 어떻게 보이는지입니다. 방향이 어긋나면 좌우 반전·상하 반전·회전으로 맞추세요.",
        .poseWalkingRight: "오른쪽으로 걷기",
        .poseWalkingLeft: "왼쪽으로 걷기",
        .poseClimbingRightWall: "오른쪽 벽 타기",
        .poseClimbingLeftWall: "왼쪽 벽 타기",
        .poseOnTheCeilingFacingRight: "천장에서 오른쪽으로",
        .poseOnTheCeilingFacingLeft: "천장에서 왼쪽으로",
        .notchPanelLabel: "노치 패널",
    ]

    private static let english: [L10nKey: String] = [
        .languageLabel: "Language",

        .tabGeneral: "General",
        .tabAvatar: "Avatar",
        .baseImageHeader: "Base image",
        .baseImageExplanation: "The drawing the avatar falls back to. Anything without a picture of its own uses this one.",
        .baseImageUpdated: "Base image replaced.",
        .tabSound: "Sound",
        .tabMovement: "Movement",

        .appearanceLabel: "Theme",
        .appearanceSystem: "System",
        .appearanceLight: "Light",
        .appearanceDark: "Dark",
        .clientThemeLabel: "Chat theme",
        .accessibilityLabel: "Accessibility",
        .accessibilityGranted: "Granted",
        .accessibilityNotGranted: "Not granted",
        .openSystemSettingsButton: "Open System Settings…",
        .accessibilityExplanation: "Needed for global shortcuts, reading other apps' UI, and synthetic clicks.",

        .volumeLabel: "Volume",
        .muteLabel: "Mute",
        .autoMuteLabel: "Mute automatically in Focus (best effort, may be inexact)",
        .muteComplaintLabel: "Grumble when muted",

        .avoidClimbingLabel: "Stay off the focused window",
        .speedLabel: "Walking speed",
        .toySizeLabel: "Toy size",
        .toyPumpkin: "Pumpkin",
        .toyWand: "Wand",

        .openCustomisationFolder: "Open the customisation folder",
        .avatarsHeader: "Avatars",
        .importAvatarButton: "Import avatar package…",
        .avatarSelectButton: "Select",
        .avatarReloadButton: "Reload avatars",
        .avatarReloadedFormat: "Reloaded '%1$@'.",
        .avatarPackageFormatExplanation:
            "An avatar package is a single folder: manifest.json, a transparent PNG per motion (idle required; walk, climb and fall recommended), and optionally a sounds/ folder of .wav files. Around 1024px on the long edge and under about 500KB per file works best.",
        .importPanelPrompt: "Import",
        .sizeHeader: "Size",
        .emotionsHeader: "Emotions",
        .emotionsExplanation: "Maps socket events (thinking, task failed, task done) to images. Anything unmapped falls back to the idle image.",
        .mappedLabel: "Mapped",
        .notMappedLabel: "Not mapped",
        .chooseImageButton: "Choose image…",
        .choosePanelPrompt: "Choose",
        .customEmotionPlaceholder: "Custom emotion name",
        .addButton: "Add",

        .mappedCountFormat: "%1$@ of %2$@ mapped",

        .permissionNeededBubble: "I need permission for that. Allow it in the window I'm pointing at!",
        .bubbleClientOffline: "The chat window isn't open",
        .bubbleMutedComplaint: "Am I being too loud?",
        .bubbleCapturePrompt: "Capture a screen area",
        .bubblePlaceholder: "What can I help with?",
        .notchNothingPlaying: "Nothing playing",

        .agentHeader: "Agent",
        .providerLabel: "AI provider",
        .apiKeyLabelFormat: "%1$@ API key",
        .cliCredentialLabelFormat: "%1$@ setup token / API key",
        .listOrJoiner: " or ",
        .apiKeySave: "Save",
        .apiKeyClear: "Delete",
        .apiKeySavedFormat: "Saved to %1$@",
        .apiKeySourceFormat: "In use — from %1$@",
        .apiKeyMissing: "No key yet — I can't run commands until there is one.",
        .apiKeyOptionalForCLI: "Leave it empty to use the login the CLI already has.",
        .apiKeySaveFailed: "Couldn't save the key file.",
        .apiKeyExplanationFormat:
            "Stored in a .env file only you can read. A %1$@ environment variable, or a .env in the project folder, takes precedence.",
        .modelLabel: "Model",
        .modelReset: "Default",
        .modelExplanationFormat: "Save it empty to use the default, %1$@. A %2$@ environment variable takes precedence.",
        .codingAgentLabel: "Coding CLI",
        .permissionsLabel: "Auto-allow",
        .permissionsExplanation: "How much the CLI may do without asking each time. File writes stay inside the selected project folder whichever setting is chosen. \"Never ask\" also runs the pet's own shell commands, AppleScripts and clicks with no approval prompt.",
        .slashModelCurrentFormat: "The model is %1$@. Use /model <name> to change it.",
        .slashModelSetFormat: "Model set to %1$@.",
        .slashModelUnsupportedFormat: "The %1$@ provider has no model to choose -- the CLI uses its own.",
        .slashEffortCurrentFormat: "Effort is '%1$@'. Use /effort low, medium or high to change it.",
        .slashEffortSetFormat: "Effort set to '%1$@'. It applies from the next turn.",
        .slashUnknownFormat: "%1$@ is not a command. Try /help.",
        .slashWriteFailed: "Couldn't write the settings file.",
        .slashPermissionsCurrentFormat: "Currently '%1$@'. `/permissions tools|edits|all|auto` changes it.",
        .slashPermissionsSetFormat: "Changed to '%1$@'. It applies from the next turn.",
        .slashSummaryModel: "Show or change the model",
        .slashSummaryEffort: "Show or change how much it thinks",
        .slashSummaryFast: "The lowest effort",
        .slashSummaryPermissions: "What the CLI may do on its own",
        .slashSummarySkills: "The skills installed here",
        .slashSummaryHelp: "The list of commands",
        .slashSkillsHeader: "Installed skills.",
        .slashSkillsEmpty: "No skills installed. Put a folder in `~/.claude/skills` or the project's `.claude/skills` and it shows up here.",
        .slashHelp: """
        Commands you can type here.

        - `/model` — show the model, `/model <name>` to set it
        - `/effort` — show effort, `/effort low|medium|high` to set it
        - `/fast` — the lowest effort (same as `/effort low`)
        - `/permissions` — what the CLI may do on its own, `/permissions tools|edits|all` to change it
        - `/skills` — the skills installed here
        - `/help` — this list
        """,
        .explorerTabFiles: "Files",
        .explorerTabSessions: "Sessions",
        .explorerTabGit: "Changes",
        .gitHeader: "Changes",
        .gitClean: "Nothing has changed.",
        .gitNotARepository: "Not a git repository.",
        .gitDetached: "Detached HEAD",
        .sessionsHeader: "Agent session history",
        .sessionsEmpty: "No history yet.",
        .sessionsLoading: "Reading…",
        .sessionsRefresh: "Refresh",
        .skillsHeader: "Skills",
        .skillSourcePersonal: "Your account",
        .skillSourceProject: "This project",
        .skillsEmpty: "No skills installed.",
        .skillsExplanation: "Skills the coding CLI loads. When a name is in both places, the project's is the one it uses.",
        .skillReveal: "Show in Finder",
        .skillCountFormat: "%1$@",
        .effortLow: "brief",
        .effortMedium: "normal",
        .effortHigh: "thorough",
        .permissionsToolsOnly: "Puck's tools only",
        .permissionsEdits: "…and file edits",
        .permissionsEverything: "…and commands",
        .permissionsAuto: "Never ask",
        .cliProviderExplanation:
            "Uses the selected CLI with a stable setup token or API key. Puck's tools are wired in over MCP, and file work inside the selected project runs in a sandbox.",
        .installedFormat: "Installed '%1$@'.",
        .installedMissingRecommendedFormat: "Installed '%1$@' — recommended clips missing (idle image used instead): %2$@",
        .failedToInstallFormat: "Couldn't install '%1$@': %2$@",
        .rejectedMissingRequiredFormat: "Rejected — required clip files missing: %1$@",
        .failedToValidateFormat: "Validation failed: %1$@",
        .updatedEmotionFormat: "Updated '%1$@'.",
        .failedToSetEmotionFormat: "Couldn't set '%1$@': %2$@",
        .islandResize: "Resize the island",
        .islandPetSize: "Resize the pet",
        .islandFold: "Fold the island down",
        .islandUnfold: "Unfold the island",
        .terminalTitle: "Terminal",
        .terminalToggle: "Terminal (⌃`)",
        .terminalHide: "Hide the terminal",
        .terminalCouldNotStart: "The shell exited as soon as it started. Close the terminal and open it again.",
        .codeBlockCopy: "Copy",
        .codeBlockCopied: "Copied",
        .commonClose: "Close",
        .a11yRemoveAttachment: "Remove attachment",
        .a11yAgentSettings: "Agent settings",
        .a11yClearSearch: "Clear search",
        .a11yCloseTab: "Close tab",
        .a11yUnsavedChanges: "Unsaved changes",
        .a11yFileModified: "Modified",
        .a11ySelectTab: "Open this tab",
        .a11yProjectReady: "Project ready",
        .a11yProjectNone: "No project",
        .a11yProjectUnavailable: "Project unavailable",
        .a11yOpenFile: "Open file",
        .a11ySelected: "In use",
        .a11yPetSaysFormat: "Puck says: %1$@",
        .a11yApprovalNeededFormat: "Approval needed: %1$@",
        .commonCancel: "Cancel",
        .commonDone: "Done",
        .commonDelete: "Delete",
        .commonCreate: "Create",
        .commonChoose: "Choose…",

        .chatSelectAConversation: "Select a conversation",
        .chatNewSession: "New chat",
        .chatCasualSession: "New chat",
        .chatThisWorkspace: "This workspace",
        .chatSettings: "Settings",
        .chatComposerPlaceholder: "Message the agent…",
        .chatStop: "Stop",
        .voicePermissionNeeded: "Speech recognition permission is needed. Turn Puck on in System Settings > Privacy & Security > Speech Recognition.",
        .chatAttach: "Attach an image",
        .chatFilterPlaceholder: "Filter chats",
        .chatRunning: "Working",
        .chatVoice: "Speak",
        .chatWorkspaces: "Workspaces",
        .chatNoSessionsHere: "No chats yet",
        .chatChatsAndTasks: "Chats and tasks",
        .chatModel: "Model",
        .chatEffort: "Thinking",
        .chatSend: "Send",
        .chatEditor: "Editor",
        .chatAttachEditor: "Attach editor",
        .chatDetachEditor: "Detach editor",
        .chatAttachEditorHelp: "Put the editor back in this window",
        .chatDetachEditorHelp: "Open the editor in a window of its own",
        .chatNoProjectLinked: "No project is linked to this workspace",
        .chatEditorInSeparateWindow: "The editor is open in its own window",
        .chatEmptyTitle: "What can I help with?",
        .chatEmptySubtitle: "Code or small talk — just say something.",
        .chatThinking: "Thinking…",
        .chatFailed: "That failed.",
        .chatDone: "Done",
        .chatDoneFailed: "Failed",
        .chatApprovalAnswered: "Answered",
        .chatApprovalRespondToPreviousFirst: "Answer the earlier request first.",
        .chatApprovalAllow: "Allow",
        .chatApprovalDeny: "Deny",
        .chatDeleteWorkspaceTitleFormat: "Delete %1$@?",
        .chatDeleteWorkspaceMessage: "Every chat in this workspace goes with it. The project folder stays where it is.",
        .chatDeleteSessionTitle: "Delete this conversation?",
        .chatDeleteSessionMessage: "Everything said here goes with it, and it cannot be undone.",
        .chatNewWorkspace: "New workspace",
        .chatWorkspaceName: "Name",
        .chatProjectFolder: "Project folder",
        .chatNoFolderSelected: "None",
        .chatProjectFolderExplanation: "Link a folder to use the editor and let the agent edit code. Leave it empty for conversation only.",

        .timeJustNow: "just now",
        .timeYesterday: "Yesterday",
        .timeMinutesFormat: "%1$@ min",
        .timeHoursFormat: "%1$@ hr",
        .timeDaysFormat: "%1$@ d",
        .timeMonthDayFormat: "%1$@/%2$@",

        .editorUnsavedTitle: "There are unsaved changes",
        .editorSaveAndClose: "Save and close",
        .editorDiscard: "Don't save",
        .editorUnsavedMessageFormat: "Save the changes to %1$@?",
        .editorProjectFolderMissing: "The project folder is gone -- moved or deleted, by the look of it",
        .editorProjectPathNotAFolder: "The linked path is not a folder",
        .editorProjectFolderUnreadable: "No permission to read the project folder",
        .editorConflictTitle: "The file changed on disk",
        .editorConflictMessage: "Choose which version to keep before saving.",
        .editorChangedOnly: "Changed files only",
        .editorGoToLine: "Go to line",
        .editorFind: "Find in file",
        .editorOpenQuickly: "Open quickly",
        .editorOpenQuicklyPlaceholder: "Open a file by name",
        .editorGoToLinePlaceholder: "Line",
        .editorNextTab: "Next tab",
        .editorPreviousTab: "Previous tab",
        .editorUseDiskVersion: "Use the disk version",
        .editorKeepMyVersion: "Keep mine",

        .fileNotAFilePath: "That is not a file path",
        .fileNotADirectoryPath: "That is not a folder path",
        .fileNameTaken: "Something with that name is already there",
        .fileInvalidName: "That name cannot be used",
        .fileCannotDeleteRoot: "The project folder itself cannot be deleted",
        .fileCouldNotCreate: "Could not create it",
        .explorerNewFile: "New file",
        .explorerNewFolder: "New folder",
        .explorerRename: "Rename",
        .explorerDelete: "Move to Trash",
        .explorerRevealInFinder: "Reveal in Finder",
        .explorerCopyPath: "Copy path",
        .explorerDeleteTitleFormat: "Move %@ to the Trash?",
        .explorerDeleteMessage: "You can put it back from the Trash.",
        .explorerRenameTitle: "Rename",
        .explorerNewFileTitle: "New file",
        .explorerNewFolderTitle: "New folder",
        .explorerNamePlaceholder: "Name",
        .explorerCreate: "Create",
        .fileInvalidPath: "That file path is not valid",
        .fileOutsideProject: "That path is outside the project",
        .fileSymlinkEscapesProject: "That symlink points outside the project",
        .fileNotFound: "File not found",
        .fileBinaryNotEditable: "Binary files cannot be edited",
        .fileBinaryNotSavable: "Binary files cannot be saved",
        .fileOnlyUTF8: "Only UTF-8 text files are supported",
        .fileImageTooLargeToPreview: "Images over 10MB cannot be previewed",
        .fileImageFormatMismatch: "The file's contents do not match any supported image format",
        .fileTooLargeReadOnly: "Files over 2MB are read-only",
        .fileChangedOnDisk: "The file on disk changed since it was last read",
        .fileSaveExceedsLimit: "The content to save is over the 2MB limit",
        .fileInUseByAnotherProcess: "The file on disk is in use by another process",

        .agentCancelled: "Stopped.",
        .agentSettingsHint: "Check the key in Settings (⌘,).",
        .agentModelNotFound: "No such model. Check the model name in Settings (⌘,).",
        .agentRateLimited: "Too many requests, or the usage limit is reached. Try again shortly.",
        .agentToolCeilingFormat: "Stopped after more than %1$@ tool calls.",
        .agentNoAPIKeyFormat: "There's no API key. %1$@",
        .agentBadAPIKeyFormat: "That API key isn't right. %1$@",
        .agentServerErrorFormat: "The AI server didn't answer (error %1$@). Try again shortly.",
        .agentAPIErrorFormat: "API error %1$@.",
        .agentAPIErrorWithMessageFormat: "API error %1$@: %2$@",

        .approvalRunShellFormat: "Run a shell command: %1$@",
        .approvalRunAppleScriptFormat: "Run AppleScript: %1$@",
        .approvalClickElementFormat: "Click on screen: %1$@",
        .approvalRunToolFormat: "Run %1$@: %2$@",

        .toolNoProjectLinked: "No project is linked to this workspace.",
        .toolShownButPetCouldNotGo: "The pet couldn't get there, but the code is showing. (%1$@)",
        .toolAmbiguousPathFormat: "Several files are named like %1$@: %2$@.",
        .toolAmbiguousPathMoreFormat: " and %1$@ more",
        .toolPickOneFullPath: " Call again with one of them as a full path.",
        .toolCouldNotOpenFormat: "Couldn't open %1$@.",
        .toolNoSuchLineFormat: "%1$@ has no line %2$@. (the file is %3$@ lines)",
        .toolEditorOffscreenShownAnyway: "The editor isn't on screen, so the pet couldn't go there. The code is showing.",
        .toolDuplicateRequest: "That request is a duplicate.",
        .toolTaskSessionUnavailable: "open_task_session is not available on this connection.",
        .toolTaskIsEmpty: "task is empty.",
        .toolPathIsEmpty: "path is empty.",
        .toolShowCodeNeedsEverything: "show_code needs all of path, start_line, end_line and caption.",
        .toolPathIsRelativeHint: " Paths are relative to the project root (for example src/App/main.swift).",
        .toolListFilesHint: " If you are unsure of the exact path, check with list_files and call again.",
        .toolCodeEditTimedOutFormat: "The code-editing agent went quiet for %1$@s, so it was stopped.",
        .toolCodeEditPurpose: "Code editing",

        .acpAborted: "Aborted",
        .acpTaskFailed: "The ACP task failed.",
        .acpWroteOutsideProject: "This task reported writing to a file outside the project. Worth a look.",
        .acpTaskDoneFormat: "ACP task finished (%1$@)",
        .acpNeedsNodeFormat: "%1$@ needs Node.js. Install it and try again.",
        .acpCLINotFoundFormat: "Couldn't find the %1$@ CLI. Install it and try again.",
        .acpAgentNotBundledFormat: "The coding agent (%1$@) isn't bundled with the app.",
        .acpCouldNotStart: "Couldn't start the coding agent.",

        .cliErrorFormat: "Coding CLI error: %1$@",
        .cliNotLoggedInFormat: "Your %1$@ login has expired. Run `%2$@` in a terminal to sign in again, then send this once more.",
        .terminalUnknownFormat: "No such terminal (%1$@).",
        .terminalEndedFormat: "That terminal has already ended (%1$@).",
        .terminalTooManyFormat: "Only %1$@ terminals can run at once. Stop one of the others first.",
        .terminalCouldNotStartFormat: "The terminal could not be started: %1$@",
        .terminalNeedsAProject: "This workspace has no project folder, so there is nowhere to open a terminal.",
        .terminalNeedsAnId: "Which terminal? An id is needed.",
        .terminalNeedsText: "There is nothing to send.",
        .terminalNeedsACommand: "There is no command to run.",
        .petAnnouncesLabel: "Let the pet speak up when the window is hidden",
        .reviewTitle: "Review changes",
        .reviewCountFormat: "%1$@ files · +%2$@ −%3$@",
        .reviewRefresh: "Read again",
        .reviewNothingChanged: "Nothing changed",
        .reviewNothingChangedDetail: "This project has no uncommitted changes.",
        .reviewBinaryFile: "A binary file, so there is nothing to show.",
        .reviewNoContentChange: "The contents are unchanged (a rename or a mode change).",
        .reviewRenamedFromFormat: "← %1$@",
        .reviewRevert: "Revert",
        .reviewRevertHelp: "Puts this file back to the last commit. A newly created file is deleted.",
        .reviewOpenFormat: "%1$@ files changed — review",
        .scheduleEveryMinutesFormat: "every %1$@ min",
        .scheduleDailyFormat: "daily at %1$@",
        .scheduleWeeklyFormat: "%1$@ at %2$@",
        .schedulesHeader: "Scheduled runs",
        .schedulesExplanation: "Something to send to this workspace at a set time. Only while Puck is running; one whose time passed while it was closed runs once when it comes back.",
        .schedulesNew: "What to send",
        .schedulesPromptPlaceholder: "e.g. check CI and tell me if it broke",
        .schedulesWhen: "When",
        .schedulesAdd: "Add",
        .scheduleEveryLabel: "Every (min)",
        .scheduleDailyLabel: "Daily",
        .scheduleWeeklyLabel: "Weekly",
        .scheduleAtLabel: "At",
        .scheduleDaysLabel: "Days",
        .chatLongMessageFormat: "%1$@ lines · %2$@",
        .chatExpandMessage: "Show all",
        .chatCollapseMessage: "Collapse",
        .chatOpenMessageAsFile: "Open as .txt",
        .cliTimedOutFormat: "The coding CLI went quiet for %1$@s, so it was stopped.",
        .cliNoAnswerFormat: "The coding CLI gave no answer. (%1$@)",
        .cliNoToolsFallbackFormat: "Couldn't open the MCP server, so this turn runs without tools: %1$@",
        .cliConversationPurpose: "Conversation",

        .providerNoAPIKey: "No API key is set.",
        .providerAPIErrorFormat: "API error %1$@: %2$@",
        .providerUndecodableFormat: "Couldn't read the response: %1$@",
        .mcpCouldNotOpenFormat: "Couldn't open the local server: %1$@",
        .mcpNoPort: "The local server got no port.",
        .keySourceEnvironmentFormat: "the %1$@ environment variable",

        .workspaceDefaultName: "Default workspace",
        .sessionDefaultTitle: "New chat",
        .themeLight: "Light",
        .themeDark: "Dark",
        .editorCollapse: "Collapse the file",
        .editorExpand: "Show the file again",
        .editorSelectAFile: "Pick a file in the explorer on the right",
        .editorSearchFiles: "Search files",
        .editorSaveHint: "Save (⌘S)",
        .providerRefusedResponse: "The model refused to answer (stop_reason: refusal)",
        .providerTruncatedFormat: "The answer was cut off at max_tokens(%1$@) -- a tool call may have been left unfinished",
        .acpProcessExited: "The ACP process exited.",

        .menuToys: "Toys",
        .menuHide: "Hide",
        .menuShow: "Show",
        .menuQuit: "Quit Puck",
        .menuOpenClient: "Open Puck Chat",
        .menuSettings: "Settings…",
        .mirrorAvatarLabel: "Mirror the avatar",
        .outlineAvatarLabel: "White outline",
        .posePreviewHeader: "Pose preview",
        .posePreviewExplanation: "How the avatar looks walking and climbing. If one faces the wrong way, flip or turn it here.",
        .poseWalkingRight: "Walking right",
        .poseWalkingLeft: "Walking left",
        .poseClimbingRightWall: "Climbing a wall on the right",
        .poseClimbingLeftWall: "Climbing a wall on the left",
        .poseOnTheCeilingFacingRight: "On the ceiling, going right",
        .poseOnTheCeilingFacingLeft: "On the ceiling, going left",
        .notchPanelLabel: "Notch panel",
    ]
}
