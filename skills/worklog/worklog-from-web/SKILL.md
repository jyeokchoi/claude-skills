---
name: worklog-from-web
description: Create a worktree and optionally a Jira issue from an existing worklog created by a web/remote session. Use when a remote branch already has commits but you want to work in an isolated worktree.
argument-hint: 'Usage: /worklog-from-web [worklog-path | branch-name]'
allowed-tools: Bash(mkdir:*), Bash(cp:*), Bash(mv:*), Bash(rm:*), Bash(date:*), Bash(git rev-parse:*), Bash(git config:*), Bash(git worktree:*), Bash(git branch:*), Bash(git checkout:*), Bash(git fetch:*), Bash(git rebase:*), Bash(git push:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(test:*), Bash(ls:*), Bash(cd:*), Bash(pwd:*), Bash(echo:*), Bash(python:*), Read, Write, Edit, AskUserQuestion, Task, mcp__plugin_atlassian_atlassian__*
---

You are setting up a local worktree from an existing worklog that was created by a Claude web session (or any remote session that already pushed commits to a branch).

**Why this exists**: The user wants their main repo to stay on the base branch. Web sessions teleport and checkout branches directly, which is disruptive. This skill creates an isolated worktree so the user can test, review, and continue work without touching their main checkout.

## Project settings

이 스킬은 `rules/workflow.md`의 프로젝트별 설정을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `base_branch` | auto-detect | 메인 repo가 머물러야 할 브랜치 |
| `fork_workflow` | `false` | fork 기반 워크플로우 여부 |
| `worktree_policy` | `always` | worktree 생성 정책 (이 스킬은 항상 생성) |
| `dependency_install` | none | worktree 생성 후 실행할 의존성 설치 명령 |
| `jira_pattern` | `[A-Z]+-\d+` | Jira 이슈 키 패턴 |
| `jira_base_url` | none | Jira 이슈 URL 접두사 |
| `branch_pattern` | `feature/{task_name}` | 브랜치 이름 패턴 |

## Inputs

- Raw arguments: $ARGUMENTS
- If argument is a path to a worklog → use that worklog directly
- If argument matches a branch name → search for worklog on that branch
- If no argument → search `.claude/worklogs/` for recent non-DONE worklogs

## Non-negotiable rules

- **Keep main repo on the base branch** - only allowed branch switch is restoring it back to base
- Always create a git worktree for the branch
- Worklog should end up in the worktree (move from main repo, or confirm it already exists from the branch commit)
- Update worklog.md INLINE
- If Jira issue is missing, offer to create one

## Steps

### 1. Locate worklog and branch

**If $ARGUMENTS is a path:** read worklog, extract `branch` from frontmatter.

**If $ARGUMENTS looks like a branch name (contains `/`):**
```bash
git fetch origin
```
Search `.claude/worklogs/*/worklog.md` for matching `branch` frontmatter.

**If no argument:**
- Check if main repo is NOT on base branch → use current branch as target
- Search for worklogs with status != DONE
- If none found, list unmerged remote feature branches:
  ```bash
  git fetch origin
  git branch -r --no-merged {base_branch}
  ```
  Filter to show only branches that look like feature branches (exclude `HEAD`, release branches, etc.)

### 2. Read and validate worklog

- Extract frontmatter: status, jira, branch, created, owner, completion_promise
- `branch` field MUST exist (error if not)
- Verify branch exists on remote:
  - `git ls-remote --heads origin {branch}`
  - If `fork_workflow` = `true`, also try: `git ls-remote --heads upstream {branch}`

Print status summary:
```
📋 워크로그 발견
━━━━━━━━━━━━━━
🎯 Task: {goal or task name}
🌿 Branch: {branch}
🔗 Jira: {jira_url or "없음"}
📊 Status: {status}
📅 Created: {created}
```

### 3. Create git worktree

a. Determine `task_name` from folder name or branch (strip prefix per `branch_pattern`, e.g. `feature/`)

b. **Handle main repo branch conflict**: if main repo is on the target branch, switch to base branch first:
```bash
base_branch={base_branch from settings or auto-detected}
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
[ "$current_branch" = "{branch}" ] && git checkout "$base_branch"
```

c. **워크트리 생성:**

- If `.claude/skills/_shared/create-worktree.md` exists:
  > **Shared**: `.claude/skills/_shared/create-worktree.md` 절차를 따른다.
  > - `task_name`, `branch_name` = worklog의 branch 필드, `base_ref` = `origin/{branch}`, `create_branch` = `false`

- Else (inline):
  ```bash
  repo_root=$(git rev-parse --show-toplevel)
  worktree_base=$(dirname "$repo_root")/worktrees
  worktree_path="$worktree_base/{task_name}"
  git worktree add "$worktree_path" "origin/{branch}"
  ```

d. **Dependency install**: if `dependency_install` is configured in project settings, print reminder:
```
💡 의존성 설치가 필요하면 다음을 실행하세요:
   cd {worktree_path} && {dependency_install}
```

### 4. Ensure worklog exists in worktree

a. Check if worklog already exists in worktree:
```bash
find {worktree_path}/.claude/worklogs -name "worklog.md" 2>/dev/null
```

b. **Already exists in worktree**: use it, remove main repo copy if exists.

c. **Only in main repo**: move to worktree:
```bash
mkdir -p {worktree_path}/.claude/worklogs/
mv {current_worklog_folder} {worktree_path}/.claude/worklogs/
```

d. Update frontmatter: add `worktree_path: {worktree_path}`

### 5. Jira issue backfill (if missing)

If `jira` frontmatter is empty or matches `{jira_pattern}-TBD` pattern or is otherwise a placeholder:

AskUserQuestion: "Jira 이슈가 없습니다. 생성하시겠습니까?" (예/아니오)

**If "예":**

- If `.claude/skills/_shared/create-jira-issue.md` exists:
  > **Shared**: `.claude/skills/_shared/create-jira-issue.md` 절차를 따른다.
  > - `task_brief` = worklog Dashboard의 Goal 내용
- Else: ask user for Jira issue title and description, then create via `mcp__plugin_atlassian_atlassian__` tools directly.

생성 후 worklog frontmatter의 `jira` 필드 업데이트.

### 6. Add Timeline entry

Determine timestamp using local time (use `timezone` from project settings if configured):
```bash
date "+%Y-%m-%d %H:%M"
```

Insert after `<!-- WORKLOG:TIMELINE:INSERT:HERE -->`:
```markdown
### {YYYY-MM-DD HH:MM} (Worktree Setup)

**Summary**
- Web 세션 워크로그에서 로컬 워크트리 생성
- 워크트리: {worktree_path}
- Jira: {jira_url or "미생성"}

**Next**
- {first pending action from Dashboard, or "워크로그 검토 후 작업 시작"}
```

### 7. Print summary

- If `.claude/skills/_shared/print-worktree-summary.md` exists:
  > **Shared**: `.claude/skills/_shared/print-worktree-summary.md` 절차를 따른다.
- Else print inline:
  ```
  🗂️  워크트리 준비 완료
  ━━━━━━━━━━━━━━━━━━━━━━

  📂 경로: {worktree_path}
  🌿 브랜치: {branch}
  🔗 Jira: {jira_url or "없음"}
  📊 Status: {status}

  👉 다음 단계:
     cd {worktree_path}
  ```

### 8. Ask about continuing work

AskUserQuestion: "워크트리가 준비되었습니다. 작업을 계속하시겠습니까?"

- **"예, 워크로그 기반 작업 재개"**: `/worklog-resume` 로직으로 진행 (validate decisions, pick resume point, delegate)
- **"아니오, 나중에"**: 종료

Proceed now.
