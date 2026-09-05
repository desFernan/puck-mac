# Puck for macOS

> Language: [English](README.md) · **한국어** (here)

> 이 저장소는 macOS용 Puck입니다 — 예전에 [Speaki-e/puck](https://github.com/Speaki-e/puck)
> (지금은 archived)에 있던 것의 새 집이에요.
>
> 플랫폼: **macOS** (여기) · [Windows](https://github.com/desFernan/puck-windows) · [Linux](https://github.com/desFernan/puck-linux)

### 💬 [디스코드 참여하기](https://discord.gg/nGqtBGP857)

버그 제보, 기능 요청, 빌드 관련 질문, 아니면 그냥 놀러 오고 싶어도 —
[서포트 서버](https://discord.gg/nGqtBGP857)가 가장 빠른 연락 방법입니다. 놀러 오세요!

AI 에이전트이기도 한 macOS 데스크톱 펫입니다. 두 개의 Swift 앱으로 구성돼 있어요:

- **Puck** — 펫 본체: 항상 위에 떠 있는 캐릭터가 화면을 걸어 다니고, 뭔가를 가리키고,
  음성을 듣고, Mac을 조작합니다 (`run_shell`, `run_applescript`, UI 요소 클릭/찾기,
  앱 실행).
- **PuckClient** — 펫의 창: 채팅, 워크스페이스, git 상태, 네이티브 SwiftUI 코드
  에디터, 터미널 패널.

둘은 로컬 소켓 브리지로 통신합니다. 에이전트 코어(채팅, 도구, 승인, 세션)는
`pet-app/Puck/Agent`에 있습니다.

![아일랜드 바닥에 서 있는 펫](.github/media/island.png)

이게 아일랜드입니다. 채팅 창 위쪽에 그림으로 채워진 패널이고, 창을 열면 펫이
걸어와서 여기로 올라옵니다. 창을 닫으면 다시 바탕화면으로 돌아갑니다.
`Tank/seabed.png`에 원하는 그림을 넣으면 그 그림으로 채워집니다.

## 설치

[Releases](https://github.com/desFernan/puck-mac/releases)에서
`Puck-<version>.dmg`를 받아 Puck을 응용 프로그램 폴더에 넣으세요. macOS 14
이상이 필요합니다. 채팅 창은 앱 안에 함께 들어 있어 같이 올라오므로, 따로 옮길
것은 없습니다.

Developer ID가 아닌 ad-hoc 서명이라 첫 실행은 "확인되지 않은 개발자"로 거부됩니다.
앱을 우클릭 → **열기** → **열기**를 한 번 해 주세요. 그다음 Puck이 손쉬운
사용(Accessibility) 권한을 요청하고, 마이크·음성 인식·화면 기록은 해당 기능을 쓸 때
요청합니다.

## 빌드

```sh
sh pet-app/scripts/install.sh   # 두 앱을 빌드 + 서명해서 /Applications에 설치
```

Xcode, `xcodegen`, Apple Development 인증서가 필요합니다 (무료 개인 팀이면
충분해요 — 안정적인 서명이 재빌드해도 손쉬운 접근성(Accessibility) 권한을
유지시켜 줍니다).

## 테스트

```sh
sh pet-app/scripts/test.sh   # PuckTests + PuckClient 빌드
```

무인 실행이며, 실패가 있으면 nonzero로 종료합니다. 이 머신에 없을 수 있는 것
(`node`, `claude`/`codex` CLI)이 필요한 테스트는 실패 대신 건너뜁니다.

## 에이전트 프로바이더

일반 채팅은 Anthropic 또는 OpenAI API와 직접 통신합니다. `code_editor` 도구는
대신 `node` 아래에서 벤더 ACP 에이전트를 실행하며, 이건 해당 벤더의 CLI
(`claude` 또는 `codex`)가 설치돼 있어야 합니다. 자격 증명은 Puck의 `.env`에
넣습니다: `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`, 또는 `CODEX_API_KEY` /
`OPENAI_API_KEY`.

## 내 것으로 만들기

바꿀 수 있는 모든 것은 폴더 하나에 있습니다:

```
~/Library/Application Support/Puck/
    Avatars/<name>/     캐릭터 하나당 폴더 하나
    Tank/seabed.png     섬을 채우는 그림
```

메뉴 바 아이콘을 우클릭하면 빠른 패널이 열립니다 — 장난감, 음소거와 볼륨,
펫 크기, 테마. 그 안의 **설정**이 설정 창을 엽니다: 아바타, 자세, 소리, 움직임,
그리고 나머지가 각각 한 페이지씩입니다. (같은 아이콘을 좌클릭하면 채팅 창이
열립니다.)

설정 창의 **아바타** 페이지에 위 폴더를 여는 버튼이 있고
(**커스터마이징 폴더 열기**), 아직 폴더가 없으면 만들어 주기도 합니다.

### 수조 (Tank)

`Tank/`에 `seabed.png`를 넣으면 앱이 기본으로 제공하는 것을 대체합니다. 앱
시작 시 한 번만 읽으므로, 바꾼 뒤엔 펫을 재시작하세요. 섬 높이에 맞춰
스케일되고 양옆은 잘리며, 창이 한 장보다 넓으면 끝에서 끝까지 반복됩니다 —
그래서 넓고 얕은 그림(번들된 것은 3596×447)이라면 대부분의 창에서 반복 없이
들어맞습니다.

### 캐릭터

아바타는 `manifest.json`과 클립별 PNG가 함께 들어 있는 폴더입니다:

```
Avatars/my-pet/
    manifest.json
    idle.png  walk.png  fall.png  …
    sounds/*.wav
```

#### 하나 추가하기, 처음부터 끝까지

1. **폴더 열기.** 설정 → 아바타 → **커스터마이징 폴더 열기**. `Avatars/`와
   `Tank/`가 없으면 만들어 주므로, 이 과정에서 폴더가 존재한다는 것도 알 수
   있습니다.
2. **캐릭터용 폴더 만들기** — `Avatars/` 안에요. 폴더 이름이 곧 선택 화면에
   뜨는 이름입니다: `Avatars/my-pet/`는 `my-pet`으로 표시됩니다.
3. **PNG 한 장과 `manifest.json` 넣기.** 그림 한 장이면 작동하는 캐릭터가
   됩니다 — `idle`만 필수 클립이고 나머지 모든 상태는 여기로 폴백되므로,
   그림 한 장으로 시작해서 걷기, 오르기 등을 원할 때 하나씩 추가하면 됩니다.
   배경은 투명하게, 오른쪽을 보도록 그리세요 (반대로 걸을 땐 펫이 좌우
   반전됩니다). 작동하는 가장 작은 manifest:

   ```json
   {
     "schema_version": 1,
     "name": "my-pet",
     "type": "sprites",
     "hitbox": { "width": 130, "height": 133 },
     "clips": { "idle": "idle" }
   }
   ```

   `hitbox`는 크기가 아니라 그림의 *비율*입니다: 아바타는 선언한 숫자와
   상관없이 모두 같은 높이로 그려지고, 이 둘의 비율만 읽습니다. 그림의 가로세로
   비율에 맞추지 않으면 찌그러져 보입니다. 실제로 얼마나 크게 서는지는 빠른
   패널의 크기 슬라이더가 정합니다.
4. **불러오기.** 설정 → 아바타 → **아바타 다시 불러오기**, 그다음 이름 옆
   **선택**을 누릅니다. 재시작 불필요: 다시 불러오기 버튼은 디스크에 있는
   내용으로 실행 중인 펫을 재구성하므로, 종료하지 않고도 다시 그린 스프라이트나
   수정한 manifest를 확인할 수 있습니다.

패키지에 문제가 있으면 펫은 바뀌지 않고 이유가 로그에 남습니다
(`~/Library/Application Support/Puck/logs/`) — 누락된 `idle` 파일, 파싱되지
않는 manifest, 이 빌드가 모르는 `schema_version` 등. 가져오기 버튼(**아바타
패키지 가져오기…**)은 위와 같은 폴더를 받아 복사해 주며, 그 전에 패키지를
검사하므로 뭐가 빠졌는지 더 크게 알려주는 방법입니다.

`manifest.json`, 중요한 필드들:

```json
{
  "schema_version": 1,
  "name": "my-pet",
  "type": "sprites",
  "scale": 1.0,
  "bounce_intensity": 0.6,
  "hitbox": { "width": 130, "height": 133 },
  "clips":    { "idle": "idle", "walk": "walk" },
  "emotions": { "happy": "beaming" },
  "sounds":   { "land": "sounds/waah.wav" }
}
```

- **`clips`**는 상태를 파일 *stem*에 매핑합니다: `"idle": "starry-eyed"`는
  `starry-eyed.png`를 그립니다. `idle`만 필수이고 나머지는 여기로
  폴백되므로, 그림 한 장이 작동하는 캐릭터가 됩니다. 나머지는 `walk`,
  `climb`, `fall`, `land`, `point`, `type`, `listen`, `react_click`,
  `react_drag`, `kick`, `pet`, `spin`입니다.
- **`emotions`**는 에이전트가 반응할 때 교체됩니다 (`happy`, `thinking`,
  `sad`, `angry`, `love`, `wink`, `laugh`, `cry`, …), 파일-stem 규칙은
  동일합니다.
- **`sounds`**는 패키지 안의 경로이며, 하위 폴더에 있어도 됩니다. 키는
  클립 이름 + 몇 가지 이벤트입니다: `app_launch`, `task_success`,
  `task_fail`, `listen_start`, `kick_<toy>`, `chatter_*`.
- **`hitbox`**는 캐릭터의 형태 — 가로와 세로의 비율입니다. 앱이 정한 표준
  높이로 그려진 다음, 펫이 클릭되고 서고 던져지는 기준이 됩니다.
  **`bounce_intensity`** (0–1)는 정지된 그림에서 squash-and-stretch가 얼마나
  보이는지입니다.
- **`type`**은 `sprites`여야 합니다. 이 빌드가 그릴 수 있는 유일한 종류이고,
  다른 값을 선언한 패키지는 불러온 뒤 아무것도 그리지 않는 대신 이유와 함께
  거부됩니다.
- `schema_version`, `name`, `type`, `hitbox`, `clips`만 필수입니다. `scale`은
  기본값 1, `sounds`와 `emotions`는 기본값 없음, `bounce_intensity`는 앱
  자체 기본값을 씁니다.
- manifest 안의 경로는 패키지 내부로 제한됩니다: 패키지 밖으로 나가는
  이름은 읽지 않고 거부됩니다.

손으로 manifest를 고치기 전에 알아 두면 좋은 것이 두 가지 있습니다. **아바타**
페이지에는 기본 이미지 칸이 있어서, 고른 그림 한 장으로 `idle`을 설정합니다 —
나머지 클립은 모두 `idle`로 폴백되므로 그것만으로 완전한 캐릭터가 됩니다.
**자세 미리보기** 페이지는 펫이 걷고, 양쪽 벽을 오르고, 천장을 양방향으로
지날 때 어떻게 보이는지를 그려 주고, 자세마다 좌우·상하 반전과 90도 회전을
제공합니다 — 거꾸로 기어오르는 그림을 다시 그리지 않고 고치는 방법입니다.

`pet-app/Puck/Resources/Avatars/dummy`가 완전한 예시이고, 가져오기 버튼은 위와
같은 폴더를 받아 복사해 줍니다.

## 커뮤니티

질문, 버그 제보, 기능 아이디어, 아니면 만든 커스텀 아바타 자랑하고 싶을 때 —
**[디스코드](https://discord.gg/nGqtBGP857)**로 오세요.

직접 고쳐보고 싶다면 [CONTRIBUTING.md](CONTRIBUTING.md)에 빌드 방법, 쉬운
이슈가 어디 있는지, 어떤 PR이 좋은지 적어두었습니다.

## 라이선스

소스는 MIT입니다 — [LICENSE](LICENSE). 옆에 있는 **그림·아이콘·폰트·오디오는
아닙니다**: 이유는 [LICENSE-ASSETS.md](LICENSE-ASSETS.md)에 적어두었습니다.
