---
name: offload-to-branch
description: Offload specific changes from the current branch to a separate branch with its own Jira issue and PR
argument-hint: "Usage: /offload-to-branch [--files <file1,file2,...>] [--no-revert] [--no-jira] [brief description]"
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git merge-base:*), Bash(git push:*), Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git remote:*), Bash(git checkout:*), Bash(git worktree:*), Bash(git fetch:*), Bash(git reset:*), Bash(git apply:*), Bash(git stash:*), Bash(git cherry-pick:*), Bash(git rebase:*), Bash(git branch:*), Bash(find:*), Bash(grep:*), Bash(ls:*), Bash(rm -rf *), Bash(cd:*), Bash(mkdir:*), Bash(cp:*), Bash(yarn:*), Bash(gh:*), Bash(date:*), Bash(test:*), Bash(echo:*), Read, Write, Edit, AskUserQuestion, Task, mcp__plugin_atlassian_atlassian__*
---

You are offloading specific file changes from the current working branch to a separate branch, creating a Jira issue and PR for them.

This is useful when, during feature development, you discover an upstream bug or unrelated improvement that should be submitted as a separate fix.

## Key Design Principles

- **Non-destructive by default**: Creates a patch, applies to new branch. Original branch changes are reverted only after successful apply.
- **Reuses shared procedures**: Jira issue creation, worktree creation, [LOCAL-ONLY] exclusion, etc.
- **Fast path**: Skips worklog creation (this is a quick offload, not a multi-session task).
- **Jira API markdown**: `\n` literal string forbidden (breaks formatting). Use real newlines or single-line.

## Project settings

스킬 시작 시 `rules/workflow.md`를 읽어 다음 설정을 가져온다:

| 설정 | 기본값 | 설명 |
|------|--------|------|
| `base_branch` | auto-detect (`gh repo view --json defaultBranchRef`) | diff/worktree 기준 브랜치 |
| `fork_workflow` | false | true면 `upstream` remote, false면 `origin` remote 사용 |
| `jira_pattern` | 없음 | 있으면 Jira 연동 활성화 (예: `VREW-\d+`) |
| `branch_pattern` | `fix/{issue_key}` 또는 `fix/{kebab-case-brief}` | 브랜치 이름 패턴 |

`rules/workflow.md`가 없으면 위 기본값으로 동작한다.

## Inputs

- Raw arguments: $ARGUMENTS

Interpretation:
- `--files <file1,file2,...>` (optional): Comma-separated list of files to offload. If omitted, auto-detect or ask user.
- `--no-revert` (optional): Keep changes in the current branch after offloading (duplicate in both branches).
- `--no-jira` (optional): Skip Jira issue creation.
- Remaining text = brief description of the offloaded change.

## Steps

### 0. Validate environment

```bash
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
CURRENT_BRANCH=$(git branch --show-current)
```

Ensure we're on a feature branch (not `develop`, `main`, or equivalent base branch).

### 1. Identify files to offload

**If `--files` provided:** use directly.

**If not provided:**

a. Determine base ref from `rules/workflow.md`, or ask and remember:
```bash
# 1. rules/workflow.md에서 base_branch 읽기 (e.g., "upstream/develop")
# 2. base_branch에 /가 포함되면 이미 remote-qualified → 그대로 사용
#    (e.g., "upstream/develop" → BASE_REF="upstream/develop", REMOTE="upstream")
# 3. base_branch가 bare name이면 (e.g., "develop"):
#    fork_workflow=true → REMOTE="upstream", BASE_REF="upstream/develop"
#    fork_workflow=false → REMOTE="origin", BASE_REF="origin/develop"
# 4. rules/workflow.md가 없으면 사용자에게 질문하고 project_memory에 기록:
#    "base branch를 알려주세요 (예: upstream/develop, origin/main)"
#    → project_memory_add_note("base_branch: {user_answer}")
BASE_REF=<resolved>
REMOTE=<extracted from BASE_REF>
git fetch $REMOTE
git diff --name-only $(git merge-base HEAD $BASE_REF)..HEAD
```

b. AskUserQuestion: "오프로드할 파일을 선택해주세요." with list of changed files (multiSelect: true).

### 2. Generate patch

```bash
MERGE_BASE=$(git merge-base HEAD $BASE_REF)
git diff $MERGE_BASE..HEAD -- {selected_files} > /tmp/offload.patch
```

Verify patch is non-empty. If empty, abort with message.

### 3. Determine change context

Analyze the patch content and ask user (or use brief from arguments):

- **변경 요약**: What the offloaded changes do (1-2 sentences)
- **영향 범위**: What existing features might be affected

If brief was provided in arguments, use it to pre-fill and confirm.

### 4. Create Jira issue (unless `--no-jira`)

**`jira_pattern`이 `rules/workflow.md`에 있는 경우에만 실행한다. 없으면 이 단계를 건너뛴다.**

> **Shared**: `_shared/create-jira-issue.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/create-jira-issue.md` → `~/.claude/skills/_shared/create-jira-issue.md`
> - `task_brief` = 변경 요약 + 영향 범위
> - `suggested_summary` = derived from brief

Returns: `issue_key`, `issue_url`

### 5. Create branch and worktree

a. Determine branch name:
- `rules/workflow.md`에 `branch_pattern`이 있으면 해당 패턴 사용
- 기본값:
  - With Jira: `fix/{issue_key}` (e.g., `fix/PROJ-1234`)
  - Without Jira: `fix/{kebab-case-brief}` (e.g., `fix/audio-duplicate-conversion`)

b. Determine worktree name from issue key or brief:
- With Jira: `{issue_key}` (e.g., `PROJ-1234`)
- Without Jira: kebab-case brief

c. Create worktree:

> **Shared**: `_shared/create-worktree.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/create-worktree.md` → `~/.claude/skills/_shared/create-worktree.md`
> - `task_name` = worktree name
> - `branch_name` = determined above
> - `base_ref` = `$BASE_REF`
> - `create_branch` = `true`

**Skip dependency installation** - this is a quick offload, not a development environment.

### 6. Apply patch in worktree

```bash
cd {worktree_path}
git apply /tmp/offload.patch
```

If `git apply` fails (e.g., context mismatch), try:
```bash
git apply --3way /tmp/offload.patch
```

If still fails, inform user and abort (keep worktree for manual resolution).

### 7. Commit in worktree

```bash
cd {worktree_path}
git add {selected_files}
git commit -m "$(cat <<'EOF'
fix: {brief_summary}

{issue_key_if_exists}
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

Check recent upstream commits for message convention:
```bash
git log $BASE_REF -5 --oneline
```

### 8. Revert changes from current branch (unless `--no-revert`)

```bash
cd {original_worktree}
git checkout $BASE_REF -- {selected_files}
git add {selected_files}
git commit -m "refactor: extract {brief} to separate branch ({issue_key_if_exists})"
```

If the files were newly added (not in base_branch), use `git rm` instead of checkout.

### 9. Lint and format

> **Shared**: `_shared/lint-format.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/lint-format.md` → `~/.claude/skills/_shared/lint-format.md`
> - `changed_files`: 오프로드된 파일 목록
> - `project_dir`: worktree 또는 메인 리포 중 node_modules가 있는 쪽의 해당 경로
>
> node_modules 탐색 순서: `{worktree_path}/` → `{MAIN_REPO}/`

### 10. Code review (MANDATORY)

> **Shared**: `_shared/code-review-gate.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/code-review-gate.md` → `~/.claude/skills/_shared/code-review-gate.md`
> - `diff_target`: `$BASE_REF`
> - `changed_files`: 오프로드된 파일 목록
>
> 수정 발생 시 Step 9(lint-format) 재실행.

### 11. Push and create PR

**a. [LOCAL-ONLY] 커밋 제외 (MANDATORY):**

> **Shared**: `_shared/exclude-local-only-commits.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/exclude-local-only-commits.md` → `~/.claude/skills/_shared/exclude-local-only-commits.md`

**b. PR 생성:**

> **Shared**: `_shared/create-pr.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/create-pr.md` → `~/.claude/skills/_shared/create-pr.md`
> - `branch_name`: {branch_name}
> - `jira_key`: {issue_key} (Step 4에서 생성, `--no-jira`거나 jira_pattern 없으면 생략)
> - `changes_summary`: Step 3에서 수집한 변경 요약
> - `impact_summary`: Step 3에서 수집한 영향 범위
> - `base_branch`: {base_branch}
> - `changed_files`: 오프로드된 파일 목록

### 12. Print summary

| Item | Value |
|------|-------|
| Jira issue | {jira_url} (jira_pattern 있을 때만) |
| PR | {pr_url} |
| Branch | {branch_name} |
| Worktree | {worktree_path} |
| Reviewers | {reviewers} |
| Labels | {labels} |
| Offloaded files | {file_list} |
| Reverted from | {current_branch} |
| Status | Waiting Review |

### 13. Worktree cleanup

Ask user: "오프로드 worktree를 정리하시겠습니까?"

**Yes:**

> **Shared**: `_shared/cleanup-worktree.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/cleanup-worktree.md` → `~/.claude/skills/_shared/cleanup-worktree.md`
> - `main_repo_path`: {MAIN_REPO}
> - `worktree_path`: {worktree_path}

**No:** "Worktree preserved at {worktree_path}"

Proceed now.
