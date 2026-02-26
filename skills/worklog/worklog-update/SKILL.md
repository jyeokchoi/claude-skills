---
name: worklog-update
description: Update the active task worklog dashboard + append a timeline entry (inline)
argument-hint: 'Usage: /worklog-update [optional: path-to-worklog-folder-or-worklog.md]'
allowed-tools: Bash(cat:*), Bash(test:*), Bash(ls:*), Bash(date:*), Bash(grep:*), Bash(awk:*), Bash(sed:*), Bash(python:*), Bash(git status:*), Bash(git diff:*), Bash(git rev-parse:*), Bash(git log:*)
---

You are updating a task worklog in-place.

## Project settings

이 스킬은 다음 프로젝트 설정을 참조한다 (`rules/workflow.md` 또는 `rules/project-params.md`):

| 설정 | 용도 |
|------|------|
| `timezone` | 타임스탬프 시간대 (e.g., `Asia/Seoul`) |
| `timestamp_suffix` | 타임스탬프 뒤에 붙는 문자열 (e.g., `KST`) |

설정이 없으면 시스템 시간대를 사용한다.

## Target selection

- If $ARGUMENTS is provided:
  - If it's a folder, target "{arg}/worklog.md"
  - If it's a file, target that file
- Else:
  - Find the active worklog using: `find .claude/worklogs -name "worklog.md" -path "*/worklog.md" | head -5`
  - If multiple results, pick the most recently modified one
- If no target exists, stop and print a single error message explaining what's missing.

## Non-negotiable rules

- Do NOT create new worklog folders.
- Update the existing worklog.md inline only.
- Dashboard is always-current (overwrite the block between WORKLOG:DASHBOARD markers).
- Remember 섹션은 Dashboard 업데이트 시에도 반드시 보존한다 (삭제/축약 금지).
- Timeline is append-only (insert a new entry immediately after WORKLOG:TIMELINE:INSERT:HERE).
- Do not edit older timeline entries.

## Context (auto-captured)

- Timestamp: `rules/workflow.md`에서 `timezone` 설정을 읽고 적용: `TZ={timezone} date "+%Y-%m-%d %H:%M"` (없으면 시스템 시간대). `timestamp_suffix`가 있으면 뒤에 추가 (e.g., "KST")
- Branch: !git rev-parse --abbrev-ref HEAD
- Git status:
  !git status -sb
- Git diff (stat):
  !git diff --stat
- Recent commits (optional signal):
  !git log -5 --oneline --no-decorate

## What to write

1. Read the current worklog.md and understand the current Dashboard:
   - status
   - Next actions
   - blockers/risks
2. Produce an updated Dashboard block:
   - Keep it concise
   - Update status: PLANNING / IN_PROGRESS / BLOCKED / DONE
   - Next actions: 3~7 items, checkbox format
   - If BLOCKED, state the blocker clearly
3. Create one new Timeline entry using the timeline-entry template format:
   - Include Summary, Work done, Evidence (commands/files/tests), Problems/Notes, Next
   - Evidence must reference at least: git status + diff stat (from above)

## Apply changes

## Apply changes (implementation requirement)

Use Bash commands to create two temp files next to the worklog:

- ".dashboard.tmp.md" containing the FULL dashboard block including:
  <!-- WORKLOG:DASHBOARD:START --> ... <!-- WORKLOG:DASHBOARD:END -->
- ".timeline.tmp.md" containing exactly ONE timeline entry

Then run:
!python ".claude/skills/_templates/worklog/apply_worklog_update.py" \
 --worklog "<PATH_TO_WORKLOG_MD>" \
 --dashboard-file "<DIR>/.dashboard.tmp.md" \
 --timeline-file "<DIR>/.timeline.tmp.md"

Finally delete the temp files.

print:

- Updated file path
- New status value
