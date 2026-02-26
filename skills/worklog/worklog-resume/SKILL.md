---
name: worklog-resume
description: Resume work on an existing worklog with Dashboard validation and decision verification
argument-hint: 'Usage: /worklog-resume [worklog-path | <issue-key>]'
# e.g. /worklog-resume PROJ-1234  or  /worklog-resume .claude/worklogs/my-task/
allowed-tools: Bash(ls:*), Bash(date:*), Bash(git config:*), Bash(find:*), Bash(grep:*), Read, Edit, AskUserQuestion, Task
---

You are resuming work on an existing task worklog with validation of previous decisions.

## Inputs

- Raw arguments: $ARGUMENTS

Interpretation:
- If argument matches `[A-Z]+-\d+` pattern → search for worklog with that Jira key
- If argument is a path → use that path directly
- If no argument → auto-search for IN_PROGRESS worklog

## Non-negotiable rules

- NEVER create a new worklog - only resume existing ones
- ALWAYS validate previous decisions before continuing work
- Update worklog.md INLINE (do not create copies)
- Add Timeline entry for session resume

## Steps

### 1. Locate worklog

**If $ARGUMENTS is empty:**
```bash
# Search for IN_PROGRESS worklogs in current directory and worktrees
find .claude/worklogs -name "worklog.md" -exec grep -l "status: 'IN_PROGRESS'" {} \; 2>/dev/null
```
- If multiple found, ask user to select
- If none found, check `../worktrees/*/` directories

**If $ARGUMENTS matches `[A-Z]+-\d+` (or project-specific pattern from rules/workflow.md `jira_pattern`):**
```bash
# Search for worklog with matching Jira key
find .claude/worklogs -name "worklog.md" -exec grep -l "{key}" {} \; 2>/dev/null
```

**If $ARGUMENTS is a path:**
- Use that path directly
- Verify file exists

### 2. Read and analyze worklog

Read the worklog.md and extract:

**Frontmatter:**
- status
- jira
- branch
- worktree_path
- completion_promise

**Dashboard sections:**
- Goal
- Completion criteria (parse checkboxes: `- [x]` vs `- [ ]`)
- Next actions (parse checkboxes)
- Decisions
- Remember (작업별 영구 컨텍스트 — 매 세션 반드시 읽고 준수)
- Blockers / Risks

**Timeline:**
- Extract most recent 2 entries (for context)

### 3. Output status summary

Print the following summary:
```
📋 워크로그 상태 요약
━━━━━━━━━━━━━━━━━━━━
🎯 Goal: {goal}
🔗 Jira: {jira_url}
🌿 Branch: {branch}

📊 완료 기준 진행률: {completed}/{total}

✅ 완료된 항목:
{list of [x] items}

⏳ 남은 항목:
{list of [ ] items}

📝 현재 결정사항:
{decisions list}

🧠 기억사항 (Remember):
{remember items — 없으면 생략}

⚠️ Blockers / Risks:
{blockers if any}

📜 최근 작업 (마지막 세션):
{summary of last timeline entry}
```

### 4. Validate previous decisions

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

**If user selects "아니오, 수정 필요":**

a. Ask which decision needs to change:
```
AskUserQuestion:
  question: "어떤 결정이 변경되었나요?"
  header: "Change"
  options:
    - label: "수정 방향"
      description: "기술적 접근 방식 변경"
    - label: "영향 범위"
      description: "수정 대상 파일/기능 변경"
    - label: "기타"
      description: "다른 결정사항 변경"
```

b. Get new decision from user (freeform input via "기타" option)

c. Update Dashboard Decisions section:
   - Mark old decision with `[INVALIDATED {date}]`
   - Add new decision with `[CURRENT]` prefix

d. Add Timeline entry:
```markdown
### {timestamp} (Direction Change)

**Summary**
- 이전 결정 무효화: {old_decision_summary}
- 새 결정: {new_decision_summary}
- 변경 사유: {reason from user}
```

### 5. Determine resume point

```
AskUserQuestion:
  question: "어디서부터 작업을 재개하시겠습니까?"
  header: "Resume"
  options:
    - label: "다음 액션부터"
      description: "{first unchecked next action}"
    - label: "특정 완료 기준부터"
      description: "남은 완료 기준 중 선택"
    - label: "처음부터 재검토"
      description: "전체 계획 재검토"
```

### 6. Add Timeline entry for session resume

Insert after `<!-- WORKLOG:TIMELINE:INSERT:HERE -->`:

```markdown
### {YYYY-MM-DD HH:MM}{timestamp_suffix} (Session Resume)

**Summary**
- 세션 재개
- 이전 진행: {completed_count}/{total_count} 완료 기준 달성
- 재개 지점: {selected resume point}

**Context from previous session**
- {1-2 sentence summary of last timeline entry}

**Next**
- {first pending action}
```

### 7. Ask about starting work

```
AskUserQuestion:
  question: "바로 작업을 시작하시겠습니까?"
  header: "Start"
  options:
    - label: "Ralph loop로 시작 (Recommended)"
      description: "완료될 때까지 자동 반복 실행"
    - label: "단일 작업만"
      description: "에이전트에게 한 번만 위임"
    - label: "수동 진행"
      description: "직접 작업 진행"
```

**If user selects "Ralph loop로 시작":**

Invoke `/worklog-ralph {worklog_path}` to start OMC ralph loop.

**If user selects "단일 작업만":**

`deep-executor` 역할로 위임:
```
  prompt: |
    워크로그 기반 작업 재개

    ## Worklog
    - Path: {worklog_path}
    - Goal: {goal}
    - Jira: {jira_url}

    ## Current State
    - 완료 기준: {completed}/{total} 달성
    - 재개 지점: {resume_point}

    ## Next Actions
    {next_actions_list}

    ## Decisions (CURRENT)
    {current_decisions}

    ## Instructions
    1. Next Actions 순서대로 진행
    2. 각 작업 완료 후 worklog Dashboard 업데이트
    3. 모든 완료 기준 달성 시 worklog status를 DONE으로 변경
```

**If user selects "수동 진행":**

Print:
```
📌 수동 진행 모드

다음 액션을 시작하세요:
  {first pending action}

작업 중 도움이 필요하면 언제든 요청하세요.
```

Proceed now.
