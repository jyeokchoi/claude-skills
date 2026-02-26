---
name: vplan
description: Structured planning pipeline (requirements → behavior/UX → UI/view → code-level) with consensus-based review
argument-hint: 'Usage: /vplan [worklog-folder-or-worklog.md]'
---

## Project settings

이 스킬은 `rules/workflow.md`의 프로젝트별 설정을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `base_branch` | auto-detect | diff 기준 브랜치 |
| `shared_types_dir` | (없음) | 공유 타입 디렉토리 |
| `jira_pattern` | `[A-Z]+-\d+` | Jira 티켓 패턴 |

You are running a structured planning pipeline that progresses through four stages, reviews the plan with parallel sub-agents until consensus, and outputs a plan file in the worklog folder.

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

## Pre-flight

1. Read the worklog.md Dashboard to understand the task goal and completion criteria.
2. Check if `{WORKLOG_DIR}/analysis.md` exists (output from `/vanalyze`):
   - If found: read it and use as additional context throughout all stages. The analysis provides architecture mapping, behavior mapping, test coverage, and impact analysis that should inform planning decisions. Print: "분석 파일을 발견했습니다. 플래닝에 반영합니다."
   - If not found: proceed normally (new feature creation flow)
3. If `PLAN_FILE` already exists, read it and ask the user:
   - "기존 플랜이 있습니다. 새로 작성할까요, 기존 플랜을 수정할까요?"
   - New: overwrite; Edit: load as starting point

## Pipeline stages

Execute each stage sequentially. Each stage MUST:
- Surface unclear or ambiguous areas and ask the user via AskUserQuestion
- Identify things the user might be missing (edge cases, dependencies, constraints)
- Only proceed to the next stage after the user confirms understanding

### Stage 1: Requirements Analysis (요구사항)

Using the worklog goal + completion criteria + any Jira context:

1. Restate the requirements in your own words
2. Identify:
   - Explicit requirements (stated)
   - Implicit requirements (unstated but necessary)
   - Ambiguous requirements (need clarification)
   - Out-of-scope items (explicitly excluded)
3. Ask the user about every ambiguous item
4. Confirm the final requirements list with the user

**Output:** A clear, numbered requirements list

### Stage 2: Behavior / UX (동작/UX)

Based on confirmed requirements:

1. Describe each user-facing behavior change
2. Map user flows: what happens when the user does X?
3. Identify edge cases in user interaction
4. Consider:
   - Error states and recovery paths
   - Loading/async states
   - Undo/redo implications
   - Accessibility considerations
   - Existing behavior that must not break
5. Ask the user about unclear UX decisions

**Output:** Behavior specification with user flows

### Stage 3: UI / View (UI/뷰)

Based on confirmed behaviors:

1. Identify which UI components are affected
2. Describe visual changes needed
3. Consider:
   - Component hierarchy and data flow
   - Responsive/adaptive layouts
   - Animation/transition needs
   - i18n implications (new translation keys needed)
   - Design system consistency
4. Ask the user about visual/interaction decisions

**Output:** UI change specification with component mapping

### Stage 4: Code-level (코드레벨)

Based on confirmed UI/behavior specs:

1. Explore the codebase to understand current architecture:
   - Use `explore` agent or direct Glob/Grep to find relevant files
   - Read key files to understand patterns and conventions
2. Map changes to specific files and modules
3. Identify:
   - Files to modify vs. files to create
   - Type changes (check `shared_types_dir` if configured in `rules/workflow.md`)
   - Test files to add/modify
   - Potential conflicts with ongoing work
4. Ask the user about architectural decisions if multiple valid approaches exist

**Output:** File-level change map

## Plan composition

After all 4 stages complete, compose the final plan as a **checklist of small, meaningful changes**:

Each checklist item MUST:
- Represent ONE intent (e.g., "Add type definition for X", "Implement behavior Y")
- Fit in a single commit
- Result in a working state (no broken intermediate states)
- Include: what changes, which files, what to test

Format:
```markdown
# Plan: {task-name}

## Requirements
{from Stage 1}

## Behavior Spec
{from Stage 2}

## UI Spec
{from Stage 3}

## Implementation Checklist

- [ ] **1. {title}**
  - Intent: {what and why}
  - Files: {list of files to touch}
  - Test: {what to verify}

- [ ] **2. {title}**
  ...
```

## Consensus review

Once the plan is composed, review it with parallel sub-agents:

### Round 1: Parallel review

Spawn 4 agents in PARALLEL using the Task tool:

```
Task(subagent_type="oh-my-claudecode:architect", model="opus",
     prompt="Review this plan for architectural soundness... [PLAN_CONTENT]")
Task(subagent_type="oh-my-claudecode:code-reviewer", model="sonnet",
     prompt="Review this plan for implementation feasibility... [PLAN_CONTENT]")
Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
     prompt="Review this plan for quality and completeness... [PLAN_CONTENT]")
Task(subagent_type="oh-my-claudecode:critic", model="opus",
     prompt="Challenge this plan — find gaps, risks, missing steps... [PLAN_CONTENT]")
```

Each agent prompt MUST include:
- The full plan content
- The worklog goal and completion criteria
- Relevant codebase context (key file contents, architecture)
- Instruction: "IMPORTANT: Do NOT use the Bash tool. Analyze ONLY the context provided."
- Output format: findings list with SEVERITY (CRITICAL/HIGH/MEDIUM/LOW) + verdict (APPROVE/REVISE)

### Round 2+: Consensus loop

Analyze the 4 reviews:

1. **All APPROVE**: Consensus reached. Proceed to user review.
2. **Mixed with no CRITICAL findings**: Synthesize feedback, apply non-controversial improvements, proceed.
3. **CRITICAL findings or strong disagreement**:
   a. Apply the feedback to revise the plan
   b. Re-run parallel review (back to Round 1)
   c. Maximum 3 rounds
4. **Agents cannot agree after 3 rounds AND user input is required**:
   - Present the contested points to the user via AskUserQuestion
   - Apply user's decisions
   - Run one final review round

### Consensus report

After consensus, print a summary:
```
## Plan Review Summary
- Rounds: {N}
- Architect: {verdict} — {1-line}
- Code Reviewer: {verdict} — {1-line}
- Quality Reviewer: {verdict} — {1-line}
- Critic: {verdict} — {1-line}
- Consensus: {REACHED / PARTIAL (user-resolved)}
```

## User review and finalization

1. Present the final plan to the user for review
2. If the user requests changes, apply them and optionally re-run a lightweight review
3. Once approved, write the plan to `PLAN_FILE`
4. Update the worklog Dashboard:
   - Status: PLANNING → IN_PROGRESS (or keep PLANNING if user wants more refinement)
   - Add plan file link to Links section
5. Add a Timeline entry documenting the planning session

## Output

Print:
- Plan file path
- Number of checklist items
- Suggestion: "플랜이 완성되었습니다. `/vimpl {WORKLOG_DIR}` 로 구현을 시작하세요."

Proceed now.
