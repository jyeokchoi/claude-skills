---
name: worklog-finish
description: Finish a worklog task, optionally update a Jira issue, and optionally create a PR
argument-hint: "Usage: /worklog-finish [--path <worklog-path>] [--pr] [--no-pr] [--no-jira]"
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git merge-base:*), Bash(git push:*), Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git remote:*), Bash(git blame:*), Bash(git worktree:*), Bash(find:*), Bash(grep:*), Bash(ls:*), Bash(rm -rf *), Bash(cd:*), Bash(yarn:*), Bash(gh:*), Read, Write, Edit, AskUserQuestion, Task, mcp__plugin_atlassian_atlassian__*, mcp__github__*
---

You are finishing a worklog task, optionally updating the linked Jira issue, and optionally creating a PR.

## Key Design Principles

- **Worklog files are NEVER committed to git.** They are uploaded to Gist, attached to Jira (if available), then deleted.
- **Jira API 마크다운**: `\n` 문자열 리터럴 사용 금지 (escape되어 포맷 깨짐). 실제 줄바꿈 또는 한 줄로 작성.

## Inputs

- `--path <worklog-path>` (optional): Direct path to worklog folder
- `--pr` (optional): Create PR after finishing (skip confirmation)
- `--no-pr` (optional): Skip PR creation
- `--no-jira` (optional): Skip Jira update even if jira field exists
- If no path, find worklog matching current branch

## Steps

### 0. Detect main repo path (for worktree cleanup later)

```bash
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
```

### 1. Find the worklog

- If `--path` provided: use directly
- Else: get current branch → search `.claude/worklogs/` for matching `branch` field in frontmatter

### 2. Read worklog and extract info

- Parse frontmatter: `jira` (→ issue key), `branch`
- Read Dashboard: Goal, Completion criteria, Decisions

### 3. Collect change information

**Determine base branch:**

`rules/workflow.md`에서 `base_branch`와 `fork_workflow` 설정을 읽는다. 없으면 auto-detect:
```bash
# 1. rules/workflow.md에서 base_branch 읽기 (있으면 사용)
# 2. fork_workflow=true → upstream remote, false → origin remote
# 3. 설정 없으면 auto-detect
BASE_REF="${base_branch_from_settings}"  # e.g., "upstream/develop" or "origin/main"
if [ -z "$BASE_REF" ]; then
  # 1. gh repo view --json defaultBranchRef로 기본 브랜치 탐지
  # 2. fork 여부: git remote -v로 upstream 존재 확인 → remote 결정
  # 3. 탐지 실패 시 사용자에게 질문 → project_memory_add_note("base_branch: {answer}")
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "")
  if git remote -v | grep -q upstream; then
    REMOTE="upstream"
  else
    REMOTE="origin"
  fi
  git fetch $REMOTE
  if [ -n "$DEFAULT_BRANCH" ]; then
    BASE_REF="$REMOTE/$DEFAULT_BRANCH"
  else
    # 사용자에게 질문 → project_memory_add_note("base_branch: {answer}")
    BASE_REF="$REMOTE/$(git symbolic-ref refs/remotes/$REMOTE/HEAD 2>/dev/null | sed "s|refs/remotes/$REMOTE/||")"
  fi
fi
git diff --name-only $(git merge-base HEAD $BASE_REF)..HEAD
```

Show changed files to user and ask for:
- **수정 범위**: Summary of what was changed
- **기존 기능 영향 범위**: What existing features might be affected

### 4. Update Jira issue (if jira field exists and not --no-jira)

a. Check Jira MCP connection (`ToolSearch` for atlassian tools). If unavailable, skip this step and notify user.

b. `getAccessibleAtlassianResources` → cloudId

c. `getJiraIssue` → current description

d. If project has `.claude/skills/_templates/jira/finish-update.md`, load it and fill `{{changes}}` and `{{impact}}`. Otherwise compose a simple update inline.

e. `editJiraIssue`: prepend update content to existing description

### 5. Archive worklog to Gist and cleanup

a. Update worklog.md: set `status: 'DONE'`, add final Timeline entry (timestamp, completion summary, changed files)

b. Upload to Gist:
```bash
gh gist create --public --filename worklog.md {worklog_path}/worklog.md
```

c. If Jira is available: `addCommentToJiraIssue` with gist URL (한 줄로 작성):
```
Worklog 파일: {gist_url}
```

d. Delete local worklog folder:
```bash
rm -rf {worklog_path}
```

### 6. Lint and format (MANDATORY)

Detect project type and run linter on changed files:
```bash
PROJECT_DIR=$(git rev-parse --show-toplevel)
```

프로젝트에 `_shared/lint-format.md`가 있는 경우:
> **Shared**: `.claude/skills/_shared/lint-format.md` 절차를 따른다.
> - `changed_files`: Step 3에서 수집한 변경 파일 목록
> - `project_dir`: 프로젝트 루트 또는 해당 서브디렉터리

없는 경우: 프로젝트의 lint 설정을 직접 탐지하여 실행한다 (package.json의 lint 스크립트, .eslintrc, pyproject.toml 등).

### 7. Code review (MANDATORY)

프로젝트에 `_shared/code-review-gate.md`가 있는 경우:
> **Shared**: `.claude/skills/_shared/code-review-gate.md` 절차를 따른다.
> - `diff_target`: Step 3에서 결정한 BASE_REF
> - `changed_files`: Step 3에서 수집한 변경 파일 목록

없는 경우: `code-reviewer` 에이전트를 직접 호출하여 변경 diff를 리뷰한다. HIGH 이상 이슈가 없을 때 통과.

수정 발생 시 Step 6(lint-format) 재실행.

### 8. Handle PR creation

- `--no-pr`: skip to Step 9
- Neither flag: ask user "PR을 생성하시겠습니까?"
- If No: skip to Step 9

**a. [LOCAL-ONLY] 커밋 제외 (MANDATORY - push 전에 반드시 실행):**

프로젝트에 `_shared/exclude-local-only-commits.md`가 있는 경우:
> **Shared**: `.claude/skills/_shared/exclude-local-only-commits.md` 절차를 따른다.

없는 경우:
```bash
# [LOCAL-ONLY] 커밋이 있으면 경고 후 사용자 확인
git log --grep='\[LOCAL-ONLY\]' --oneline
```
[LOCAL-ONLY] 커밋이 발견되면 사용자에게 알리고 처리 방법을 확인한다.

**b. PR 생성:**

프로젝트에 `_shared/create-pr.md`가 있는 경우:
> **Shared**: `.claude/skills/_shared/create-pr.md` 절차를 따른다.
> - `branch_name`: {branch_name}
> - `jira_key`: {jira_key} (frontmatter에서 추출, 없으면 생략)
> - `changes_summary`: Step 3에서 수집한 수정 범위
> - `impact_summary`: Step 3에서 수집한 영향 범위
> - `base_branch`: Step 3에서 결정한 BASE_REF의 브랜치명
> - `changed_files`: Step 3에서 수집한 변경 파일 목록

없는 경우: `gh pr create` 명령을 직접 실행한다:
```bash
gh pr create \
  --title "{pr_title}" \
  --body "$(cat <<'EOF'
## Summary
{changes_summary}

## Impact
{impact_summary}

## Changed files
{changed_files}
EOF
)" \
  --base {base_branch}
```

### 9. Print final summary

| Item           | Value                                  |
| -------------- | -------------------------------------- |
| Jira issue     | {jira_url or "없음"}                   |
| Gist (worklog) | {gist_url}                             |
| PR             | {pr_url or "미생성"}                   |
| Branch         | {branch_name}                          |
| Changed files  | {count}                                |
| Status         | DONE                                   |

### 10. Handle worktree cleanup (if applicable)

- Check if worklog had `worktree_path` in frontmatter (before deletion)
- If worktree exists and differs from main repo: ask user "Worktree를 정리하시겠습니까?"

**Yes:**

프로젝트에 `_shared/cleanup-worktree.md`가 있는 경우:
> **Shared**: `.claude/skills/_shared/cleanup-worktree.md` 절차를 따른다.
> - `main_repo_path`: {MAIN_REPO}
> - `worktree_path`: {worktree_path}

없는 경우:
```bash
cd {MAIN_REPO}
git worktree remove {worktree_path} --force
```

**No:** "Worktree preserved at {worktree_path}"

Proceed now.
