# Scenario-Based Recording — Design Spec

## Overview

Screenize의 새로운 핵심 기능으로, 화면 녹화의 시나리오 작성과 실행을 분리하는 "시나리오 기반 녹화" 시스템을 도입한다.

**핵심 가치**: 인디 해커가 데모 영상을 만들 때, 시나리오를 머릿속에 기억하며 녹화할 필요 없이 — 한 번 리허설하고, 시나리오를 편집한 뒤, 자동 재생으로 완벽한 녹화를 얻는다.

**기존 기능과의 관계**: 기존 Direct Recording은 그대로 유지. 시나리오 녹화는 "녹화 방식의 선택지"로 추가되며, 재생+녹화 후에는 기존 편집 파이프라인(줌/커서/키스트로크/추출)에 합류한다.

## User Scenarios

시나리오 시스템은 인디 해커가 겪는 4가지 상황을 해결한다:

| 상황 | 시나리오의 역할 | 필요 기능 |
|------|----------------|----------|
| A: 실수로 여러 번 재녹화 | 시나리오 수정 후 자동 재생으로 재촬영 | Replay (Phase 2) |
| B: 편집이 오래 걸림 | 시나리오 스텝이 편집 마커 + Smart Generation 줌 힌트 | Phase 1 |
| C: 제품 업데이트 후 재촬영 | 이전 시나리오 수정 후 재생 | Replay (Phase 2) |
| D: 의도적 마우스 제스처 | 리허설 영상 그대로 사용, 시나리오는 편집 마커 | Phase 1 |

**두 가지 사용자 플로우**:

### 플로우 1: "리허설 → 그대로 사용" (상황 B, D)

```
리허설 녹화 (영상 + 시나리오 동시 기록)
    │
    ▼
VideoEditor (ScenarioTrack 포함)
  - 영상 프리뷰 + Smart Generation (시나리오 힌트 활용)
  - 시나리오 마커를 보며 빠르게 편집
    │
    ▼
추출
```

리허설 영상이 곧 최종 영상. 시나리오는 편집을 가속하는 도구.

### 플로우 2: "리허설 → 시나리오 수정 → 재생" (상황 A, C)

```
리허설 녹화 (영상 + 시나리오 동시 기록)
    │
    ▼
VideoEditor에서 영상 확인 + 시나리오 스텝 편집
    │
    ▼
[▶ Replay & Record] → 수정된 시나리오로 자동 재생 + 새 녹화
    │
    ▼
새 영상으로 VideoEditor (시나리오 마커 포함) → 편집 → 추출
```

## UX Flow

### Stage 1: 녹화 모드 선택

CaptureToolbar의 Record 버튼에 드롭다운 추가:

```
┌─ CaptureToolbar ───────────────────────────────────────────┐
│                                                             │
│  [Screen ▼]  [Display 1 ▼]    [ ⏺ Record           ▼ ]   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                                          │
                                ┌─────────┴─────────┐
                                │ ⏺ Direct Record    │
                                │ 📋 Rehearsal       │
                                └────────────────────┘
```

- **Direct Record** (기본값): 기존과 동일.
- **Rehearsal**: 선택 시 버튼이 `[ 📋 Rehearse ▼ ]`로 변경 (보라/파랑 아이콘).
- 모드 선택은 `@AppStorage`로 기억된다 — 다음 실행 시에도 마지막 선택 유지.

### Stage 2: 리허설 진행 중

리허설 = 기존 녹화 + AX 이벤트 기반 시나리오 기록. **영상도 함께 녹화된다.**

```
┌─ CaptureToolbar (Rehearsal) ──────────────────────────────────┐
│                                                                │
│  📋 Rehearsing  ◉ 00:32       [ ⏸ Pause ]  [ ■ Stop ]       │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

- "Rehearsing" 텍스트 + 녹색 점 펄스 — 기록 중임을 표시
- Direct Recording과 시각적으로 구분 (Recording: 빨강, Rehearsal: 보라/파랑)
- **Pause**: 녹화 + 이벤트 기록 모두 일시정지. 정지 구간은 시나리오에 반영 안 됨.
- **Stop**: 녹화 종료 + 시나리오 자동 생성 (1~3초 스피너) + VideoEditor로 전환
- 메뉴바 아이콘도 리허설 상태로 변경
- 클릭 시 팝업/하이라이트 등 방해 요소 없음

### Stage 3: VideoEditor + ScenarioTrack

Stop 후 기존 VideoEditor가 열린다. **ScenarioTrack이 타임라인에 추가된 상태로.**

```
┌─ VideoEditor ───────────────────────────────────────────────────┐
│                                                                  │
│  ┌─ Preview ──────────────────────────────────────────────┐     │
│  │                                                         │     │
│  │         (영상 프리뷰 + Smart Generation 적용)           │     │
│  │                                                         │     │
│  └─────────────────────────────────────────────────────────┘     │
│                                                                  │
│  ┌─ Timeline ─────────────────────────────────────────────┐     │
│  │  ▶ 0:00          0:15          0:30          0:45      │     │
│  │                                                         │     │
│  │  Scenario ┃→┃App┃→┃Click┃→┃Scroll┃→┃Drag ┃→┃Type┃    │ ← 신규
│  │           (→ = mouse_move auto, 작은 화살표 블록)       │
│  │  Camera   ┃▓▓▓▓▓▓▓▓┃      ┃▓▓▓▓┃                     │     │
│  │  Cursor   ┃████████████████████████████████┃           │     │
│  │  Keys     ┃   ┃cmd+c┃         ┃cmd+v┃                 │     │
│  │  Audio    ┃████████████████████████████████┃           │     │
│  └─────────────────────────────────────────────────────────┘     │
│                                                                  │
│  ┌─ Scenario Inspector (스텝 선택 시) ────────────────────┐     │
│  │  Type: [click ▼]    Description: [Foo.swift 클릭]      │     │
│  │  Target: AXStaticText "Foo.swift"                       │     │
│  │  Duration: [300] ms                                     │     │
│  └─────────────────────────────────────────────────────────┘     │
│                                                                  │
│  ┌─ Bottom Bar ───────────────────────────────────────────┐     │
│  │          [🔄 Re-rehearse from here]  [▶ Replay & Record]│     │
│  │          (Phase 2 buttons — disabled in Phase 1)        │     │
│  └─────────────────────────────────────────────────────────┘     │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**ScenarioTrack 특징:**
- 타임라인 최상단에 위치 — 편집 마커 역할이므로 가장 먼저 눈에 들어와야 함
- 각 스텝이 시간축 위에 블록으로 표시 (아이콘 + 짧은 라벨)
- 스텝 클릭 → 해당 시점으로 프리뷰 이동 + Scenario Inspector 표시
- drag group은 연결된 블록으로 시각적 묶음
- **영상 시간에 비의존**: 다른 트랙(Camera, Cursor, Keys, Audio)의 세그먼트는 영상의 start/end에 clamp되지만, ScenarioTrack은 영상 시간과 독립적이다. 시나리오는 "대본"이므로 영상보다 길거나 짧을 수 있다. Re-rehearse 시 시나리오는 유지한 채 영상만 새로 생성되므로 이 독립성이 필수적이다.

**ScenarioTrack 아이콘:**

| type | 아이콘 | 색상 |
|------|--------|------|
| `activate_app` | ● | 초록 |
| `click` | ◎ | 파랑 |
| `double_click` | ◎◎ | 파랑 |
| `right_click` | ◎ | 주황 |
| `mouse_move` | → | 회색 (연결선 스타일, 얇은 블록) |
| `mouse_down`/`up` | ↓↑ | 회색 |
| `scroll` | ↕ | 보라 |
| `keyboard` | ⌨ | 노랑 |
| `type_text` | Aa | 노랑 |
| `wait` | ⏳ | 회색 |

**Smart Generation 힌트**: ScenarioTrack의 click/keyboard 스텝 위치를 CameraTrack의 Continuous Camera Generator에 전달. 커서 휴리스틱만으로 추측하던 줌 포인트를 시나리오 데이터로 보강.

**Scenario Inspector (스텝 선택 시):**

기존 Inspector 영역에 Scenario Inspector가 표시된다. 스텝 type별 편집 필드:

`mouse_move` (경로 편집의 핵심):
```
Type: [mouse_move ▼]
Description: [Foo.swift로 이동]
─ Path ───────────
  ● Auto  ○ Waypoints [Edit]
  [Generate from recording]  Hz: [5 ▼]
─ Timing ─────────
  Duration: [350] ms
```
- **Auto**: 베지어 자동 생성
- **Waypoints**: [Edit] 클릭 시 프리뷰에서 점 찍어 웨이포인트 추가/이동/삭제. Catmull-Rom 스플라인 미리보기 실시간 표시.
- **Generate from recording**: 리허설 시 기록된 실제 마우스 경로에서 웨이포인트를 자동 생성. path를 waypoints로 전환하고 points를 채움.
  - **Hz 설정**: 초당 몇 개의 웨이포인트를 추출할지 (1~30Hz, 기본 5Hz). 낮을수록 부드럽고 단순한 경로, 높을수록 원본에 가까운 정밀한 경로.
  - 생성 후 개별 웨이포인트를 수동으로 이동/삭제하여 미세 조정 가능.

`click` / `double_click` / `right_click`:
```
Type: [click ▼]
Description: [Foo.swift 클릭]
─ Target ─────────
  Role: AXStaticText
  Title: [Foo.swift]
  Path: AXWindow > AXSplitGroup > AXOutline
  Position: (0.18, 0.04) [Edit]
─ Timing ─────────
  Duration: [300] ms
```

`keyboard`:
```
Type: [keyboard ▼]
Description: [코드 복사]
─ Keys ───────────
  Combo: [cmd+c]
─ Timing ─────────
  Duration: [200] ms
```

`type_text`:
```
Type: [type_text ▼]
Description: [검색어 입력]
─ Text ───────────
  Content: [Hello World]
  Typing speed: [50] ms/char
─ Timing ─────────
  Duration: [auto] ms
```

`scroll`:
```
Type: [scroll ▼]
Description: [에디터 스크롤]
─ Scroll ─────────
  Direction: [down ▼]
  Amount: [400] px
─ Target ─────────
  (AX target 정보)
─ Timing ─────────
  Duration: [1200] ms
```

**스텝 편집 작업:**

| 작업 | 방식 |
|------|------|
| 순서 변경 | 타임라인에서 블록 드래그 |
| 삭제 | 선택 후 Delete 키 |
| 스텝 추가 | 타임라인 우클릭 → "Add Step" / 또는 Bottom Bar |
| 타이밍 수정 | Inspector에서 durationMs 입력 또는 타임라인에서 블록 리사이즈 |
| 타겟 수정 | Inspector에서 편집 |
| 스텝 복제 | Cmd+D |
| Undo/Redo | Cmd+Z / Shift+Cmd+Z |

**파일 직접 편집 (Phase 2 이후 고려):**
- ~~Bottom Bar의 "Open in Editor" → 기본 텍스트 에디터에서 scenario.json~~
- ~~FSEvents로 변경 감지 → 자동 리로드~~
- ~~"Export JSON" / "Import JSON" → 시나리오 파일 내보내기/불러오기~~

### Stage 4: 재생 + 녹화 (Phase 2)

VideoEditor의 Bottom Bar에서 `[▶ Replay & Record]` 클릭 시:

```
[▶ Replay & Record] 클릭
    │
    ▼
확인 다이얼로그
  "시나리오를 자동 실행하며 새 영상을 녹화합니다.
   실행 중 ESC를 누르면 즉시 중단됩니다."
  [Cancel]  [Start]
    │
    ▼ Start
모든 Screenize 창 최소화 (녹화에 방해 안 되게)
    │
    ▼
┌─ Replay HUD (화면 상단, 작은 플로팅 바) ──────────────┐
│  ▶ Replaying  Step 3/7  "에디터 스크롤"   [■ Stop]    │
└────────────────────────────────────────────────────────┘
    │
    ▼
시나리오 스텝 자동 실행 (CGEvent 주입 + 화면 녹화)
    │
    ▼
완료 (또는 ESC로 중단)
    │
    ▼
새 영상으로 VideoEditor 열림 (ScenarioTrack 포함)
```

**Replay HUD:**
- 화면 상단 중앙, 반투명 작은 바
- 현재 스텝 번호 + description 표시
- Stop 버튼으로 즉시 중단
- 녹화 영역 밖에 위치 (ScreenCaptureKit excludeWindows로 제외)

**에러 발생 시:**

```
┌─ Replay HUD (에러) ──────────────────────────────────────┐
│  ⚠ Step 3 실패: "Foo.swift" 요소를 찾을 수 없음          │
│  [Skip]  [Do Manually]  [Stop]                            │
└───────────────────────────────────────────────────────────┘
```

- **Skip**: 현재 스텝 건너뛰고 다음 진행
- **Do Manually**: 일시정지, 사용자가 직접 수행 후 Continue
- **Stop**: 중단, 여기까지의 녹화 저장

### Stage 4-1: Re-rehearse from Step N (Phase 2)

VideoEditor에서 특정 스텝을 선택한 뒤 `[🔄 Re-rehearse from here]` 클릭 시:

```
VideoEditor에서 Step N 선택 + [🔄 Re-rehearse from here] 클릭
    │
    ▼
확인 다이얼로그
  "Step N부터 다시 리허설합니다.
   Step 1~(N-1)은 자동 재생되며, Step N부터 직접 조작합니다."
  [Cancel]  [Start]
    │
    ▼ Start
모든 Screenize 창 최소화
    │
    ▼
녹화 시작 + Step 1~(N-1) Replay 엔진으로 자동 실행
┌─ Replay HUD ────────────────────────────────────────────┐
│  ▶ Replaying  Step 2/6  "Foo.swift 클릭"   [■ Stop]     │
└──────────────────────────────────────────────────────────┘
    │
    ▼
Step N 도달 — Replay → Rehearsal 모드 자동 전환
┌─ Rehearsal HUD ─────────────────────────────────────────┐
│  📋 Your turn — Rehearsing   ◉ 01:23        [■ Stop]    │
└──────────────────────────────────────────────────────────┘
(사운드 + 시각 알림으로 전환 시점을 명확히 전달)
    │
    ▼
사용자가 직접 조작하며 리허설 진행
    │
    ▼
Stop
    │
    ▼
하나의 연속된 영상 (Replay 구간 + Rehearsal 구간 모두 포함)
시나리오: Step 1~(N-1) 기존 유지 + Step N~ 새 리허설에서 생성
    │
    ▼
VideoEditor (새 영상 + 병합된 시나리오)
```

**핵심 설계:**
- 녹화는 Step 1 시작 시점부터 켜져있으므로 **영상은 하나의 연속 파일** — 이어붙이기 불필요
- Replay 구간도 녹화되므로 최종 영상에 자연스럽게 포함
- 시나리오 병합: Step 1~(N-1)은 기존 시나리오 그대로 복사, Step N 이후는 새 리허설의 raw event에서 생성
- scenario-raw.json도 새로 생성 (Replay 구간의 이벤트 + Rehearsal 구간의 이벤트)

**Replay 구간 에러 처리:**
- Step 1~(N-1) 자동 재생 중 에러 발생 시, Stage 4와 동일한 에러 HUD 표시 (Skip / Do Manually / Stop)
- Do Manually 선택 시 해당 스텝만 수동 수행 후 Continue → 나머지 Replay 계속 → Step N에서 Rehearsal 전환

**Re-rehearse 버튼 활성 조건:**
- ScenarioTrack에서 스텝이 선택되어 있을 때만 활성화
- Step 1 선택 시 = 전체 Re-rehearse (기존 Replay & Record와 동일하되 이후 Rehearsal로 전환)

### Stage 5: 편집 + 추출

재생 완료 후 기존 VideoEditor 플로우와 동일. ScenarioTrack이 마커로 남아있어 편집 시점 파악에 도움.

기존 편집 기능(Camera, Cursor, Keystroke, Audio) + 추출(MP4/GIF) 모두 그대로.

## Phased Delivery

| Phase | 범위 | UX Stages |
|-------|------|-----------|
| Phase 1 | 리허설 녹화 + 시나리오 생성 + 타임라인 통합 + 편집 | Stage 1, 2, 3, 5 |
| Phase 2 | 재생 엔진 + Replay HUD + Re-rehearse | Stage 4, 4-1 |

Phase 1만으로 상황 B, D를 해결. Phase 2 추가 시 상황 A, C까지 해결.

### Phase 1 Scope Details

**포함:**
- 리허설 녹화 (영상 + AX 이벤트 기반 시나리오 기록)
- Raw event → semantic step 변환 (ScenarioGenerator)
- ScenarioTrack 타임라인 UI 표시
- Scenario Inspector 편집 (type/target/duration/path 등)
- 타임라인 블록 드래그/리사이즈, Add Step, 삭제, 복제, Undo/Redo
- Generate from recording (raw mouse path → waypoints, Hz 설정)
- 모드 선택 persistence (`@AppStorage`)
- AX Parent Path 기록 (scenario.json의 target.path에 저장, Inspector에 읽기 전용 표시)
- 기존 1Hz UI state 샘플링은 리허설 모드에서도 그대로 유지

**제외 (Phase 1에서):**
- Smart Generation 힌트 연동 (시나리오 → CameraTrack 줌 보강)
- Export/Import JSON, Open in Editor
- Replay & Record (Phase 2)
- Re-rehearse from here (Phase 2)

### Phase 1 Architecture Decisions

**Scenario 모델 분리**: `Scenario`는 `Timeline`과 독립된 모델이다. `ScreenizeProject` 레벨에서 optional 프로퍼티로 관리한다. ScenarioTrack UI는 타임라인 뷰와 동일한 시간축을 공유하며 최상단에 렌더링되지만, 모델 레벨에서는 Timeline 밖에 존재한다. 이를 통해 시나리오의 영상 시간 비의존성을 자연스럽게 구현한다.

```
ScreenizeProject
├── timeline: Timeline          (기존)
├── scenario: Scenario?         (신규, optional)
└── mediaAsset: MediaAsset      (기존)
```

`EditorViewModel`이 `Scenario`를 Timeline과 함께 관리하며, playhead 위치와 스텝 시간 동기화를 담당한다.

## Coordinate System

시나리오 파일에서는 **CG 좌표계 (top-left origin)**를 사용한다. 이는 CGEvent API와 AXUIElementCopyElementAtPosition 모두 CG 좌표계를 사용하기 때문이다.

| 필드 | 좌표계 | 설명 |
|------|--------|------|
| `absoluteCoord` | CG pixels, top-left origin | 리허설 시 기록된 절대 좌표 |
| `positionHint` | 0~1 normalized, top-left origin | 캡처 영역 대비 상대 좌표 |
| `mouse_move.path.points` | 0~1 normalized, top-left origin | 커서 경로 웨이포인트 |
| Raw event `x`, `y` | CG absolute screen pixels, top-left origin | scenario-raw.json의 모든 좌표 |

**코드베이스와의 좌표 변환**: 기존 Screenize 코드베이스는 내부적으로 `NormalizedPoint` (0-1, bottom-left origin)를 사용한다. 시나리오 파일의 top-left origin 좌표와는 Y축이 반전된다. 변환 경계:

- **Recording 시**: CGEvent/AX 좌표 (CG top-left) → 그대로 scenario-raw.json에 기록
- **ScenarioGenerator**: raw CG 좌표 → `positionHint` 계산 시 `y = (absY - captureArea.y) / captureArea.height` (top-left 유지)
- **Timeline UI 렌더링**: `positionHint` (top-left) → `NormalizedPoint` (bottom-left) 변환 시 `y = 1.0 - positionHint.y`
- **Phase 2 Replay**: scenario 좌표는 이미 CG 좌표계이므로 CGEvent 주입 시 변환 불필요

`CoordinateConverter`에 `cgNormalizedToNormalized()` / `normalizedToCGNormalized()` 헬퍼를 추가하여 Y-flip 변환을 명시적으로 처리한다.

## Data Model

### Scenario File

시나리오는 순서가 있는 Step 배열이다. `.screenize` 패키지 내 `scenario.json`으로 저장한다. `project.json`에는 포함되지 않는다 — 독립 파일로 존재하며 기존 프로젝트 포맷에 영향 없음. `ScreenizeProject`의 `scenario` 프로퍼티는 runtime-only이며 `CodingKeys`에서 제외한다. `PackageManager`가 패키지 로드 시 `scenario.json` 존재 여부를 확인하고 별도로 디코딩하여 `ScreenizeProject.scenario`에 할당한다. 저장 시에도 `PackageManager`가 `scenario.json`을 독립적으로 인코딩하여 기록한다.

```
MyProject.screenize/
├── project.json          (기존 — 변경 없음)
├── recording/
│   ├── video.mp4         (기존)
│   └── video.mouse.json  (기존)
├── scenario.json         (신규 — 편집된 시나리오)
└── scenario-raw.json     (신규 — 원시 이벤트, Generate from recording용)
```

### Scenario Schema

```json
{
  "version": 1,
  "appContext": "com.apple.dt.Xcode",
  "steps": [
    {
      "id": "step-1",
      "type": "mouse_move",
      "description": "Xcode로 이동",
      "durationMs": 200,
      "path": "auto"
    },
    {
      "id": "step-2",
      "type": "activate_app",
      "app": "com.apple.dt.Xcode",
      "description": "Xcode 활성화",
      "durationMs": 500
    },
    {
      "id": "step-3",
      "type": "mouse_move",
      "description": "Foo.swift로 이동",
      "durationMs": 350,
      "path": "auto",
      "rawTimeRange": { "startMs": 500, "endMs": 850 }
    },
    {
      "id": "step-4",
      "type": "click",
      "target": {
        "role": "AXStaticText",
        "axTitle": "Foo.swift",
        "axValue": null,
        "path": ["AXWindow", "AXSplitGroup", "AXOutline"],
        "positionHint": { "x": 0.18, "y": 0.04 },
        "absoluteCoord": { "x": 340, "y": 52 }
      },
      "description": "Foo.swift 파일 클릭",
      "durationMs": 300
    },
    {
      "id": "step-5",
      "type": "mouse_move",
      "description": "에디터 영역으로 이동",
      "durationMs": 400,
      "rawTimeRange": { "startMs": 1150, "endMs": 1550 },
      "path": {
        "type": "waypoints",
        "points": [
          { "x": 0.3, "y": 0.3 },
          { "x": 0.4, "y": 0.45 }
        ]
      }
    },
    {
      "id": "step-6",
      "type": "type_text",
      "content": "Hello World",
      "typingSpeedMs": 50,
      "description": "텍스트 입력",
      "durationMs": 550
    },
    {
      "id": "step-7",
      "type": "scroll",
      "target": {
        "role": "AXTextArea",
        "axTitle": null,
        "axValue": null,
        "path": ["AXWindow", "AXSplitGroup", "AXScrollArea"],
        "positionHint": { "x": 0.5, "y": 0.5 },
        "absoluteCoord": { "x": 600, "y": 400 }
      },
      "direction": "down",
      "amount": 400,
      "description": "에디터 아래로 스크롤",
      "durationMs": 1200
    }
  ]
}
```

**`mouse_move` step의 `path` 필드:**
- `"auto"` — 이전 스텝 위치에서 다음 스텝 타겟까지 Cubic Bezier 자동 생성
- `{ "type": "waypoints", "points": [...] }` — 지정된 웨이포인트를 통과하는 Catmull-Rom 스플라인

시나리오 생성 시 모든 액션 스텝 사이에 `path: "auto"`인 `mouse_move` 스텝이 자동 삽입된다. 사용자는 이를 waypoints로 변경하거나, 삭제(즉시 이동)하거나, 추가(액션 없이 커서만 이동)할 수 있다.

`appContext`: 시나리오의 주요 대상 앱. 정보 표시 목적이며 재생 동작에 영향을 주지 않는다. Phase 2에서 타겟 앱 자동 활성화 등에 활용 가능.

**Step ID**: 스텝 `id`는 UUID 문자열을 사용한다 (예: `"550e8400-e29b-41d4-a716-446655440000"`). 스키마 예시의 `"step-1"` 등은 가독성을 위한 약식 표기. 순서 변경/복제 시 ID 충돌을 방지하기 위해 UUID가 필수적이다.

### AX Target 필드 명명

혼동을 피하기 위해 AX 속성 필드와 스텝 설명 필드를 구분한다:
- `description`: 스텝의 사람이 읽을 수 있는 설명 (예: "Foo.swift 파일 클릭")
- `target.axTitle`: AXTitle 속성 (많은 UI 요소가 가짐)
- `target.axValue`: AXValue 속성 (텍스트 필드 등의 값)

리허설 시 AXTitle, AXValue, AXDescription을 모두 캡처한다. Target resolution 시 axTitle → axValue → AXDescription 순으로 매칭을 시도한다.

### Step Types

**Action Steps** (액션 — 무엇을 했는가):

| type | 설명 | target 방식 |
|------|------|------------|
| `activate_app` | 앱 활성화 (포그라운드로) | bundle ID |
| `click` | UI 요소 클릭 | AX target |
| `double_click` | 더블클릭 | AX target |
| `right_click` | 우클릭 | AX target |
| `mouse_down` | 마우스 누름 (드래그 시작 등) | AX target 또는 좌표 |
| `mouse_up` | 마우스 뗌 | AX target 또는 좌표 |
| `scroll` | 스크롤 | AX target + direction (`up`/`down`/`left`/`right`) + amount (pixels) |
| `keyboard` | 키 조합 (cmd+c 등) | key combo 문자열 |
| `type_text` | 텍스트 타이핑 | 문자열 + `typingSpeedMs` (ms/char). Shift로 인한 대문자는 문자열에 포함. `durationMs`는 `content.length * typingSpeedMs`로 자동 계산 |
| `wait` | 대기 | duration만. 자동 생성되지 않음 — 사용자가 수동으로 추가하는 용도 |

**Movement Step** (이동 — 어떻게 이동했는가):

| type | 설명 | path 방식 |
|------|------|----------|
| `mouse_move` | 커서 이동 | `"auto"` (Cubic Bezier) 또는 `{ "type": "waypoints", "points": [...] }` (Catmull-Rom) |

시나리오 생성 시 모든 액션 스텝 사이에 `path: "auto"`인 `mouse_move`가 자동 삽입된다. 사용자는:
- `path`를 `waypoints`로 변경 → 프리뷰에서 점 찍어 경로 커스터마이즈
- `mouse_move` 삭제 → 즉시 이동 (경로 없음)
- `mouse_move` 추가 삽입 → 액션 없이 커서만 이동하는 구간

**드래그 그룹화**: 연속된 `mouse_down` → `mouse_move`(들) → `mouse_up` 스텝은 **implicit drag group**을 형성한다. 재생 엔진은 이 그룹 내 스텝 간에 추가 대기를 삽입하지 않고 연속적으로 실행한다. 에디터에서도 그룹을 시각적으로 묶어 표시한다.

### Target Resolution (Fallback Chain)

AX 요소를 찾을 때 단일 방법이 아닌 fallback chain을 사용한다:

1. **AX path + axTitle** (가장 정확)
2. **axTitle only** (path 변경 시)
3. **role + positionHint** (타이틀 없을 때)
4. **absoluteCoord** (최후 수단)

리허설 시 4가지를 모두 기록해두고, 재생 시 위에서부터 순서대로 시도한다.

## Phase 1: Rehearsal Recording + Scenario Generation + Timeline Integration

### Rehearsal Recording

리허설 = 기존 녹화 + AX 이벤트 기반 시나리오 기록. **영상도 함께 녹화된다.**

| | Direct Recording (기존) | Rehearsal Recording (신규) |
|--|------------------------|---------------------------|
| 화면 녹화 | O | O |
| 마우스 이벤트 기록 | O | O |
| 키보드 이벤트 기록 | O | O |
| AX 샘플링 | 1Hz (주기적) | 1Hz (기존 유지) + 이벤트 기반 (매 인터랙션마다) |
| 시나리오 생성 | X | O |
| 출력물 | video.mp4 + mouse.json | video.mp4 + mouse.json + scenario.json |

**이벤트 기반 AX 샘플링 성능 전략**: AXUIElementCopyElementAtPosition은 동기 Mach IPC이므로:
- AX 쿼리는 전용 background DispatchQueue에서 실행
- 인터랙션 이벤트는 즉시 기록하고, AX 정보는 비동기로 첨부
- AX 쿼리 타임아웃: 500ms. 초과 시 좌표만 기록
- 빠른 연속 클릭 시 debounce: 50ms 이내 중복 AX 쿼리 스킵

### AX Parent Path Traversal (신규 구현 필요)

기존 `AccessibilityInspector`는 부모 체인에서 applicationName만 추출한다. 시나리오 시스템은 중간 요소의 role을 path로 기록해야 한다.

구현 방침:
- `AXUIElementCopyAttributeValue(.parent)`를 반복하여 AXWindow까지 순회
- 각 단계에서 role만 기록
- 최대 depth: 15
- 동일 부모 아래 같은 role이 여러 개일 경우: 0-based index 추가 (예: `"AXButton[2]"`)
- background queue에서 실행, 500ms 타임아웃 적용

### Raw Event Schema (scenario-raw.json)

리허설 녹화의 중간 산출물. ScenarioGenerator의 입력이 된다. 최종 사용자에게는 노출되지 않음.

```json
{
  "version": 1,
  "startTimestamp": "2026-03-16T10:30:00Z",
  "captureArea": { "x": 0, "y": 0, "width": 1920, "height": 1080 },
  "events": [
    {
      "timeMs": 0,
      "type": "mouse_move",
      "x": 312,
      "y": 45
    },
    {
      "timeMs": 200,
      "type": "mouse_down",
      "button": "left",
      "x": 340,
      "y": 52,
      "ax": {
        "role": "AXStaticText",
        "axTitle": "Foo.swift",
        "axValue": null,
        "axDescription": null,
        "path": ["AXWindow", "AXSplitGroup", "AXOutline"],
        "frame": { "x": 320, "y": 40, "width": 80, "height": 18 }
      }
    },
    {
      "timeMs": 210,
      "type": "mouse_up",
      "button": "left",
      "x": 340,
      "y": 52
    },
    {
      "timeMs": 500,
      "type": "scroll",
      "deltaX": 0,
      "deltaY": -3,
      "x": 600,
      "y": 400,
      "ax": {
        "role": "AXTextArea",
        "axTitle": null,
        "axValue": null,
        "axDescription": null,
        "path": ["AXWindow", "AXSplitGroup", "AXScrollArea"],
        "frame": { "x": 200, "y": 100, "width": 800, "height": 600 }
      }
    },
    {
      "timeMs": 1800,
      "type": "key_down",
      "keyCode": 55,
      "characters": "",
      "modifiers": ["cmd"]
    },
    {
      "timeMs": 1820,
      "type": "key_down",
      "keyCode": 8,
      "characters": "c",
      "modifiers": ["cmd"]
    },
    {
      "timeMs": 2500,
      "type": "app_activated",
      "bundleId": "com.apple.Safari",
      "appName": "Safari"
    }
  ]
}
```

이벤트 타입: `mouse_move`, `mouse_down`, `mouse_up`, `scroll`, `key_down`, `key_up`, `app_activated`. AX 정보는 `mouse_down` 이벤트에만 첨부된다 (비동기, 없을 수 있음). `key_up`은 modifier 키 해제 타이밍 추적에 사용된다 (변환 시 modifier 상태 머신 유지용). `scroll` 이벤트에도 AX 정보를 첨부한다 — 스크롤 타겟 해상도에 필요.

**scenario-raw.json 보존**: 시나리오 생성 후에도 `scenario-raw.json`을 `.screenize` 패키지에 보존한다. "Generate from recording" 기능이 원시 mouse_move 이벤트 데이터를 참조하기 때문이다. 각 `mouse_move` 스텝은 `rawTimeRange` 필드 (`{ "startMs": N, "endMs": N }`)로 원시 이벤트의 시간 범위를 기록하며, 이를 통해 해당 구간의 원시 마우스 경로를 추출하여 지정된 Hz로 샘플링한다.

### Raw Event → Semantic Step Conversion

리허설 종료 후 원시 이벤트 로그를 의미적 Step 배열로 자동 변환한다.

**변환 규칙:**

| 원시 패턴 | 변환 결과 |
|-----------|----------|
| mouseDown(left) → mouseUp(left), 같은 위치 (< 5px) | `click` |
| mouseDown(left) → mouseUp(left) 2회, 400ms 이내 | `double_click` |
| mouseDown(right) → mouseUp(right), 같은 위치 (< 5px) | `right_click` |
| mouseDown → mouseMove(들) → mouseUp, 이동 거리 > 5px | `mouse_down` + `mouse_move`(들) + `mouse_up` (implicit drag group) |
| scrollWheel 연속 (100ms 이내 간격) | 하나의 `scroll`로 병합, deltaY 합산. Raw delta는 CGEvent의 `scrollingDeltaFixedPt` (fixed-point pixels). 합산 결과가 semantic step의 `amount` (pixels)가 됨 |
| modifier + key | `keyboard` (combo로 표현, 예: `"cmd+c"`) |
| 연속 key_down (modifier 없음, Shift 제외) | `type_text` (문자열로 병합, Shift로 인한 대문자 포함) |
| app_activated | `activate_app` |
| 200ms 이상 무동작 | 스텝 간 `durationMs`에 반영 |

**mouse_move 자동 삽입**: 변환 완료 후, 모든 액션 스텝 사이에 `path: "auto"`인 `mouse_move` 스텝을 자동 삽입한다. `durationMs`는 이전 액션과 다음 액션 사이의 마우스 이동 시간에서 산출한다.

각 변환된 스텝에는 원시 이벤트의 `timeMs`를 기반으로 타임라인 위치가 할당된다. 이를 통해 ScenarioTrack의 블록이 영상 타임라인과 정확히 동기화된다.

## Phase 2: Replay Engine + Re-rehearse

### Phase 2 Scope

**포함:**
- ScenarioPlayer — 시나리오 자동 재생 엔진
- StepExecutor (AXTargetResolver, EventInjector, PathGenerator, TimingController)
- StateValidator — 실행 전/후 상태 검증
- RecordingBridge — 기존 녹화 파이프라인 연결
- Replay HUD — 진행 상황 표시 + 에러 처리 UI
- Re-rehearse from Step N — 부분 재생 후 리허설 전환
- Bottom Bar 버튼 활성화 (Replay & Record, Re-rehearse from here)

### Architecture

```
ScenarioPlayer (@MainActor, ObservableObject)
├── state: PlaybackState (idle/playing/paused/error/completed)
├── currentStepIndex: Int
├── currentStep: ScenarioStep?
├── mode: PlaybackMode (.replayAll / .replayUntilStep(N))
│
├── StepExecutor
│   ├── AXTargetResolver    — Fallback chain: path+title → title → role+position → absoluteCoord
│   ├── EventInjector       — CGEvent 주입 (mouse/keyboard/scroll), DispatchSourceTimer 10ms 간격
│   ├── PathGenerator       — Auto: Cubic Bezier (seed = step.id), Waypoints: Catmull-Rom
│   └── TimingController    — Step 간 durationMs 대기, ease-in-out 속도 프로파일
│
├── StateValidator          — 앱 실행 중? 요소 visible? enabled? 예상 외 다이얼로그?
├── RecordingBridge         — RecordingCoordinator 연결 (녹화 시작/중지)
└── ReplayHUDController     — NSPanel (floating, excludeWindows), Step 진행/에러 표시
```

### PlaybackState

```swift
enum PlaybackState: Equatable {
    case idle
    case playing
    case paused(reason: PauseReason)
    case error(stepIndex: Int, message: String)
    case waitingForUser    // Re-rehearse: Step N 도달, 사용자 시작 대기
    case countdown(Int)    // Re-rehearse: 카운트다운 3..2..1
    case rehearsing        // Re-rehearse: 사용자 직접 조작 중
    case completed
}

enum PauseReason: Equatable {
    case userRequested     // ESC 또는 Stop
    case doManually        // 에러 후 사용자 수동 수행 모드
}

enum PlaybackMode: Equatable {
    case replayAll                     // Replay & Record: 전체 재생
    case replayUntilStep(Int)          // Re-rehearse: Step N까지 재생 후 전환
}
```

### Ownership & Configuration

**ScenarioPlayer**는 `EditorViewModel`이 소유한다. `AppState`의 `RecordingCoordinator`를 RecordingBridge를 통해 주입받는다.

**ReplayConfiguration**: ScenarioPlayer.start() 호출 시 녹화 설정을 함께 전달한다. 이 설정은 마지막 녹화의 capture target/settings를 `AppState`에서 스냅샷으로 가져온다:

```swift
struct ReplayConfiguration {
    let captureTarget: CaptureTarget
    let backgroundStyle: BackgroundStyle
    let frameRate: Int
    let isSystemAudioEnabled: Bool
    let isMicrophoneEnabled: Bool
    let microphoneDevice: AVCaptureDevice?
}
```

`AppState`는 마지막 녹화의 설정을 `lastCaptureConfiguration: ReplayConfiguration?`으로 보존한다. Replay & Record / Re-rehearse 시 이 설정을 그대로 사용.

### Step Index Convention

UI에서는 1-based (Step 1, Step 2, ...), 코드에서는 0-based (steps[0], steps[1], ...). `PlaybackMode.replayUntilStep(Int)`의 파라미터는 **0-based index**. UI는 표시 시 +1.

### Step Execution Flow

```
ScenarioPlayer.start(scenario:, mode:, config: ReplayConfiguration)
    │
    ├── RecordingBridge: RecordingCoordinator.startRecording(config) (기존 코드 재사용)
    │   (isRehearsalMode = false — Replay 구간에서는 ScenarioEventRecorder 미활성)
    ├── Screenize 창 최소화
    ├── ReplayHUD 표시
    │
    ├── Step 루프:
    │   ├── mode == .replayUntilStep(N) && currentIndex == N?
    │   │   └── YES → state = .waitingForUser
    │   │         → [▶ Start 클릭]
    │   │         → state = .countdown(3) → .countdown(2) → .countdown(1)
    │   │         → RecordingCoordinator.activateScenarioRecorder() (mid-session 활성화)
    │   │         → state = .rehearsing
    │   │         → (사용자 직접 조작, 루프 종료)
    │   │
    │   ├── 1. AXTargetResolver: fallback chain으로 타겟 찾기 (background queue에서 실행)
    │   ├── 2. StateValidator: 앱 실행 중? 요소 visible? enabled?
    │   │   └── 실패 → state = .error → HUD에 Skip/DoManually/Stop 표시
    │   ├── 3. mouse_move → PathGenerator + EventInjector
    │   │   action step → EventInjector
    │   ├── 4. TimingController: durationMs 대기 → 다음 스텝
    │   └── (implicit drag group: 연속 실행, 추가 대기 없음)
    │
    ├── ESC 키 → 즉시 중단 → RecordingBridge.stopRecording() → 여기까지 녹화 보존 → state = .completed
    │
    ├── 재생 완료 → RecordingBridge: RecordingCoordinator.stopRecording()
    └── 새 영상으로 VideoEditor 열림 (ScenarioTrack 포함)
```

핵심: CGEvent 주입은 시스템 레벨이므로 기존 마우스/키보드 트래킹이 별도 처리 없이 캡처한다. 녹화 파이프라인 수정 불필요.

### Mid-Session ScenarioEventRecorder Activation

Re-rehearse 시 Replay → Rehearsal 전환을 위해 `RecordingCoordinator`에 새 메서드 추가:

```swift
/// Activate ScenarioEventRecorder mid-session (for Re-rehearse transition).
/// Called while recording is already in progress.
func activateScenarioRecorder() {
    guard scenarioEventRecorder == nil else { return }
    scenarioEventRecorder = ScenarioEventRecorder()
    scenarioEventRecorder?.startRecording(captureArea: captureBounds)
    isRehearsalMode = true
}
```

Replay & Record (전체 재생)에서는 `isRehearsalMode = false`로 시작하고, ScenarioEventRecorder는 활성화되지 않는다. Re-rehearse에서만 Step N 전환 시점에 `activateScenarioRecorder()` 호출.

### AXTargetResolver Threading

AXTargetResolver의 AX API 호출은 동기 Mach IPC (최대 500ms/fallback 단계). 메인 스레드 차단 방지를 위해:
- AXTargetResolver는 전용 background queue (`DispatchQueue(label: "com.screenize.axResolver", qos: .userInitiated)`)에서 실행
- ScenarioPlayer는 `await withCheckedContinuation`으로 resolution 결과를 기다린 후 EventInjector에 전달

### Re-rehearse from Step N Flow

```
VideoEditor에서 Step N 선택 + [🔄 Re-rehearse from here] 클릭
    │
    ▼
확인 다이얼로그
  "Step N부터 다시 리허설합니다.
   Step 1~(N-1)은 자동 재생되며, Step N부터 직접 조작합니다."
  [Cancel]  [Start]
    │
    ▼ Start
모든 Screenize 창 최소화
    │
    ▼
녹화 시작 + Step 1~(N-1) Replay 엔진으로 자동 실행
┌─ Replay HUD ────────────────────────────────────────────┐
│  ▶ Replaying  Step 2/6  "Foo.swift 클릭"   [■ Stop]     │
└──────────────────────────────────────────────────────────┘
    │
    ▼
Step N 도달 — Replay 일시정지, 커서/화면 상태 유지
┌─ Rehearsal Ready HUD ──────────────────────────────────┐
│  📋 Your turn — Step N "Foo.swift 클릭"                 │
│              [▶ Start]  [■ Stop]                        │
└─────────────────────────────────────────────────────────┘
(사운드 알림으로 전환 시점 전달)
    │
    ▼ Start 클릭
3초 카운트다운 (기존 CountdownPanel 시각 효과 재사용, 단 ESC 감지는 global monitor 사용 — Screenize 창이 최소화되어 있으므로 local monitor 무효)
    │
    ▼
ScenarioEventRecorder 활성화
┌─ Rehearsal HUD ────────────────────────────────────────┐
│  📋 Rehearsing  ◉ 01:23                    [■ Stop]    │
└─────────────────────────────────────────────────────────┘
사용자가 직접 조작하며 리허설 진행
    │
    ▼
Stop
    │
    ▼
하나의 연속된 영상 (Replay 구간 + 카운트다운 + Rehearsal 구간 모두 포함)
시나리오 병합: Step 1~(N-1) 기존 유지 + Step N~ 새 리허설에서 ScenarioGenerator로 생성
scenario-raw.json 새로 생성 (Replay 구간 이벤트 + Rehearsal 구간 이벤트)
    │
    ▼
VideoEditor (새 영상 + 병합된 시나리오)
```

**핵심 설계:**
- 녹화는 Step 1 시작 시점부터 켜져있으므로 **영상은 하나의 연속 파일** — 이어붙이기 불필요
- Replay 구간도 녹화되므로 최종 영상에 자연스럽게 포함
- 카운트다운 중에도 녹화 계속 (나중에 trim 가능)
- 시나리오 병합: `steps[0..<N]` (기존) + `ScenarioGenerator.generate(from: newRawEvents)` (새 리허설)
- **타이밍 오프셋**: 새 리허설 스텝의 `rawTimeRange`는 리허설 시작 기준이므로, 병합 시 Replay duration을 오프셋으로 더한다
- **scenario-raw.json**: Rehearsal 구간의 raw event만 포함 (Replay 구간은 ScenarioEventRecorder 미활성)

**Re-rehearse 버튼 활성 조건:**
- ScenarioTrack에서 스텝이 선택되어 있을 때만 활성화
- Step 0 선택 = 전체 Re-rehearse

**Replay 구간 에러 처리:**
- Step 1~(N-1) 자동 재생 중 에러 발생 시 동일한 에러 HUD 표시 (Skip / Do Manually / Stop)
- Do Manually 선택 시 해당 스텝만 수동 수행 후 Continue → 나머지 Replay 계속 → Step N에서 Rehearsal 전환

### Replay HUD

NSPanel 기반 (기존 CaptureToolbarPanel과 동일한 패턴):
- `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`, level `.floating`
- 녹화에서 제외: Replay HUD는 Screenize 프로세스 소유의 NSPanel이므로, 기존 `SCContentFilter`의 `excludingApplications`에 Screenize 앱이 포함되어 있으면 자동 제외됨. window capture 모드에서는 대상 윈도우만 캡처하므로 HUD가 포함되지 않음. display capture 모드에서는 `SCStream.updateContentFilter(_:)`로 HUD window를 동적 제외 (macOS 14+) — `ScreenCaptureManager`에 `addExcludedWindow(_ window: NSWindow) async` 메서드 추가 필요.
- 화면 상단 중앙, 반투명 작은 바

**상태별 HUD 표시:**

| 상태 | HUD 내용 |
|------|---------|
| Playing | `▶ Replaying  Step 3/7  "에디터 스크롤"   [■ Stop]` |
| Error | `⚠ Step 3 실패: "Foo.swift" 요소를 찾을 수 없음  [Skip] [Do Manually] [Stop]` |
| Do Manually | `✋ Manual mode — Step 3  [Continue] [Stop]` |
| Waiting for User | `📋 Your turn — Step N "Foo.swift 클릭"  [▶ Start] [■ Stop]` |
| Countdown | `3... 2... 1...` (전체 화면 오버레이, 기존 CountdownPanel 재사용) |
| Rehearsing | `📋 Rehearsing  ◉ 01:23  [■ Stop]` |

### EventInjector Implementation

**CGEvent API 사용:**

| 이벤트 | API |
|--------|-----|
| 마우스 이동 | `CGEventCreateMouseEvent(.mouseMoved, point, .left)` |
| 좌클릭 | `CGEventCreateMouseEvent(.leftMouseDown, ...)` + `.leftMouseUp` |
| 우클릭 | `CGEventCreateMouseEvent(.rightMouseDown, ...)` + `.rightMouseUp` |
| 더블클릭 | clickCount = 2 on mouseDown/mouseUp pair |
| 키보드 | `CGEventCreateKeyboardEvent(nil, keyCode, true/false)` + modifier flags |
| 스크롤 | `CGEventCreateScrollWheelEvent2(nil, .pixel, 1, deltaY, deltaX)` — `.pixel` 단위 사용 (시나리오의 `amount`는 fixed-point pixels이므로) |
| 앱 활성화 | `NSWorkspace.shared.open(URL)` 또는 `NSRunningApplication.activate()` |

**주입 방법:** `CGEventPost(.cghidEventTap, event)` — 시스템 레벨 주입.

**이벤트 주입 타이밍:** `DispatchSourceTimer` 10ms 간격. mouse_move 경로를 따라 포인트를 순차 주입. 타이머는 `DispatchQueue(label: "com.screenize.eventInjector", qos: .userInteractive)`에서 실행.

### PathGenerator Implementation

**`path: "auto"` — Deterministic Cubic Bezier:**

```
seed = step.id.hashValue (deterministic — 같은 시나리오는 항상 같은 경로)
rng = SeededRandomNumberGenerator(seed: seed)

A = 이전 스텝 위치, B = 다음 스텝 타겟
perpendicular = normalize(rotate90(B - A))
offset1 = rng.next(in: 0.02...0.08) * (rng.nextBool() ? 1 : -1)
offset2 = rng.next(in: 0.02...0.08) * (rng.nextBool() ? 1 : -1)
C1 = A + (B-A)*0.3 + perpendicular * offset1
C2 = A + (B-A)*0.7 + perpendicular * offset2
path = cubicBezier(A, C1, C2, B)
```

**`path: waypoints` — Catmull-Rom Spline:**

`[이전 위치, ...waypoints, 다음 타겟]`을 Catmull-Rom 스플라인으로 보간. 모든 웨이포인트를 정확히 통과하는 부드러운 곡선. alpha = 0.5 (centripetal).

**공통 속도 프로파일:** ease-in-out. 포인트 개수 = `durationMs / 10` (10ms 간격). 시간 매핑: `t = easeInOut(linearT)` where `easeInOut(t) = t < 0.5 ? 2t² : 1 - (-2t+2)²/2`.

### AXTargetResolver Implementation

**Fallback Chain (순서대로 시도):**

1. **AX path + axTitle**: 루트(AXApplication)부터 path를 따라 내려가며 각 depth에서 role 매칭. 마지막 요소에서 axTitle 확인. sibling index `[N]` suffix가 있으면 해당 인덱스의 자식 선택.

2. **axTitle only**: 현재 앱의 AX 트리 전체를 BFS로 탐색하며 title이 매칭되는 첫 번째 요소 반환. 최대 탐색 depth: 10, timeout: 500ms.

3. **role + positionHint**: `positionHint`를 절대 좌표로 변환 후 `AXUIElementCopyElementAtPosition`으로 해당 위치의 요소를 가져옴. role이 일치하면 반환.

4. **absoluteCoord (최후 수단)**: 저장된 절대 좌표를 직접 사용. AX 타겟 없이 좌표만으로 이벤트 주입. 해상도/윈도우 위치 변경 시 부정확할 수 있음.

각 단계 timeout: 500ms. 전부 실패 → state = .error, HUD에 Skip/DoManually/Stop 표시.

### StateValidator Implementation

**스텝 실행 전 검증:**

| 검증 항목 | 방법 | 실패 시 |
|-----------|------|---------|
| 대상 앱 실행 중 | `NSRunningApplication.runningApplications(withBundleIdentifier:)` | 에러: "앱이 실행되지 않음" |
| 대상 앱 응답 중 | `NSRunningApplication.isTerminated` == false | timeout 5초 후 에러 |
| 요소 visible | AXTargetResolver가 찾은 요소의 `kAXPositionAttribute` + `kAXSizeAttribute` 확인 | fallback chain 다음 단계로 |
| 요소 enabled | `kAXEnabledAttribute` 확인 | 에러: "요소가 비활성화됨" |
| 예상 외 다이얼로그 | focused window의 `kAXRoleAttribute`가 `AXSheet` 또는 `AXDialog` | 에러: "예상 외 다이얼로그" |

### Error Handling

| 상황 | 대응 |
|------|------|
| 타겟 요소를 못 찾음 | fallback chain 전부 시도 → 실패 시 일시정지 + HUD 알림 |
| 앱이 응답 없음 | timeout (5초) 후 일시정지 |
| 예상 외 다이얼로그 팝업 | AX로 감지 → 일시정지 + 알림 |
| 사용자가 중간에 개입 | ESC 키로 즉시 중단, 해당 스텝까지의 녹화 보존 |

일시정지 시 선택지:
- **Skip** — 현재 스텝 무시, 다음으로
- **Do Manually** — 일시정지, 사용자가 수동 수행 후 Continue 버튼으로 다음 스텝부터 재생 계속
- **Stop** — 중단, 여기까지만 녹화 저장

### Bottom Bar Button Activation (Phase 2)

Phase 1에서 disabled placeholder로 있던 Bottom Bar 버튼들을 활성화:

- **[▶ Replay & Record]**: 항상 활성 (시나리오가 있을 때). 클릭 시 확인 다이얼로그 → ScenarioPlayer.start(mode: .replayAll)
- **[🔄 Re-rehearse from here]**: ScenarioTrack에서 스텝이 선택되어 있을 때만 활성. 클릭 시 확인 다이얼로그 → ScenarioPlayer.start(mode: .replayUntilStep(selectedIndex))

### macOS Permissions

| 권한 | 용도 | 현재 상태 |
|------|------|----------|
| Screen Recording | 화면 캡처 | 이미 있음 |
| Accessibility | AX 읽기 + CGEvent 주입 | 이미 있음 (추가 요청 불필요) |

## Non-Goals

- 크로스 플랫폼 지원 (macOS only)
- 실시간 시나리오 편집 중 프리뷰 (Phase 2 이후 고려)
- AI 기반 시나리오 자동 생성 (사용자 리허설 기반만)
- 커서 이동 시 미세 노이즈/jitter 주입 (베지어 + ease-in-out으로 충분)

## Version Migration

`scenario.json`의 `version` 필드로 포맷 변경을 관리한다. 로드 시 현재 버전보다 낮으면 마이그레이션 함수를 순차 적용한다 (v1→v2→v3). 기존 `ScreenizeProject`의 버전 관리 패턴을 따른다.
