---
name: vimpl
description: Incremental or auto implementation with TDD, code-simplifier, parallel verification, and ralph loop persistence
argument-hint: 'Usage: /vimpl [worklog-folder-or-worklog.md]'
---

## Project settings

이 스킬은 `rules/workflow.md`의 프로젝트별 설정을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `test_command` | 프로젝트 설정에서 탐지 | 테스트 실행 명령 |
| `completion_promise_default` | `**WORKLOG_TASK_COMPLETE**` | worklog 기본 완료 약속 |

You are running an implementation workflow that executes a plan checklist item by item, using TDD, code simplification, parallel verification, and ralph loop persistence.

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
- If `PLAN_FILE` does not exist, stop: "플랜 파일이 없습니다. `/vplan` 으로 먼저 플랜을 작성하세요."

## Mode selection (session-persistent)

Ask the user ONCE at the start. Remember this choice for the entire session using `<remember priority>vimpl mode: {choice}</remember>`.

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

If a previous mode choice exists in memory, confirm: "이전에 {mode} 모드를 선택하셨습니다. 계속할까요?"

## Ralph loop activation

After mode selection, activate the ralph loop to ensure work never stops:

1. Read `completion_promise` from worklog frontmatter. If not set, use `completion_promise_default` from `rules/workflow.md`, falling back to `**WORKLOG_TASK_COMPLETE**`.
2. Create ralph state via `state_write(mode="ralph")`:
   ```json
   {
     "active": true,
     "iteration": 1,
     "max_iterations": 100,
     "completion_promise": "<PROMISE>",
     "worklog_path": "<WORKLOG_DIR>",
     "linked_ultrawork": true
   }
   ```
3. Create ultrawork state via `state_write(mode="ultrawork")`:
   ```json
   {
     "active": true,
     "linked_to_ralph": true
   }
   ```

## Implementation loop (per checklist item)

Read the plan file. Find the first unchecked item (`- [ ]`). For each item, execute:

### Step 1: Understand the unit

Read the checklist item's intent, files, and test criteria. Read the relevant source files to understand current state.

### Step 2: TDD — Write tests FIRST (Red phase)

Before writing any implementation code:

1. **UX/Behavior-level tests**: Write integration or component tests that describe the expected behavior from a user's perspective. These tests should FAIL initially.
2. **Unit tests**: Write unit tests for the specific logic being implemented. These should also FAIL initially.
3. Run the tests to confirm they fail (Red). Use `test_command` from `rules/workflow.md` if available; otherwise detect from package.json or project config.
4. If tests cannot be written first (e.g., testing infrastructure missing), note this in the worklog and proceed with implementation, but add tests immediately after.

### Step 3: Implementation (Green phase)

Write the minimum code needed to make all tests pass:

1. Implement the change described in the checklist item
2. Run the tests to confirm they pass (Green). Use `test_command` from `rules/workflow.md` if available; otherwise detect from project config.
3. If tests fail, iterate until Green.

### Step 4: Code simplification (Refactor phase)

1. Invoke the `code-simplifier` agent on the modified files:
   ```
   Task(subagent_type="code-simplifier:code-simplifier", model="sonnet",
        prompt="Simplify the recently modified code without changing behavior. Files: {list}")
   ```
2. After simplification, run tests again to verify nothing broke. Use `test_command` from `rules/workflow.md` if available.
3. If tests fail after simplification, revert the simplification changes and note in worklog.

### Step 5: Parallel verification

Run these two verifications in PARALLEL:

**Verification A — Correctness check:**
```
Task(subagent_type="oh-my-claudecode:verifier", model="sonnet",
     prompt="Verify this implementation is correct.
     - Checklist item: {item description}
     - Changed files: {list with diffs}
     - Test results: {test output}
     - Check: types, logic, edge cases, test coverage
     IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

**Verification B — Intent alignment check:**
```
Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
     prompt="Cross-verify this implementation against the plan and worklog.
     - Plan item: {checklist item from plan.md}
     - Worklog goal: {from worklog Dashboard}
     - Implementation diff: {changes made}
     - Check: Does the implementation match the intent? Missing anything?
     IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

If either verification finds issues:
- Fix the issues
- Re-run tests
- Re-run only the failed verification

### Step 6: Approval

**Explain to the user** (both modes):
- Which files were changed and why
- Where in the overall architecture these changes sit
- Why these specific changes were needed

**Incremental mode:**
- Present the explanation and wait for user approval via AskUserQuestion:
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
- If "수정 필요": apply feedback → re-run from Step 3
- If "롤백": `git checkout -- {files}` → mark item as blocked in plan, proceed to next

**Auto mode:**
- Run exhaustive-review on the changes:
  ```
  Invoke /exhaustive-review skill logic with the current changes as scope
  ```
- If final recommendation is APPROVE: auto-approve
- If REQUEST_CHANGES:
  - Apply suggested fixes
  - Re-run tests
  - Re-run lightweight verification
  - If still not approved after 2 iterations, fall back to asking the user

### Step 7: Commit and mark complete

1. Mark the checklist item as done in plan.md: `- [ ]` → `- [x]`
2. Update worklog Dashboard (next actions, progress)
3. Add Timeline entry with evidence
4. Proceed to next unchecked item

## Completion

When ALL checklist items in plan.md are checked (`- [x]`):

1. Update worklog Dashboard: status → DONE (only if completion criteria met)
2. Add final Timeline entry with evidence
3. Output the completion promise: `<promise>{COMPLETION_PROMISE}</promise>`
4. Cancel ralph loop: `/oh-my-claudecode:cancel`

## Non-negotiable rules

- **Never skip TDD.** Tests come before implementation code.
- **Never skip code-simplifier.** Always refactor after Green.
- **Never proceed without approval.** Incremental = user. Auto = exhaustive-review consensus.
- **Never stop working.** Ralph loop ensures persistence. Each iteration must do meaningful work.
- **Always update worklog.** Before and after each checklist item.
- **Remember the mode.** Incremental vs Auto is chosen once and persists.

Proceed now.
