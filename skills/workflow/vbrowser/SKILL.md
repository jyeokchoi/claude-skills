---
name: vbrowser
description: Claude in Chrome으로 PRD 유저 시나리오와 테스트 케이스를 브라우저에서 직접 실행하는 E2E 테스트 스킬. vtest에서 호출되거나 단독 실행 가능.
argument-hint: 'Usage: /vbrowser [worklog-folder-or-url]'
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded).

## 대상 결정

- $ARGUMENTS가 URL 형식(`http://`, `https://`, `localhost`)이면 → `APP_URL`로 직접 설정하고 Phase 0 Step 1~2는 건너뜀. `WORKLOG_DIR`은 `.claude/worklogs/.active`를 읽어 활성 워크로그 폴더로 설정한다 (없으면 `WORKLOG_DIR=null`로 유지하고, Phase 1에서 Source 0, 1, 2를 건너뛰고 Source 3으로 직접 진행한다).
- 그 외: `_shared/resolve-worklog-target.md`가 존재하면 로드하여 해당 로직을 따름
- 폴백:
  - $ARGUMENTS가 폴더이면 `{arg}/worklog.md` 대상으로 설정
  - 그 외: `.claude/worklogs/.active`를 읽어 활성 워크로그 폴더 가져옴
- `WORKLOG_DIR` = 워크로그 폴더 경로
- `PLAN_FILE` = `{WORKLOG_DIR}/plan.md`

참고: `ORCHESTRATED=true`인 경우 vwork가 항상 `WORKLOG_DIR`을 인자로 전달하므로, `WORKLOG_DIR=null`은 독립 실행(standalone) 경로에서만 발생한다.

## 오케스트레이션 컨텍스트

- `_shared/orchestration-context.md`를 로드하고 **서브 스킬 — 읽기** 프로토콜을 따른다.
- `ORCHESTRATED=true`이고 `ORCHESTRATION_MODE=auto`인 경우:
  - Phase 2 사용자 확인 → 기본값: 전체 실행

## Knowledge Base 로드

`{WORKLOG_DIR}/browser-kb.md`가 존재하면 로드하여 테스트 전반에 활용한다:
- 이전 세션에서 발견한 인증/로그인 패턴 파악
- 알려진 UI 패턴 및 셀렉터 참고
- 이전에 실패한 경로 및 우회 방법 확인

KB 내용은 LLM 컨텍스트에 포함되어 Phase 3 시나리오 실행 전반에 걸쳐 참고된다. 예를 들어 인증 섹션이 있으면 로그인이 필요한 시나리오 시작 전에 해당 패턴을 참고하고, 알려진 이슈 섹션이 있으면 해당 경로를 우회하여 실행한다.

파일이 없으면 이 단계를 건너뛴다 (첫 세션).

## Phase 0: 앱 URL 감지

앱이 실행 중인 URL을 세 단계로 탐지한다.

### Step 1: 현재 Chrome 탭 확인

`tabs_context_mcp`를 호출하여 현재 열린 탭 목록을 가져온다.

다음 패턴의 탭을 탐색한다 (우선순위 순):
- `localhost:*`, `127.0.0.1:*`
- `0.0.0.0:*`
- `*.local`, `*.dev`, `*.test` (IP/호스트명 기반 dev URL)

| 결과 | 처리 |
|------|------|
| 1개 발견 | `APP_URL`로 설정 후 Phase 0 종료 |
| 2개 이상 발견 | AskUserQuestion으로 사용자 선택 |
| 0개 | Step 2로 진행 |

탭이 2개 이상이면:
```
AskUserQuestion:
  question: "테스트할 앱 탭을 선택하세요."
  header: "앱 선택"
  options: [발견된 탭 URL 목록, 최대 4개]
```

### Step 2: 워크로그 메타데이터 확인

Step 1에서 탭을 찾지 못한 경우, `{WORKLOG_DIR}/worklog.md`를 읽어 다음 필드를 탐색한다:
- frontmatter: `base_url`, `dev_url`, `app_url`, `local_url`
- Remember 섹션: URL 패턴(`http://localhost:*` 등)

찾으면 → `APP_URL`로 설정 후 Phase 0 종료.

### Step 3: 사용자에게 직접 질문

Step 1, 2 모두 실패한 경우:

```
AskUserQuestion:
  question: "테스트할 앱의 URL을 알려주세요."
  header: "앱 URL"
  options:
    - label: "http://localhost:3000"
      description: "기본 Node.js/React 개발 서버"
    - label: "http://localhost:5173"
      description: "Vite 기본 포트"
    - label: "http://localhost:8080"
      description: "대체 포트"
    - label: "직접 입력"
      description: "다른 URL을 지정합니다"
```

`APP_URL` 확정 후 계속 진행. 사용자가 취소하면 중단하고 오류 출력.

## Phase 1: 테스트 케이스 수집

PRD와 vtest 갭에서 브라우저 테스트 케이스를 수집한다.

### Source 0: 버그 재현 시나리오 (최우선)

`{WORKLOG_DIR}/browser-scenarios.md`가 존재하면 이를 최우선으로 로드한다. vanalyze가 버그 재현 목적으로 vbrowser를 호출할 때 이 파일에 시나리오를 기록한다.

- **파일이 존재하면**: `browser-scenarios.md`의 시나리오를 테스트 케이스로 로드하고 Source 1, 2, 3을 건너뛴다.
- **파일이 없으면**: Source 1으로 진행한다.

### Source 1: PRD 유저 시나리오 (primary)

`{PLAN_FILE}` 또는 `.omc/plans/prd.md`를 읽어 다음 섹션을 추출한다:
- `## 유저 시나리오` / `## User Scenarios`
- `## 사용자 흐름` / `## User Flows`
- `## 기능 요구사항` 하위의 step-by-step 시나리오
- Acceptance criteria에서 "사용자가 ~하면 ~된다" 패턴

각 시나리오를 다음 형식으로 정규화한다:

| # | 시나리오 | 시작 URL | 예상 결과 | 우선순위 |
|---|---------|---------|----------|----------|
| 1 | {이름} | {경로} | {성공 조건} | HIGH/MED/LOW |

### Source 2: vtest E2E 갭 (secondary)

`{WORKLOG_DIR}/report.md`의 E2E 갭 섹션을 읽는다.
`ORCHESTRATED=true`인 경우 호출자(vtest)가 전달한 시나리오 목록도 포함한다.

### Source 3: 사용자 요청 (tertiary)

Source 1, 2 모두 없는 경우:

```
AskUserQuestion:
  question: "테스트할 시나리오를 어떻게 지정할까요?"
  header: "시나리오"
  options:
    - label: "직접 설명"
      description: "테스트할 유저 흐름을 직접 설명합니다"
    - label: "앱 탐색 후 결정"
      description: "앱을 먼저 열어보고 시나리오를 결정합니다"
```

### 수집 결과 요약

수집 후 사용자에게 출력:

```
## 브라우저 테스트 케이스 ({N}개)

| # | 시나리오 | 소스 | 우선순위 |
|---|---------|------|----------|
| 1 | {name} | PRD | HIGH |
| 2 | {name} | E2E 갭 | MED |
...
```

케이스가 0개이면 사용자에게 보고하고 중단.

## Phase 2: 실행 준비 및 확인

### Step 1: 브라우저 탭 준비

```
tabs_create_mcp() → TAB_ID
navigate(tab_id=TAB_ID, url=APP_URL)
read_page(tab_id=TAB_ID)  # 페이지 로딩 확인
```

페이지 로딩 실패 시 (에러, 빈 페이지) → 사용자에게 앱 실행 여부 확인 후 중단.

### Step 2: 실행 계획 제시 및 확인

수집된 시나리오와 녹화 계획을 제시한다:

```
## 브라우저 테스트 실행 계획

앱: {APP_URL}
탭 ID: {TAB_ID}

시나리오 목록:
1. {scenario-1}: {핵심 단계 미리보기}
2. {scenario-2}: {핵심 단계 미리보기}
...

각 시나리오는 GIF로 녹화됩니다. 실패 지점에서 스크린샷이 자동 저장됩니다.
```

```
AskUserQuestion:
  question: "브라우저 테스트를 시작할까요?"
  header: "실행 확인"
  options:
    - label: "전체 실행 (Recommended)"
      description: "모든 시나리오를 순서대로 실행합니다"
    - label: "선택 실행"
      description: "특정 번호의 시나리오만 실행합니다"
    - label: "취소"
      description: "브라우저 테스트를 건너뜁니다"
```

"선택 실행" 선택 시: 실행할 시나리오 번호를 쉼표로 구분하여 입력받는다 (예: `1,3` 또는 `2`). 해당 번호의 시나리오만 `selected_scenarios`에 포함하여 Phase 3을 실행한다.

`ORCHESTRATED=true` + `auto` 모드: 사용자 확인 생략, 전체 실행.

## Phase 3: 시나리오 실행

선택된 각 시나리오에 대해 다음 루프를 실행한다.

### 시나리오별 실행 루프

```
RESULTS = []
PENDING_DISCOVERIES = []

FOR each scenario in selected_scenarios:
  SCENARIO_IDX = 두 자리 번호 (예: "01", "02")
  SCENARIO_SLUG = 시나리오명을 kebab-case로 변환
  GIF_NAME = "{worklog-slug}-{SCENARIO_IDX}-{SCENARIO_SLUG}.gif"
  RESULT = "PASS"
  FAIL_REASON = null
  SCREENSHOT_PATH = null

  # GIF 녹화 시작 (시작점 프레임 포함)
  gif_creator(action="start", filename=GIF_NAME)

  # 시작점으로 이동
  navigate(tab_id=TAB_ID, url=scenario.start_url or APP_URL)

  # 초기 상태 프레임 캡처 (안정적인 첫 프레임)
  read_page(tab_id=TAB_ID)

  FOR each step in scenario.steps:
    TRY:
      # 단계 실행 (아래 단계 실행 전략 참조)
      execute_step(step, TAB_ID)

      # 각 액션 후 프레임 확보를 위해 페이지 상태 확인
      read_page(tab_id=TAB_ID)

    CATCH failure (도구 오류 / 예상 요소 없음 / 예상 상태 불일치):
      RESULT = "FAIL"
      FAIL_REASON = "{step.description}: {error_detail}"

      # 실패 지점 스크린샷
      computer(action="screenshot") → SCREENSHOT_PATH

      BREAK  # 해당 시나리오 종료

  # GIF 녹화 종료 (최종 상태 프레임 포함)
  gif_creator(action="stop") → GIF_PATH

  RESULTS.append({
    scenario: scenario.name,
    result: RESULT,
    gif: GIF_PATH,
    screenshot: SCREENSHOT_PATH,
    fail_reason: FAIL_REASON
  })

  # 중요 발견 감지 (LLM이 직접 판단)
  # 다음 중 하나라도 해당하면 기록 대상:
  # - 예상과 다른 UI 흐름 발견 (실제 동작 ≠ PRD)
  # - 특수한 인증 패턴 (토큰 위치, 세션 처리 방식)
  # - 특정 셀렉터/경로가 다른 방법으로만 접근 가능
  # - 재현 가능한 환경 의존성 (특정 데이터 상태 필요 등)
  # - 앱의 비표준 동작 패턴
  # 해당하면: DISCOVERY = { category: "인증|네비게이션|UI패턴|이슈|기타", summary: "한 줄 요약", detail: "상세 내용" }
  # 해당 없으면: DISCOVERY = null
  if DISCOVERY:
    PENDING_DISCOVERIES.append(DISCOVERY)
```

### 단계 실행 전략

| 단계 유형 | 사용 도구 | 비고 |
|----------|----------|------|
| 페이지 이동 | `navigate` | 상대 경로는 `APP_URL` 기준으로 절대 경로 조합 |
| 텍스트 입력 | `find` → `form_input` | selector로 요소 탐색 후 입력 |
| 버튼/링크 클릭 | `find` → `javascript_tool` (`.click()`) | |
| 체크박스/라디오/셀렉트 | `find` → `form_input` | |
| 페이지 텍스트 확인 | `get_page_text` 또는 `read_page` | 예상 문자열 포함 여부 확인 |
| 시각적 요소 확인 | `computer` (screenshot 분석) | 텍스트 기반 확인 불가 시 |
| JS 직접 실행 필요 | `javascript_tool` | DOM 조작, 이벤트 트리거 |
| 콘솔 에러 확인 | `read_console_messages` | 실패 원인 추가 정보 수집 시 |

### 실패 판단 기준

다음 중 하나라도 해당하면 FAIL 처리:
- 예상 DOM 요소가 `find`로 탐색되지 않음
- 예상 텍스트/메시지가 페이지에 없음
- 에러 메시지 또는 오류 UI가 표시됨
- 예상 URL/경로로 이동되지 않음
- 브라우저 도구가 2~3회 연속 오류 반환

### 주의사항

- **Alert 트리거 절대 금지**: confirm, alert, prompt 다이얼로그를 유발할 수 있는 요소(삭제 버튼 등)는 클릭하지 않는다. 해당 케이스를 "수동 확인 필요" (SKIP)로 기록.
- **기존 탭 간섭 금지**: Phase 2에서 생성한 전용 탭(TAB_ID)만 사용한다.
- **도구 오류 루프 금지**: 같은 단계에서 2~3회 실패하면 FAIL 처리 후 다음 시나리오로 넘어간다.

## Phase 4: 결과 보고서

`WORKLOG_DIR=null`인 경우 (URL 직접 입력 + 활성 워크로그 없음):
- 보고서는 콘솔 출력만 수행하고 파일 저장을 건너뛴다.
- 워크로그 업데이트와 Knowledge Base 업데이트를 건너뛴다.
- Phase 5 인계 시 `report` 필드는 null로 설정한다.

### 결과 집계 및 출력

```
## 브라우저 E2E 테스트 결과

앱: {APP_URL}
실행 일시: {TIMESTAMP}

| # | 시나리오 | 결과 | 녹화 | 실패 원인 |
|---|---------|------|------|----------|
| 1 | {name} | ✅ PASS | [{GIF_NAME}]({GIF_PATH}) | - |
| 2 | {name} | ❌ FAIL | [{GIF_NAME}]({GIF_PATH}) | {FAIL_REASON} |
| 3 | {name} | ⏭ SKIP | - | 수동 확인 필요 |
...

**통계: {PASS_COUNT}/{TOTAL_COUNT} 통과 ({PASS_RATE}%)**
```

### 실패 분석 (실패가 있는 경우)

각 FAIL 시나리오에 대해:
```
### ❌ {scenario.name}

- **실패 단계**: {step.description}
- **실패 이유**: {error_detail}
- **스크린샷**: {SCREENSHOT_PATH}
- **가능한 원인**:
  - [ ] 앱 버그 (기능 미구현 또는 오작동)
  - [ ] 시나리오 오류 (PRD와 실제 UI 흐름 불일치)
  - [ ] 환경 문제 (데이터, 로그인 상태 등)
```

### 보고서 저장

`{WORKLOG_DIR}/browser-test-report.md`에 전체 결과를 저장한다.

### 워크로그 업데이트

`_shared/update-worklog.md`를 통해 업데이트:
- `dashboard_updates`:
  - Next actions: FAIL 시나리오 버그 수정 항목
  - Decisions: 브라우저 테스트 결과 요약 ({PASS}/{TOTAL})
- `stable_updates`:
  - Links: GIF 파일 경로 목록, 보고서 경로 추가
- `timeline_entry`: 브라우저 E2E 테스트 실행 결과. PENDING_DISCOVERIES가 있으면 "Knowledge Base 업데이트 — {N}개 발견 기록"도 포함

### Knowledge Base 업데이트

PENDING_DISCOVERIES가 있으면 `{WORKLOG_DIR}/browser-kb.md`를 업데이트한다:

- 파일이 없으면 새로 생성한다.
- 파일이 있으면 기존 내용을 읽고 관련 섹션에 병합한다 (중복 기록하지 않는다).

`DISCOVERY.category` → KB 섹션 헤더 매핑:

| category | KB 섹션 헤더 |
|----------|-------------|
| 인증 | `## 인증 / 로그인` |
| 네비게이션 | `## 네비게이션 패턴` |
| UI패턴 | `## UI 패턴 / 셀렉터` |
| 이슈 | `## 알려진 이슈 / 우회법` |
| 기타 | `## 기타 발견` |

KB 파일 형식:
```markdown
# Browser Knowledge Base

_마지막 업데이트: {DATE} | 앱: {APP_URL}_

## 인증 / 로그인
<!-- 로그인 URL, 필수 필드, 세션 처리 방식 등 -->

## 네비게이션 패턴
<!-- 특정 페이지 접근 경로, 숨겨진 경로, 리다이렉트 패턴 등 -->

## UI 패턴 / 셀렉터
<!-- 자주 쓰이는 셀렉터, 특이한 UI 구조, 동적 클래스명 패턴 등 -->

## 알려진 이슈 / 우회법
<!-- 타이밍 문제, 플레이키한 요소, 우회 방법 등 -->

## 기타 발견
<!-- 위 카테고리에 맞지 않는 기타 중요 발견 -->
```

발견이 없으면 이 단계를 건너뛴다.

## Phase 5: 인계

**`ORCHESTRATED=true`인 경우:** vwork 오케스트레이터에게 SendMessage로 결과를 보고하고 종료:
```
SendMessage(type="message", recipient="vwork",
  content="브라우저 E2E 테스트 완료.

  BROWSER_TEST_RESULT = {
    total: N,
    pass: N,
    fail: N,
    skip: N,
    report: \"{WORKLOG_DIR}/browser-test-report.md\",
    gifs: [경로 목록]
  }",
  summary="브라우저 테스트 완료 — {pass}/{total} 통과")
```

**그 외 (독립 실행):**

```
AskUserQuestion:
  question: "브라우저 테스트가 완료되었습니다. 다음 단계를 선택하세요."
  header: "Next"
  options:
    - label: "실패 분석 (/vqa)"
      description: "실패 시나리오를 QA 관점에서 재분석합니다"
    - label: "실패 시나리오 재실행"
      description: "FAIL 시나리오만 다시 실행합니다"
    - label: "완료"
      description: "브라우저 테스트를 종료합니다"
```

## 절대 규칙

- **GIF 녹화 필수.** 모든 시나리오는 gif_creator로 녹화한다. 시나리오 시작 시 초기 프레임을 확보하고, 각 액션 후 read_page를 호출하여 충분한 프레임을 확보한다.
- **실패 시 스크린샷 필수.** FAIL 지점에서 반드시 computer(screenshot)으로 캡처한다.
- **Alert 트리거 금지.** confirm/alert/prompt 유발 요소는 클릭하지 않는다. SKIP 처리.
- **전용 탭 사용.** tabs_create_mcp로 전용 탭을 생성하고 기존 사용자 탭을 건드리지 않는다.
- **워크로그 업데이트 필수.** 완료 후 `_shared/update-worklog.md`로 결과를 기록한다.
- **브라우저 도구 오류 루프 금지.** 2~3회 연속 실패 시 FAIL 처리 후 사용자에게 보고하고 다음으로 넘어간다.
- **무거운 작업은 위임한다.** `_shared/delegation-policy.md` 참조.

이제 실행하라.
