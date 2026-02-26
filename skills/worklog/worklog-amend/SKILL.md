---
name: worklog-amend
description: Use when a worklog exists but is missing required fields (jira, branch, frontmatter) or when you need to move an existing worklog to a new worktree
argument-hint: 'Usage: /worklog-amend [worklog-path]'
allowed-tools: Bash(mkdir:*), Bash(cp:*), Bash(mv:*), Bash(rm:*), Bash(date:*), Bash(git rev-parse:*), Bash(git config:*), Bash(git worktree:*), Bash(git branch:*), Bash(git checkout:*), Bash(git fetch:*), Bash(test:*), Bash(ls:*), Bash(cd:*), Bash(pwd:*), Read, Write, Edit, AskUserQuestion, mcp__plugin_atlassian_atlassian__*
---

You are amending an existing worklog to fill in missing fields and optionally migrating it to a new worktree.

## Project settings

이 스킬은 `rules/workflow.md`의 프로젝트별 설정을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `worktree_policy` | `optional` | worktree 생성 정책 (`always` / `optional` / `never`) |
| `branch_pattern` | `feature/{task_name}` | 브랜치 이름 패턴 |
| `jira_pattern` | `[A-Z]+-\d+` | Jira 이슈 키 패턴 |
| `jira_base_url` | none | Jira 이슈 URL 접두사 |
| `base_branch` | auto-detect | worktree base 브랜치 |

## Inputs

- Raw arguments: $ARGUMENTS
- If no argument provided, search for active worklog in `.claude/worklogs/`

## Non-negotiable rules

- Never create a new worklog - only amend existing ones
- Update worklog.md INLINE (do not create copies)
- Preserve all existing content when amending

## Steps

### 1. Locate worklog

- If $ARGUMENTS contains a path: use directly
- If no argument: search `.claude/worklogs/*/worklog.md` for most recent or IN_PROGRESS worklog
- If multiple found, ask user to select

### 2. Read and check missing fields

Read worklog.md and identify missing required frontmatter fields:

| Field              | Required | Default if missing                  |
| ------------------ | -------- | ----------------------------------- |
| `jira`             | yes      | (ask user)                          |
| `branch`           | yes      | derive from task name + jira key    |
| `created`          | yes      | extract from folder name or today   |
| `owner`            | yes      | `git config user.name`              |
| `status`           | yes      | `PLANNING`                          |
| `completion_promise` | yes    | `**WORKLOG_TASK_COMPLETE**`         |

Also check Dashboard content (Goal, Next actions, Decisions).

### 3. Fill missing fields

**jira (if empty and user wants to add):**

AskUserQuestion: "Jira 이슈를 생성하시겠습니까?" (예/아니오)

If "예":

- If `.claude/skills/_shared/create-jira-issue.md` exists:
  > **Shared**: `.claude/skills/_shared/create-jira-issue.md` 절차를 따른다.
- Else: ask user for Jira issue title and description, then create via `mcp__plugin_atlassian_atlassian__` tools directly.

**branch (if empty):**
- Use `branch_pattern` from project settings (default: `feature/{task_name}`)
- If jira key is available: `feature/{JIRA_KEY}.{task_name_short}` (or as configured by `branch_pattern`)
- Ask user to confirm or modify

**created/owner/status/completion_promise:**
- Fill with defaults from table above

### 4. Amend Dashboard content (if sparse)

If Dashboard is minimal:
- Ask user if they want to bootstrap content
- If yes, run brainstorm + plan workflow (same as worklog-start)
- Update Dashboard and add Timeline entry

### 5. Ask about worktree migration

If `worktree_policy` = `never`: skip this step entirely.

If `worktree_policy` = `always`: proceed directly to Step 6 without asking.

If `worktree_policy` = `optional` (default):
AskUserQuestion: "워크로그 수정이 완료되었습니다. 새 워크트리를 생성하고 워크로그를 이동하시겠습니까?" (예/아니오)

### 6. Create worktree and migrate (if applicable)

Determine `base_branch`:
- Use `base_branch` from project settings if configured
- Else auto-detect: `gh repo view --json defaultBranchRef`로 기본 브랜치 탐지 + `fork_workflow` 설정 또는 `git remote -v`로 remote 결정. 탐지 실패 시 사용자에게 질문 → `project_memory_add_note("base_branch: {answer}")`

If `.claude/skills/_shared/create-worktree.md` exists:
> **Shared**: `.claude/skills/_shared/create-worktree.md` 절차를 따른다.
> - `task_name` = branch-name-short (remove prefix per `branch_pattern`), `branch_name` = worklog frontmatter의 branch, `base_ref` = `{base_branch}`, `create_branch` = `true`

Else (inline worktree creation):
```bash
# Determine worktree path: sibling to repo root
repo_root=$(git rev-parse --show-toplevel)
worktree_base=$(dirname "$repo_root")/worktrees
worktree_path="$worktree_base/{task_name}"
git worktree add -b {branch_name} "$worktree_path" {base_branch}
```

Move worklog to new worktree:
```bash
mkdir -p {worktree_path}/.claude/worklogs/
mv {current_worklog_folder} {worktree_path}/.claude/worklogs/
```

Update frontmatter: add `worktree_path: {worktree_path}`

### 7. Print summary

```
✅ 워크로그 수정 완료

📝 수정된 항목:
   - [list of amended fields]

📁 워크로그 위치: {worklog_path}
🔗 Jira: {jira_url or "없음"}
🌿 브랜치: {branch_name}
```

If worktree was created:

- If `.claude/skills/_shared/print-worktree-summary.md` exists:
  > **Shared**: `.claude/skills/_shared/print-worktree-summary.md` 절차를 따른다.
- Else print inline:
  ```
  🗂️  워크트리 생성 완료

  📂 경로: {worktree_path}
  🌿 브랜치: {branch_name}
  🔗 Base: {base_branch}

  👉 다음 단계:
     cd {worktree_path}
  ```

Proceed now.
