---
name: vimpl
description: Incremental or auto implementation with TDD, code-simplifier, parallel verification, and ralph loop persistence
argument-hint: 'Usage: /vimpl [worklog-folder-or-worklog.md]'
---

## 경로 규칙

> **`_shared/X`** → `{Base directory}/../_shared/X` (`{Base directory}`는 시스템이 주입하는 "Base directory for this skill" 값)
> **`X` 스킬** → 스킬 시스템이 제공하는 경로. `Glob("**/X/SKILL.md")`로 탐색 가능.

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.local.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `test_command` | 프로젝트 설정에서 탐지 | 테스트 실행 명령 |
| `completion_promise` | `**WORKLOG_TASK_COMPLETE**` | ralph loop 완료 감지용 (OMC 내부) |

TDD, 코드 단순화, 병렬 검증, ralph loop 지속성을 사용하여 플랜 체크리스트를 항목별로 실행하는 구현 워크플로우를 실행한다.

## 정규 단계 테이블 (SSOT)

아래 표가 vimpl의 단계 전이 단일 진실 기준이다.

| 현재 단계 | 완료 조건 | 다음 단계 | 주요 출력 |
|-----------|-----------|----------|----------|
| Step 0 (재수화) | state/plan 교차검증 완료 | 대상 결정 | 복구 컨텍스트 |
| 대상 결정/컨텍스트 | PLAN/TEST/project_type 확정 | 모드 선택 | 실행 컨텍스트 |
| 모드 선택 | mode/state 초기화 완료 | Ralph loop 활성화 | `state(mode=vimpl)` 초기 상태 |
| 병렬 전략 결정 | 병렬/순차 실행 방식 확정 | 구현 루프 | 실행 전략 |
| Step 1 | 항목 이해 완료 | Step 2 | 현재 항목 컨텍스트 |
| Step 2 | Red 테스트 확보 | Step 3 | failing test |
| Step 3 | Green 통과 | Step 4 | 구현 변경 |
| Step 4 | code-simplifier + 회귀 통과 | Step 5 | 정리된 변경 |
| Step 5 | 병렬 검증 통과 | Step 6 | 검증 결과 |
| Step 6 | 승인 완료 | Step 7 | 승인 결과 |
| Step 7 | 스테이징 + 체크박스/워크로그 갱신 | Step 1 또는 완료 | 진행 업데이트 |
| 완료 | 미완료 항목 없음 + 상태 종료 | 종료 | 완료 상태 |

## 0. 상태 재수화 (compaction 복구)

**가장 먼저 실행한다.** `<notepad-context>`에 `vimpl활성`이 보이거나 `state_read(mode="vimpl")`에서 `active=true`이면 compaction 재진입으로 간주한다.

### 감지

- `<notepad-context>`에 `vimpl활성` 텍스트가 존재
- 또는 `state_read(mode="vimpl").active == true`

둘 중 하나라도 해당하면 아래 복구 절차를 따른다. 해당하지 않으면 "대상 결정" 섹션부터 정상 진행.

### 변수 복구

`state_read(mode="vimpl")`를 실행하여 다음 변수를 복원한다:

- `WORKLOG_DIR` = `state.worklog_dir`
- `PLAN_FILE` = `state.plan_file`
- `TEST_COMMAND` = `state.test_command`
- `mode` = `state.mode`
- `project_type` = `state.project_type`
- `cli_type` = `state.cli_type`
- `ORCHESTRATED` = `state.orchestrated`
- `execution_mode` = `state.execution_mode`
- `current_item_index` = `state.current_item_index`
- `current_item_title` = `state.current_item_title`
- `current_step` = `state.current_step`
- `changed_files` = `state.changed_files`
- `test_file` = `state.test_file`
- `verify_retry_count` = `state.verify_retry_count`
- `approval_retry_count` = `state.approval_retry_count`
- `parallel_batch` = `state.parallel_batch`

### 행동 규칙 복구

compaction 후 규칙이 유실될 수 있으므로 SKILL.md에서 두 구간을 읽어 컨텍스트에 복원한다:

1. `Glob(pattern="**/workflow/vimpl/SKILL.md")`로 스킬 파일 경로를 찾는다.
2. `Read`로 다음 구간을 읽는다:
   - **`## 절대 규칙`** 섹션
   - **`### Step {current_step}`** 섹션 — 현재 Step의 구체적 실행 지침

### plan.md 교차 검증

plan.md 체크박스가 진실 기준이다:
- `PLAN_FILE`을 읽어 완료된 항목(`- [x]`) 수를 센다.
- state의 `current_item_index`와 비교하여 불일치하면 plan.md 기준으로 보정한다.
- 불일치 이유: compaction 직전에 plan.md 업데이트는 완료됐지만 state_write가 완료되지 않았을 수 있다.

### Step 재개 분기

| current_step | 파일시스템 검증 | 재개 지점 |
|---|---|---|
| 1 | (읽기만 — 멱등) | Step 1 재시작 |
| 2 | test_file 존재? | 존재 → 테스트 실행 → FAIL이면 Step 3, PASS면 Step 4. 미존재 → Step 2 |
| 3 | TEST_COMMAND 실행 | PASS → Step 4. FAIL → Step 3 계속 |
| 4 | changed_files diff | code-simplifier 재실행 (멱등) → Step 5 |
| 5 | verify_retry_count | <2 → Step 5 재실행. ≥2 → 사용자 보고 |
| 6 | approval_retry_count | auto: review 재실행. incremental: 재질문 |
| 7 | git status | staged → plan 확인 후 다음 항목. 미staged → stage+update |

### 병렬 배치 복구

`parallel_batch.active == true`이면:
1. `mcp__team__omc_run_team_status(team_name="{team_name}")`로 각 job 확인:
   - `running` → 대기 (`mcp__team__omc_run_team_status(team_name="{team_name}")` 재확인)
   - `completed` → 결과 수집
   - `failed` → Claude fallback으로 1회 재시도
2. `post_processing_step`부터 후처리 재개 (code-simplifier → 검증 → 스테이징 → plan 업데이트)

## 대상 결정

- `_shared/resolve-worklog-target.md`를 로드하고 해당 절차를 따른다 (`required_files: ["plan.md"]`).
- `PLAN_FILE` = `{WORKLOG_DIR}/plan.md`
- `PLAN_FILE`이 없으면 중단: "플랜 파일이 없습니다. `/vplan` 으로 먼저 플랜을 작성하세요."
- 테스트 명령 결정: `_shared/resolve-test-command.md`를 로드하고 해당 로직을 따라 `TEST_COMMAND`를 설정한다.

## 오케스트레이션 컨텍스트

- `_shared/orchestration-context.md`를 로드하고 **서브 스킬 — 읽기** 프로토콜을 따른다.
- `ORCHESTRATED=true`인 경우: 아래 모드 선택과 Ralph loop 활성화의 동작이 변경된다.

## 상태 보존 규칙

`_shared/state-preservation-rule.md`를 로드하고 해당 규칙을 따른다. vimpl 추가 규칙:

- `current_item_index`, `current_step`, `verify_retry_count`, `parallel_batch` 등 누적 필드 유실 방지.

## Notepad 라이프사이클

**이중 모드 전략:**
- `ORCHESTRATED=true` → `notepad_write_working` (vwork가 priority notepad 소유)
- standalone → `<remember priority>` (vimpl이 priority 소유)

**템플릿** (standalone 예시):
```
vimpl활성|mode:{mode}|item:{N}|step:{step}
wl:{WORKLOG_DIR}|plan:{PLAN_FILE}|test_cmd:{TEST_COMMAND}

[compaction복구]
1.state_read(mode="vimpl")→변수복구
2.SKILL.md→절대규칙+Step섹션 재읽기
3.plan.md→체크박스 교차검증→Step재개

[절대규칙]
-TDD건너뛰기금지:테스트먼저
-code-simplifier건너뛰기금지
-승인없이진행금지
-커밋금지:git add만
```

**라이프사이클:**

| 시점 | 갱신 내용 |
|------|----------|
| 모드 선택 후 (초기화) | 전체 템플릿 기록 (`item:1\|step:1`) |
| 항목 전이 (Step 7 → Step 1) | `item:{N}` 갱신 |
| Step 전이 | `step:{step}` 갱신 |
| 배치 시작 | `step:parallel\|batch_items:{count}` |
| 배치 후처리 | `step:post_{step_name}` |
| 전체 완료 | standalone: `<remember priority></remember>` (클리어). orchestrated: `notepad_write_working("")` |

## 모드 선택 (세션 유지)

**`ORCHESTRATED=true`이고 `ORCHESTRATION_MODE=auto`인 경우:**
- 자동으로 Auto 모드 선택. 질문 생략.

**`ORCHESTRATED=true`이고 `ORCHESTRATION_MODE=step`인 경우:**
- 자동으로 Incremental 모드 선택. 질문 생략.

**그 외 (독립 실행):**

세션 시작 시 한 번만 질문한다. `<remember priority>vimpl mode: {choice}</remember>`로 전체 세션 동안 선택을 기억한다.

```
AskUserQuestion:
  question: "구현 모드를 선택해주세요."
  header: "Mode"
  options:
    - label: "점진 모드 (Incremental)"
      description: "각 구현 단위마다 유저가 직접 변경사항을 검토하고 승인합니다."
    - label: "자동 모드 (Auto)"
      description: "서브에이전트의 exhaustive-review 컨센서스로 자동 승인합니다."
```

이전 모드 선택이 메모리에 있으면 확인: "이전에 {mode} 모드를 선택하셨습니다. 계속할까요?"

**모드 선택 후 상태 초기화:**

`state_write(mode="vimpl")`로 초기 상태를 기록한다 (상태 보존 규칙 준수):
```json
{
  "active": true,
  "worklog_dir": "{WORKLOG_DIR}",
  "plan_file": "{PLAN_FILE}",
  "test_command": "{TEST_COMMAND}",
  "mode": "{incremental|auto}",
  "orchestrated": "{ORCHESTRATED}",
  "execution_mode": "sequential",
  "current_item_index": 1,
  "current_item_title": "",
  "current_step": 1,
  "parallel_batch": { "active": false },
  "verify_retry_count": 0,
  "approval_retry_count": 0,
  "changed_files": [],
  "test_file": ""
}
```

Notepad 라이프사이클에 따라 초기 notepad를 기록한다 (`item:1|step:1`).

## Ralph loop 활성화

`_shared/ralph-activation.md`를 로드하고 해당 절차를 따른다.

## project_type 감지

`_shared/resolve-project-type.md`를 로드하고 해당 절차를 따른다. 오케스트레이션 컨텍스트에서 설정된 `PROJECT_TYPE` 변수가 있으면 그대로 사용한다.

project_type 결정 후 `state_write(mode="vimpl")`로 `project_type`과 `cli_type`을 갱신한다 (상태 보존 규칙 준수).

## 병렬 구현 전략

플랜 파일을 읽어 미완료 체크리스트 항목들의 **의존성**을 분석한다:

- 서로 다른 파일을 건드리고 의존 관계가 없는 항목 → **병렬 그룹**
- 이전 항목의 결과물(타입, 함수 등)에 의존하는 항목 → **순차 그룹**

**병렬 그룹 처리 (자동 모드):**

의존성 없는 항목이 있으면 CLI 워커를 사용하여 병렬 실행한다. `ORCHESTRATED=true`이고 `cli_type`이 `codex` 또는 `gemini`인 경우, **반드시** 해당 CLI 워커를 사용하여 병렬성을 최대화한다 (Claude fallback 금지).

`_shared/orchestration-context.md`의 **CLI 가용성 결정** 절차에 따라 `CODEX_AVAILABLE`, `GEMINI_AVAILABLE`, `cli_type`을 사용한다.

- `cli_type=codex` → **반드시** 아래 omc-teams MCP 도구(codex) 경로 실행. Claude fallback 전환 금지.
- `cli_type=gemini` → **반드시** 아래 omc-teams MCP 도구(gemini) 경로 실행. Claude fallback 전환 금지.
- `cli_type=claude` → 아래 Claude fallback 경로 실행

> **유일한 예외 — TDD 출력 파싱 실패**: CLI 워커가 `completed`이지만 TDD 출력 형식(`### Red Phase`, `### Green Phase`, `### Refactor Phase`)이 누락된 경우에만 해당 항목을 claude Task(executor, sonnet) fallback으로 1회 재실행한다. 이 예외는 CLI 워커의 형식 비준수에 대한 안전장치이며, 성공적으로 실행된 CLI 워커를 Claude로 대체하는 것은 여전히 금지한다.

**독립 실행 (`ORCHESTRATED=false`):** `_shared/cli-runtime-check.md`를 참조하여 CLI 가용성을 확인한다.

**CLI 라우팅 분기:**

- `project_type=backend` + `CODEX_AVAILABLE=true` → 각 항목을 omc-teams MCP 도구로 실행:
  ```
  mcp__team__omc_run_team_start(count=1, provider="codex", task="{item title}: {아래 task description 형식 참조}")
  # 출력: {"teamName": "{WORKLOG_SLUG}-impl", "jobId": ..., "message": "..."}
  mcp__team__omc_run_team_status(team_name="{WORKLOG_SLUG}-impl")
  ```
- `project_type=frontend` + `GEMINI_AVAILABLE=true` → omc-teams MCP 도구(gemini)로 실행 (동일 패턴, `provider="gemini"`)
- `project_type=fullstack` → claude Task(executor) fallback (v1: 전체 Claude fallback)
- `project_type=cli/library` 또는 CLI 미가용 → 기존 Claude Task(executor)로 실행 (변경 없음)

**CLI 워커 task description 형식** (`_shared/cli-runtime-check.md` 섹션 5 참조):

```
Implement the following checklist item using TDD.

## Checklist Item
{item title, intent, files, test criteria}

## Plan Context
{behavior spec + technical spec from plan.md}

## Relevant Source Files
{current content of files to modify}

## Existing Test Patterns
{1-2 existing test file contents for convention reference}

## TEST_COMMAND
{test command}

## Required Output Format

### Red Phase
- Test file: {path}
- Test command: {command}
- Result: FAIL (expected)

### Green Phase
- Implementation files: {paths}
- Test result: PASS

### Refactor Phase
- Changes: {description}
- Test result: PASS (no regression)

## Testing Rules (MUST follow)
1. Test ONLY externally observable behavior (function input/output, UI state, user-visible results)
2. Do NOT test implementation details (internal refs, private variables, internal call counts)
3. Use mocks/stubs ONLY for external dependencies (APIs, timers, browser APIs) — never mock internal functions of the module under test
4. Do NOT modify implementation to make tests pass by exploiting knowledge of internals — fix the external behavior instead

## Rules
- Write failing test FIRST (Red), then implement (Green), then simplify (Refactor)
- Follow existing naming and code patterns exactly
- Do NOT commit or modify plan.md — the orchestrator handles this after all parallel agents complete
```

**Claude fallback (CLI 미가용 또는 cli/library):**

```
Task(subagent_type="oh-my-claudecode:executor", model="sonnet",
     prompt="
Implement the following checklist item using TDD.

## Checklist Item
{item title, intent, files, test criteria}

## Plan Context
{behavior spec + technical spec from plan.md}

## Relevant Source Files
{current content of files to modify}

## Existing Test Patterns
{1-2 existing test file contents for convention reference}

## TEST_COMMAND
{test command}

## Rules
- Write failing test FIRST (Red), then implement (Green), then simplify (Refactor)
- Test external behavior only — no implementation detail tests
- Follow existing naming and code patterns exactly
- Do NOT commit or modify plan.md — the orchestrator handles this after all parallel agents complete
")
```

병렬 배치 시작 시 `state_write(mode="vimpl")`로 상태를 갱신한다 (상태 보존 규칙 준수):
- `execution_mode` = `"parallel"`
- `parallel_batch` = `{ "active": true, "items": [{batch items}], "completed": [], "in_progress": [{batch items}], "failed": [], "job_ids": {}, "post_processing_step": null }`

Notepad 라이프사이클에 따라 `step:parallel|batch_items:{count}` 갱신.

병렬 실행 완료 후 오케스트레이터가 일괄 처리한다:

1. 각 executor/CLI 워커 결과에서 변경된 파일 목록 수집. 배치 항목 완료 시 `state_write(mode="vimpl")`로 `parallel_batch`의 `in_progress` → `completed`/`failed` 이동 갱신.

1-B. **CLI 워커 TDD 출력 파싱 검증** (CLI 워커 경로에서만):
   - `taskResults[0].output`에서 `### Red Phase`, `### Green Phase`, `### Refactor Phase` 섹션 존재 확인
   - 형식 불일치 시 → 해당 항목을 claude Task(executor, sonnet) fallback으로 재실행 (1회, 라운드 카운트 미소진)
   - 재실행 후에도 실패 → 사용자에게 보고

2. **code-simplifier 실행** (검증 전, CLI/Claude 양 경로 모두):
   ```
   Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
        prompt="Simplify and refactor the recently modified code for clarity and maintainability without changing behavior. Focus on: reducing complexity, improving naming, removing redundancy. Files: {list of all changed files from this batch}")
   ```
   `state_write(mode="vimpl")`로 `parallel_batch.post_processing_step = "code_simplifier"` 갱신. Notepad `step:post_code_simplifier` 갱신.

3. **Step 5 병렬 검증 수행** (커밋 전):
   - 검증 실패 시: 해당 항목의 변경사항을 수정하고 검증을 재실행한다 (최대 2회 재시도)
   - 2회 재시도 후에도 검증을 통과하지 못하면 사용자에게 보고하고 해당 항목 처리 여부를 확인한다
   - 검증 통과 후 다음 단계로 진행한다
   - `state_write(mode="vimpl")`로 `parallel_batch.post_processing_step = "verify"` 갱신. Notepad `step:post_verify` 갱신.

4. `git add {all changed source and test files}` 스테이징. `state_write(mode="vimpl")`로 `parallel_batch.post_processing_step = "staging"` 갱신.
5. plan.md에서 완료된 항목들을 `- [ ]` → `- [x]`로 일괄 업데이트. `state_write(mode="vimpl")`로 `parallel_batch.active = false`, `current_item_index` 진행 갱신.

> **커밋하지 않는다.** 커밋은 유저가 명시적으로 요청할 때만 수행한다.

**순차 그룹 (자동 모드 포함) / 점진 모드:**

자동 모드이더라도 의존성이 있는 순차 그룹 항목은 기존 구현 루프(Step 1~7)를 항목별로 순서대로 실행한다. 병렬 불가 이유(의존성 존재)를 워크로그에 기록한다.

## 구현 루프 (체크리스트 항목별)

플랜 파일을 읽는다. 첫 번째 미완료 항목(`- [ ]`)을 찾는다. 각 항목에 대해 다음을 실행한다:

### Step 1: 단위 이해

체크리스트 항목의 의도, 파일, 테스트 기준을 읽는다. 관련 소스 파일을 읽어 현재 상태를 파악한다.

`state_write(mode="vimpl")`로 상태 갱신 (상태 보존 규칙 준수): `current_item_index`, `current_item_title`, `current_step=1`, `verify_retry_count=0`, `approval_retry_count=0`, `changed_files=[]`, `test_file=""`. Notepad 라이프사이클에 따라 `item:{N}|step:1` 갱신.

### Step 2: TDD — 테스트 먼저 작성 (Red 단계)

구현 코드를 작성하기 전에:

1. **UX/동작 수준 테스트**: 사용자 관점에서 기대 동작을 기술하는 통합 또는 컴포넌트 테스트를 작성한다. 이 테스트는 초기에 FAIL해야 한다.
2. **유닛 테스트**: 구현할 특정 로직에 대한 유닛 테스트를 작성한다. 이 테스트도 초기에 FAIL해야 한다.
3. 테스트를 실행하여 실패 확인 (Red): `{TEST_COMMAND} {test-file}`
4. 테스트를 먼저 작성할 수 없는 경우 (예: 테스트 인프라 미비), 워크로그에 기록하고 구현을 진행하되 즉시 테스트를 추가한다.

테스트 작성 완료 후 `state_write(mode="vimpl")`로 `current_step=3`, `test_file={test-file path}` 갱신. Notepad `step:3` 갱신.

### Step 3: 구현 (Green 단계)

모든 테스트를 통과하는 데 필요한 최소한의 코드를 작성한다:

1. 체크리스트 항목에 기술된 변경사항을 구현한다
2. 테스트를 실행하여 통과 확인 (Green): `{TEST_COMMAND} {test-file}`
3. 테스트가 실패하면 Green이 될 때까지 반복한다.

Green 완료 후 `state_write(mode="vimpl")`로 `current_step=4`, `changed_files={modified file list}` 갱신. Notepad `step:4` 갱신.

### Step 4: 코드 단순화 (Refactor 단계)

> **CLI 워커 경로에서도 이 단계는 반드시 실행한다.** CLI 워커가 구현을 완료한 후에도 code-simplifier는 항상 별도 claude Task()로 실행한다 (CLI 워커 내부에서 수행하지 않음).

1. 수정된 파일에 대해 code-simplifier 에이전트를 실행한다:
   ```
   Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
        prompt="Simplify and refactor the recently modified code for clarity and maintainability without changing behavior. Focus on: reducing complexity, improving naming, removing redundancy. Files: {list}")
   ```
2. 단순화 후 테스트를 다시 실행하여 아무것도 깨지지 않았는지 확인: `{TEST_COMMAND}`
3. 단순화 후 테스트가 실패하면 단순화 변경을 되돌리고 워크로그에 기록한다.

Refactor 완료 후 `state_write(mode="vimpl")`로 `current_step=5` 갱신. Notepad `step:5` 갱신.

### Step 5: 병렬 검증

다음 두 검증을 **병렬로** 실행한다:

**검증 A — 정확성 확인:**
```
Task(subagent_type="oh-my-claudecode:verifier", model="sonnet",
     prompt="Verify this implementation is correct.
     - Checklist item: {item description}
     - Changed files: {list with diffs}
     - Test results: {test output}
     - Check: types, logic, edge cases, test coverage
     IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

**검증 B — 의도 정합성 확인:**
```
Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
     prompt="Cross-verify this implementation against the plan and worklog.
     - Plan item: {checklist item from plan.md}
     - Worklog goal: {from worklog Goal section}
     - Implementation diff: {changes made}
     - Check: Does the implementation match the intent? Missing anything?
     IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

어느 한 검증에서 문제가 발견되면:
- 문제를 수정한다
- 테스트를 재실행한다
- 실패한 검증만 재실행한다 (최대 2회 재시도)
- 재시도 시 `state_write(mode="vimpl")`로 `verify_retry_count` 증가 갱신
- 2회 재시도 후에도 검증을 통과하지 못하면 사용자에게 보고하고 해당 항목 처리 여부를 확인한다

검증 통과 후 `state_write(mode="vimpl")`로 `current_step=6` 갱신. Notepad `step:6` 갱신.

### Step 6: 승인

**사용자에게 설명** (두 모드 모두):
- 어떤 파일이 왜 변경되었는가
- 전체 아키텍처에서 이 변경이 어디에 위치하는가
- 왜 이 특정 변경이 필요했는가

**점진 모드:**
- 설명을 제시하고 AskUserQuestion으로 사용자 승인 대기:
  ```
  AskUserQuestion:
    question: "구현 #{N} 검토: {title}. 승인하시겠습니까?"
    header: "Review"
    options:
      - label: "승인"
        description: "변경사항을 승인하고 다음 항목으로 진행"
      - label: "수정 필요"
        description: "피드백을 주시면 수정 후 다시 검토합니다"
      - label: "롤백"
        description: "이 변경을 되돌립니다"
  ```
- "수정 필요"인 경우: 피드백 반영 → Step 3으로 복귀. `state_write(mode="vimpl")`로 `approval_retry_count` 증가 갱신.
- "롤백"인 경우: `git checkout -- {files}` → 플랜에서 해당 항목을 차단됨으로 표시하고 다음으로 진행

**자동 모드:**
- 변경사항에 대해 exhaustive-review 실행:
  ```
  Task(subagent_type="oh-my-claudecode:code-reviewer", model="opus",
       prompt="Review this implementation change as three personas (Advocate, Surgeon, Challenger).
       Diff: {diff of current checklist item changes}
       Context: {relevant file contents}
       Output: APPROVE or REQUEST_CHANGES with findings.
       IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
  ```
- 최종 권고가 APPROVE이면: 자동 승인
- REQUEST_CHANGES이면:
  - 제안된 수정사항 반영
  - 테스트 재실행
  - 가벼운 검증 재실행
  - `state_write(mode="vimpl")`로 `approval_retry_count` 증가 갱신
  - 2회 반복 후에도 승인되지 않으면 사용자에게 질문으로 폴백

승인 완료 후 `state_write(mode="vimpl")`로 `current_step=7` 갱신. Notepad `step:7` 갱신.

### Step 7: 스테이징 및 완료 표시

1. 이 체크리스트 항목의 변경사항을 스테이징한다:
   ```bash
   git add {changed source files} {changed test files}
   ```
   > **커밋하지 않는다.** 커밋은 유저가 명시적으로 요청할 때만 수행한다.
2. plan.md에서 체크리스트 항목을 완료로 표시: `- [ ]` → `- [x]`
3. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - `dashboard_updates`: 다음 작업, 진행 상황
   - `timeline_entry`: 완료된 작업 + 근거
4. `state_write(mode="vimpl")`로 다음 항목 준비: `current_item_index` 진행, `current_step=1`. Notepad `item:{N+1}|step:1` 갱신.
5. 다음 미완료 항목으로 진행

### 항목 전이 트랜잭션 순서 (고정)

각 항목 완료 시 아래 순서를 고정한다:
1. 테스트/검증 통과 확인
2. `git add` 스테이징
3. `plan.md` 체크박스 갱신
4. 워크로그 업데이트
5. `state_write(mode="vimpl")` + notepad 갱신

## 완료

plan.md의 모든 체크리스트 항목이 완료되면 (`- [x]`):

1. `state_write(mode="vimpl", data={ "active": false })` (상태 보존 규칙의 예외)
2. Notepad 클리어: standalone → `<remember priority></remember>`. orchestrated → `notepad_write_working("")`
3. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - `timeline_entry`: 완료 근거 (모든 항목 완료, 테스트 결과)

**`ORCHESTRATED=true`인 경우:** 여기서 종료. vwork가 다음 phase(VERIFY)를 관리한다.

**그 외 (독립 실행):**

4. 완료 약속 출력: `<promise>{COMPLETION_PROMISE}</promise>`
5. ralph loop 취소: `/oh-my-claudecode:cancel`

## 절대 규칙

- **TDD를 건너뛰지 않는다.** 테스트가 구현 코드보다 먼저 작성된다.
- **code-simplifier를 건너뛰지 않는다.** Green 이후 항상 리팩토링한다.
- **승인 없이 진행하지 않는다.** 점진 모드 = 사용자. 자동 모드 = exhaustive-review 합의.
- **작업을 멈추지 않는다.** Ralph loop이 지속성을 보장한다. 각 반복은 의미 있는 작업을 해야 한다.
- **워크로그를 항상 업데이트한다.** 각 체크리스트 항목 전후에 `_shared/update-worklog.md`를 통해 업데이트한다.
- **모드를 기억한다.** Incremental vs Auto는 한 번 선택하고 유지된다.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조
- **상태를 기록한다.** 모든 Step 전이와 항목 전이 시 `state_write(mode="vimpl")`로 상태 갱신. 상태 보존 규칙 준수.
- **plan.md가 진실 기준이다.** Compaction 복구 시 plan.md 체크박스가 state의 `current_item_index`보다 우선.
- **사용자 명시 요청 없이는 단계 생략/워크플로우 변경 금지.** vimpl이 임의로 Step/TDD/검증/승인 순서를 건너뛰거나 재배치하지 않는다.
- **정규 단계 테이블(SSOT)을 따른다.** 명시된 예외(재수화/병렬 전략/오케스트레이션 분기) 외 전이는 허용하지 않는다.

이제 실행하라.
