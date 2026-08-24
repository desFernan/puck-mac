# Puck 디자인 시스템 (현재 구현 기준)

> **디자인 시스템 v2 — 2026-08-14.** 아래 문서는 이전 팔레트/테마 체계(호박 주황 accent +
> 다크/화이트/글래스 3무드)를 전면 교체한 결과를 기록한다. 근거/배경은 `docs/decisions.md`의
> 2026-08-14 항목 참고 — 교체 사유는 기술적 결함이 아니라 아트디렉션 전면 재조정이었다.
> `.glass` 테마는 폐기됐다(macOS 26+ 전용 기능 유지보수 비용 대비 실익이 낮다는 판단,
> `docs/decisions.md`).
>
> **v4 — 2026-08-15 채팅 UI가 네이티브 SwiftUI로 복귀.** 이 문서의 이전 판(v2/v3)은 F13
> 클라이언트 창의 사이드바/탑바/메시지 목록이 `chat-web/`(React/Tailwind/shadcn)에 있다고
> 적고 있었다. 그 웹 레이어는 **삭제됐다** — 지금 채팅 UI는 전부 Swift이고
> `Puck/ClientWindow/Chat/`에 산다(`docs/decisions.md`의 "the chat UI goes back to native
> SwiftUI; chat-web is deleted", 2026-08-15). 같은 날 `workspace/`도 삭제됐다.
>
> 그래서 아래 §6은 **네이티브 기준으로 다시 썼다**. 팔레트/타이포/간격(§1-§5)과 설정창(§9),
> 에디터 표면(§9.5)은 그 교체에 영향받지 않았고 값도 그대로다 — 웹은 같은 값을 CSS 변수로
> 한 벌 더 갖고 있었을 뿐, 정본은 언제나 `ClientPalette`/`ClientTheme`였다.
>
> `ClientWindowView.swift`가 실제로 그리는 것: `ChatPaneView`(단독 또는 `HSplitView`로
> `EditorPaneView`와 나란히, §9.5) + 상시 `ClientStatusBarView`(§4.5).

F13 클라이언트 창의 디자인이 확정된 상태를 **코드에 실제로 존재하는 값 그대로** 기록한 문서다.
새 디자인 제안이 아니라 현황 스냅샷이며, 값이 바뀌면 이 문서가 아니라 아래 소스가 먼저 바뀐다.

| 역할 | 파일 |
|---|---|
| 색 토큰 (2세트: light/dark) | `Puck/ClientWindow/ClientPalette.swift` |
| 타입·간격·모양 토큰 | `Puck/ClientWindow/ClientTheme.swift` |
| 테마 선택/동기화 | `Puck/ClientWindow/ClientThemeStyle.swift` |
| 팔레트 주입 | `Puck/ClientWindow/ClientPaletteEnvironment.swift` |
| 상태 점 컴포넌트 | `Puck/ClientWindow/StatusDotView.swift` |
| 상태 바 | `Puck/ClientWindow/ClientStatusBarView.swift` |

원칙 하나: **뷰는 시스템 색/폰트를 직접 쓰지 않는다.** 전부 `ClientPalette`(색)와 `ClientTheme`(그 외)에서 나온다.

---

## 1. 테마 — light / dark

`ClientThemeStyle`은 이제 정말 라이트/다크 축이다(v1은 독립적으로 아트디렉션된 3개 무드 — 다크,
화이트, 글래스 — 였다). `.glass`는 v2에서 완전히 삭제됐다.

| 값 | 표시명 | colorScheme |
|---|---|---|
| `.light` | 화이트 | light |
| `.dark` | 다크 | dark |

- 기본값(파싱 실패 시 폴백)은 `.dark` — 이 앱이 원래 갖고 있던 룩.
- 저장 위치는 Puck 쪽 `SettingsStore`(`Puck.clientThemeStyle`). 채팅 창 안이 아니라 **메뉴막대 → Puck 설정 → "채팅 테마"** 에서 바꾼다.
- PuckClient는 별도 프로세스라 UserDefaults를 못 읽는다. `ClientThemeStyle.crossProcessChangeNotification`으로 브로드캐스트하되 **값을 notification userInfo에 실어 보낸다** — `UserDefaults.set()` 직후 다른 프로세스에서 읽으면 아직 옛 값일 수 있는 실제 레이스가 있었다.
- 앱 전체 외관(`AppAppearance`: system/light/dark, 펫 오버레이·노치·설정창)은 이것과 **별개 설정**이다.

## 2. 색 토큰

`ClientPalette`는 12개 프로퍼티 — 10개 저장 필드 + 2개 계산 프로퍼티. 계산 프로퍼티는 다른 필드를
재사용해서 절대 따로 어긋나지 않는다: `statusIdle { textSecondary }`, `statusActive { accent }`.

`background` `surface` `surfaceBorder` `textPrimary` `textSecondary` `accent` `onAccent`
`statusSuccess` `statusError` `statusWarning` (저장) · `statusIdle` `statusActive` (계산)

### light

| 토큰 | 값 |
|---|---|
| background | `#fafafa` |
| surface | `#ffffff` |
| surfaceBorder | `#e5e5e5` |
| textPrimary | `#1a1a1a` |
| textSecondary | `#6b6b6b` |
| accent | `#ed8c33` |
| onAccent | `#ffffff` |

### dark

| 토큰 | 값 |
|---|---|
| background | `#0a0a0a` |
| surface | `#131313` |
| surfaceBorder | `#242424` |
| textPrimary | `#ededed` |
| textSecondary | `#7a7a7a` |
| accent | `#ed8c33` |
| onAccent | `#161616` (거의 검정 — 이 팔레트에서는 흰색보다 accent 위 대비/무드가 낫다) |

v2 값은 Orca 레퍼런스 기반으로 새로 잡은 값이다(`docs/decisions.md`의 2026-08-14 항목 참고).
당시엔 소비처가 셋이었다 — `ClientPalette.swift`와, 웹 쪽 CSS 변수 두 벌(chat-web/workspace).
**지금은 `ClientPalette.swift` 하나뿐이다**: 두 웹 레이어 모두 2026-08-15에 삭제됐다. 값 자체는
그때 갈아끼운 것 그대로이고, 위 표가 유일한 정본이다.

### 상태 색 (v2 신규)

| 토큰 | 값 | 비고 |
|---|---|---|
| `statusSuccess` | `#3fb950` | light/dark 공통(테마 무관 고정) |
| `statusError` | `#f85149` | light/dark 공통 |
| `statusWarning` | `#e3b341` | light/dark 공통 |
| `statusIdle` | `textSecondary` 재사용 | 계산 프로퍼티 |
| `statusActive` | `accent` 재사용 | 계산 프로퍼티 |

`statusSuccess`/`statusError`/`statusWarning`은 accent와 마찬가지로 라이트/다크 두 팔레트에서 값이
동일하다(테마가 바뀌어도 안 바뀐다). 오늘 기준 실제 소비처는 둘뿐이다: `statusWarning`은
`ConflictBannerView`(디스크 변경 경고 아이콘)에서 직접 쓰고, 나머지 네 값은 `StatusDotView`/
`DotStatus`를 거쳐 `ClientStatusBarView`(§4.5)에서 쓰인다.

### accent 사용 규칙

accent는 **여전히 유일하게 튀는 색**이고 값도 안 바뀌었다(`#ed8c33`, light/dark 공통).

구체적으로 어디에 칠해지는지는 §7의 상태 표현 규칙 표를 보는 게 정확하다. 이 절에서 수치를
다시 단정하지 않는 건 v2 때부터 지켜온 방침이다 — v1 문서가 나열했던 `accent.opacity(0.14)`류
수치가 실제 코드와 어긋난 적이 있었고, 값의 정본은 언제나 `ClientPalette`/`ClientTheme`이지
이 문서가 아니다.

## 3. 타이포그래피

전부 `Font.system`, 기본 디자인. `mono`만 monospaced로 예외. v1의 11개 토큰 중 6개만 남았다(Task 3,
쓰는 곳이 없어진 토큰은 이름만 남겨두지 않고 그대로 삭제).

| 토큰 | 정의 | 용도 |
|---|---|---|
| `sectionHeader` | caption · semibold | 설정창 섹션 제목(`SettingsSection`) |
| `workspaceName` | callout · medium | 설정창 헤더의 앱 이름 |
| `sessionTitle` | footnote | 범용 라벨 — 설정 행 라벨, 에디터 빈 상태/로딩 메시지 |
| `toolLabel` | footnote · medium | 충돌 배너(`ConflictBannerView`) 제목 |
| `mono` | caption · monospaced | 상태 바의 워크스페이스명, 설정 슬라이더 라이브 값, 이미지 미리보기 캡션 |
| `caption` | caption2 | 탭 스트립 파일명, 파일트리 행, 충돌 배너 부제 |

전부 시스템 텍스트 스타일 기반이라 **동적 타입(사용자 글자 크기)을 따라간다.**

## 4. 간격·크기·모양

```
spacingSmall    4      cardCornerRadius   6
spacingMedium   8      rowCornerRadius    4
spacingLarge   12
windowMinWidth 960     windowMinHeight  640
```

v1의 11개 메트릭 중 7개만 남았다 — 사이드바 폭/말풍선 최대폭/아바타 크기는 그 값을 쓰던 뷰(구
ChatView 계열)와 함께 삭제됐다.

- 코너 라운딩은 v2에서 한 단계 더 줄었다(`cardCornerRadius` 12→6, `rowCornerRadius` 6→4) — chat-web/workspace의 `--radius` 계열도 같은 방향으로 같이 줄었다(`ClientTheme.swift`의 코드 주석 기준, Task 6).
- 모양은 `ClientTheme.Shapes`에 `card`/`row` 두 개만 선언돼 있다(둘 다 `style: .continuous`) — v1에 있던 `bubble`/`panel` 모양은 그걸 쓰던 뷰와 함께 없어졌다.
- `spacingSmall`/`spacingMedium`/`spacingLarge`는 `ClientWindow/Editor/*`뿐 아니라 `Puck/Settings/*`, `PuckClient/AgentSettingsView.swift`에서도 쓰인다 — ClientWindow 폴더 전용 토큰이 아니라 Puck 쪽 UI 전반의 공용 간격 스케일이다.
- `windowMinWidth`/`windowMinHeight`는 SwiftUI `.frame(minWidth:)`(`ClientWindowView.swift`)와 AppKit `NSWindow.minSize`(`PuckClient/AppDelegate.swift`)가 **같은 상수 하나**를 읽는다.

## 4.5 상태 표현 (신규) — `StatusDotView` / `ClientStatusBarView`

이 절은 v2에서 새로 생긴 것(Task 4-5) — v1 문서에는 없었다.

**`DotStatus`**(`Puck/ClientWindow/StatusDotView.swift`)는 4개 case다: `idle`/`active`/`success`/`error`,
각각 `palette.statusIdle`/`statusActive`/`statusSuccess`/`statusError`로 매핑된다. `StatusDotView`는
지름 6pt(호출부에서 override 가능) 원 하나를 그리고, **`.active`일 때만 펄스**한다(불투명도
1↔0.4, `.easeInOut(duration: 0.9).repeatForever(autoreverses: true)`) — idle/success/error는 정지된
상태를 나타내므로 모션이 없다.

**`ClientStatusBarView`**는 `ClientWindowView`의 콘텐츠 아래(항상 표시되는 얇은 바, height 22,
`palette.surface` 배경 + 위쪽 1px `palette.surfaceBorder` 헤어라인)에 상태 점 + 프로젝트 경로 +
세로 헤어라인 구분선 + 모델 이름, 이렇게 네 조각을 왼쪽부터 순서대로 보여준다(v3, Task 3 —
이전엔 워크스페이스 이름 하나뿐이었다). 프로젝트 경로는 `abbreviatedPath(_:home:)`로 홈 디렉터리
접두사만 `~`로 줄인 값(`/Users/x/dev/p` → `~/dev/p`, 경로 경계에서만 치환하므로 `/Users/xyz`가
홈이 `/Users/x`일 때 잘못 잘리지 않는다)이고, 프로젝트가 없는 워크스페이스(`projectPath == nil`)는
그 워크스페이스 이름("일상 대화" 등)을 그대로 쓴다. 모델 이름은 `AgentConfiguration.load().model`을
매 렌더마다 새로 읽는다 — 스토어에서 주입받지 않는 이유는 코드 주석 그대로: 모델이 바뀌려면
리빌드나 `.env` 수정이 필요하지, 이 뷰가 실시간으로 관찰해야 할 값이 아니기 때문. 두 텍스트 모두
`ClientTheme.Typography.mono` + `palette.textSecondary`. `dotStatus(for:)`가 `EditorAvailability`를 `DotStatus`로 매핑한다:
`.noProject → .idle`, `.ready → .success`, `.unavailable → .error`. **`.active`는 이 매핑에서 절대
나오지 않는다** — 상태 바 자체는 idle/success/error 세 값만 보여준다.

이름에 대한 코드 주석을 그대로 옮기면: "Reports the active workspace's editor/project status --
deliberately not called 'connection', since that term means the pet-app↔workspace bridge socket
elsewhere in this codebase and this bar doesn't observe that." 즉 이 바가 보여주는 건 브릿지 소켓
연결 여부가 **아니라** 에디터/프로젝트 상태다 — 이름을 헷갈리지 않게 의도적으로 고른 것.

**두 번째 소비처, 그리고 v3에서 해소된 긴장**: `EditorTabStripView`가 더러워진(unsaved) 파일 탭
옆에 `StatusDotView(status: .active, palette: palette, diameter: 5, pulses: false)`를 붙인다. v2
문서가 여기 적어뒀던 긴장 — `.active`는 원래 "실행 중" 같은 **짧게 지속되는 진행 상태**를 위해
설계됐는데, dirty 플래그는 사용자가 저장하기 전까지 무기한 지속되면서도 계속 펄스했다 — 는 v3
(Task 2)에서 `StatusDotView`에 `pulses: Bool = true` 파라미터를 추가하는 것으로 풀렸다.
`EditorTabStripView`는 이제 `pulses: false`를 넘겨서, 색은 `.active`(accent)를 그대로 쓰되 애니메이션
없이 정지해 있다. 즉 세션 어휘에서 `.active`의 의미는 이제 확실히 "지금 진짜로 실행 중"(짧게
지속) 하나로 좁혀졌고, dirty 표시처럼 무기한 지속되는 상태는 `.active`의 색만 빌리되 펄스는 끈
별도 표현으로 분리됐다 — 이 구분은 사이드바 세션 행(§6, `ChatSessionRow`)에서도 그대로
지켜진다: `pulses: session.isRunning`이라 실행 중일 때만 펄스하고, 그 외에는 `lastRunOk`가
성공/실패를 정지 상태로 보여준다.

## 5. 표면

`GlassSurface.swift`는 Task 1-2 수정 라운드에서 **완전히 삭제됐다**(단순화된 게 아니라 파일 자체가
없어짐). 대체할 공용 `themedSurface`류 함수도 새로 만들어지지 않았다 — 팔레트가 라이트/다크
둘뿐이고 둘 다 항상 플랫이라 분기할 게 없기 때문이다. 호출부마다 필요한 만큼만 직접 조합한다:

```
배경만                    .background(palette.surface)
                          (EditorTabStripView, FileTreeView)

배경 + 테두리 카드         .background(palette.surface)
                          .clipShape(ClientTheme.Shapes.card)
                          .overlay(ClientTheme.Shapes.card.stroke(palette.surfaceBorder))
                          (ConflictBannerView — 이 패턴의 유일한 사용처)

배경 + 위쪽 헤어라인만     .background(palette.surface)
                          .overlay(alignment: .top) {
                              Rectangle().fill(palette.surfaceBorder).frame(height: 1)
                          }
                          (ClientStatusBarView)
```

`VisualEffectBackground`(`NSVisualEffectView` 래퍼)도 이번 라운드에서 **완전히 삭제됐다** — 확인
결과 아무 뷰도 쓰지 않는 죽은 코드였고, 원래 (이미 삭제된) 사이드바 배경용으로 만들어졌던 것으로
보인다. `GlassSurface.swift`(SwiftUI 쪽 절반, 이미 삭제됨)와 같은 이유로 같이 삭제됐다.

## 6. 레이아웃

> **이 절은 v4(2026-08-15) 기준 현재 상태다.** 여기 서술하는 화면은 전부 SwiftUI이고
> `Puck/ClientWindow/Chat/`에 있다. 창 크롬(아래 첫 항목)만 `PuckClient/AppDelegate.swift`
> 소관이다.
>
> 스톡 macOS 관용구를 쓴다 — `NavigationSplitView`, 워크스페이스마다 `Section`을 둔 `List`,
> 툴 호출은 `DisclosureGroup`, 작성창은 `TextField(axis: .vertical)`. 커스텀 트리나 커스텀
> 탭 컨트롤을 짓지 않는 게 이 판의 기본 방침이고, 그래서 선택·키보드 내비게이션·접근성이
> 공짜로 따라온다.

### 창 크롬 (Swift)

`.titled + .closable + .resizable + .miniaturizable + .fullSizeContentView`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`. 콘텐츠가 타이틀바 아래까지 올라가 사이드바 배경이 신호등까지 닿는다.

> 알려진 미해결 이슈: 신호등 주변 색이 어긋나 보이는 문제. `isOpaque = false` + `backgroundColor = .clear`를 시도했으나 **더 나빠져서 되돌렸다.** 이 트릭은 진짜 borderless 창(오버레이/노치/입력 버블)에만 통하고, `.titled` 창은 네이티브 타이틀바 컨테이너가 콘텐츠 위에 따로 있어서 창을 비불투명으로 만들면 그 레이어의 반투명이 데스크톱을 비친다.

### 골격

```
ClientWindowView
├ ChatPaneView                        (에디터가 붙어 있으면 HSplitView 좌측)
│ └ NavigationSplitView
│   ├ sidebar  ChatSidebarView        min 180 / ideal 220 / max 280
│   └ detail   ChatTranscriptView     + Divider + ChatInputBar
│               └ 툴바: 에디터 토글(⇧⌘E) · 에디터 떼기/붙이기(⇧⌘D) · 설정
├ EditorPaneView                      (에디터가 붙어 있을 때만, min 540 — §9.5)
└ ClientStatusBarView                 창 전체 폭 — §4.5
```

사이드바 폭은 `.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)`. 하한이 220이
아니라 180인 건, 960pt 창 최소폭에서 세 패널이 이미 빡빡해서 사이드바가 폭을 한 뼘도 안 내주면
작성창 placeholder가 두 줄로 접히기 때문이다. 상한이 있는 건 넓은 창에서 사이드바가 채팅을
잡아먹지 않게 하려고.

접기/펼치기 버튼은 없다 — `NavigationSplitView`가 제 토글을 갖고 있다.

### 사이드바 구성

`List(selection:)` 하나에 **워크스페이스마다 `Section`**, 그 안에 세션 행. 모든 워크스페이스가
항상 펼쳐져 있어서 다른 워크스페이스의 세션을 보려고 무언가를 열 필요가 없다.

- 섹션 헤더(`WorkspaceHeader`) = 워크스페이스 이름 + 새 채팅 버튼
- 세션 행(`ChatSessionRow`) = `StatusDotView` + 제목 + 상대 시간(`RelativeTime`)
- 선택 강조는 `List`의 것을 그대로 쓴다. 선택 태그는 `SessionSelection`(워크스페이스 id +
  세션 id를 한 `Hashable` 값으로 묶은 것) — `List`는 태그 하나만 고를 수 있는데 세션을
  가리키려면 두 id가 다 필요해서다
- 세션 삭제는 컨텍스트 메뉴 + 확인 다이얼로그(`삭제`/`취소`)

**세션 탭 스트립은 없다.** v3까지 있던 상단 탭 줄은 네이티브 복귀 때 사라졌고, 세션 전환은
사이드바 선택 하나로 한다. 지금 코드에 남아 있는 탭 스트립은 에디터의 파일 탭
(`EditorTabStripView`)뿐이며 다른 물건이다.

### 채팅 영역

- 제목은 창 타이틀바가 받는다 — `navigationTitle`은 세션 제목, `navigationSubtitle`은
  워크스페이스 이름. 별도 탑바를 그리지 않는다
- 메시지 라우팅(`sendMessage`/`cancelActiveRun`/`respondToPendingApproval`)은
  `ClientWindowStore`의 활성 워크스페이스/세션 id로 간다. 웹 시절 리듀서 사본이 사라지면서
  "어느 id가 최신인가" 문제 자체가 없어졌다 — 상태가 한 벌뿐이다
- 작성창(`ChatInputBar`)은 `TextField(axis: .vertical)`이라 내용에 따라 늘어나고, 포커스 링과
  텍스트 동작은 스톡 그대로다. 실행 중이면 전송 버튼이 정지 버튼이 된다(§7)

### 툴 호출 표현

`ToolCallRow` — **호출 하나당 행 하나**다. `ChatSession.swift`가 호출과 결과가 같은 `tool_use`
id를 공유한다고 명시하고 있어, 트랜스크립트가 그 id로 결과를 찾아 같은 행에 붙인다.

- `DisclosureGroup`이라 인자/결과 상세는 접혀 있고 펼쳐서 본다
- 헤더: 상태 아이콘 + 도구명. 성공 `checkmark.circle.fill`(녹색), 실패
  `exclamationmark.triangle.fill`(주황), 아직 실행 중이면 `ProgressView`
- 짝이 되는 결과가 아직 없으면 실행 중으로 그린다 — 별도 결과 행을 만들지 않는다

### 실행 상태 줄

`RunningStatusLine` — 활성 세션이 실행 중일 때만, 스피너 + "생각 중…" 한 줄.

모델 이름과 프로젝트 경로는 여기 없다. 그건 네이티브 상태 바(§4.5)가 `AgentConfiguration`에서
직접 읽어 그린다 — 한 화면에 두 번 적을 이유가 없다.

### 말풍선

`MessageBubble`. 사용자/어시스턴트가 **같은 채움**을 쓰고, 구분은 정렬로만 한다(사용자는 우측).

### 승인 / 완료 줄

- `ApprovalBanner` — 승인 대기 중인 요청이 있을 때. 이미 응답했으면 "응답함", 앞에 다른 요청이
  밀려 있으면 "앞의 요청에 먼저 응답해 주세요."로 바뀐다 — 승인은 큐라서 오래된 것부터 답한다
- `DoneRow` — 실행이 끝난 자리에 결과 한 줄

### 빈 상태

`EmptyTranscript` — 인사말 2줄("무엇을 도와드릴까요?" / "코드든 잡담이든, 편하게 말 걸어보세요.").
호박 마크는 없다. 프롬프트 추천 카드와 글로우도 없다.

## 7. 상태 표현 규칙

| 상태 | 표현 |
|---|---|
| 활성(세션/워크스페이스 행) | `accent.opacity(0.14)` 채움 + accent 아이콘 |
| 호버(세션 행) | `surfaceBorder.opacity(0.6)` 채움 |
| 호버(설정 액션 행) | `.quaternary` 채움 |
| 호버(새 채팅) | `opacity 0.8` |
| 비활성(전송 버튼) | 회색 원(`surfaceBorder`) → 활성 시 accent 채움. 투명도 페이드가 아니다 |
| 실행 중 | 세션 행에 `ProgressView`, 입력바 전송 버튼이 정지 버튼으로 교체 |

## 8. 접근성

아이콘만 있는 버튼은 전부 `.accessibilityLabel` + `.help`를 단다 — 사이드바 접기/펼치기, 새 채팅, 워크스페이스 전환(`accessibilityValue`에 현재 이름), 세션 전환, 설정.
접힘 상태에서 글자 하나뿐인 워크스페이스 버튼처럼, 화면에 읽을 텍스트가 없는 컨트롤이 판정 기준이다.

## 9. 설정창 (같은 토큰, 다른 형태)

`SettingsComponents.swift`. pokoPet 메뉴막대 팝오버가 레퍼런스이고, 360×560 단일 패널이다.

**섹션마다 카드를 두지 않는다** — 패널이 유일한 표면이고 나머지는 그 위에 바로 얹힌다. 이전의 GlassCard 스택이 "슬래브 더미"처럼 보였던 원인이라 걷어냈다.

- `SettingsSection` — 회색 소제목만, 배경 없음
- `SettingsRow` — 라벨 좌 / 컨트롤 우
- `SettingsStackedRow` — 넓은 컨트롤(슬라이더·세그먼트)용, 라벨 위 컨트롤 아래. 우측에 라이브 값(mono)
- `ToyTile` — 그리드 타일. 채움은 아이템 **자기 아트워크의 틴트**(`0.14`, 꺼내둔 상태면 `0.28` + 1.5pt 링). 이 창에서 색이 살아남는 유일한 자리이며 앱 accent와 무관
- `SettingsActionRow` — 텍스트 + 셰브론, 호버 전까지 버튼 크롬 없음

## 9.5 코드 에디터 표면 (2026-08-14 신규)

`Puck/ClientWindow/Editor/`(파일트리·탭·`CodeEditSourceEditor` 호스팅)는 chrome(파일트리 행, 탭, 빈 상태, 충돌 배너)에 §2의 `ClientPalette`를 그대로 쓴다 — 새 표면이라고 별도 색 체계를 만들지 않았다.

구문 강조만 예외다. `CodeEditorHostView.theme(for:)`가 `ClientPalette`에서 **5개 필드**
(`background`/`surface`(lineHighlight로)/`textPrimary`/`textSecondary`/`accent`)를 물려받는다 —
그중 `accent`는 insertionPoint·selection(25% 알파)·strings·characters 네 자리에 재사용되고,
`textSecondary`는 invisibles와 comments(이탤릭)에 재사용된다. 그 위에 코드 전용으로 고정된 3색
(키워드 보라·타입 청록·리터럴 녹색, 팔레트 무관 고정 hex)을 얹는다. 코드 색 팔레트는 UI 색 토큰
10개보다 훨씬 많은 구분이 필요해서 나온 의도적 예외이지, 누락이 아니다.

**미검증 항목**: 이 3색(보라/청록/녹색)은 `.dark`(어두운 배경) 기준으로 고른 값이라 `.light` 팔레트(흰 배경)에서도 대비가 충분한지 실제로 확인된 적이 없다 — 렌더링해서 눈으로 봐야 판단 가능한 사안이라 이번 정리에서는 건드리지 않았다.

## 10. 이 문서에 없는 것

- 펫 오버레이(F1)·텍스트 입력 버블(F6)은 `ClientTheme` 토큰을 쓰지 않는 별개 표면이다.
- ~~에디터 뷰(`EditorWebView`)는 아직 어디에도 호스팅되지 않는다~~ — **2026-08-14 해소**. `EditorWebView`(workspace가 서빙하는 웹 뷰) 자체는 삭제되고 네이티브 `Puck/ClientWindow/Editor/`로 대체됐다(위 9.5절, `docs/decisions.md` 참고). "에디터는 따로 할거라 토글 빼"는 그 사이 임시 상태를 설명하던 문장이라 더 이상 유효하지 않다.
- `onAccent`(§2)는 `ClientPalette`에 정의돼 있지만 이 필드를 읽는 뷰가 **아직 없다** — accent 위에 텍스트/아이콘을 얹는 자리가 지금 코드엔 없다. v1에서 `success`/`failure`/`warning`이 시스템 색 그대로였던 것과 비슷한 모양의, 정의는 됐지만 아직 안 쓰이는 필드.
