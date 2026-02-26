---
name: vqa
description: Parallel QA verification with team-based research, report generation, and feedback loop
argument-hint: 'Usage: /vqa [worklog-folder-or-worklog.md]'
---

## Project settings

이 스킬은 `rules/workflow.md`의 프로젝트별 설정을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `base_branch` | auto-detect | diff 기준 브랜치 |
| `test_command` | 프로젝트 설정에서 탐지 | 테스트 실행 명령 |
| `shared_types_dir` | (없음) | 공유 타입 디렉토리 |
| `timestamp_suffix` | (없음) | 타임스탬프 뒤 문자열 (예: KST) |

You are running a comprehensive QA verification workflow that uses parallel sub-agents to verify implementation correctness, then produces a report for user review.

## Target resolution

- Try loading `_shared/resolve-worklog-target.md` if it exists and follow its logic.
- Fallback (if shared resolver not available):
  - If $ARGUMENTS is provided:
    - If it's a folder: target "{arg}/worklog.md"
    - If it's a file: target that file, derive folder from dirname
  - Else:
    - Read ".claude/worklogs/.active" to get the active worklog folder
- If no target exists, stop and print an error.
- Set `WORKLOG_DIR` = the worklog folder path
- Set `PLAN_FILE` = `{WORKLOG_DIR}/plan.md`
- Set `REPORT_FILE` = `{WORKLOG_DIR}/report.md`
- If `PLAN_FILE` does not exist, stop: "플랜 파일이 없습니다."
- Read the worklog.md and plan.md to understand task goal, completion criteria, and implementation checklist.

## Phase 1: Context gathering (orchestrator)

Gather all context needed for the parallel research agents. Agents must NOT use Bash — all context goes into their prompts.

1. **Worklog context**: Read worklog.md — goal, completion criteria, decisions, timeline entries
2. **Plan context**: Read plan.md — requirements, behavior spec, UI spec, full checklist with completion status
3. **Code context**:
   - Use `base_branch` from `rules/workflow.md` if available; otherwise auto-detect from worklog or git config
   - `git diff <base-branch>...HEAD --stat` to identify all changed files
   - `git diff <base-branch>...HEAD` for the full diff
   - Read key changed files in full (new files, heavily modified files, type definitions)
4. **Test context**:
   - Find test files related to the changes (`Glob` for `*.test.*`, `*.spec.*` near changed files)
   - Read test file contents
   - Run the test suite using `test_command` from `rules/workflow.md` if available; otherwise detect from project config. Capture results.

Assemble this into a `QA_CONTEXT` block for agent prompts.

## Phase 2: Parallel research (4 agents)

Spawn 4 verification agents in PARALLEL:

### Agent 1: Intent Verification (워크로그 기반 의도 검증)

```
Task(subagent_type="oh-my-claudecode:verifier", model="sonnet",
     prompt="
IMPORTANT: Do NOT use the Bash tool. Analyze ONLY the context provided.

You are verifying that the implementation matches the INTENDED behavior from the worklog.

## Your Task
Compare the worklog's stated goal and completion criteria against what was actually implemented.

## Check
- Does each completion criterion have corresponding code changes?
- Are there implementation decisions that deviate from the worklog's stated intent?
- Were any goals partially implemented or missed entirely?
- Do the timeline entries accurately reflect what was done?

## Worklog
{worklog content}

## Code Changes
{diff}

## Output Format
### Intent Alignment Score: {1-5}/5
### Findings
- [MET/PARTIAL/MISSED] {criterion} — {evidence}
### Gaps
- {any missing implementations}
### Verdict: PASS / NEEDS_WORK
")
```

### Agent 2: Spec Verification (플랜 기반 동작/스펙 검증)

```
Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
     prompt="
IMPORTANT: Do NOT use the Bash tool. Analyze ONLY the context provided.

You are verifying that the implementation correctly fulfills the plan's specifications.

## Your Task
Compare the plan's requirements, behavior spec, and UI spec against the actual implementation.

## Check
- Does each requirement have corresponding implementation?
- Does the behavior match the behavior spec (user flows, edge cases, error states)?
- Does the UI match the UI spec (components, layout, interactions)?
- Are all checklist items properly implemented (not just checked off)?
- Any spec items that were implemented differently than planned? Is the deviation justified?

## Plan
{plan content}

## Code Changes
{diff + key file contents}

## Output Format
### Spec Compliance Score: {1-5}/5
### Checklist Audit
- [CORRECT/INCOMPLETE/DEVIATED] Item #{N}: {title} — {evidence}
### Behavior Gaps
- {missing or incorrect behaviors}
### Verdict: PASS / NEEDS_WORK
")
```

### Agent 3: Test Verification (테스트 커버리지/올바름 검증)

```
Task(subagent_type="oh-my-claudecode:test-engineer", model="sonnet",
     prompt="
IMPORTANT: Do NOT use the Bash tool. Analyze ONLY the context provided.

You are verifying test coverage and correctness for the implementation.

## Your Task
Evaluate whether the tests adequately cover the implementation and are themselves correct.

## Check
- Do tests cover all behavior spec items (happy path + edge cases)?
- Are there untested code paths in the changed files?
- Are the test assertions meaningful (not just 'does not throw')?
- Do tests verify the RIGHT things (behavior, not implementation details)?
- Are there missing test categories (unit, integration, error cases)?
- Are existing tests still valid after the changes?

## Test Files
{test file contents}

## Test Results
{test run output}

## Implementation
{diff + key file contents}

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
IMPORTANT: Do NOT use the Bash tool. Analyze ONLY the context provided.

You are verifying that the implementation is architecturally sound and consistent.

## Your Task
Evaluate the code changes for architectural quality, consistency with codebase patterns, and long-term maintainability.

## Check
- Does the implementation follow existing codebase patterns and conventions?
- Are module boundaries respected? Any leaking abstractions?
- Is the code consistent with the project's type system? (branded types, shared types if applicable — check shared_types_dir from project settings if available)
- Are there performance concerns (unnecessary re-renders, N+1 queries, etc.)?
- Is error handling appropriate?
- Any security concerns?
- Is the change backward-compatible where needed?

## Code Changes
{diff + key file contents}

## Relevant Existing Code (for pattern comparison)
{existing similar files/patterns}

## Output Format
### Architecture Score: {1-5}/5
### Findings
- [SEVERITY] {finding} — {file:line} — {recommendation}
### Pattern Violations
- {where the code diverges from established patterns}
### Verdict: PASS / NEEDS_WORK
")
```

## Phase 3: Report synthesis

After all 4 agents complete, synthesize their findings into `REPORT_FILE`:

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
```

## Phase 4: User review and feedback loop

1. Present the report summary to the user
2. Write the report to `REPORT_FILE`
3. Ask the user:

```
AskUserQuestion:
  question: "QA 리포트를 검토해주세요. 피드백이 있나요?"
  header: "QA Result"
  options:
    - label: "통과 (Pass)"
      description: "모든 검증이 충분합니다. 작업을 완료합니다."
    - label: "수정 필요 (Feedback)"
      description: "피드백을 주시면 플랜에 추가하고 vimpl로 수정합니다."
    - label: "재검증 (Re-verify)"
      description: "특정 영역을 더 깊이 검증합니다."
```

### If "통과":
- Update worklog Dashboard: confirm completion
- Add Timeline entry: "QA 검증 통과"
- Print: "QA 검증이 완료되었습니다."

### If "수정 필요":
- Collect user feedback
- Append feedback items to plan.md as new unchecked checklist items
- Update worklog Dashboard
- Print: "피드백이 플랜에 추가되었습니다. `/vimpl {WORKLOG_DIR}` 로 수정 후 `/vqa {WORKLOG_DIR}` 를 다시 실행하세요."

### If "재검증":
- Ask which dimension(s) to re-verify
- Re-run only the selected agent(s) with deeper context
- Append results to the existing report

## Non-negotiable rules

- **All context in agent prompts.** Agents must NOT use Bash or Read tools.
- **All 4 dimensions verified.** Never skip a verification dimension.
- **Report always written.** Even if all PASS, write the report for audit trail.
- **Feedback goes to plan.** Never fix issues directly — route through plan.md → vimpl.

Proceed now.
