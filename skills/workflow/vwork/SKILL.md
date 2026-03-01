---
name: vwork
description: Unified workflow orchestrator. Single entry point for analyze → PRD → plan → implement → verify → test → finish pipeline, driven by worklog phase.
argument-hint: 'Usage: /vwork [--auto] [worklog-path | task-name | ISSUE-KEY] [brief]'
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용.

워크로그 phase를 기반으로 전체 작업 라이프사이클을 관리하는 통합 오케스트레이터.

## 입력

- 원본 인자: $ARGUMENTS

인자 해석:
- `--auto` 플래그: 자동 모드 활성화 (ralph loop이 모든 phase를 구동)
- `--session` 플래그: 세션 모드 활성화 (ralph loop 상시 유지, 모든 요청을 전담 팀원에게 자동 라우팅)
- 첫 번째 비플래그 토큰: 워크로그 경로, 작업명, 또는 Jira 이슈 키
- 나머지 텍스트: 작업 설명 (task brief)

## Phase 상태 머신

워크로그의 `phase` 필드가 워크플로우를 구동한다:

```
[기존 수정] → ANALYZE → PRD → PLAN → IMPL ←──┐
                                        ↓     │
[신규 기능] ──────────→ PRD → PLAN → IMPL   VERIFY ─┤──→ DONE
                                        ↓     │
                                       TEST ──┘
```

진입점은 작업 유형에 따라 달라진다:
- **기존 코드 수정** (modification): ANALYZE부터 시작 — 기존 코드 이해와 영향도 분석이 필요
- **신규 기능** (new-feature): PRD부터 시작 — 분석할 기존 코드가 없으므로 요구사항 정의부터

피드백 루프:
- VERIFY → IMPL (비테스트 이슈) → VERIFY (수정 후 재검증)
- VERIFY → TEST (테스트 갭) → VERIFY (테스트 작성 후 재검증)

phase 전이는 피드백 루프를 제외하면 **전진 전용**이다.

## 절차

### 0. 상태 재수화 (ralph 재진입 감지)

**가장 먼저 실행한다.** 이 단계는 컨텍스트 컴팩션 후 ralph 재진입을 감지하고 인메모리 변수를 복구한다.

`state_read(mode="vwork")`를 실행한다:

**`active=true`이고 `current_phase`가 설정된 경우 (ralph 재진입):**

state에서 모든 변수를 복구한다:
- `WORKLOG_DIR` = `state.worklog_dir`
- `WORKLOG_SLUG` = `state.worklog_slug`
- `project_type` = `state.project_type`
- `task_type` = `state.task_type`
- `mode` = `state.mode`
- `team_name` = `state.team_name`
- `feedback_iterations` = `state.feedback_iterations`
- `spawned_agents` = `state.spawned_agents` (스폰된 팀원 이름 목록)

phase 일치 검증 (state와 워크로그 동기화):
- 워크로그 파일(`{WORKLOG_DIR}`)의 `phase` 필드를 읽는다.
- 워크로그 `phase`와 state의 `current_phase`가 다른 경우: **워크로그 값을 진실 기준으로 사용**하고 state의 `current_phase`를 워크로그 값으로 갱신한다.
  - 이유: 컴팩션 직전에 워크로그 업데이트는 완료됐지만 state_write가 완료되지 않았을 수 있기 때문이다.
- 일치하거나 워크로그 읽기 실패 시: state 값을 그대로 사용한다.

팀 생존 여부 확인:
- `~/.claude/teams/{team_name}/config.json`이 존재하면: 기존 팀 활성 상태 → **Step 4 (Phase 실행)로 직접 점프**
- config.json이 없으면: 팀이 종료됨 → **Step 3-B (팀 재생성)로 점프**

**`active=false` 또는 state 없는 경우 (신규 실행):**

아래 Step 1부터 정상 진행한다.

### 1. 워크로그 결정 또는 생성

**인자가 워크로그 경로(폴더 또는 .md 파일)인 경우:**
- 기존 워크로그를 로드하고 `phase` 필드를 읽는다
- phase가 비어있거나 미설정이면: 작업 유형 감지 (아래 참조) → 초기 phase 설정
- 재개 검증 수행 (아래 참조)
- Step 2 (모드 선택)로 진행

**인자가 작업명 또는 Jira 이슈 키인 경우 (기존 워크로그 없음):**
- `/worklog-start` 로직을 호출하여 새 워크로그 생성
- 작업 유형 감지 (아래 참조) → 초기 phase 설정
- Step 2로 진행

**인자 없음:**
- 활성 워크로그 검색 (`.claude/worklogs/.active` 또는 find)
- 발견 시: 워크로그 로드, phase 읽기, 재개 검증 수행, Step 2로 진행
- 미발견 시: 사용자에게 작업명 또는 이슈 키를 요청, `/worklog-start`로 새 워크로그 생성

**작업 유형 감지 (신규 vs 기존 수정):**

워크로그의 Goal, Completion criteria, task brief에서 작업 유형을 자동 감지한다:

| 유형 | 감지 신호 | 초기 phase |
|------|-----------|------------|
| **신규 기능** (new-feature) | "새 기능", "new feature", "신규", "새로 만들", "create", "build from scratch", "greenfield" | `PRD` |
| **기존 수정** (modification) | "수정", "변경", "fix", "refactor", "modify", "개선", "migrate", "버그", "regression", 또는 특정 파일/모듈 경로 언급 | `ANALYZE` |

- frontmatter에 `type: new-feature` 또는 `type: modification`이 명시되어 있으면 감지를 건너뛰고 해당 값을 사용한다.
- 키워드로 명확히 판별된 경우에도, 판단 결과와 근거를 워크로그 Decisions에 기록한다.
- 감지 불가 시:
  - **auto 모드**: 에이전트가 Goal, Completion criteria, task brief, 관련 코드베이스 상태(기존 파일 존재 여부 등)를 종합하여 최선의 판단을 내린다. **판단 결과와 근거를 반드시 워크로그 Dashboard의 Decisions 섹션에 기록한다:**
    ```
    - [CURRENT] Task type: {new-feature|modification} — 근거: {판단 근거 1~2문장}
    ```
  - **step 모드**: 사용자에게 질문:
    ```
    AskUserQuestion:
      question: "이 작업은 신규 기능인가요, 기존 코드 수정인가요?"
      header: "Task Type"
      options:
        - label: "신규 기능"
          description: "새로 만드는 기능입니다. 요구사항 정의(PRD)부터 시작합니다."
        - label: "기존 코드 수정"
          description: "기존 코드를 변경합니다. 코드 분석(ANALYZE)부터 시작합니다."
    ```

**재개 검증 (기존 워크로그만 해당):**

방금 생성된 워크로그(빈 Dashboard)면 건너뛴다. 기존 워크로그를 재개할 때:

1. 상태 요약 출력:
   ```
   워크로그 상태 요약
   Goal: {goal}
   Jira: {jira_url}
   Branch: {branch}
   완료 기준: {completed}/{total}
   Phase: {phase}
   결정사항: {decisions}
   최근 작업: {last timeline entry summary}
   ```

2. 이전 결정 검증 (Decisions 섹션이 비어있지 않은 경우):
   ```
   AskUserQuestion:
     question: "이전 세션의 결정사항이 여전히 유효한가요?"
     header: "Decisions"
     options:
       - label: "예, 유효함"
         description: "기존 결정대로 이어서 진행"
       - label: "아니오, 수정 필요"
         description: "일부 결정이 바뀌었거나 재검토 필요"
   ```
   - "수정 필요" 선택 시: 자유 입력으로 변경사항 수집, 기존 결정에 `[INVALIDATED {date}]` 표시, 새 결정에 `[CURRENT]` 추가

3. `_shared/update-worklog.md`로 워크로그 업데이트:
   - `timeline_entry`: "세션 재개 — Phase: {phase}, 재개 지점: {first pending action}"

### 2. 모드 선택

**`--auto` 플래그가 있는 경우:**
- mode = auto 설정
- 출력: "자동 모드 활성화. 완료까지 자동으로 진행합니다."
- ralph loop 활성화:
  1. `rules/project-params.md`에서 `completion_promise` 사용 (기본값: `**WORKLOG_TASK_COMPLETE**`)
  2. `state_write(mode="ralph")`로 ralph 상태 생성:
     ```json
     {
       "active": true,
       "iteration": 1,
       "max_iterations": 100,
       "completion_promise": "{COMPLETION_PROMISE}",
       "worklog_path": "{WORKLOG_DIR}",
       "linked_ultrawork": true
     }
     ```
  3. `state_write(mode="ultrawork")`로 ultrawork 상태 생성:
     ```json
     {
       "active": true,
       "linked_to_ralph": true
     }
     ```
- Step 3으로 진행

**`--session` 플래그가 있는 경우:**
- mode = session 설정
- 출력: "vwork 세션이 활성화되었습니다. 모든 요청은 전담 팀원에게 위임됩니다. '종료' 또는 'exit vwork'를 입력하면 세션이 종료됩니다."
- ralph loop 활성화:
  1. `completion_promise = "**VWORK_SESSION_END**"` (고정값, `project-params.md` 설정 무시)
  2. `state_write(mode="ralph")`로 ralph 상태 생성:
     ```json
     {
       "active": true,
       "iteration": 1,
       "max_iterations": 500,
       "completion_promise": "**VWORK_SESSION_END**",
       "worklog_path": "{WORKLOG_DIR}",
       "linked_ultrawork": false
     }
     ```
- Step 3으로 진행 (오케스트레이션 컨텍스트 설정 후 Step 4-S 세션 라우팅 진입)

**`--auto` 플래그도 `--session` 플래그도 없는 경우:**

```
AskUserQuestion:
  question: "워크플로우 모드를 선택하세요."
  header: "Mode"
  options:
    - label: "자동 모드 (Auto)"
      description: "Ralph loop으로 모든 페이즈를 자동 진행합니다. 각 단계에서 중요 결정만 물어봅니다."
    - label: "단계별 모드 (Step-by-step)"
      description: "각 페이즈 완료 후 다음 단계 진행 여부를 확인합니다."
    - label: "세션 모드 (Session)"
      description: "vwork를 항상 활성 상태로 유지합니다. 모든 요청이 전담 팀원에게 자동 위임됩니다. '종료'를 입력할 때만 세션이 끝납니다."
```

- "자동 모드": mode = auto, ralph loop 활성화 (--auto 경로와 동일)
- "단계별 모드": mode = step
- "세션 모드": mode = session, --session 경로와 동일하게 처리

### 3. 오케스트레이션 컨텍스트

서브 스킬이 오케스트레이션 상태를 인식할 수 있도록 컨텍스트를 기록한다:

- `_shared/orchestration-context.md`를 로드하고 **vwork — 쓰기** 프로토콜을 따른다.
- **상태 보존 규칙**: 이 규칙은 vwork 실행 중 **모든 `state_write(mode="vwork")` 호출**에 적용된다. 호출 전에 반드시 `state_read(mode="vwork")`로 현재 상태를 읽고 기존 필드를 모두 보존한 뒤, 변경할 필드만 덮어쓴다 (`team_name`, `current_phase`, `feedback_iterations` 등 누적 필드 유실 방지). VERIFY→IMPL 또는 VERIFY→TEST 전이 시 `feedback_iterations`를 1 증가시킨다 (IMPL→VERIFY, TEST→VERIFY 전이에서는 증가하지 않음). `code_issues_and_test_gaps` route 처리 시 VERIFY→IMPL(+1) 후 재검증에서 test_gaps가 남아 VERIFY→TEST(+1)가 추가될 수 있으며, 이는 의도된 동작이다 (해당 경로는 최대 2회 소비). 최대 5회 초과 시 사용자에게 보고.
- `state_write(mode="vwork", data={ "active": true, "mode": "{auto|step|session}", "current_phase": "{phase}", "worklog_dir": "{WORKLOG_DIR}", "worklog_slug": "{WORKLOG_SLUG}", "project_type": "{project_type}", "task_type": "{task_type}", "feedback_iterations": {state_read로 읽은 기존 값, 없으면 0}, "spawned_agents": {state_read로 읽은 기존 값, 없으면 []} })`
  - **`team_name` 참고**: 이 시점에서는 팀이 아직 생성되지 않았으므로 `team_name`을 포함하지 않는다. `team_name`은 Step 3-B에서 팀 생성 후 별도 `state_write`로 추가된다. 상태 보존 규칙에 따라 Step 3-B의 state_write가 이 시점의 필드를 모두 보존하면서 `team_name`을 추가한다.
- **재수화 대상 필드**: `worklog_slug`, `project_type`, `task_type`, `spawned_agents`는 Step 0에서 읽어 변수를 복구하는 용도이므로, 이 값들을 처음 결정하는 시점(Step 1, 2, 3-B)에서 반드시 최신값으로 갱신해야 한다.
- **step 모드 참고**: step 모드에서는 ralph loop이 없으므로 Step 0 재수화가 실행되지 않는다. 그러나 `spawned_agents`를 포함한 확장 필드는 동일하게 state에 저장한다 — `/vwork` 재호출 없이 세션이 연속될 가능성에 대비하고, 향후 step 모드도 재개 가능하도록 일관성을 유지한다.
- 각 서브 스킬 호출 전에 `current_phase`를 해당 phase로 업데이트한다.

### 3-B. 에이전트 팀 생성

vwork는 항상 5명으로 구성된 전담 팀을 생성하여 실제 작업을 위임한다.

팀 생성 전에 기존 팀이 있는지 확인한다:
- `state_read(mode="vwork")`에서 `team_name` 필드가 있으면:
  - `~/.claude/teams/{team_name}/config.json`이 존재하면: 기존 팀을 재사용하고 TeamCreate를 건너뛴다 (ralph loop 재진입은 같은 세션 내에서 이루어지므로 팀원들은 활성 상태로 간주한다).
  - config.json이 없으면 (팀이 이미 종료/삭제됨): 새 팀을 생성한다 (team_name을 새 값으로 덮어씀).
- `team_name` 필드가 없으면: 아래와 같이 새 팀을 생성한다.

```
TeamCreate(team_name="vwork-{WORKLOG_SLUG}", description="vwork 에이전트 팀 — {GOAL_SUMMARY}")
```

팀 멤버 구성:

| 역할 | 담당 Phase | subagent_type | model |
|------|-----------|---------------|-------|
| `analyzer` | ANALYZE | oh-my-claudecode:debugger | sonnet |
| `planner` | PRD, PLAN | oh-my-claudecode:planner | opus |
| `implementer` | IMPL | oh-my-claudecode:executor | sonnet |
| `tester` | TEST | oh-my-claudecode:test-engineer | sonnet |
| `vbrowser-agent` | VERIFY (브라우저 테스트) | oh-my-claudecode:qa-tester | sonnet |

스폰 조건:
- 작업 유형이 `new-feature`이면 `analyzer`는 스폰하지 않는다 (ANALYZE phase가 없음).
- `project_type`이 `frontend` 또는 `fullstack`이 아니면 `vbrowser-agent`는 스폰하지 않는다.

팀원 스폰:
```
Task(subagent_type="oh-my-claudecode:debugger", model="sonnet",
     team_name="vwork-{WORKLOG_SLUG}", name="analyzer",
     prompt="당신은 vwork 팀의 analyzer입니다. 팀 리드(vwork)의 지시를 기다리세요.")

Task(subagent_type="oh-my-claudecode:planner", model="opus",
     team_name="vwork-{WORKLOG_SLUG}", name="planner",
     prompt="당신은 vwork 팀의 planner입니다. 팀 리드(vwork)의 지시를 기다리세요.")

Task(subagent_type="oh-my-claudecode:executor", model="sonnet",
     team_name="vwork-{WORKLOG_SLUG}", name="implementer",
     prompt="당신은 vwork 팀의 implementer입니다. 팀 리드(vwork)의 지시를 기다리세요.")

Task(subagent_type="oh-my-claudecode:test-engineer", model="sonnet",
     team_name="vwork-{WORKLOG_SLUG}", name="tester",
     prompt="당신은 vwork 팀의 tester입니다. 팀 리드(vwork)의 지시를 기다리세요.")

Task(subagent_type="oh-my-claudecode:qa-tester", model="sonnet",
     team_name="vwork-{WORKLOG_SLUG}", name="vbrowser-agent",
     prompt="당신은 vwork 팀의 vbrowser-agent입니다. 팀 리드(vwork)의 지시를 기다리세요.")
```

참고: 팀원들은 OMC 런타임에서 `/vanalyze`, `/vplan` 등의 스킬 명령을 실행할 수 있다고 가정한다. Claude Code 팀원 서브에이전트는 동일한 스킬 로딩 메커니즘을 갖는다. vwork 오케스트레이터는 팀 리더로 동작하며, 팀원이 결과를 보고할 때 `recipient="vwork"`를 사용한다.

팀 생성 후 `state_write(mode="vwork")`에 `team_name`과 `spawned_agents` 필드를 추가한다:
- `spawned_agents`: 실제 스폰된 팀원 이름 목록. 스폰 조건에 따라 다름:
  - 항상 포함: `["planner", "implementer", "tester"]`
  - `task_type=modification`이면 추가: `"analyzer"`
  - `project_type=frontend/fullstack`이면 추가: `"vbrowser-agent"`
- 이 목록은 Step 0 재수화 시 팀원 생존 여부 확인과 DONE phase shutdown_request 대상 결정에 사용된다.

### 4-S. 세션 라우팅 (session 모드 전용)

이 단계는 `mode = session`인 경우에만 실행된다. Step 3-B 팀 생성 완료 후, ralph loop의 각 반복마다 다음 순서로 처리한다. **session 모드에서 오케스트레이터는 라우터 역할만 수행하며 어떤 요청도 직접 처리하지 않는다.**

**1. 종료 감지 (최우선)**

사용자 메시지에 다음 패턴이 포함된 경우 즉시 세션을 종료한다:
- "종료", "exit vwork", "vwork 종료", "세션 종료", "그만", "끝내", "/vwork exit", "stop"

종료 절차:
1. "vwork 세션이 종료됩니다. 진행 중인 워크로그는 이후 `/vwork`로 재개할 수 있습니다." 출력
2. `state_read(mode="vwork").spawned_agents` 목록의 각 팀원에게 shutdown_request 전송 → 응답 수신 → TeamDelete
3. `state_write(mode="vwork", data={ "active": false })`
4. `**VWORK_SESSION_END**` 출력 (ralph loop 종료 트리거)

**2. 현재 phase 읽기**

`state_read(mode="vwork")`로 `current_phase`를 확인한다.

**3. 요청 분류 및 팀원 라우팅**

아래 규칙에 따라 항상 팀원에게 위임한다 (직접 처리 금지):

| 요청 유형 | 위임 대상 |
|----------|----------|
| 코드 분석, 파일 탐색, 버그 조사, 코드베이스 질문 | `analyzer` (스폰되지 않은 경우 `planner`) |
| 요구사항 정의, PRD, 사용자 스토리 | `planner` |
| 아키텍처 설계, 구현 플랜 | `planner` |
| 코드 구현, 수정, 리팩토링 | `implementer` |
| 테스트 작성, 커버리지 보강 | `tester` |
| 브라우저 E2E 테스트, UI 검증 | `vbrowser-agent` (스폰된 경우; 미스폰 시 `tester`) |
| "계속 진행", "다음 단계", phase 실행 요청 | 현재 phase 담당 팀원 |
| 그 외 모든 요청 | 현재 phase 담당 팀원 |

**현재 phase 담당 팀원 기본 매핑:**

| current_phase | 기본 위임 대상 |
|--------------|--------------|
| ANALYZE | `analyzer` |
| PRD | `planner` |
| PLAN | `planner` |
| IMPL | `implementer` |
| VERIFY | `tester` |
| TEST | `tester` |

**4. SendMessage로 위임**

```
SendMessage(type="message", recipient="{팀원}",
  content="사용자 요청: {사용자 메시지}

  현재 phase: {current_phase}
  워크로그: {WORKLOG_DIR}

  요청을 처리하고 결과를 보고하세요.",
  summary="세션 요청 위임")
```

**5. 팀원 응답 수신 후 처리**

- 응답을 사용자에게 전달한다.
- 팀원이 **phase 완료**를 보고하면 Step 5 Phase 전이 프로토콜에 따라 다음 phase로 자동 전이한다 (사용자 확인 없음).
- phase 전이 후에도 세션은 유지된다. ralph loop이 다음 사용자 메시지를 대기한다.
- phase가 DONE으로 전이되면 위 종료 절차를 수행한다.

### 4. Phase 실행

워크로그의 `phase` 필드를 읽고 해당 phase 스킬을 실행한다.

#### ANALYZE phase

담당 팀원: `analyzer`

`analyzer`에게 ANALYZE 작업을 위임한다:
```
SendMessage(type="message", recipient="analyzer",
  content="ANALYZE phase를 실행하세요.

  작업: /vanalyze {WORKLOG_DIR} 를 실행하고 결과를 보고하세요.
  완료 시 분석 결과 요약과 analysis.md 경로를 반환하세요.",
  summary="ANALYZE phase 위임")
```

`analyzer`로부터 결과 수신 후:
- 분석 결과를 사용자에게 요약 보고
- 사용자 인터랙션이 있으면 결정사항을 `_shared/update-worklog.md`로 기록:
  - `dashboard_updates`: Decisions에 `[CURRENT] {결정사항}`
- 완료 시: `phase: 'PRD'`로 업데이트
- step 모드인 경우:
  ```
  AskUserQuestion:
    question: "분석이 완료되었습니다. PRD(요구사항 정의)로 진행할까요?"
    header: "Phase: ANALYZE → PRD"
    options:
      - label: "진행"
        description: "요구사항 정의를 시작합니다"
      - label: "분석 재실행"
        description: "추가 분석이 필요합니다"
      - label: "PRD 건너뛰기 → 바로 플래닝"
        description: "이미 요구사항이 명확합니다"
  ```
  - "진행": PRD로 계속
  - "분석 재실행": ANALYZE에 머무름
  - "PRD 건너뛰기": `phase: 'PLAN'`으로 업데이트

#### PRD phase

담당 팀원: `planner`

`planner`에게 PRD 작업을 위임한다:
```
SendMessage(type="message", recipient="planner",
  content="PRD phase를 실행하세요.

  작업: /vplan {WORKLOG_DIR} 를 실행하세요 (orchestration state current_phase=PRD에 따라 Stage 1 PRD만 실행).
  완료 시 PRD 결과 요약을 반환하세요.",
  summary="PRD phase 위임")
```

`planner`로부터 결과 수신 후:
- PRD 결과를 사용자에게 요약 보고
- 사용자 인터랙션이 있으면 결정사항을 `_shared/update-worklog.md`로 기록:
  - `dashboard_updates`: Decisions에 `[CURRENT] {결정사항}`
- 완료 시: `phase: 'PLAN'`으로 업데이트
- step 모드인 경우: "구현 플래닝으로 진행할까요?" 질문

#### PLAN phase

담당 팀원: `planner`

`planner`에게 PLAN 작업을 위임한다:
```
SendMessage(type="message", recipient="planner",
  content="PLAN phase를 실행하세요.

  작업: /vplan {WORKLOG_DIR} 를 실행하세요 (orchestration state current_phase=PLAN에 따라 Stages 2-4 + consensus review 실행).
  완료 시 플랜 결과 요약을 반환하세요.",
  summary="PLAN phase 위임")
```

`planner`로부터 결과 수신 후:
- 플랜 결과를 사용자에게 요약 보고
- 사용자 인터랙션이 있으면 결정사항을 `_shared/update-worklog.md`로 기록:
  - `dashboard_updates`: Decisions에 `[CURRENT] {결정사항}`
- 완료 시: `phase: 'IMPL'`로 업데이트
- step 모드인 경우: "구현을 시작할까요?" 질문

#### IMPL phase

담당 팀원: `implementer`

`implementer`에게 IMPL 작업을 위임한다:
```
SendMessage(type="message", recipient="implementer",
  content="IMPL phase를 실행하세요.

  작업: /vimpl {WORKLOG_DIR} 를 실행하고 결과를 보고하세요.
  완료 시 구현 결과 요약을 반환하세요.",
  summary="IMPL phase 위임")
```

`implementer`로부터 결과 수신 후:
- 구현 결과를 사용자에게 요약 보고
- 완료 시: `phase: 'VERIFY'`로 업데이트
- step 모드인 경우: "검증을 시작할까요?" 질문

#### VERIFY phase

담당 팀원: `tester` (기본). 다음 조건을 **모두** 충족하면 `vbrowser-agent`에게도 병행 위임한다:
- `project-params.md`의 `project_type`이 `frontend` 또는 `fullstack`
- `{WORKLOG_DIR}/browser-scenarios.md`가 존재하거나, `{WORKLOG_DIR}/report.md`에 E2E 시나리오가 있음

`tester`에게 VERIFY 작업을 위임한다:
```
SendMessage(type="message", recipient="tester",
  content="VERIFY phase를 실행하세요.

  작업: /vqa {WORKLOG_DIR} 를 실행하고 결과를 보고하세요.
  완료 시 verdict route와 결과 요약을 반환하세요.",
  summary="VERIFY phase 위임")
```

브라우저 테스트가 필요한 경우 `vbrowser-agent`에게도 병행 위임한다:
```
SendMessage(type="message", recipient="vbrowser-agent",
  content="브라우저 E2E 테스트를 실행하세요.

  작업: /vbrowser {WORKLOG_DIR} 를 실행하고 결과를 보고하세요.
  ORCHESTRATED=true, ORCHESTRATION_MODE=auto 로 실행하세요 (Phase 2 사용자 확인 생략, 전체 자동 실행). (vwork state에 이미 기록되어 있으나, 메시지에도 명시하여 안전장치로 활용한다.)
  완료 시 테스트 결과 요약과 pass/fail 수를 반환하세요.",
  summary="브라우저 테스트 위임")
```

각 결과가 도착하는 즉시 `.verify-partial.json`에 기록한다 (tester 또는 vbrowser-agent 순서 무관):
```
# tester 결과 도착 즉시:
Write(file_path="{WORKLOG_DIR}/.verify-partial.json",
  content={
    "tester_route": "{route}", "tester_summary": "{요약}", "tester_received_at": "{timestamp}",
    "vbrowser_result": null, "vbrowser_summary": null, "vbrowser_received_at": null
  })

# vbrowser-agent 결과 도착 즉시 (tester 결과 기존 필드 보존):
Write(file_path="{WORKLOG_DIR}/.verify-partial.json",
  content={ ...기존 tester 필드 보존...,
    "vbrowser_result": "PASS|FAIL|SKIP", "vbrowser_summary": "{요약}", "vbrowser_received_at": "{timestamp}"
  })
```

컴팩션 후 재진입 시 `.verify-partial.json` 처리:
- `tester_route`만 있고 `vbrowser_result=null`인 경우: tester 결과 복구 완료. vbrowser-agent 처리:
  - 팀 config.json이 존재하면 (vbrowser-agent 활성): 이전 요청의 응답이 아직 큐에 있다고 가정하고 대기한다. 30초 이내 응답 없으면 vbrowser-agent에게 "이전 브라우저 테스트 결과를 다시 보고해 주세요"라고 요청한다.
  - 팀 config.json이 없으면 (vbrowser-agent 비활성): tester 결과만으로 통합 verdict를 판정한다.
- 두 결과 모두 있는 경우: 파일에서 읽어 통합 verdict 계산으로 직접 진행한다.

tester와 vbrowser-agent(위임한 경우) **두 결과를 모두 수신한 후** 통합 verdict를 결정한다:
- `{WORKLOG_DIR}/report.md`를 읽는다. `<!-- QA:VERDICT:START -->` 블록을 파싱하여 `route:` 필드를 추출한다.

vbrowser-agent에게도 위임한 경우, 아래 로직으로 통합 verdict를 결정한다:
- tester route가 `code_issues` 또는 `code_issues_and_test_gaps` → tester 결과를 우선 적용 (vbrowser 결과 무관)
- tester route가 `test_gaps` → `test_gaps` 유지 (vbrowser 결과 무관)
- tester route가 `all_pass`이고 vbrowser-agent FAIL → route를 `code_issues`로 격상 (브라우저 이슈로 재구현 필요)
- tester route가 `all_pass`이고 vbrowser-agent PASS (SKIP만 있는 경우 포함) → 최종 route `all_pass`
- vbrowser-agent 결과 판정: FAIL이 하나라도 있으면 FAIL, PASS와 SKIP만 있으면 PASS로 간주한다

통합 verdict 결정 후 `.verify-partial.json`을 삭제한다 (정리):
```bash
rm -f "{WORKLOG_DIR}/.verify-partial.json"
```

최종 verdict `route`에 따른 매핑:
  - **all_pass** (전체 통과): `phase: 'DONE'`으로 업데이트
  - **code_issues 또는 code_issues_and_test_gaps** (Intent/Spec/Architecture NEEDS_WORK, 테스트 갭 동반 여부 무관): `phase: 'IMPL'`로 업데이트 (vqa가 이미 FIX/TEST items를 plan.md에 추가함. code_issues_and_test_gaps인 경우 IMPL 완료 후 VERIFY에서 test_gaps만 남으면 TEST로 진행)
  - **test_gaps** (Test Verification NEEDS_WORK만 해당): `phase: 'TEST'`로 업데이트
- step 모드인 경우: 결과를 제시하고 사용자에게 질문

#### TEST phase

담당 팀원: `tester`

`tester`에게 TEST 작업을 위임한다:
```
SendMessage(type="message", recipient="tester",
  content="TEST phase를 실행하세요.

  작업: /vtest {WORKLOG_DIR} 를 실행하고 결과를 보고하세요.
  완료 시 테스트 결과 요약을 반환하세요.",
  summary="TEST phase 위임")
```

`tester`로부터 결과 수신 후:
- 완료 시: `phase: 'VERIFY'`로 업데이트 (테스트 작성 후 재검증)
- VERIFY ↔ TEST 반복은 Step 6의 전체 피드백 루프 카운터(`feedback_iterations`)로 추적한다. 최대 5회 도달 시 처리는 Step 6 규칙을 따른다.

#### DONE phase

- `/worklog-finish {WORKLOG_DIR}` 호출
- 팀 종료 (`spawned_agents` 목록 기반으로 shutdown_request 전송):
  ```
  # state_read(mode="vwork")에서 spawned_agents를 읽어 각 팀원에게 전송:
  for agent in spawned_agents:
      SendMessage(type="shutdown_request", recipient=agent, content="작업 완료")
  ```
  - `spawned_agents`는 Step 0 재수화 또는 Step 3-B 스폰 시 state에 저장된 목록을 사용한다.
  - 컴팩션 후 재진입으로 인메모리 변수가 유실된 경우에도 `state_read(mode="vwork").spawned_agents`로 복구한다.
  스폰된 팀원 전원의 응답 수신 후 TeamDelete 호출
- 오케스트레이션 컨텍스트 정리: `state_write(mode="vwork", data={ "active": false })` — DONE phase는 최종 정리이므로 상태 보존 규칙의 예외다. active=false만 기록하면 충분하다.
- ralph loop이 활성 상태면 종료: `/oh-my-claudecode:cancel`
- 완료 요약 출력

### 5. Phase 전이 프로토콜

모든 phase 전이는 `_shared/update-worklog.md`를 따른다:
- `phase_update`: `{NEW_PHASE}`
- `dashboard_updates`: 현재 phase를 반영하는 다음 액션
- `timeline_entry`: "Phase 전이: {OLD} → {NEW}"

### 6. 피드백 루프

```
VERIFY → IMPL    (비테스트 이슈: 스펙 이탈, 아키텍처 문제)
VERIFY → TEST    (테스트 갭: 커버리지 부족, 약한 assertion)
TEST   → VERIFY  (테스트 작성 완료, 재검증 필요)
IMPL   → VERIFY  (수정 적용 완료, 재검증 필요)
```

루프당 최대 피드백 반복: 5회. 5회 이후 해결되지 않은 경우:
- **step 모드**: 남은 이슈를 사용자에게 보고. 계속 반복 / 현재 상태 수용 / 중단 중 선택.
- **auto 모드**: 에이전트가 남은 이슈를 평가하고 최선의 판단을 내린다. **판단 결과와 근거를 반드시 워크로그 Dashboard의 Decisions에 기록한다:**
  ```
  - [CURRENT] Feedback loop 종료 (5회 도달) — 근거: {미해결 이슈 요약 + 수용/중단 판단 이유}
  ```
  수용 가능한 수준이면 다음 phase로 진행하고, 치명적 이슈가 남아있으면 사용자에게 보고한다.

### 7. 에러 처리

| 상황 | 처리 |
|------|------|
| 워크로그 미발견 | 에러 출력, `/worklog-start` 안내 |
| phase 필드 비어있음 | 작업 유형 감지 → `ANALYZE` (modification) 또는 `PRD` (new-feature) |
| phase 스킬 실패 | 워크로그에 에러 기록, 사용자에게 질문 |
| ralph loop 활성 상태인데 phase가 DONE | ralph 종료, 워크로그 마무리 |

## 절대 규칙

- **워크로그가 유일한 출처.** 모든 phase는 워크로그에서 읽고 워크로그에 쓴다.
- **phase 필드를 항상 최신으로 유지.** 각 phase 전후에 반드시 업데이트.
- **auto 모드에서 phase를 건너뛰지 않는다.** 전진 전용. 단, 신규 기능은 PRD부터 시작하므로 ANALYZE를 건너뛰는 것이 아니라 시작점이 다른 것이다.
- **step 모드는 건너뛸 수 있다.** 사용자가 PRD 생략이나 phase 점프를 선택할 수 있다.
- **auto 모드는 ralph loop을 활성화한다.** 컨텍스트 윈도우 한계를 넘어 지속성을 보장.
- **step 모드는 항상 질문한다.** 사용자 확인 없이 자동 진행하지 않는다.
- **피드백 루프는 상한이 있다.** 루프당 최대 5회 반복. auto 모드에서 상한 도달 시 판단 근거를 워크로그에 기록.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조
- **세션 모드에서 직접 처리 금지.** `mode = session`인 경우 오케스트레이터는 라우터 역할만 수행한다. 사용자의 모든 요청은 Step 4-S 규칙에 따라 전담 팀원에게 위임해야 하며, 오케스트레이터가 직접 응답하거나 작업을 수행해서는 안 된다. 유일한 예외는 종료 감지이다.

이제 실행하라.
