---
name: offload-to-branch
description: Offload specific changes from the current branch to a separate branch with its own Jira issue and PR
argument-hint: "Usage: /offload-to-branch [--files <file1,file2,...>] [--no-revert] [--no-jira] [brief description]"
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git merge-base:*), Bash(git push:*), Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git remote:*), Bash(git checkout:*), Bash(git worktree:*), Bash(git fetch:*), Bash(git reset:*), Bash(git apply:*), Bash(git stash:*), Bash(git cherry-pick:*), Bash(git rebase:*), Bash(git branch:*), Bash(find:*), Bash(grep:*), Bash(ls:*), Bash(rm -rf .claude*), Bash(cd:*), Bash(mkdir:*), Bash(cp:*), Bash(yarn:*), Bash(gh:*), Bash(date:*), Bash(test:*), Bash(echo:*), Read, Write, Edit, AskUserQuestion, Task, mcp__plugin_atlassian_atlassian__*
---

현재 작업 브랜치의 특정 파일 변경사항을 별도 브랜치로 분리하여 Jira 이슈와 PR을 생성한다.

기능 개발 중 업스트림 버그나 관련 없는 개선사항을 발견했을 때 유용하다. 해당 변경을 별도 픽스로 제출해야 할 경우에 사용한다.

## 핵심 설계 원칙

- **기본적으로 비파괴**: 패치를 생성하여 새 브랜치에 적용한다. 원본 브랜치의 변경사항은 적용 성공 후에만 되돌린다.
- **공유 절차 재사용**: Jira 이슈 생성, worktree 생성, [LOCAL-ONLY] 제외 등.
- **빠른 경로**: worklog 생성 생략 (멀티 세션 작업이 아닌 빠른 오프로드).
- **Jira API 마크다운**: `\n` 리터럴 문자열 사용 금지 (포맷 깨짐). 실제 줄바꿈 또는 한 줄로 작성.

## 프로젝트 설정

스킬 시작 시 프로젝트 설정 파일(`rules/project-params.md`)을 읽어 다음 설정을 가져온다:

| 설정 | 기본값 | 설명 |
|------|--------|------|
| `base_branch` | auto-detect (`gh repo view --json defaultBranchRef`) | diff/worktree 기준 브랜치 |
| `fork_workflow` | false | true면 `upstream` remote, false면 `origin` remote 사용 |
| `jira_pattern` | 없음 | 있으면 Jira 연동 활성화 (예: `VREW-\d+`) |
| `branch_pattern` | `fix/{issue_key}` 또는 `fix/{kebab-case-brief}` | 브랜치 이름 패턴 |

`rules/project-params.md`가 없으면 위 기본값으로 동작한다.

## 입력

- 원시 인자: $ARGUMENTS

해석:
- `--files <file1,file2,...>` (선택): 오프로드할 파일의 쉼표 구분 목록. 생략 시 자동 감지하거나 사용자에게 질문.
- `--no-revert` (선택): 오프로드 후 현재 브랜치에 변경사항 유지 (양쪽 브랜치에 중복).
- `--no-jira` (선택): Jira 이슈 생성 건너뜀.
- 나머지 텍스트 = 오프로드할 변경의 간략한 설명.

## 단계

### 0. 환경 검증

```bash
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
CURRENT_BRANCH=$(git branch --show-current)
```

피처 브랜치(`develop`, `main` 또는 동등한 베이스 브랜치가 아님)에 있는지 확인한다.

### 1. 오프로드할 파일 식별

**`--files`가 제공된 경우:** 해당 파일을 직접 사용한다.

**제공되지 않은 경우:**

a. `rules/project-params.md`에서 베이스 ref를 결정하거나, 사용자에게 질문하고 기억한다:
```bash
# 1. rules/project-params.md에서 base_branch 읽기 (e.g., "upstream/develop")
# 2. base_branch에 /가 포함되면 이미 remote-qualified → 그대로 사용
#    (e.g., "upstream/develop" → BASE_REF="upstream/develop", REMOTE="upstream")
# 3. base_branch가 bare name이면 (e.g., "develop"):
#    fork_workflow=true → REMOTE="upstream", BASE_REF="upstream/develop"
#    fork_workflow=false → REMOTE="origin", BASE_REF="origin/develop"
# 4. rules/project-params.md가 없으면 사용자에게 질문하고 project_memory에 기록:
#    "base branch를 알려주세요 (예: upstream/develop, origin/main)"
#    → project_memory_add_note("base_branch: {user_answer}")
BASE_REF=<resolved>
REMOTE=<extracted from BASE_REF>
git fetch $REMOTE
git diff --name-only $(git merge-base HEAD $BASE_REF)..HEAD
```

b. AskUserQuestion: "오프로드할 파일을 선택해주세요." (변경된 파일 목록과 함께, multiSelect: true).

### 2. 패치 생성

```bash
MERGE_BASE=$(git merge-base HEAD $BASE_REF)
git diff $MERGE_BASE..HEAD -- {selected_files} > /tmp/offload.patch
```

패치가 비어 있지 않은지 확인한다. 비어 있으면 메시지와 함께 중단한다.

### 3. 변경 컨텍스트 파악

패치 내용을 분석하고 사용자에게 질문한다 (또는 인자의 brief 사용):

- **변경 요약**: 오프로드할 변경이 하는 일 (1-2 문장)
- **영향 범위**: 영향받을 수 있는 기존 기능

인자에 brief가 제공된 경우 이를 미리 채워 넣고 확인한다.

### 4. Jira 이슈 생성 (`--no-jira`가 아닌 경우)

**`jira_pattern`이 `rules/project-params.md`에 있는 경우에만 실행한다. 없으면 이 단계를 건너뛴다.**

> **Shared**: `_shared/create-jira-issue.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/create-jira-issue.md` → `~/.claude/skills/_shared/create-jira-issue.md`
> - `task_brief` = 변경 요약 + 영향 범위
> - `suggested_summary` = brief로부터 도출

반환: `issue_key`, `issue_url`

### 5. 브랜치 및 worktree 생성

a. 브랜치 이름 결정:
- `rules/project-params.md`에 `branch_pattern`이 있으면 해당 패턴 사용
- 기본값:
  - Jira 있음: `fix/{issue_key}` (예: `fix/PROJ-1234`)
  - Jira 없음: `fix/{kebab-case-brief}` (예: `fix/audio-duplicate-conversion`)

b. 이슈 키 또는 brief로부터 worktree 이름 결정:
- Jira 있음: `{issue_key}` (예: `PROJ-1234`)
- Jira 없음: kebab-case brief

c. Worktree 생성:

> **Shared**: `_shared/create-worktree.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/create-worktree.md` → `~/.claude/skills/_shared/create-worktree.md`
> - `task_name` = worktree 이름
> - `branch_name` = 위에서 결정한 브랜치 이름
> - `base_ref` = `$BASE_REF`
> - `create_branch` = `true`

**의존성 설치 생략** - 개발 환경이 아닌 빠른 오프로드이다.

### 6. Worktree에 패치 적용

```bash
cd {worktree_path}
git apply /tmp/offload.patch
```

`git apply`가 실패하면 (예: 컨텍스트 불일치), 다음을 시도한다:
```bash
git apply --3way /tmp/offload.patch
```

그래도 실패하면 사용자에게 알리고 중단한다 (수동 해결을 위해 worktree 유지).

### 7. Worktree에서 커밋

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

업스트림의 최근 커밋에서 메시지 컨벤션을 확인한다:
```bash
git log $BASE_REF -5 --oneline
```

### 8. 현재 브랜치에서 변경사항 되돌리기 (`--no-revert`가 아닌 경우)

```bash
cd {original_worktree}
git checkout $BASE_REF -- {selected_files}
git add {selected_files}
git commit -m "refactor: extract {brief} to separate branch ({issue_key_if_exists})"
```

파일이 새로 추가된 경우 (base_branch에 없는 경우), checkout 대신 `git rm`을 사용한다.

### 9. Lint 및 포맷

> **Shared**: `_shared/lint-format.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/lint-format.md` → `~/.claude/skills/_shared/lint-format.md`
> - `changed_files`: 오프로드된 파일 목록
> - `project_dir`: worktree 또는 메인 리포 중 node_modules가 있는 쪽의 해당 경로
>
> node_modules 탐색 순서: `{worktree_path}/` → `{MAIN_REPO}/`

### 10. 코드 리뷰 (필수)

> **Shared**: `_shared/code-review-gate.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/code-review-gate.md` → `~/.claude/skills/_shared/code-review-gate.md`
> - `diff_target`: `$BASE_REF`
> - `changed_files`: 오프로드된 파일 목록
>
> 수정 발생 시 Step 9(lint-format) 재실행.

### 11. 푸시 및 PR 생성

**a. [LOCAL-ONLY] 커밋 제외 (필수):**

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

### 12. 요약 출력

| 항목 | 값 |
|------|-------|
| Jira 이슈 | {jira_url} (jira_pattern 있을 때만) |
| PR | {pr_url} |
| 브랜치 | {branch_name} |
| Worktree | {worktree_path} |
| 리뷰어 | {reviewers} |
| 레이블 | {labels} |
| 오프로드된 파일 | {file_list} |
| 되돌린 브랜치 | {current_branch} |
| 상태 | 리뷰 대기 중 |

### 13. Worktree 정리

사용자에게 질문한다: "오프로드 worktree를 정리하시겠습니까?"

**예:**

> **Shared**: `_shared/cleanup-worktree.md` 절차를 따른다.
> - 경로 우선순위: 프로젝트 `.claude/skills/_shared/cleanup-worktree.md` → `~/.claude/skills/_shared/cleanup-worktree.md`
> - `main_repo_path`: {MAIN_REPO}
> - `worktree_path`: {worktree_path}

**아니오:** "Worktree를 {worktree_path}에 유지합니다"

지금 시작한다.
