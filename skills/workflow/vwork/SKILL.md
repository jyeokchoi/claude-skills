---
name: vwork
description: Unified workflow orchestrator. Single entry point for analyze → PRD → plan → implement → verify → test → finish pipeline, driven by worklog phase.
argument-hint: 'Usage: /vwork [--auto] [worklog-path | task-name | ISSUE-KEY] [brief]'
# --auto: phase 전이를 자동으로 진행. 없으면 step-by-step (사용자 확인 필요).
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용.

워크로그 phase를 기반으로 전체 작업 라이프사이클을 관리하는 통합 오케스트레이터.

## 입력

- 원본 인자: $ARGUMENTS

인자 해석:
- `--auto` 플래그: 자동 모드 활성화 (ralph loop이 모든 phase를 자동 구동)
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

**가장 먼저 실행한다.** 이 단계는 컨텍스트 컴팩션 후 ralph 재진입을 감지하고 인메모리 변수와 행동 규칙을 복구한다. 컴팩션 후 두 가지 자동 복구 소스가 존재한다:
1. `<notepad-context>` — priority notepad. `vwork활성` 텍스트가 보이면 ralph 재진입으로 간주.
2. `<worklog-context>` — PreCompact/SessionStart 훅이 주입한 워크로그 Dashboard, Goal, phase 정보. 이 컨텍스트가 있으면 워크로그를 다시 읽지 않고도 현재 상태를 파악할 수 있다.
두 소스 중 하나라도 보이면 아래 복구 절차를 반드시 따른다.

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

행동 규칙 복구 (compaction 후 규칙 유실 방지):
- `Glob(pattern="**/workflow/vwork/SKILL.md")`로 이 스킬 파일 경로를 찾는다.
- `Read`로 두 구간을 읽어 행동 규칙을 컨텍스트에 복원한다:
  1. **`## 절대 규칙`** 섹션 (파일 끝부분) — 위임 금지, 워크로그 업데이트 등 핵심 행동 규칙
  2. **`#### {current_phase} phase`** 섹션 — 현재 phase의 구체적 실행 지침 (담당 팀원, SendMessage 템플릿 등)
- 이 단계는 priority notepad의 요약 규칙을 보완하여 상세한 행동 지침을 복원하는 역할이다.
- **복원 후 행동 원칙**: 오케스트레이터는 SendMessage로 팀원에게 작업을 위임하는 것만 수행한다. 코드 읽기/수정/분석을 직접 하지 않는다.

phase 일치 검증 (state와 워크로그 동기화):
- 워크로그 파일(`{WORKLOG_DIR}`)의 `phase` 필드를 읽는다.
- 워크로그 `phase`와 state의 `current_phase`가 다른 경우: **워크로그 값을 진실 기준으로 사용**하고 state의 `current_phase`를 워크로그 값으로 갱신한다.
  - 이유: 컴팩션 직전에 워크로그 업데이트는 완료됐지만 state_write가 완료되지 않았을 수 있기 때문이다.
- 일치하거나 워크로그 읽기 실패 시: state 값을 그대로 사용한다.

팀 생존 여부 확인 (좀비 팀 감지 포함):
- `~/.claude/teams/{team_name}/config.json`이 **없으면**: 팀이 종료됨 → **Step 3-B (팀 재생성)로 점프** (Step 3 본체는 건너뜀 — state와 notepad는 이미 존재하므로 팀 재생성만 필요)
- `config.json`이 **존재하면**: 팀원 프로세스의 실제 활성 여부를 검증한다 (config.json 존재만으로는 프로세스 활성을 보장할 수 없다):
  1. config.json의 `members` 배열에서 현재 phase의 필수 팀원이 있는지 확인 (Phase별 필수 멤버 매핑):
     - ANALYZE → `analyzer`
     - PRD, PLAN → `planner`
     - IMPL → `implementer`
     - VERIFY → `qa` (+ `implementer` — 피드백 루프 대비)
     - TEST → `tester`
  2. 필수 팀원이 `members`에 없으면: **TeamDelete → Step 3-B로 점프** (Step 3 본체는 건너뜀 — 팀 재생성만 필요)
  3. 필수 팀원이 `members`에 있으면: 필수 팀원 **전원**에게 ping 전송 (VERIFY처럼 복수인 경우 모두에게 전송):
     ```
     SendMessage(type="message", recipient="{필수팀원}", content="health check — 응답하세요", summary="ping")
     ```
  4. **15초 이내 전원 응답 있으면**: 기존 팀 활성 확인 → **Step 4 (Phase 실행)로 직접 점프**
  5. **15초 이내 응답 없으면**: 좀비 팀 판정 → **TeamDelete → Step 3-B로 점프** (Step 3 본체는 건너뜀 — 팀 재생성만 필요)

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

vwork는 항상 세션 모드로 동작한다. ralph loop이 상시 활성화되어 컴팩션 복원력을 보장하고, 모든 작업은 팀원에게 위임된다. auto와 step의 차이는 **phase 전이 방식**뿐이다:
- **auto**: phase 전이가 자동으로 진행된다.
- **step**: 각 phase 완료 후 사용자에게 다음 단계 진행 여부를 확인한다.

**`--auto` 플래그가 있는 경우:**
- mode = auto 설정
- 출력: "자동 모드 활성화. 완료까지 자동으로 진행합니다."

**`--auto` 플래그가 없는 경우:**

```
AskUserQuestion:
  question: "워크플로우 모드를 선택하세요."
  header: "Mode"
  options:
    - label: "자동 모드 (Auto)"
      description: "모든 페이즈를 자동 진행합니다. 각 단계에서 중요 결정만 물어봅니다."
    - label: "단계별 모드 (Step-by-step)"
      description: "각 페이즈 완료 후 다음 단계 진행 여부를 확인합니다."
```

- "자동 모드": mode = auto
- "단계별 모드": mode = step

**ralph loop 활성화 (auto/step 공통):**

모드 결정 후 ralph loop을 활성화한다:
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

Step 3으로 진행

### 3. 오케스트레이션 컨텍스트

서브 스킬이 오케스트레이션 상태를 인식할 수 있도록 컨텍스트를 기록한다:

- `_shared/orchestration-context.md`를 로드하고 **vwork — 쓰기** 프로토콜을 따른다.
- **상태 보존 규칙**: 이 규칙은 vwork 실행 중 **모든 `state_write(mode="vwork")` 호출**에 적용된다. 호출 전에 반드시 `state_read(mode="vwork")`로 현재 상태를 읽고 기존 필드를 모두 보존한 뒤, 변경할 필드만 덮어쓴다 (`team_name`, `current_phase`, `feedback_iterations` 등 누적 필드 유실 방지). VERIFY→IMPL 또는 VERIFY→TEST 전이 시 `feedback_iterations`를 1 증가시킨다 (IMPL→VERIFY, TEST→VERIFY 전이에서는 증가하지 않음). `code_issues_and_test_gaps` route 처리 시 VERIFY→IMPL(+1) 후 재검증에서 test_gaps가 남아 VERIFY→TEST(+1)가 추가될 수 있으며, 이는 의도된 동작이다 (해당 경로는 최대 2회 소비). 최대 5회 초과 시 사용자에게 보고.
- `state_write(mode="vwork", data={ "active": true, "mode": "{auto|step}", "current_phase": "{phase}", "worklog_dir": "{WORKLOG_DIR}", "worklog_slug": "{WORKLOG_SLUG}", "project_type": "{project_type}", "task_type": "{task_type}", "feedback_iterations": {state_read로 읽은 기존 값, 없으면 0}, "spawned_agents": {state_read로 읽은 기존 값, 없으면 []} })`
  - **`team_name` 참고**: 이 시점에서는 팀이 아직 생성되지 않았으므로 `team_name`을 포함하지 않는다. `team_name`은 Step 3-B에서 팀 생성 후 별도 `state_write`로 추가된다. 상태 보존 규칙에 따라 Step 3-B의 state_write가 이 시점의 필드를 모두 보존하면서 `team_name`을 추가한다.
- **재수화 대상 필드**: `worklog_slug`, `project_type`, `task_type`, `spawned_agents`는 Step 0에서 읽어 변수를 복구하는 용도이므로, 이 값들을 처음 결정하는 시점(Step 1, 2, 3-B)에서 반드시 최신값으로 갱신해야 한다.
- **step 모드 참고**: step 모드에서도 ralph loop이 활성화되므로 Step 0 재수화가 동일하게 동작한다.
- 각 서브 스킬 호출 전에 `current_phase`를 해당 phase로 업데이트한다.
- **Priority notepad 초기 기록**: 오케스트레이션 컨텍스트 설정 후, 컴팩션 복원력을 위해 priority notepad에 핵심 규칙을 기록한다. 이 시점에서 `team_name`은 미정이며 Step 3-B에서 갱신된다:
  ```
  <remember priority>vwork활성|mode:{mode}|phase:{phase}|team:미정
  wl:{WORKLOG_DIR}

  [compaction복구]
  1.state_read(mode="vwork")→변수복구
  2.Glob("**/workflow/vwork/SKILL.md")→Read로 절대규칙+현재phase섹션 재읽기
  3.팀생존확인→phase실행재개

  [절대규칙]
  -실질작업 절대금지:SendMessage로 팀원위임만 수행
  -팀원은 스킬(/vanalyze,/vplan,/vimpl,/vqa,/vtest)을 명시적으로 호출
  -phase전이→워크로그+notepad갱신
  -순서:ANALYZE→PRD→PLAN→IMPL→VERIFY↔IMPL/TEST→DONE</remember>
  ```
  - `{mode}`, `{phase}`, `{WORKLOG_DIR}`는 현재 값으로 치환한다.

### 3-B. 에이전트 팀 생성

vwork는 **Just-in-Time 스폰 + Eager Cleanup** 정책을 따른다. 현재 phase에 필요한 팀원만 스폰하고, phase가 완료되면 더 이상 필요 없는 팀원은 즉시 정리한다. 이는 컨텍스트 윈도우와 리소스를 효율적으로 사용하기 위함이다.

팀 생성 전에 기존 팀이 있는지 확인한다:
- `state_read(mode="vwork")`에서 `team_name` 필드가 있으면:
  - `~/.claude/teams/{team_name}/config.json`이 존재하면: 기존 팀을 재사용하고 TeamCreate를 건너뛴다 (ralph loop 재진입은 같은 세션 내에서 이루어지므로 팀원들은 활성 상태로 간주한다).
  - config.json이 없으면 (팀이 이미 종료/삭제됨): 새 팀을 생성한다 (team_name을 새 값으로 덮어씀).
- `team_name` 필드가 없으면: 아래와 같이 새 팀을 생성한다.

```
TeamCreate(team_name="vwork-{WORKLOG_SLUG}", description="vwork 에이전트 팀 — {GOAL_SUMMARY}")
```

팀 멤버 풀 (전체 역할 정의):

| 역할 | 담당 Phase | subagent_type | model |
|------|-----------|---------------|-------|
| `analyzer` | ANALYZE | oh-my-claudecode:debugger | sonnet |
| `planner` | PRD, PLAN | oh-my-claudecode:planner | opus |
| `implementer` | IMPL | oh-my-claudecode:executor | sonnet |
| `qa` | VERIFY | oh-my-claudecode:verifier | sonnet |
| `tester` | TEST | oh-my-claudecode:test-engineer | sonnet |

참고: 브라우저 E2E 테스트(`/vbrowser`)는 팀원이 아닌, `qa`나 `tester`가 필요 시 내부 서브에이전트로 스폰하여 처리한다.

#### Just-in-Time 스폰 정책

현재 phase에 필요한 팀원만 스폰한다. 이미 `spawned_agents`에 있고 팀 config에 활성 상태이면 재스폰하지 않는다.

| Phase | 스폰 대상 | 비고 |
|-------|----------|------|
| ANALYZE | `analyzer` | task_type=new-feature면 스폰하지 않음 |
| PRD | `planner` | |
| PLAN | `planner` | PRD에서 이미 스폰했으면 재사용 |
| IMPL | `implementer` | |
| VERIFY | `qa` | |
| TEST | `tester` | |

피드백 루프 대비 스폰:
- VERIFY phase에서 `implementer`가 팀에 없으면 추가 스폰한다 (VERIFY→IMPL 피드백 루프 대비).
- TEST phase에서 `implementer`가 팀에 없으면 추가 스폰한다 (TEST→VERIFY→IMPL 가능성 대비).

#### Eager Cleanup 정책

phase 전이 시 이후 phase에서 필요 없는 팀원을 `shutdown_request`로 정리한다.

| Phase 전이 | 정리 대상 | 근거 |
|-----------|----------|------|
| ANALYZE → PRD | `analyzer` | ANALYZE 이후 불필요 |
| PLAN → IMPL | `planner` | PLAN 이후 불필요 |
| VERIFY → DONE | (DONE phase에서 `spawned_agents` 전원 정리) | 모든 작업 완료 |

정리하지 **않는** 경우:
- PRD → PLAN: `planner`는 PLAN에서도 필요하므로 유지
- IMPL → VERIFY: `implementer`는 피드백 루프(VERIFY→IMPL) 대비로 유지
- VERIFY → IMPL: 피드백 루프 진입. `qa`는 유지 (재검증 필요)
- VERIFY → TEST: `qa` 유지 (TEST 완료 후 재검증), `tester` 스폰
- TEST → VERIFY: `tester` 유지 (재투입 가능), `qa` 이미 활성

정리 절차:
```
SendMessage(type="shutdown_request", recipient="{팀원}", content="Phase 완료 — 정리")
```
응답 수신 후 `spawned_agents`에서 제거하고 `state_write`로 갱신한다.

#### 팀원 스폰 템플릿

필요 시 아래 템플릿으로 스폰한다 (현재 phase에 해당하는 팀원만):
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

Task(subagent_type="oh-my-claudecode:verifier", model="sonnet",
     team_name="vwork-{WORKLOG_SLUG}", name="qa",
     prompt="당신은 vwork 팀의 qa입니다. 팀 리드(vwork)의 지시를 기다리세요.")

Task(subagent_type="oh-my-claudecode:test-engineer", model="sonnet",
     team_name="vwork-{WORKLOG_SLUG}", name="tester",
     prompt="당신은 vwork 팀의 tester입니다. 팀 리드(vwork)의 지시를 기다리세요.")
```

참고: 팀원들은 OMC 런타임에서 `/vanalyze`, `/vplan` 등의 스킬 명령을 실행할 수 있다고 가정한다. Claude Code 팀원 서브에이전트는 동일한 스킬 로딩 메커니즘을 갖는다. vwork 오케스트레이터는 팀 리더로 동작하며, 팀원이 결과를 보고할 때 `recipient="vwork"`를 사용한다.

팀 생성 후 `state_write(mode="vwork")`에 `team_name`과 `spawned_agents` 필드를 추가한다 (상태 보존 규칙에 따라 기존 `feedback_iterations` 등 누적 필드를 보존한다):
- `spawned_agents`: 현재 활성 팀원 이름 목록. 스폰 시 append, 정리 시 제거.
- 이 목록은 Step 0 재수화 시 팀원 생존 여부 확인과 DONE phase shutdown_request 대상 결정에 사용된다.
- 스폰 또는 정리 발생 시 즉시 `state_write`로 `spawned_agents`를 갱신한다.
- **Priority notepad 갱신 (team_name 반영)**: 팀 생성 완료 후, Step 3에서 기록한 notepad의 `team:미정`을 실제 `team:{team_name}`으로 교체하여 전체 템플릿을 `<remember priority>...</remember>`로 다시 출력한다.

### 4-S. 세션 라우팅 (사용자 자유 요청 처리)

ralph loop의 각 반복에서 사용자가 phase 실행이 아닌 자유 요청을 보낸 경우, 이 단계에 따라 적절한 팀원에게 라우팅한다. **오케스트레이터는 라우터 역할만 수행하며 어떤 요청도 직접 처리하지 않는다.**

**1. 요청 분류 및 팀원 라우팅**

아래 규칙에 따라 항상 팀원에게 위임한다 (직접 처리 금지):

| 요청 유형 | 위임 대상 |
|----------|----------|
| 코드 분석, 파일 탐색, 버그 조사, 코드베이스 질문 | `analyzer` (스폰되지 않은 경우 현재 phase 담당 팀원) |
| 요구사항 정의, PRD, 사용자 스토리 | `planner` |
| 아키텍처 설계, 구현 플랜 | `planner` |
| 코드 구현, 수정, 리팩토링 | `implementer` |
| 테스트 작성, 커버리지 보강 | `tester` |
| 검증, QA, 코드 리뷰 | `qa` |
| "계속 진행", "다음 단계", phase 실행 요청 | Step 4 Phase 실행으로 진행 |
| 그 외 모든 요청 | 현재 phase 담당 팀원 |

**현재 phase 담당 팀원 기본 매핑:**

| current_phase | 기본 위임 대상 |
|--------------|--------------|
| ANALYZE | `analyzer` |
| PRD | `planner` |
| PLAN | `planner` |
| IMPL | `implementer` |
| VERIFY | `qa` |
| TEST | `tester` |

위임 대상 팀원이 아직 스폰되지 않은 경우, Step 3-B의 JIT 스폰 정책에 따라 먼저 스폰한 후 위임한다.

**2. SendMessage로 위임**

```
SendMessage(type="message", recipient="{팀원}",
  content="사용자 요청: {사용자 메시지}

  현재 phase: {current_phase}
  워크로그: {WORKLOG_DIR}

  요청을 처리하고 결과를 보고하세요.",
  summary="세션 요청 위임")
```

**3. 팀원 응답 수신 후 처리**

- 응답을 사용자에게 전달한다.
- 팀원이 **phase 완료**를 보고하면 Step 5 Phase 전이 프로토콜에 따라 다음 phase로 전이한다 (auto 모드: 자동 전이, step 모드: 사용자 확인 후 전이).
- phase 전이 후에도 세션은 유지된다. ralph loop이 다음 반복을 계속한다.

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

담당 팀원: `qa`

`qa`에게 VERIFY 작업을 위임한다:
```
SendMessage(type="message", recipient="qa",
  content="VERIFY phase를 실행하세요.

  작업: /vqa {WORKLOG_DIR} 를 실행하고 결과를 보고하세요.
  완료 시 verdict route와 결과 요약을 반환하세요.",
  summary="VERIFY phase 위임")
```

`qa`로부터 결과 수신 후:
- `{WORKLOG_DIR}/report.md`를 읽는다. `<!-- QA:VERDICT:START -->` 블록을 파싱하여 `route:` 필드를 추출한다.

verdict `route`에 따른 매핑:
  - **all_pass** (전체 통과): `phase: 'DONE'`으로 업데이트
  - **code_issues 또는 code_issues_and_test_gaps** (Intent/Spec/Architecture NEEDS_WORK, 테스트 갭 동반 여부 무관): `phase: 'IMPL'`로 업데이트 (vqa가 이미 FIX/TEST items를 plan.md에 추가함. code_issues_and_test_gaps인 경우 IMPL 완료 후 VERIFY에서 test_gaps만 남으면 TEST로 진행)
  - **test_gaps** (Test Verification NEEDS_WORK만 해당): `phase: 'TEST'`로 업데이트
- step 모드인 경우: 결과를 제시하고 사용자에게 질문

참고: 브라우저 E2E 테스트가 필요한 경우, `qa`가 `/vqa` 실행 중 내부적으로 서브에이전트를 스폰하여 `/vbrowser`를 실행한다. vwork 오케스트레이터가 직접 브라우저 테스트를 위임하지 않는다.

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
- Priority notepad 정리: `<remember priority></remember>` (빈 내용)을 출력하여 vwork 관련 priority context를 클리어한다.
- 완료 요약 출력

### 5. Phase 전이 프로토콜

모든 phase 전이는 `_shared/update-worklog.md`를 따른다:
- `phase_update`: `{NEW_PHASE}`
- `dashboard_updates`: 현재 phase를 반영하는 다음 액션
- `timeline_entry`: "Phase 전이: {OLD} → {NEW}"
- **Priority notepad 갱신**: phase 전이 완료 후, priority notepad의 `phase:{OLD}`를 `phase:{NEW}`로 교체하여 전체 템플릿을 `<remember priority>...</remember>`로 다시 출력한다. 워크로그 업데이트 → notepad 갱신 → state_write 순서를 지킨다.

**팀원 Lifecycle 관리 (phase 전이 시 반드시 수행):**

phase 전이가 확정된 후, Step 3-B의 Eager Cleanup 정책과 Just-in-Time 스폰 정책에 따라 아래를 순차 실행한다:

1. **Cleanup**: 이후 phase에서 불필요한 팀원에게 `shutdown_request` 전송. 응답 수신 후 `spawned_agents`에서 제거.
2. **Spawn**: 다음 phase에 필요한 팀원이 `spawned_agents`에 없으면 Step 3-B 템플릿으로 스폰. `spawned_agents`에 append.
3. **State 갱신**: `state_write(mode="vwork")`로 `spawned_agents`와 `current_phase`를 갱신.

전이별 실행 요약:

| 전이 | Cleanup | Spawn |
|------|---------|-------|
| ANALYZE → PRD | `analyzer` 정리 | `planner` 스폰 |
| PRD → PLAN | (없음) | (planner 재사용) |
| PLAN → IMPL | `planner` 정리 | `implementer` 스폰 |
| IMPL → VERIFY | (implementer 유지) | `qa` 스폰 |
| VERIFY → IMPL | (없음) | (implementer 이미 활성) |
| VERIFY → TEST | (없음) | `tester` 스폰 |
| TEST → VERIFY | (없음) | (qa, tester 이미 활성) |
| VERIFY → DONE | (DONE phase에서 `spawned_agents` 전원 정리) | (없음) |

### 6. 피드백 루프

```
VERIFY → IMPL    (비테스트 이슈: 스펙 이탈, 아키텍처 문제, 소스 코드 수정 필요)
VERIFY → TEST    (테스트 갭: 커버리지 부족, 약한 assertion)
VERIFY ⟳ VERIFY  (trivial test fix: 테스트 파일만 수정, 변경 < 20줄 → qa가 VERIFY 내에서 수정+재검증)
TEST   → VERIFY  (테스트 작성 완료, 재검증 필요)
IMPL   → VERIFY  (수정 적용 완료, 재검증 필요)
```

Trivial test fix 경로:
- VERIFY verdict가 `code_issues` 또는 `code_issues_and_test_gaps`일 때, 이슈 목록을 평가한다.
- 수정 대상이 **테스트 파일만**이고 **변경 < 20줄**이면: qa에게 수정 + 재검증을 위임한다 (IMPL 전이 없이 VERIFY 내에서 처리). 테스트 파일이란 `*.test.{ts,tsx,js,jsx}`, `*.spec.{ts,tsx,js,jsx}`, `__tests__/` 디렉토리 내 파일을 의미한다. 테스트 헬퍼, fixture, mock, config 파일은 소스 코드와 동일하게 IMPL 전이를 거친다.
- 이 경우에도 `feedback_iterations` 카운터를 1 증가시킨다 (루프 상한 추적).
- 소스 코드 수정이 필요한 경우는 반드시 IMPL 전이.

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
- **auto/step 모두 ralph loop을 활성화한다.** 컨텍스트 윈도우 한계를 넘어 지속성을 보장.
- **step 모드는 항상 질문한다.** 사용자 확인 없이 자동 진행하지 않는다.
- **피드백 루프는 상한이 있다.** 루프당 최대 5회 반복. auto 모드에서 상한 도달 시 판단 근거를 워크로그에 기록.
- **오케스트레이터는 실행하지 않는다.** 코드 분석, 구현, 테스트, 리뷰 등 실질적인 모든 작업은 반드시 팀원에게 `SendMessage`로 위임한다. 메인 에이전트가 `Read`/`Edit`/`Write`/`Bash`로 직접 코드를 읽거나 수정하는 것은 **금지**된다. 유일한 예외는 워크로그 파일 읽기, state/notepad 관리, 그리고 Step 0 행동 규칙 복구를 위한 SKILL.md 읽기뿐이다.
- **팀원은 반드시 스킬을 명시적으로 사용한다.** 각 phase의 팀원은 해당 스킬(`/vanalyze`, `/vplan`, `/vimpl`, `/vqa`, `/vtest`)을 호출하여 작업을 수행해야 한다. 스킬 없이 임의로 작업하는 것은 금지된다. 브라우저 E2E 테스트(`/vbrowser`)는 `qa`나 `tester`가 필요 시 내부 서브에이전트로 스폰하여 처리한다.
- **위임 정책을 준수한다** — `_shared/delegation-policy.md` 참조
- **사용자 자유 요청도 직접 처리 금지.** ralph loop 중 사용자가 phase 실행과 무관한 요청을 보낸 경우에도 Step 4-S 규칙에 따라 전담 팀원에게 위임해야 하며, 오케스트레이터가 직접 응답하거나 작업을 수행해서는 안 된다.

이제 실행하라.
