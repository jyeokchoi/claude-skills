---
name: vqa
description: Parallel QA verification with team-based research, report generation, and feedback loop
argument-hint: 'Usage: /vqa [worklog-folder-or-worklog.md]'
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `base_branch` | auto-detect | diff 기준 브랜치 |
| `test_command` | 프로젝트 설정에서 탐지 | 테스트 실행 명령 |
| `shared_types_dir` | (없음) | 공유 타입 디렉토리 |
| `timestamp_suffix` | (없음) | 타임스탬프 뒤 문자열 (예: KST) |

병렬 서브에이전트로 구현 정확성을 검증하고 사용자 검토를 위한 보고서를 생성하는 종합 QA 검증 워크플로우를 실행한다.

## 정규 단계 테이블 (SSOT)

아래 표가 vqa의 단계 전이 단일 진실 기준이다.

| 현재 단계 | 완료 조건 | 다음 단계 | 주요 출력 |
|-----------|-----------|----------|----------|
| 대상 결정/컨텍스트 | PLAN/REPORT/QA_CONTEXT 확정 | Phase 1 | 검증 컨텍스트 |
| Phase 1 (수집) | worklog/plan/diff/test 결과 수집 완료 | Phase 2 | `QA_CONTEXT` |
| Phase 2 (병렬 리서치) | 에이전트 결과 수집 완료 | Phase 3 | Agent 1~4(+5) 결과 |
| Phase 3 (보고서 합성) | `report.md` 작성 완료 | Phase 3.5 | QA 보고서 |
| Phase 3.5 (route 감지) | verdict 블록 생성 완료 | Phase 4 | `route` |
| Phase 4 (검토/루프) | action handler 적용 완료 | 종료 또는 다음 액션 | 인계/수정 지시 |

route 우선순위 계약:
- `all_pass`: 모든 차원 PASS
- `test_gaps`: test 차원 NEEDS_WORK, intent/spec/architecture 차원은 모두 PASS
- `code_issues`: intent/spec/architecture 차원 NEEDS_WORK, test 차원 PASS
- `code_issues_and_test_gaps`: test 차원 NEEDS_WORK + intent/spec/architecture 차원 NEEDS_WORK

## 대상 결정

- `_shared/resolve-worklog-target.md`를 로드하고 해당 절차를 따른다 (`required_files: ["plan.md"]`).
- `PLAN_FILE` = `{WORKLOG_DIR}/plan.md`
- `REPORT_FILE` = `{WORKLOG_DIR}/report.md`
- `PLAN_FILE`이 없으면 중단: "플랜 파일이 없습니다."
- worklog.md와 plan.md를 읽어 작업 목표, 완료 기준, 구현 체크리스트를 파악한다.

## 오케스트레이션 컨텍스트

- `_shared/orchestration-context.md`를 로드하고 **서브 스킬 — 읽기** 프로토콜을 따른다.
- `ORCHESTRATED=true`인 경우: Phase 4에서 자동 분류 결과에 따라 action handler만 자동 선택/적용하고 종료한다 (유저 질문 생략, 서브 스킬 체이닝 없음).

**CLI 가용성 확인:** `_shared/orchestration-context.md`의 **CLI 가용성 결정** 절차에 따라 `CODEX_AVAILABLE`을 설정한다.

## Phase 1: 컨텍스트 수집 (orchestrator)

병렬 리서치 에이전트에 필요한 시드 컨텍스트를 수집한다. 에이전트는 Read/Glob/Grep으로 직접 코드를 탐색할 수 있으므로, 핵심 컨텍스트와 탐색 시작점을 준비한다.

1. **워크로그 컨텍스트**: worklog.md 읽기 — 목표, 완료 기준, 결정사항, 타임라인 항목
2. **플랜 컨텍스트**: plan.md 읽기 — 요구사항, 동작 명세, 완료 상태가 포함된 전체 체크리스트
3. **코드 컨텍스트**:
   - 기준 브랜치 결정: `_shared/resolve-base-branch.md`를 로드하고 해당 로직을 따라 `BASE_REF`를 설정한다.
   - `git diff {BASE_REF}...HEAD --stat`으로 변경된 파일 목록 파악
   - `git diff {BASE_REF}...HEAD`로 전체 diff 확인
4. **테스트 컨텍스트**:
   - 변경 파일 근처의 테스트 파일 경로 탐색 (`Glob`으로 `*.test.*`, `*.spec.*` 검색)
   - 테스트 명령 결정: `_shared/resolve-test-command.md`를 로드하고 해당 로직을 따라 `TEST_COMMAND`를 설정한다. 실행: `{TEST_COMMAND}`. 결과 캡처.

이를 에이전트 프롬프트용 `QA_CONTEXT` 블록으로 조합한다. 여기에는 워크로그, 플랜, diff, 테스트 실행 결과, 변경/테스트 파일 경로 목록이 포함된다.

## Phase 2: 병렬 리서치 (4+1 에이전트)

4개 Claude 검증 에이전트를 **병렬로** 실행한다. `CODEX_AVAILABLE=true`이면 Codex 크로스 검증 에이전트를 추가로 병렬 실행한다:

### Agent 1: Intent Verification (워크로그 기반 의도 검증)

```
Task(subagent_type="oh-my-claudecode:critic", model="sonnet",
     prompt="
Read-only 검증 에이전트. Read, Glob, Grep으로 코드를 직접 탐색할 수 있다. Write, Edit, Bash는 사용하지 않는다.

You are verifying that the implementation matches the INTENDED behavior from the worklog.

## Your Task
Compare the worklog's stated goal and completion criteria against what was actually implemented.
Use Read tool to examine changed files in detail beyond the diff.

## Check
- Does each completion criterion have corresponding code changes?
- Are there implementation decisions that deviate from the worklog's stated intent?
- Were any goals partially implemented or missed entirely?
- Do the timeline entries accurately reflect what was done?

## Worklog
{worklog content}

## Code Changes
{diff + changed file paths}

## Output Format
### Intent Alignment Score: {1-5}/5
### Findings
- [MET/PARTIAL/MISSED] {criterion} — {evidence with file:line references}
### Gaps
- {any missing implementations}
### Verdict: PASS / NEEDS_WORK
")
```

### Agent 2: Spec Verification (플랜 기반 동작/스펙 검증)

```
Task(subagent_type="oh-my-claudecode:code-reviewer", model="sonnet",
     prompt="
Read-only 검증 에이전트. Read, Glob, Grep으로 코드를 직접 탐색할 수 있다. Write, Edit, Bash는 사용하지 않는다.

You are verifying that the implementation correctly fulfills the plan's specifications.

## Your Task
Compare the plan's requirements, behavior spec, and UI spec against the actual implementation.
Use Read tool to examine implementation files referenced in the diff.

## Check
- Does each requirement have corresponding implementation?
- Does the behavior match the behavior spec (user flows, edge cases, error states)?
- Does the UI match the UI spec (components, layout, interactions)?
- Are all checklist items properly implemented (not just checked off)?
- Any spec items that were implemented differently than planned? Is the deviation justified?

## Plan
{plan content}

## Code Changes
{diff + changed file paths}

## Output Format
### Spec Compliance Score: {1-5}/5
### Checklist Audit
- [CORRECT/INCOMPLETE/DEVIATED] Item #{N}: {title} — {evidence with file:line references}
### Behavior Gaps
- {missing or incorrect behaviors}
### Verdict: PASS / NEEDS_WORK
")
```

### Agent 3: Test Verification (테스트 커버리지/올바름 검증)

```
Task(subagent_type="oh-my-claudecode:analyst", model="sonnet",
     prompt="
Read-only 검증 에이전트. Read, Glob, Grep으로 코드를 직접 탐색할 수 있다. Write, Edit, Bash는 사용하지 않는다.

You are verifying test coverage and correctness for the implementation.

## Your Task
Evaluate whether the tests adequately cover the implementation and are themselves correct.
Use Read tool to examine test files and implementation files in detail.

## Check
- Do tests cover all behavior spec items (happy path + edge cases)?
- Are there untested code paths in the changed files?
- Are the test assertions meaningful (not just 'does not throw')?
- Do tests verify the RIGHT things (behavior, not implementation details)?
- Are there missing test categories (unit, integration, error cases)?
- Are existing tests still valid after the changes?

## Test Files
{test file paths — Read로 상세 확인}

## Test Results
{test run output}

## Implementation
{diff + changed file paths}

## Plan (for coverage reference)
{behavior spec + checklist items}

## Output Format
### Coverage Score: {1-5}/5
### Coverage Map
- {behavior} → {test file:test name} / MISSING
### Test Quality Issues
- [SEVERITY] {issue description}
### Missing Tests
- {what should be tested but isn't}
### Verdict: PASS / NEEDS_WORK
")
```

### Agent 4: Architecture Verification (코드 아키텍처/정합성 검증)

```
Task(subagent_type="oh-my-claudecode:architect", model="opus",
     prompt="
Read-only 검증 에이전트. Read, Glob, Grep으로 코드를 직접 탐색할 수 있다. Write, Edit, Bash는 사용하지 않는다.

You are verifying that the implementation is architecturally sound and consistent.

## Your Task
Evaluate the code changes for architectural quality, consistency with codebase patterns, and long-term maintainability.
Use Read tool to examine changed files and surrounding code for pattern comparison.

## Check
- Does the implementation follow existing codebase patterns and conventions?
- Are module boundaries respected? Any leaking abstractions?
- Is the code consistent with the project's type system? (branded types, shared types if applicable — check shared_types_dir from project settings if available)
- Are there performance concerns (unnecessary re-renders, N+1 queries, etc.)?
- Is error handling appropriate?
- Any security concerns?
- Is the change backward-compatible where needed?

## Code Changes
{diff + changed file paths}

## Output Format
### Architecture Score: {1-5}/5
### Findings
- [SEVERITY] {finding} — {file:line} — {recommendation}
### Pattern Violations
- {where the code diverges from established patterns}
### Verdict: PASS / NEEDS_WORK
")
```

### Agent 5: Codex Cross-Verification (CODEX_AVAILABLE=true 시만)

`CODEX_AVAILABLE=false`이면 이 에이전트를 건너뛴다.

Agent 1-4와 **병렬로** Codex CLI 워커를 실행하여 독립적 크로스 검증을 수행한다:

```
ToolSearch(query="+omc_run_team_start")
mcp__plugin_oh-my-claudecode_team__omc_run_team_start({
  "teamName": "{WORKLOG_SLUG}-qa-codex-xverify",
  "agentTypes": ["codex"],
  "tasks": [{
    "subject": "QA 크로스 검증",
    "description": "
You are an independent cross-verifier. Analyze the implementation from a fresh perspective.

## Your Task
Independently verify the implementation against the worklog goals and plan spec.
Focus on issues that might be missed by individual dimension-focused reviewers.

## Check ALL dimensions:
1. **Intent**: Does the implementation match the worklog's stated goals?
2. **Spec**: Does it fulfill the plan's requirements and behavior spec?
3. **Tests**: Are tests adequate and correct?
4. **Architecture**: Is the code consistent with codebase patterns?
5. **Cross-cutting**: Are there issues that span multiple dimensions?

## Worklog
{worklog content}

## Plan
{plan content}

## Code Changes
{diff}

## Test Results
{test run output}

## Changed File Paths
{changed file paths}

## Test File Paths
{test file paths}

## Required Output Format
### Cross-Verification Score: {1-5}/5
### Findings
| # | Dimension | Severity | Finding | Suggestion |
|---|-----------|----------|---------|------------|

### Unique Insights
{issues not likely caught by single-dimension reviewers}

### Verdict: PASS / NEEDS_WORK
"
  }],
  "cwd": "{cwd}"
})
mcp__plugin_oh-my-claudecode_team__omc_run_team_wait({"job_id": "{jobId}"})
mcp__plugin_oh-my-claudecode_team__omc_run_team_cleanup(
  {"job_id": "{jobId}"}
)
```

- completed → `CODEX_XVERIFY` 결과로 저장, Phase 3에서 병합
- failed/timeout → silent skip (4개 Claude 결과만 사용)

## Phase 3: 보고서 합성

모든 에이전트가 완료되면 `REPORT_FILE`에 발견사항을 합산한다 (Codex 포함 시 5개, 미포함 시 4개):

```markdown
# QA Report: {task-name}

**Date:** {timestamp}{timestamp_suffix if configured}
**Worklog:** {worklog path}
**Plan:** {plan path}

## Summary

| Dimension | Score | Verdict |
|-----------|-------|---------|
| Intent Alignment | {1-5}/5 | {PASS/NEEDS_WORK} |
| Spec Compliance | {1-5}/5 | {PASS/NEEDS_WORK} |
| Test Coverage | {1-5}/5 | {PASS/NEEDS_WORK} |
| Architecture | {1-5}/5 | {PASS/NEEDS_WORK} |
| Codex Cross-Verification | {1-5}/5 | {PASS/NEEDS_WORK/SKIPPED} |
| **Overall** | **{avg}/5** | **{PASS/NEEDS_WORK}** |

## Critical Findings (action required)

{CRITICAL and HIGH severity findings from all agents, deduplicated}

## Recommendations

{MEDIUM findings and improvement suggestions}

## Positive Highlights

{Things done well, noted by agents}

## Detailed Agent Reports

### Intent Verification
{Agent 1 full output}

### Spec Verification
{Agent 2 full output}

### Test Verification
{Agent 3 full output}

### Architecture Verification
{Agent 4 full output}

### Codex Cross-Verification
{Agent 5 full output — CODEX_AVAILABLE=false이면 "SKIPPED: Codex CLI 미사용"}
```

## Phase 3.5: 피드백 경로 자동 감지

사용자에게 제시하기 전에 에이전트 평결을 분석하여 자동 분류한다 (Codex 결과 포함, SKIPPED이면 제외):

- **code_issues_and_test_gaps**: test 차원 NEEDS_WORK **그리고** intent/spec/architecture 차원도 NEEDS_WORK
- **test_gaps**: test 차원 NEEDS_WORK **그리고** intent/spec/architecture 차원은 모두 PASS
- **code_issues**: test 차원 PASS **그리고** intent/spec/architecture 차원 중 하나 이상 NEEDS_WORK
- **all_pass**: 모든 에이전트 평결이 PASS (Codex 포함, SKIPPED인 경우 4개만)

이 분류에 따라 Phase 4에서 제시되는 옵션이 결정된다.

vwork의 기계 판독 파싱을 위해 보고서 끝에 구조화된 평결을 추가한다:

```markdown
<!-- QA:VERDICT:START -->
intent: {PASS|NEEDS_WORK}
spec: {PASS|NEEDS_WORK}
test: {PASS|NEEDS_WORK}
architecture: {PASS|NEEDS_WORK}
codex_cross: {PASS|NEEDS_WORK|SKIPPED}
overall: {PASS|NEEDS_WORK}
route: {all_pass|test_gaps|code_issues|code_issues_and_test_gaps}
<!-- QA:VERDICT:END -->
```

verdict 계약(엄격):
- `route`는 정확히 1개여야 한다.
- 허용 값은 위 4개(`all_pass`, `test_gaps`, `code_issues`, `code_issues_and_test_gaps`)만 가능하다.
- 누락/다중/미지 값이면: action handler 실행 금지, 워크로그에 에러 기록 후 사용자에게 질문한다.

## Phase 4: 사용자 검토 및 피드백 루프

1. 사용자에게 보고서 요약 제시
2. `REPORT_FILE`에 보고서 작성

**`ORCHESTRATED=true`이고 `ORCHESTRATION_MODE=auto`인 경우:**

유저 질문을 생략하고 자동 분류 결과에 따라 **action handler만 자동 선택/적용**한다 (서브 스킬 체이닝 없이 여기서 종료):
- **all_pass** → "통과 (Pass)" action handler 실행
- **test_gaps** → "테스트 작성 (/vtest)" action handler 실행
- **code_issues** → "코드 수정 (/vimpl)" action handler 실행
- **code_issues_and_test_gaps** → "코드 수정 + 테스트 (/vimpl → /vtest)" action handler 실행

**그 외:**

3. 자동 분류 결과에 따라 옵션 제시:

### all_pass인 경우:

```
AskUserQuestion:
  question: "모든 검증을 통과했습니다. 완료할까요?"
  header: "QA Result: ALL PASS"
  options:
    - label: "통과 (Pass)"
      description: "작업을 완료합니다."
    - label: "추가 검증"
      description: "특정 영역을 더 깊이 검증합니다."
```

### test_gaps가 감지된 경우 (code_issues 없음):

```
AskUserQuestion:
  question: "테스트 커버리지 갭이 발견되었습니다. 어떻게 진행할까요?"
  header: "QA Result: TEST GAPS"
  options:
    - label: "테스트 작성 (/vtest)"
      description: "누락 테스트를 작성한 후 재검증합니다."
    - label: "코드 수정 + 테스트 (/vimpl → /vtest)"
      description: "코드 이슈 수정 후 테스트도 작성합니다."
    - label: "수동 처리"
      description: "피드백을 직접 지정합니다."
```

### code_issues만 있는 경우 (test_gaps 없음):

```
AskUserQuestion:
  question: "구현 이슈가 발견되었습니다. 수정할까요?"
  header: "QA Result: NEEDS WORK"
  options:
    - label: "코드 수정 (/vimpl)"
      description: "이슈를 플랜에 추가하고 수정합니다."
    - label: "수동 처리"
      description: "피드백을 직접 지정합니다."
    - label: "무시하고 통과"
      description: "현재 상태로 완료합니다."
```

### Action handlers:

**"통과 (Pass)":**
- `_shared/update-worklog.md`를 통해 워크로그 업데이트:
  - `dashboard_updates`: 완료 확인
  - `timeline_entry`: "QA 검증 통과"
- 출력: "QA 검증이 완료되었습니다."

**"테스트 작성 (/vtest)":**
- Agent 3 + Codex (Agent 5, 해당 시) 보고서에서 테스트 갭 항목 추출
- `_shared/update-worklog.md`를 통해 워크로그 업데이트:
  - `dashboard_updates`: 테스트 갭 항목
- 출력: "테스트 갭이 식별되었습니다. `/vtest {WORKLOG_DIR}` 로 테스트를 작성하세요."
- `ORCHESTRATED=true`인 경우: 여기서 종료. vwork가 report verdict를 읽고 phase 전이를 관리한다.

**"코드 수정 (/vimpl)":**
- Agent 1/2/4 + Codex (Agent 5, 해당 시) 보고서에서 테스트 외 이슈 항목 추출
- plan.md에 새로운 미완료 체크리스트 항목으로 추가:
  ```
  - [ ] **FIX-{N}. {title}** [from:vqa]
    - Source: {agent name} — {finding description}
    - Intent: {what needs to change and why}
    - Files: {affected files}
    - Test: {verification method}
  ```
- `_shared/update-worklog.md`를 통해 워크로그 업데이트:
  - `dashboard_updates`: 플랜에 추가된 피드백 항목
- 출력: "피드백이 플랜에 추가되었습니다. `/vimpl {WORKLOG_DIR}` 로 수정하세요."
- `ORCHESTRATED=true`인 경우: 여기서 종료. vwork가 report verdict를 읽고 phase 전이를 관리한다.

**"코드 수정 + 테스트 (/vimpl → /vtest)":**
- Agent 1/2/4 + Codex (Agent 5, 해당 시)에서 테스트 외 이슈 추출
- 테스트 외 이슈만 plan.md에 `FIX-{N}` 체크리스트 항목으로 추가 (위와 동일한 형식)
- 테스트 갭은 plan.md에 추가하지 **않는다** — report.md에만 기록되며, vtest가 Source 1(report.md)에서 읽어 처리한다. plan.md에 TEST-N 항목을 추가하면 vimpl이 IMPL phase에서 소화하여 TEST phase가 dead path가 되므로 금지.
- `_shared/update-worklog.md`를 통해 워크로그 업데이트:
  - `dashboard_updates`: 플랜에 추가된 코드 수정 항목 + 테스트 갭 요약 (report.md 참조)
- 출력: "코드 수정 항목이 플랜에 추가되었습니다. 테스트 갭은 report.md에 기록되어 TEST phase에서 처리됩니다."
- `ORCHESTRATED=true`인 경우: 여기서 종료. vwork가 report verdict를 읽고 phase 전이를 관리한다. vwork는 IMPL → VERIFY → TEST 순으로 진행.

**"추가 검증" / "재검증":**
- 재검증할 차원을 질문
- 선택된 에이전트만 더 깊은 컨텍스트로 재실행
- 기존 보고서에 결과 추가

**"수동 처리":**
- 사용자 피드백 수집 (자유 형식)
- 피드백 항목을 plan.md에 새로운 미완료 체크리스트 항목으로 추가
- `_shared/update-worklog.md`를 통해 워크로그 업데이트:
  - `dashboard_updates`: 사용자 피드백 반영

## 절대 규칙

- **에이전트는 read-only.** Write/Edit/Bash를 사용하지 않으며, Read/Glob/Grep으로만 코드를 탐색한다.
- **4개 차원 모두 검증.** 검증 차원을 건너뛰지 않는다. Codex 크로스 검증은 `CODEX_AVAILABLE=true` 시 필수.
- **보고서는 항상 작성.** 모두 PASS여도 감사 추적을 위해 보고서를 작성한다.
- **피드백은 플랜으로.** 직접 수정하지 않고 plan.md → vimpl 경로를 통한다.
- **사용자 명시 요청 없이는 단계 생략/워크플로우 변경 금지.** vqa가 임의로 phase를 건너뛰거나 순서를 재배치하지 않는다.
- **정규 단계 테이블(SSOT)을 따른다.** route 우선순위 계약 외 임의 분기/전이는 허용하지 않는다.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조

이제 실행하라.
